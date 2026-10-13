import AppKit

/// Context menus of the bar, built fresh on every right click.
extension DockStore {
    func itemMenu(for item: DockItem, pinned: Bool) -> NSMenu {
        let menu = NSMenu()
        let app = runningApp(for: item)

        if let app {
            let windows = AX.windows(of: app)
            if !windows.isEmpty {
                menu.addItem(.header("Окна"))
                for window in windows {
                    let entry = ActionMenuItem(window.title) { AX.focus(window, of: app) }
                    if window.minimized {
                        entry.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil)
                    }
                    menu.addItem(entry)
                }
                menu.addItem(.separator())
            }
        }

        menu.addItem(ActionMenuItem(item.isFolder ? "Открыть в Finder" : "Открыть") { [weak self] in
            self?.open(item)
        })
        if item.isWeb {
            menu.addItem(ActionMenuItem("Скопировать ссылку") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            })
        } else {
            menu.addItem(ActionMenuItem("Показать в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            })
        }

        if let app {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(app.isHidden ? "Показать" : "Скрыть") {
                _ = app.isHidden ? app.unhide() : app.hide()
            })
            menu.addItem(ActionMenuItem("Завершить") { _ = app.terminate() })
            let force = ActionMenuItem("Завершить принудительно", modifiers: .option) { _ = app.forceTerminate() }
            force.isAlternate = true
            menu.addItem(force)
        }

        menu.addItem(.separator())
        guard pinned else {
            menu.addItem(ActionMenuItem("Закрепить в «\(current.name)»") { [weak self] in
                self?.add(urls: [item.url])
            })
            return menu
        }

        let spacesMenu = NSMenu()
        spacesMenu.autoenablesItems = false
        for (index, space) in config.spaces.enumerated() {
            let entry = ActionMenuItem(space.name, enabled: index != config.current) { [weak self] in
                self?.move(item.id, toSpace: index)
            }
            entry.isEnabled = index != config.current
            entry.image = NSImage(systemSymbolName: space.symbol, accessibilityDescription: nil)
            spacesMenu.addItem(entry)
        }
        menu.addItem(.nested("Переместить в пространство", spacesMenu))
        menu.addItem(ActionMenuItem("Сдвинуть назад") { [weak self] in self?.move(item.id, by: -1) })
        menu.addItem(ActionMenuItem("Сдвинуть вперёд") { [weak self] in self?.move(item.id, by: 1) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Убрать из бара") { [weak self] in self?.remove(item.id) })
        return menu
    }

    func timerMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(.header("Таймер фокуса"))
        menu.addItem(ActionMenuItem(focus.running ? "Пауза" : "Старт") { [weak self] in self?.focus.toggle() })
        menu.addItem(ActionMenuItem("Сбросить") { [weak self] in self?.focus.reset() })
        menu.addItem(.separator())
        for minutes in [5.0, 10, 15, 25, 45, 60, 90] {
            menu.addItem(ActionMenuItem("\(Int(minutes)) мин", checked: config.timerMinutes == minutes) { [weak self] in
                self?.config.timerMinutes = minutes
                self?.focus.start(minutes: minutes)
            })
        }
        return menu
    }

    func spaceMenu(for index: Int) -> NSMenu {
        let menu = NSMenu()
        guard config.spaces.indices.contains(index) else { return menu }
        let space = config.spaces[index]

        menu.addItem(.header(space.name))
        menu.addItem(ActionMenuItem("Переименовать…") { [weak self] in
            DispatchQueue.main.async { self?.renameSpace(index) }
        })

        let icons = NSMenu()
        for symbol in Self.symbols {
            let entry = ActionMenuItem("", checked: symbol == space.symbol) { [weak self] in
                self?.setSymbol(symbol, for: index)
            }
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
            icons.addItem(entry)
        }
        menu.addItem(.nested("Иконка", icons))

        let desktops = NSMenu()
        desktops.addItem(ActionMenuItem("Не привязано", checked: space.desktop == nil) { [weak self] in
            self?.bind(space.id, desktop: nil)
        })
        desktops.addItem(.separator())
        for number in 1...max(desktopCount, space.desktop ?? 0, 4) {
            var title = "Рабочий стол \(number)"
            if number == currentDesktop { title += " (текущий)" }
            desktops.addItem(ActionMenuItem(title, checked: space.desktop == number) { [weak self] in
                self?.bind(space.id, desktop: number)
            })
        }
        menu.addItem(.nested("Рабочий стол macOS", desktops))

        menu.addItem(.separator())
        let delete = ActionMenuItem("Удалить пространство", enabled: config.spaces.count > 1) { [weak self] in
            DispatchQueue.main.async { self?.deleteSpace(index) }
        }
        menu.addItem(delete)
        return menu
    }

    func trashMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("Открыть") { NSWorkspace.shared.open(DockStore.trashURL) })
        menu.addItem(ActionMenuItem("Очистить Корзину") { [weak self] in self?.emptyTrash() })
        return menu
    }
}
