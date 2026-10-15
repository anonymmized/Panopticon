import AppKit
import SwiftUI
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = BarModel.shared
    let music = MusicController()
    let focus = FocusTimer()
    let dock = DockIntegration()
    let agenda = CalendarController()
    let catalog = AppCatalog()
    private var ownsSession = false
    var lastShortcutChoice = ""
    var globalShortcut: GlobalShortcut?
    var searchPanel: SearchPanel?
    var calendarPopover: NSPopover?
    var lastAgendaConfig = ""
    var lastMusicPoll = Date.distantPast
    var lastClockStamp = ""
    var lastPulseAutoHide: Bool?
    var lastReplaceDock: Bool?
    var lastTimerMinutes: Double = 25
    var collectionPopover: NSPopover?
    var panel: BarPanel!
    var bar: BarView!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var musicPopover: NSPopover?
    var timer: Timer?
    var tick = 0
    var hidden = false
    var hoverDeadline = Date.distantPast
    var screenObserver: NSObjectProtocol?
    var settingsObserver: NSObjectProtocol?
    var languageObserver: NSObjectProtocol?
    var desktopObserver: NSObjectProtocol?
    var spaceHotKeys: [UInt32] = []
    var folderPopover: NSPopover?
    var lastBadgesPoll = Date.distantPast
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let activation = NSNotification.Name(AppIdentity.preferencesDomain + ".showPreferences")
        let instances = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier && !$0.isTerminated }
        let winner = instances.min { a, b in
            let first = a.launchDate ?? .distantFuture; let second = b.launchDate ?? .distantFuture
            return first == second ? a.processIdentifier < b.processIdentifier : first < second
        }
        if let existing = winner, existing.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            existing.activate(options: [.activateAllWindows])
            DistributedNotificationCenter.default().postNotificationName(activation, object: Bundle.main.bundleIdentifier, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil); return
        }
        ownsSession = true
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleActivation(_:)), name: activation, object: Bundle.main.bundleIdentifier)
        lastTimerMinutes = model.timerMinutes
        if UserDefaults.standard.dictionary(forKey: "focusSession") == nil { focus.reset(minutes: model.timerMinutes) }
        if UserDefaults.standard.integer(forKey: "layoutVersion") < 2 {
            model.iconSize = 36; model.iconSpacing = 8; model.bottomOffset = 4
            model.cornerRadius = 20; model.magnification = 1.35; model.opacity = 0.08
            UserDefaults.standard.set(2, forKey: "layoutVersion")
        }
        rebuildApplicationMenu()
        panel = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        // Mission Control reveals the native Dock. A stationary panel stays
        // onscreen there and overlaps it; a transient panel hides for the overview
        // and AppKit brings it back when the user returns to the desktop.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.title = "Panopticon"
        let root = PassthroughView()
        bar = BarView(model: model, music: music, focus: focus, agenda: agenda)
        root.addSubview(bar.glass); root.addSubview(bar)
        panel.contentView = root
        bar.openFolder = { [weak self] url, rect in self?.showFolder(url, rect: rect) }
        for (index, key) in HotKeys.digitKeys.enumerated() {
            if let id = HotKeys.shared.register(key, handler: { [weak self] in
                guard let self, index < self.model.spaces.count else { return }
                self.model.selectSpace(self.model.spaces[index].id); self.reveal()
            }) { spaceHotKeys.append(id) }
        }
        if let id = HotKeys.shared.register(kVK_ANSI_D, handler: { [weak self] in
            guard let self else { return }; self.model.barVisible.toggle()
        }) { spaceHotKeys.append(id) }
        settingsObserver = NotificationCenter.default.addObserver(forName: .openBarSettings, object: nil, queue: .main) { [weak self] _ in self?.showSettings() }
        for (key, delta) in [(kVK_LeftArrow, -1), (kVK_RightArrow, 1)] {
            if let id = HotKeys.shared.register(key, handler: { [weak self] in self?.model.cycleSpace(delta) }) { spaceHotKeys.append(id) }
        }
        desktopObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.updateDesktop() }
        bar.openSettings = { [weak self] in self?.showSettings() }
        bar.openAgenda = { [weak self] rect in self?.showAgenda(rect) }
        agenda.onChange = { [weak self] in self?.bar.needsDisplay = true }
        bar.openMusic = { [weak self] rect in self?.showMusic(rect) }
        model.onChange = { [weak self] in self?.preferencesChanged() }
        bar.openCollection = { [weak self] collection, rect in self?.showCollection(collection, rect) }
        focus.onChange = { [weak self] in self?.bar.needsDisplay = true }
        music.onChange = { [weak self] in self?.bar.needsDisplay = true }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: "Panopticon")
        rebuildStatusMenu()
        languageObserver = NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.languageChanged()
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.updatePanel() }
        preferencesChanged(); updateDesktop()
        // A nil view hit-test cannot forward a click to another application.
        // Update the window itself when the pointer crosses its transparent margin.
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            self?.updateMousePassthrough()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }
        configurePulse()
        updateMousePassthrough()
        if ProcessInfo.processInfo.arguments.contains("--settings") { showSettings() }
    }
    func rebuildApplicationMenu() {
        let mainMenu = NSMenu(); let appMenuItem = NSMenuItem(); let appMenu = NSMenu()
        let preferences = NSMenuItem(title: L("Настройки…"), action: #selector(showSettings), keyEquivalent: ","); preferences.target = self; appMenu.addItem(preferences)
        let search = NSMenuItem(title: L("Быстрый поиск…"), action: #selector(showLauncher), keyEquivalent: "k"); search.target = self; appMenu.addItem(search)
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: L("Завершить Panopticon"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu; mainMenu.addItem(appMenuItem); NSApp.mainMenu = mainMenu
    }
    func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Panopticon — бесплатно"), action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: L("Настройки…"), action: #selector(showSettings), keyEquivalent: ","); settings.target = self
        let statusSearch = menu.addItem(withTitle: L("Быстрый поиск…  ⌃⌥Пробел"), action: #selector(showLauncher), keyEquivalent: ""); statusSearch.target = self; statusSearch.tag = 301
        let show = menu.addItem(withTitle: L("Показать панель"), action: #selector(reveal), keyEquivalent: ""); show.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Завершить"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        updateProfileMenu()
        statusItem?.menu?.item(withTag: 301)?.title = L("Быстрый поиск…  ") + (model.launcherEnabled && model.launcherShortcutAvailable ? model.launcherShortcutLabel : "")
    }
    func languageChanged() {
        rebuildApplicationMenu(); rebuildStatusMenu()
        dock.message = Localization.shared.status(dock.message)
        agenda.message = Localization.shared.status(agenda.message)
        music.relocalizeStatus()
        // Repaint without revealing a hidden panel or mutating layout/preferences.
        bar.refresh()
    }
    var screen: NSScreen? { let screens = NSScreen.screens; return screens.isEmpty ? nil : screens[min(max(0, model.screenIndex), screens.count - 1)] }
    func updatePanel(animated: Bool = false) {
        guard panel != nil, let screen else { return }
        guard model.barVisible else { panel.orderOut(nil); return }
        let width = min(bar.preferredWidth, screen.frame.width - 24)
        let height = min(bar.preferredHeight, screen.visibleFrame.height - 24)
        let offset = CGFloat(model.bottomOffset)
        let area = screen.frame
        var frame: NSRect
        switch model.dockEdge {
        case .bottom: frame = NSRect(x: area.midX - width / 2, y: area.minY + offset, width: width, height: height)
        case .top: frame = NSRect(x: area.midX - width / 2, y: screen.visibleFrame.maxY - height - offset, width: width, height: height)
        case .left: frame = NSRect(x: area.minX + offset, y: screen.visibleFrame.midY - height / 2, width: width, height: height)
        case .right: frame = NSRect(x: area.maxX - width - offset, y: screen.visibleFrame.midY - height / 2, width: width, height: height)
        }
        if hidden && model.autoHide {
            switch model.dockEdge {
            case .bottom: frame.origin.y = area.minY - height + 3
            case .top: frame.origin.y = area.maxY - 3
            case .left: frame.origin.x = area.minX - width + 3
            case .right: frame.origin.x = area.maxX - 3
            }
        }
        if animated && !model.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.2; context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); panel.animator().setFrame(frame, display: true) }
        } else { panel.setFrame(frame, display: true) }
        bar.frame = NSRect(origin: .zero, size: panel.frame.size)
        bar.refresh()
        panel.orderFrontRegardless()
        updateMousePassthrough()
        music.preference = model.playerPreference
        if model.widgetKinds.contains("music") { music.refresh() }
    }
    func updateMousePassthrough() {
        guard let panel, let bar else { return }
        panel.updateMousePassthrough(for: bar, at: NSEvent.mouseLocation)
    }
    func updateDesktop() { model.desktopChanged(Desktops.current(for: screen)?.number) }
    func configurePulse() {
        guard lastPulseAutoHide != model.autoHide else { return }
        lastPulseAutoHide = model.autoHide; timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: model.autoHide ? 0.1 : 1, repeats: true) { [weak self] _ in self?.pulse() }
        timer?.tolerance = model.autoHide ? 0.02 : 0.15
    }
    func pulse() {
        updateMousePassthrough()
        let now = Date()
        if now.timeIntervalSince(lastBadgesPoll) >= 2 { lastBadgesPoll = now; model.refreshBadges() }
        if model.followMouse, let index = NSScreen.screens.firstIndex(where: { $0.frame.contains(NSEvent.mouseLocation) }), index != model.screenIndex {
            model.screenIndex = index; updateDesktop()
        }
        guard model.barVisible else { return }
        if model.widgetKinds.contains("music"), (!hidden || musicPopover?.isShown == true), now.timeIntervalSince(lastMusicPoll) >= (musicPopover?.isShown == true ? 1 : 4) { lastMusicPoll = now; music.refresh() }
        if model.calendarEventsEnabled { agenda.refresh() }
        let timestamp = String(Int(now.timeIntervalSince1970) / (model.clockSeconds || focus.isRunning ? 1 : 60))
        if !hidden && timestamp != lastClockStamp { lastClockStamp = timestamp; bar.needsDisplay = true }
        guard let screen else { return }
        if !model.autoHide { if hidden { hidden = false; updatePanel() }; return }
        let mouse = NSEvent.mouseLocation
        let nearBottom: Bool
        switch model.dockEdge {
        case .bottom: nearBottom = (panel.frame.minX...panel.frame.maxX).contains(mouse.x) && mouse.y < screen.frame.minY + 7 && mouse.y >= screen.frame.minY
        case .top: nearBottom = (panel.frame.minX...panel.frame.maxX).contains(mouse.x) && mouse.y > screen.visibleFrame.maxY - 7 && mouse.y <= screen.frame.maxY
        case .left: nearBottom = (panel.frame.minY...panel.frame.maxY).contains(mouse.y) && mouse.x < screen.frame.minX + 7 && mouse.x >= screen.frame.minX
        case .right: nearBottom = (panel.frame.minY...panel.frame.maxY).contains(mouse.y) && mouse.x > screen.frame.maxX - 7 && mouse.x <= screen.frame.maxX
        }
        let inside = !hidden && panel.frame.insetBy(dx: -12, dy: -10).contains(mouse)
        if inside || nearBottom || (settingsWindow?.isVisible == true || musicPopover?.isShown == true || collectionPopover?.isShown == true || calendarPopover?.isShown == true || folderPopover?.isShown == true || NSEvent.pressedMouseButtons != 0) { hoverDeadline = Date().addingTimeInterval(0.8); if hidden { hidden = false; updatePanel(animated: true) } }
        else if !hidden && Date() > hoverDeadline { hidden = true; updatePanel(animated: true) }
    }
    func showAgenda(_ rect: NSRect) {
        musicPopover?.close(); collectionPopover?.close(); folderPopover?.close(); reveal()
        if calendarPopover == nil {
            let popover = NSPopover(); popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: CalendarPopoverView(agenda: agenda, model: model))
            popover.contentSize = NSSize(width: 350, height: 540); calendarPopover = popover
        }
        calendarPopover?.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
    }
    func showMusic(_ rect: NSRect) {
        calendarPopover?.close(); collectionPopover?.close(); folderPopover?.close(); reveal()
        if musicPopover == nil {
            let popover = NSPopover(); popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: MusicPopoverView(music: music))
            popover.contentSize = NSSize(width: 350, height: 280)
            musicPopover = popover
        }
        music.refresh(force: true, requestPermission: true); musicPopover?.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
    }
    func preferencesChanged() {
        configurePulse()
        if model.launcherEnabled && (globalShortcut == nil || lastShortcutChoice != model.launcherShortcutChoice) { globalShortcut = nil; lastShortcutChoice = model.launcherShortcutChoice; globalShortcut = GlobalShortcut(choice: model.launcherShortcutChoice) { [weak self] in self?.showLauncher() }; model.launcherShortcutAvailable = globalShortcut?.registered == true }
        if !model.launcherEnabled { globalShortcut = nil; model.launcherShortcutAvailable = false }
        statusItem?.menu?.item(withTag: 301)?.title = L("Быстрый поиск…  ") + (model.launcherEnabled && model.launcherShortcutAvailable ? model.launcherShortcutLabel : "")
        let agendaConfig = "\(model.calendarEventsEnabled)-\(model.selectedCalendarIDs.sorted())"
        agenda.enabled = model.calendarEventsEnabled; agenda.selectedIDs = model.selectedCalendarIDs
        if agendaConfig != lastAgendaConfig { lastAgendaConfig = agendaConfig; agenda.refresh(force: true) }
        if lastReplaceDock != model.replaceDock {
            lastReplaceDock = model.replaceDock
            if model.replaceDock { dock.enable() } else { dock.restore() }
        }
        if lastTimerMinutes != model.timerMinutes {
            lastTimerMinutes = model.timerMinutes
            if !focus.isRunning { focus.reset(minutes: model.timerMinutes) }
        }
        updateProfileMenu()
        updatePanel()
    }
    func showCollection(_ collection: AppCollection, _ rect: NSRect) {
        musicPopover?.close(); calendarPopover?.close(); folderPopover?.close(); reveal()
        collectionPopover?.close()
        let popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: CollectionPopoverView(collection: collection, model: model))
        popover.contentSize = NSSize(width: 330, height: 270); collectionPopover = popover
        popover.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
    }
    func showFolder(_ url: URL, rect: NSRect) {
        closePopovers(); reveal()
        let popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: FolderStackView(folder: url))
        popover.contentSize = NSSize(width: 370, height: 410); folderPopover = popover
        popover.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
    }
    func updateProfileMenu() {
        guard let menu = statusItem?.menu else { return }
        for item in menu.items where item.tag == 302 { menu.removeItem(item) }
        let spaceGroup = NSMenuItem(title: L("Пространства"), action: nil, keyEquivalent: ""); spaceGroup.tag = 302
        let spaceMenu = NSMenu()
        for (index, space) in model.spaces.enumerated() {
            spaceMenu.addItem(ActionMenuItem(space.name + (index < 9 ? "  ⌃⌥\(index + 1)" : ""), checked: space.id == model.selectedSpaceID) { [weak self] in self?.model.selectSpace(space.id) })
        }
        spaceGroup.submenu = spaceMenu; menu.insertItem(spaceGroup, at: min(4, menu.numberOfItems))
        for item in menu.items where item.tag == 300 { menu.removeItem(item) }
        if !model.profiles.isEmpty {
            let group = NSMenuItem(title: L("Профили панели"), action: nil, keyEquivalent: ""); group.tag = 300
            let submenu = NSMenu()
            for profile in model.profiles { let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: ""); item.target = self; item.representedObject = profile; submenu.addItem(item) }
            group.submenu = submenu; menu.insertItem(group, at: min(4, menu.numberOfItems))
        }
    }
    @objc func selectProfile(_ sender: NSMenuItem) { if let profile = sender.representedObject as? DockProfile { model.applyProfile(profile) } }
    func closePopovers() { musicPopover?.close(); calendarPopover?.close(); collectionPopover?.close(); folderPopover?.close() }
    @objc func handleActivation(_ notification: Notification) { showSettings() }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        if let desktopObserver { NSWorkspace.shared.notificationCenter.removeObserver(desktopObserver) }
        for id in spaceHotKeys { HotKeys.shared.unregister(id) }
        if ownsSession { dock.restore() }
        DistributedNotificationCenter.default().removeObserver(self)
    }
    @objc func showLauncher() {
        if searchPanel?.isVisible == true { searchPanel?.orderOut(nil); return }
        closePopovers(); catalog.refresh()
        if searchPanel == nil {
            let window = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 590, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true; window.level = .floating; window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false; searchPanel = window
        }
        searchPanel?.contentView = NSHostingView(rootView: QuickLauncherView(model: model, catalog: catalog, close: { [weak self] in self?.searchPanel?.orderOut(nil) }))
        searchPanel?.center(); NSApp.activate(ignoringOtherApps: true); searchPanel?.makeKeyAndOrderFront(nil)
    }
    @objc func reveal() { if !model.barVisible { model.barVisible = true }; hidden = false; hoverDeadline = Date().addingTimeInterval(3); updatePanel(); panel.orderFrontRegardless() }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 990, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Panopticon"; window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.075, green: 0.085, blue: 0.1, alpha: 1)
            window.contentView = NSHostingView(rootView: SettingsView(model: model, dock: dock, focus: focus, catalog: catalog, agenda: agenda)); window.minSize = NSSize(width: 920, height: 680)
            window.setFrameAutosaveName("Panopticon.Settings"); window.isReleasedWhenClosed = false; window.delegate = self
            if !window.setFrameUsingName("Panopticon.Settings") { window.center() }; settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

