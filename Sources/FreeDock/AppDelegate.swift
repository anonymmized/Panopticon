import AppKit
import Carbon
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = DockStore()
    private var dock: DockWindowController?
    private var settings: SettingsWindowController?
    private var launcher: LauncherController?
    private var statusItem: NSStatusItem?
    private var launcherHotKey: UInt32?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsWindowController(store: store)
        self.settings = settings
        dock = DockWindowController(store: store)
        launcher = LauncherController(store: store) { settings.show() }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "FreeDock") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "▦"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        registerHotKeys()
        store.$config
            .map(\.launcherEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setLauncherHotKey(enabled) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showLauncher)
            .sink { [weak self] _ in self?.launcher?.show() }
            .store(in: &cancellables)

        // Re-apply "replace the system Dock" if it was restored when FreeDock last quit.
        if store.config.replaceSystemDock && !SystemDock.isHiddenByUs {
            SystemDock.hide()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if store.config.restoreDockOnQuit {
            SystemDock.restore()
        }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return false
    }

    private func registerHotKeys() {
        for (index, key) in HotKeys.digitKeys.enumerated() {
            HotKeys.shared.register(key) { [weak self] in self?.store.select(index) }
        }
        HotKeys.shared.register(kVK_LeftArrow) { [weak self] in self?.store.cycle(-1) }
        HotKeys.shared.register(kVK_RightArrow) { [weak self] in self?.store.cycle(1) }
        HotKeys.shared.register(kVK_ANSI_D) { [weak self] in self?.store.config.visible.toggle() }
    }

    private func setLauncherHotKey(_ enabled: Bool) {
        if let launcherHotKey {
            HotKeys.shared.unregister(launcherHotKey)
            self.launcherHotKey = nil
        }
        if enabled {
            launcherHotKey = HotKeys.shared.register(kVK_Space) { [weak self] in self?.launcher?.toggle() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = store.config
        let hotkey: NSEvent.ModifierFlags = [.control, .option]

        menu.addItem(ActionMenuItem(config.visible ? "Скрыть бар" : "Показать бар", key: "d", modifiers: hotkey) {
            [weak self] in self?.store.config.visible.toggle()
        })
        menu.addItem(ActionMenuItem("Быстрый поиск…", key: " ", modifiers: hotkey) { [weak self] in
            self?.launcher?.show()
        })
        menu.addItem(.separator())

        menu.addItem(.header("Пространства"))
        for (index, space) in config.spaces.enumerated() {
            var title = space.name
            if let desktop = space.desktop { title += "  · стол \(desktop)" }
            let item = ActionMenuItem(title, key: index < 9 ? "\(index + 1)" : "", modifiers: hotkey,
                                      checked: index == config.current) { [weak self] in
                self?.store.select(index)
            }
            item.image = NSImage(systemSymbolName: space.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(ActionMenuItem("Новое пространство…") { [weak self] in
            DispatchQueue.main.async { self?.store.addSpace() }
        })
        menu.addItem(ActionMenuItem("Импортировать из системного Dock") { [weak self] in
            self?.store.importSystemDock()
        })
        menu.addItem(.separator())

        let edges = NSMenu()
        for edge in DockEdge.allCases {
            edges.addItem(ActionMenuItem(edge.title, checked: config.edge == edge) { [weak self] in
                self?.store.config.edge = edge
            })
        }
        menu.addItem(.nested("Положение", edges))

        let themes = NSMenu()
        for theme in DockTheme.allCases {
            themes.addItem(ActionMenuItem(theme.title, checked: config.theme == theme) { [weak self] in
                self?.store.config.theme = theme
            })
        }
        menu.addItem(.nested("Тема", themes))

        menu.addItem(ActionMenuItem("Автоматически скрывать", checked: config.autohide) { [weak self] in
            self?.store.config.autohide.toggle()
        })
        menu.addItem(ActionMenuItem("Заменить системный Dock", checked: config.replaceSystemDock) { [weak self] in
            guard let self else { return }
            self.store.setReplaceSystemDock(!self.store.config.replaceSystemDock)
        })
        menu.addItem(ActionMenuItem("Настройки…", key: ",", modifiers: .command) { [weak self] in
            self?.settings?.show()
        })
        menu.addItem(.separator())

        if SystemDock.isHiddenByUs {
            menu.addItem(ActionMenuItem("Вернуть системный Dock") { [weak self] in
                self?.store.setReplaceSystemDock(false)
            })
        }
        menu.addItem(ActionMenuItem("Выйти из FreeDock", key: "q", modifiers: .command) {
            NSApp.terminate(nil)
        })
    }
}
