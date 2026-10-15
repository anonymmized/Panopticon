import AppKit

extension BarView {
    func makeContextMenu(_ event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        if hasOverflow && overflowRect.contains(point) { return overflowMenu() }
        if let index = spaceFrames.firstIndex(where: { $0.contains(point) }), index < visibleSpaces.count {
            return spaceMenu(visibleSpaces[index])
        }
        if let index = linkFrames.firstIndex(where: { $0.contains(point) }), index < displayLinks.count {
            return linkMenu(displayLinks[index])
        }
        if let index = collectionFrames.firstIndex(where: { $0.contains(point) }),
            index < displayCollections.count
        {
            return collectionMenu(displayCollections[index], rect: collectionFrames[index])
        }
        if contentLayout.showsTrash && trashRect.contains(point) {
            menu.addItem(ActionMenuItem(L("Открыть Корзину")) { NSWorkspace.shared.open(BarModel.trashURL) })
            menu.addItem(
                ActionMenuItem(L("Очистить Корзину…")) {
                    DispatchQueue.main.async { TrashActions.confirmEmpty() }
                })
            return menu
        }
        if let index = hitItem(point), index < displayItems.count {
            let item = displayItems[index]
            if let app = model.runningApplication(for: item) {
                for window in AX.windows(of: app) {
                    menu.addItem(ActionMenuItem(window.title) { AX.focus(window, of: app) })
                }
                if !menu.items.isEmpty { menu.addItem(.separator()) }
            }
            if model.pinned.contains(item) {
                let spaces = NSMenu()
                for space in model.spaces where space.id != model.selectedSpaceID {
                    spaces.addItem(
                        ActionMenuItem(space.name) { [weak self] in
                            self?.model.moveApp(item, toSpace: space.id)
                        })
                }
                let entry = NSMenuItem(title: L("Переместить в пространство"), action: nil, keyEquivalent: "")
                entry.submenu = spaces
                menu.addItem(entry)
            }
            addMenu(menu, item.name, #selector(openItem(_:)), item)
            addMenu(
                menu, model.pinned.contains(item) ? L("Убрать из Dock") : L("Оставить в Dock"),
                #selector(pinItem(_:)), item)
            addMenu(menu, L("Показать в Finder"), #selector(revealItem(_:)), item)
            if model.isRunning(item), item.bundleID != "com.apple.finder" {
                addMenu(menu, L("Скрыть / показать приложение"), #selector(hideItem(_:)), item)
                addMenu(menu, L("Завершить приложение"), #selector(quitItem(_:)), item)
                let force = NSMenuItem(
                    title: L("Завершить принудительно"), action: #selector(forceQuitItem(_:)), keyEquivalent: "")
                force.target = self
                force.representedObject = item
                force.isAlternate = true
                force.keyEquivalentModifierMask = .option
                menu.addItem(force)
            }
            menu.addItem(.separator())
        }
        if zip(visibleWidgets, widgetFrames).contains(where: { $0.0 == "timer" && $0.1.contains(point) }) {
            addMenu(menu, L("Сбросить таймер"), #selector(resetTimer(_:)), nil)
            menu.addItem(.separator())
        }
        if let undoRemoval {
            menu.addItem(
                ActionMenuItem(L("Отменить удаление ярлыка")) { [weak self] in
                    self?.undoRemoval = nil
                    undoRemoval()
                })
        }
        addMenu(menu, L("Открыть выбранный календарь"), #selector(calendarAction(_:)), nil)
        addMenu(menu, L("Настройки Panopticon…"), #selector(settingsAction(_:)), nil)
        addMenu(menu, L("Завершить Panopticon"), #selector(quitBar(_:)), nil)
        return menu
    }
    func showOverflow() {
        overflowMenu().popUp(
            positioning: nil, at: NSPoint(x: overflowRect.minX, y: overflowRect.maxY), in: self)
    }
    func overflowMenu() -> NSMenu {
        let menu = NSMenu()
        for item in model.items.dropFirst(displayItems.count) {
            menu.addItem(ActionMenuItem(item.name) { [weak self] in self?.activate(item) })
        }
        for group in model.collections.dropFirst(displayCollections.count) {
            let entry = NSMenuItem(title: L("Коллекция: ") + group.name, action: nil, keyEquivalent: "")
            entry.submenu = collectionMenu(group, rect: overflowRect)
            menu.addItem(entry)
        }
        for link in model.quickLinks.dropFirst(displayLinks.count) {
            let entry = NSMenuItem(title: link.name, action: nil, keyEquivalent: "")
            entry.submenu = linkMenu(link)
            menu.addItem(entry)
        }
        for kind in model.widgetKinds.dropFirst(visibleWidgets.count) {
            menu.addItem(
                ActionMenuItem(
                    ["music": L("Музыка"), "calendar": L("Календарь"), "clock": L("Часы"), "timer": L("Таймер")][kind]
                        ?? kind
                ) { [weak self] in
                    guard let self else { return }
                    self.activateWidget(kind, rect: self.overflowRect)
                })
        }
        if model.showTrash && !contentLayout.showsTrash { menu.addItem(ActionMenuItem(L("Корзина")) { NSWorkspace.shared.open(BarModel.trashURL) }) }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        for space in model.spaces {
            menu.addItem(
                ActionMenuItem(space.name, checked: space.id == model.selectedSpaceID) { [weak self] in
                    self?.model.selectSpace(space.id)
                })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L("Настройки…")) { [weak self] in self?.openSettings?() })
        return menu
    }
    func linkMenu(_ link: QuickLink) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            ActionMenuItem(L("Открыть ") + link.name) {
                if let url = link.url { ActionRouter.open(.resource(url)) }
            })
        menu.addItem(
            ActionMenuItem(L("Скопировать адрес")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.destination, forType: .string)
            })
        if let url = link.url, url.isFileURL {
            menu.addItem(
                ActionMenuItem(L("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        }
        let spaces = NSMenu()
        for space in model.spaces where space.id != model.selectedSpaceID {
            spaces.addItem(
                ActionMenuItem(space.name) { [weak self] in
                    guard let self else { return }
                    _ = PanelActions.moveLink(link.id, toSpace: space.id, model: self.model)
                })
        }
        let move = NSMenuItem(title: L("Переместить в пространство"), action: nil, keyEquivalent: "")
        move.submenu = spaces
        menu.addItem(move)
        menu.addItem(
            ActionMenuItem(L("Редактировать ярлыки…")) { [weak self] in
                UIStateStore.shared.section = "connections"
                self?.openSettings?()
            })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L("Убрать ярлык")) { [weak self] in self?.removeLinkWithUndo(link.id) })
        if let undoRemoval {
            menu.addItem(
                ActionMenuItem(L("Отменить удаление ярлыка")) { [weak self] in
                    self?.undoRemoval = nil
                    undoRemoval()
                })
        }
        return menu
    }
    func collectionMenu(_ group: AppCollection, rect: NSRect) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            ActionMenuItem(L("Открыть коллекцию")) { [weak self] in self?.openCollection?(group, rect) })
        menu.addItem(
            ActionMenuItem(L("Запустить все приложения")) { [weak self] in
                guard let self else { return }
                group.items.forEach { self.model.launch($0) }
            })
        let spaces = NSMenu()
        for space in model.spaces where space.id != model.selectedSpaceID {
            spaces.addItem(
                ActionMenuItem(space.name) { [weak self] in
                    guard let self else { return }
                    _ = PanelActions.moveCollection(group.id, toSpace: space.id, model: self.model)
                })
        }
        let move = NSMenuItem(title: L("Переместить в пространство"), action: nil, keyEquivalent: "")
        move.submenu = spaces
        menu.addItem(move)
        menu.addItem(
            ActionMenuItem(L("Настроить коллекции…")) { [weak self] in
                UIStateStore.shared.section = "collections"
                self?.openSettings?()
            })
        menu.addItem(.separator())
        menu.addItem(
            ActionMenuItem(L("Убрать коллекцию")) { [weak self] in self?.removeCollectionWithUndo(group.id) })
        return menu
    }
    func removeAppWithUndo(_ item: DockItem) {
        let space = model.selectedSpaceID
        let index = model.pinned.firstIndex(of: item) ?? 0
        model.remove(item)
        undoRemoval = { [weak model] in
            guard let model, model.spaces.contains(where: { $0.id == space }) else { return }
            model.selectSpace(space)
            model.add(item.url, at: index)
        }
    }
    func removeLinkWithUndo(_ id: String) {
        guard let index = model.quickLinks.firstIndex(where: { $0.id == id }) else { return }
        let space = model.selectedSpaceID
        let link = model.quickLinks[index]
        model.removeQuickLink(id)
        undoRemoval = { [weak model] in
            guard let model, model.spaces.contains(where: { $0.id == space }) else { return }
            model.selectSpace(space)
            guard !model.quickLinks.contains(where: { $0.id == id || $0.destination == link.destination })
            else { return }
            model.batch { model.quickLinks.insert(link, at: min(index, model.quickLinks.count)) }
        }
    }
    func removeCollectionWithUndo(_ id: String) {
        guard let index = model.collections.firstIndex(where: { $0.id == id }) else { return }
        let space = model.selectedSpaceID
        let group = model.collections[index]
        model.removeCollection(id)
        undoRemoval = { [weak model] in
            guard let model, model.spaces.contains(where: { $0.id == space }) else { return }
            model.selectSpace(space)
            guard !model.collections.contains(where: { $0.id == id }) else { return }
            model.batch { model.collections.insert(group, at: min(index, model.collections.count)) }
        }
    }
    func spaceMenu(_ space: BarSpace) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            ActionMenuItem(L("Открыть «\(space.name)»")) { [weak self] in self?.model.selectSpace(space.id) })
        menu.addItem(
            ActionMenuItem(L("Привязать к текущему рабочему столу"), enabled: model.currentDesktop != nil) {
                [weak self] in
                guard let self else { return }
                PanelActions.bind(space, desktop: self.model.currentDesktop, model: self.model)
            })
        menu.addItem(
            ActionMenuItem(L("Снять привязку"), enabled: space.desktop != nil) { [weak self] in
                self?.model.bindSpace(space.id, desktop: nil)
            })
        addMenu(menu, L("Настроить пространства…"), #selector(settingsAction(_:)), nil)
        return menu
    }
    func addMenu(_ menu: NSMenu, _ title: String, _ action: Selector, _ item: DockItem?) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = item
        menu.addItem(entry)
    }
    @objc private func openItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? DockItem { activate(item) }
    }
    @objc private func pinItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? DockItem {
            model.pinned.contains(item) ? removeAppWithUndo(item) : model.add(item.url)
        }
    }
    @objc private func revealItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? DockItem {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
    }
    @objc private func quitItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? DockItem {
            model.runningApplication(for: item)?.terminate()
        }
    }
    @objc private func hideItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem,
            let app = model.runningApplication(for: item)
        else { return }
        if app.isHidden { app.unhide() } else { app.hide() }
    }
    @objc private func forceQuitItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? DockItem {
            model.runningApplication(for: item)?.forceTerminate()
        }
    }
    @objc private func calendarAction(_ sender: Any?) { model.openCalendar() }
    @objc private func resetTimer(_ sender: Any?) { focus.reset(minutes: model.timerMinutes) }
    @objc private func settingsAction(_ sender: Any?) { openSettings?() }
    @objc private func quitBar(_ sender: Any?) { NSApp.terminate(nil) }
}