func runSelfTests() {
    let suite = "app.panopticon.selftest.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set([String](), forKey: "pinned")
    let model = BarModel(defaults: defaults, observe: false)
    let paths = ["/System/Library/CoreServices/Finder.app", "/System/Applications/Music.app", "/System/Applications/Calendar.app"]
    for path in paths { model.add(URL(fileURLWithPath: path)) }
    precondition(model.pinned.count == 3, "App validation / insertion")
    model.add(URL(fileURLWithPath: paths[0])); precondition(model.pinned.count == 3, "Deduplication")
    model.add(URL(fileURLWithPath: "/private/tmp/not-an-app.txt")); precondition(model.pinned.count == 3, "Reject invalid drop")
    model.move(paths[0], to: 3); precondition(model.pinned.map(\.id) == [paths[1], paths[2], paths[0]], "Move right")
    model.move(paths[0], to: 0); precondition(model.pinned.map(\.id) == paths, "Move left")
    model.move(paths[1], to: 2); precondition(model.pinned.map(\.id) == paths, "Adjacent insertion is no-op")
    model.move(paths[0], to: 999); precondition(model.pinned.last?.id == paths[0], "Clamp boundary")
    model.iconSize = 52; model.widget = "music"
    let restored = BarModel(defaults: defaults, observe: false)
    precondition(restored.pinned == model.pinned && restored.iconSize == 52 && restored.widget == "music", "Persistence")
    model.remove(model.pinned[0]); precondition(model.pinned.count == 2, "Remove")
    model.widgetWidth = 212; model.widgetAccent = "mint"; model.widgetStyle = "compact"
    model.clockSeconds = true; model.replaceDock = false; model.hoverStyle = "scale"
    let group = AppCollection(name: L("Работа"), paths: paths)
    model.updateCollection(group)
    var updated = group; updated.name = L("Фокус"); updated.paths.removeLast()
    model.updateCollection(updated)
    precondition(model.collections.count == 1 && model.collections[0] == updated, "Collection edit")
    let reloaded = BarModel(defaults: defaults, observe: false)
    precondition(reloaded.collections == [updated] && reloaded.widgetWidth == 212 && reloaded.clockSeconds && !reloaded.replaceDock && reloaded.widgetAccent == "mint" && reloaded.widgetStyle == "compact" && reloaded.hoverStyle == "scale", "Detailed settings persistence, collections, widget configuration, focus timer")
    model.removeCollection(group.id); precondition(model.collections.isEmpty, "Collection deletion")
    let focus = FocusTimer(defaults: defaults); focus.reset(minutes: 5); precondition(focus.text == "05:00", "Timer duration")
    focus.toggle(minutes: 5); precondition(focus.isRunning, "Timer start")
    focus.toggle(minutes: 5); precondition(!focus.isRunning && focus.remaining <= 300, "Timer pause")
    focus.reset(minutes: 25); precondition(focus.remaining == 1500 && !focus.isRunning, "Timer reset")
    let appURL = URL(fileURLWithPath: paths[1])
    precondition(ActionRouter.calendarTarget(kind: "app", appPath: paths[1], webURL: "") == .application(appURL), "Custom calendar app")
    precondition(ActionRouter.calendarTarget(kind: "app", appPath: "/private/tmp/missing.app", webURL: "") == nil, "Missing calendar app")
    precondition(ActionRouter.calendarTarget(kind: "web", appPath: "", webURL: "https://calendar.google.com") == .resource(URL(string: "https://calendar.google.com")!), "Web calendar")
    precondition(ActionRouter.calendarTarget(kind: "web", appPath: "", webURL: "javascript:alert(1)") == nil, "Calendar URL validation")
    precondition(!model.addQuickLink(name: "", kind: "web", destination: "https://example.com"), "Empty link label")
    precondition(!model.addQuickLink(name: "Unsafe", kind: "web", destination: "file:///etc/passwd"), "Only web protocols for sites")
    precondition(model.addQuickLink(name: "Example", kind: "web", destination: "https://example.com"), "Add website link")
    precondition(!model.addQuickLink(name: "Duplicate", kind: "web", destination: "https://example.com"), "Website deduplication")
    precondition(model.addQuickLink(name: "Temp", kind: "folder", destination: "/private/tmp"), "Add folder link")
    model.secondaryWidget = "calendar"; precondition(model.widgetKinds == ["music", "calendar"], "Two distinct widgets")
    model.secondaryWidget = "music"; precondition(model.widgetKinds == ["music"], "Duplicate widgets collapse")
    model.secondaryWidget = "calendar"
    model.calendarDestination = "web"; model.calendarWebURL = "https://calendar.google.com"
    model.calendarEventsEnabled = true; model.selectedCalendarIDs = ["test-calendar"]; model.launcherEnabled = false
    model.applyPreset("aurora")
    model.saveProfile(name: L("Работа"))
    precondition(model.profiles.count == 1, "Create profile")
    let savedProfile = model.profiles[0]
    let before = ProfileAppearance(model)
    var notifications = 0; model.onChange = { notifications += 1 }
    model.applyPreset("electric"); precondition(notifications == 1, "Preset saves atomically")
    model.quickLinks = []; model.pinned = []; model.applyProfile(savedProfile)
    precondition(ProfileAppearance(model) == before && model.quickLinks.count == 2 && !model.pinned.isEmpty, "Profile restores layout and actions")
    precondition(model.calendarWebURL == "https://calendar.google.com" && !model.replaceDock, "Profile preserves external integrations")
    let settings = BarModel(defaults: defaults, observe: false)
    precondition(settings.profiles == model.profiles && settings.quickLinks == model.quickLinks && settings.secondaryWidget == "calendar" && settings.calendarDestination == "web" && settings.selectedCalendarIDs == ["test-calendar"] && settings.calendarEventsEnabled && !settings.launcherEnabled, "New feature persistence")
    model.removeQuickLink(model.quickLinks[0].id); precondition(model.quickLinks.count == 1, "Remove quick link")
    model.deleteProfile(savedProfile.id); precondition(model.profiles.isEmpty, "Delete profile")
    precondition(AppCatalog.searchScore("SAF", in: "Safari") == 0 && AppCatalog.searchScore("vsc", in: "Visual Studio Code") != nil && AppCatalog.searchScore("zzz", in: "Safari") == nil, "Launcher search ranking")
    do { try runRegressionTests(defaults: defaults, model: model) } catch { preconditionFailure("Regression test failed: \(error)") }
    do { try runIntegrationTests() } catch { preconditionFailure("Integration test failed: \(error)") }
    defaults.removePersistentDomain(forName: suite)
    print("PASS: app validation, reorder, persistence, collections, timer, calendar routing, link validation, two widgets, profiles, atomic preset changes, launcher search")
}

if CommandLine.arguments.contains("--self-test") {
    runLocalizationTests()
    for language in [AppLanguage.english, .russian] {
        Localization.shared.withTemporaryLanguage(language) { runSelfTests() }
    }
}
else if CommandLine.arguments.contains("--panel-self-test") { runPanelSelfTests() }
else if CommandLine.arguments.contains("--diagnostics") {
    for instance in NSWorkspace.shared.runningApplications where instance.bundleIdentifier == AppIdentity.preferencesDomain {
        print("Panopticon pid=\(instance.processIdentifier) terminated=\(instance.isTerminated) path=\(instance.bundleURL?.path ?? "unknown")")
    }
}
else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
