import AppKit
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    lazy var model = BarModel.shared
    lazy var music = MusicController()
    lazy var focus = FocusTimer()
    lazy var dock = DockIntegration()
    lazy var agenda = CalendarController()
    lazy var catalog = AppCatalog()
    private var applicationID: String { Bundle.main.bundleIdentifier ?? "app.newmacbar.desktop" }
    private var ownsSession = false
    private let session = SessionLifecycle()
    private let badgePoller = BadgePoller()
    private var appearanceObservation: NSKeyValueObservation?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var pendingScreen: Int?
    private var pendingScreenSince = Date.distantPast
    var lastShortcutChoice = ""
    var globalShortcut: GlobalShortcut?
    var searchPanel: SearchPanel?
    private var launcherPreviousApp: NSRunningApplication?
    var calendarPopover: NSPopover?
    var lastAgendaConfig = ""
    var lastMusicPoll = Date.distantPast
    var lastClockStamp = ""
    var lastPulseAutoHide: Bool?
    var lastReplaceDock: Bool?
    var lastTimerMinutes: Double = 25
    var collectionPopover: NSPopover?
    var dockWindow: DockWindowController!
    var panel: BarPanel! { dockWindow?.panel }
    var bar: BarView!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var musicPopover: NSPopover?
    var focusPopover: NSPopover?
    var timer: Timer?
    var hidden: Bool { dockWindow?.hidden ?? false }
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
        let activation = NSNotification.Name("app.newmacbar.desktop.showPreferences")
        let instances = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == applicationID && !$0.isTerminated
        }
        let winner = instances.min { a, b in
            let first = a.launchDate ?? .distantFuture
            let second = b.launchDate ?? .distantFuture
            return first == second ? a.processIdentifier < b.processIdentifier : first < second
        }
        if let existing = winner, existing.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            existing.activate(options: [.activateAllWindows])
            DistributedNotificationCenter.default().postNotificationName(
                activation, object: applicationID, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        guard session.claim() else {
            if let error = session.claimError {
                let alert = NSAlert(); alert.messageText = L("Panopticon не удалось запустить"); alert.informativeText = error; alert.runModal()
            } else {
                DistributedNotificationCenter.default().postNotificationName(activation, object: applicationID, userInfo: nil, deliverImmediately: true)
            }
            NSApp.terminate(nil); return
        }
        ownsSession = true
        PerformanceProbe.startIfRequested()
        let needsOnboarding =
            !UserDefaults.standard.bool(forKey: "ui.onboardingCompleted")
            && UserDefaults.standard.object(forKey: "layoutVersion") == nil
        session.begin()
        dock.prepareRecovery()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleRestoreRequest(_:)), name: SessionLifecycle.restoreNotification,
            object: applicationID)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleVisibilityRequest(_:)), name: DockVisibilityDiagnostics.request,
            object: applicationID)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleActivation(_:)), name: activation,
            object: applicationID)
        lastTimerMinutes = model.timerMinutes
        if UserDefaults.standard.dictionary(forKey: "focusSession") == nil {
            focus.reset(minutes: model.timerMinutes)
        }
        if UserDefaults.standard.integer(forKey: "layoutVersion") < 2 {
            model.iconSize = 36
            model.iconSpacing = 8
            model.bottomOffset = 4
            model.cornerRadius = 20
            model.magnification = 1.35
            model.opacity = 0.08
            UserDefaults.standard.set(2, forKey: "layoutVersion")
        }
        if CommandLine.arguments.contains("--native-dock") {
            model.batch {
                model.importDock()
                model.applyNativeDockStyle()
            }
        }
        rebuildApplicationMenu()
        bar = BarView(model: model, music: music, focus: focus, agenda: agenda)
        dockWindow = DockWindowController(model: model, bar: bar)
        bar.openFolder = { [weak self] url, rect in self?.showFolder(url, rect: rect) }
        for (index, key) in HotKeys.digitKeys.enumerated() {
            if let id = HotKeys.shared.register(
                key,
                handler: { [weak self] in
                    guard let self, index < self.model.spaces.count else { return }
                    self.model.selectSpace(self.model.spaces[index].id)
                    self.reveal()
                })
            {
                spaceHotKeys.append(id)
            }
        }
        if let id = HotKeys.shared.register(
            kVK_ANSI_D,
            handler: { [weak self] in
                guard let self else { return }
                self.model.barVisible.toggle()
            })
        {
            spaceHotKeys.append(id)
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .openBarSettings, object: nil, queue: .main
        ) { [weak self] _ in self?.showSettings() }
        for (key, delta) in [(kVK_LeftArrow, -1), (kVK_RightArrow, 1)] {
            if let id = HotKeys.shared.register(
                key, handler: { [weak self] in self?.model.cycleSpace(delta) })
            {
                spaceHotKeys.append(id)
            }
        }
        desktopObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateDesktop() }
        bar.openSettings = { [weak self] in self?.showSettings() }
        bar.openFocus = { [weak self] rect in self?.showFocus(rect) }
        bar.openAgenda = { [weak self] rect in self?.showAgenda(rect) }
        agenda.onChange = { [weak self] in self?.bar.needsDisplay = true }
        bar.openMusic = { [weak self] rect in self?.showMusic(rect) }
        model.onChange = { [weak self] in self?.preferencesChanged() }
        bar.openCollection = { [weak self] collection, rect in self?.showCollection(collection, rect) }
        focus.onChange = { [weak self] in self?.bar.needsDisplay = true }
        music.onChange = { [weak self] in self?.bar.needsDisplay = true }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: "Panopticon")
        rebuildStatusMenu()
        languageObserver = NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.languageChanged()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updatePanel() }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            lifecycleObservers.append(
                NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    self?.dockWindow?.resume()
                    self?.updateDesktop()
                })
        }
        lifecycleObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.closePopovers()
                self?.dockWindow?.stop()
            })
        preferencesChanged()
        updateDesktop()
        // A nil view hit-test cannot forward a click to another application.
        // Update the window itself when the pointer crosses its transparent margin.
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.dockWindow?.pointerEvent(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.dockWindow?.pointerEvent(event)
            return event
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.bar.refresh() }
        }
        configurePulse()
        updateMousePassthrough()
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.agenda.refresh(force: true)
                self?.bar.refresh()
            })
        lifecycleObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil,
                queue: .main
            ) { [weak self] _ in self?.updatePanel() })
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(forName: .openBarLauncher, object: nil, queue: .main) {
                [weak self] _ in self?.showLauncher()
            })
        if ProcessInfo.processInfo.arguments.contains("--settings") || dock.recoveryPending {
            showSettings()
        } else if needsOnboarding {
            showOnboarding()
        }
    }
    var screen: NSScreen? { dockWindow?.screen }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func updatePanel(animated: Bool = false) {
        dockWindow?.update(animated: animated)

    }
    func updateMousePassthrough() { dockWindow?.updatePassthrough() }
    func updateDesktop() { model.desktopChanged(Desktops.current(for: screen)?.number) }
    func configurePulse() {
        let frequent = model.barVisible && (model.autoHide || model.followMouse || dockWindow?.requiresOverviewPolling == true)
        guard lastPulseAutoHide != frequent else { return }
        lastPulseAutoHide = frequent
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: frequent ? 0.1 : 1, repeats: true) { [weak self] _ in
            self?.pulse()
        }
        timer?.tolerance = frequent ? 0.02 : 0.15
    }
    func pulse() {
        let now = Date()
        if now.timeIntervalSince(lastBadgesPoll) >= 3 {
            lastBadgesPoll = now
            badgePoller.refresh(enabled: model.showBadges && model.barVisible) { [weak self] badges in
                guard let self, self.model.badges != badges else { return }
                self.model.badges = badges
                self.bar.needsDisplay = true
            }
        }
        let popupOpen =
            focusPopover?.isShown == true || musicPopover?.isShown == true || calendarPopover?.isShown == true
            || collectionPopover?.isShown == true || folderPopover?.isShown == true
        if model.followMouse && !popupOpen && !bar.hasActiveDrag && NSEvent.pressedMouseButtons == 0,
            let index = NSScreen.screens.firstIndex(where: { $0.frame.contains(NSEvent.mouseLocation) }),
            index != model.screenIndex
        {
            if pendingScreen != index {
                pendingScreen = index
                pendingScreenSince = now
            }
            if now.timeIntervalSince(pendingScreenSince) >= 0.35 {
                model.screenIndex = index
                pendingScreen = nil
                updateDesktop()
            }
        } else {
            pendingScreen = nil
        }
        guard model.barVisible else { return }
        if model.widgetKinds.contains("music"), !hidden || musicPopover?.isShown == true,
            now.timeIntervalSince(lastMusicPoll) >= (musicPopover?.isShown == true ? 1 : 4)
        {
            lastMusicPoll = now
            music.refresh()
        }
        if model.calendarEventsEnabled { agenda.refresh() }
        let timestamp = String(
            Int(now.timeIntervalSince1970) / (model.clockSeconds || focus.isRunning ? 1 : 60))
        if !hidden && timestamp != lastClockStamp {
            lastClockStamp = timestamp
            bar.needsDisplay = true
        }
        let busy =
            focusPopover?.isShown == true
            || musicPopover?.isShown == true
            || collectionPopover?.isShown == true || calendarPopover?.isShown == true
            || folderPopover?.isShown == true
        dockWindow?.tick(keepVisible: busy, now: now)
        configurePulse()
    }

    func showFocus(_ rect: NSRect) {
        closePopovers()
        reveal()
        if focusPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(
                rootView: FocusPopoverView(focus: focus, model: model))
            popover.contentSize = NSSize(width: 340, height: 440)
            focusPopover = popover
        }
        if let focusPopover {
            constrainPopover(focusPopover)
            focusPopover.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
        }
    }
    func showAgenda(_ rect: NSRect) {
        closePopovers()
        reveal()
        if calendarPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(
                rootView: CalendarPopoverView(agenda: agenda, model: model))
            popover.contentSize = NSSize(width: 380, height: 600)
            calendarPopover = popover
        }
        if let calendarPopover { constrainPopover(calendarPopover) }
        calendarPopover?.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
    }
    func showMusic(_ rect: NSRect) {
        closePopovers()
        reveal()
        if musicPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: MusicPopoverView(music: music))
            popover.contentSize = NSSize(width: 370, height: 340)
            musicPopover = popover
        }
        music.refresh(force: true)
        if let musicPopover { constrainPopover(musicPopover) }
        musicPopover?.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
    }
    func preferencesChanged() {
        music.preference = model.playerPreference
        configurePulse()
        if model.launcherEnabled
            && (globalShortcut == nil || lastShortcutChoice != model.launcherShortcutChoice)
        {
            globalShortcut = nil
            lastShortcutChoice = model.launcherShortcutChoice
            globalShortcut = GlobalShortcut(choice: model.launcherShortcutChoice) { [weak self] in
                self?.showLauncher()
            }
            model.launcherShortcutAvailable = globalShortcut?.registered == true
        }
        if !model.launcherEnabled {
            globalShortcut = nil
            model.launcherShortcutAvailable = false
        }
        statusItem?.menu?.item(withTag: 301)?.title =
            L("Быстрый поиск…  ")
            + (model.launcherEnabled && model.launcherShortcutAvailable ? model.launcherShortcutLabel : "")
        let agendaConfig = "\(model.calendarEventsEnabled)-\(model.selectedCalendarIDs.sorted())"
        agenda.enabled = model.calendarEventsEnabled
        agenda.selectedIDs = model.selectedCalendarIDs
        if agendaConfig != lastAgendaConfig {
            lastAgendaConfig = agendaConfig
            agenda.refresh(force: true)
        }
        if lastReplaceDock != model.replaceDock {
            lastReplaceDock = model.replaceDock
            if model.replaceDock {
                model.importSystemDockIfNeeded()
                if !dock.recoveryPending && !dock.enable() { model.replaceDock = false }
            } else {
                dock.restore()
            }
        }
        if lastTimerMinutes != model.timerMinutes {
            lastTimerMinutes = model.timerMinutes
            focus.prepareNextSession(minutes: model.timerMinutes)
        }
        updateProfileMenu()
        updatePanel()
    }
    func showCollection(_ collection: AppCollection, _ rect: NSRect) {
        closePopovers()
        reveal()
        collectionPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: CollectionPopoverView(collection: collection, model: model))
        popover.contentSize = NSSize(width: 330, height: 270)
        collectionPopover = popover
        constrainPopover(popover)
        popover.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
    }
    func showFolder(_ url: URL, rect: NSRect) {
        closePopovers()
        reveal()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: FolderStackView(folder: url))
        popover.contentSize = NSSize(width: 400, height: 480)
        folderPopover = popover
        constrainPopover(popover)
        popover.show(relativeTo: rect, of: bar, preferredEdge: model.dockEdge.popoverEdge)
    }
    func constrainPopover(_ popover: NSPopover) {
        guard let screen else { return }
        let size = popover.contentSize
        popover.contentSize = NSSize(
            width: min(size.width, max(200, screen.visibleFrame.width - 32)),
            height: min(size.height, max(200, screen.visibleFrame.height - 32)))
    }
    func rebuildApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let preferences = NSMenuItem(title: L("Настройки…"), action: #selector(showSettings), keyEquivalent: ",")
        preferences.target = self
        appMenu.addItem(preferences)
        let search = NSMenuItem(title: L("Быстрый поиск…"), action: #selector(showLauncher), keyEquivalent: "k")
        search.target = self
        appMenu.addItem(search)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L("Завершить Panopticon"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        ApplicationMenus.addEditing(to: mainMenu)
        NSApp.mainMenu = mainMenu
    }
    func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Panopticon — бесплатно"), action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(
            withTitle: L("Настройки…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let statusSearch = menu.addItem(
            withTitle: L("Быстрый поиск…  ⌃⌥Пробел"), action: #selector(showLauncher), keyEquivalent: "")
        statusSearch.target = self
        statusSearch.tag = 301
        let show = menu.addItem(withTitle: L("Показать панель"), action: #selector(reveal), keyEquivalent: "")
        show.target = self
        let restore = menu.addItem(
            withTitle: L("Вернуть системный Dock"), action: #selector(restoreSystemDock), keyEquivalent: "")
        restore.target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L("Завершить"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        updateProfileMenu()
        statusItem?.menu?.item(withTag: 301)?.title = L("Быстрый поиск…  ") + (model.launcherEnabled && model.launcherShortcutAvailable ? model.launcherShortcutLabel : "")
    }
    func languageChanged() {
        rebuildApplicationMenu(); rebuildStatusMenu()
        onboardingWindow?.title = L("Добро пожаловать в Panopticon")
        dock.relocalizeStatus(); agenda.message = Localization.shared.status(agenda.message)
        music.relocalizeStatus(); bar.refresh()
    }
    func updateProfileMenu() {
        guard let menu = statusItem?.menu else { return }
        for item in menu.items where item.tag == 302 { menu.removeItem(item) }
        let spaceGroup = NSMenuItem(title: L("Пространства"), action: nil, keyEquivalent: "")
        spaceGroup.tag = 302
        let spaceMenu = NSMenu()
        for (index, space) in model.spaces.enumerated() {
            spaceMenu.addItem(
                ActionMenuItem(
                    space.name + (index < 9 ? "  ⌃⌥\(index + 1)" : ""),
                    checked: space.id == model.selectedSpaceID
                ) { [weak self] in self?.model.selectSpace(space.id) })
        }
        spaceGroup.submenu = spaceMenu
        menu.insertItem(spaceGroup, at: min(4, menu.numberOfItems))
        for item in menu.items where item.tag == 300 { menu.removeItem(item) }
        if !model.profiles.isEmpty {
            let group = NSMenuItem(title: L("Профили панели"), action: nil, keyEquivalent: "")
            group.tag = 300
            let submenu = NSMenu()
            for profile in model.profiles {
                let item = NSMenuItem(
                    title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile
                submenu.addItem(item)
            }
            group.submenu = submenu
            menu.insertItem(group, at: min(4, menu.numberOfItems))
        }
    }
    @objc func selectProfile(_ sender: NSMenuItem) {
        if let profile = sender.representedObject as? DockProfile { model.applyProfile(profile) }
    }
    func closePopovers() {
        focusPopover?.close()
        musicPopover?.close()
        calendarPopover?.close()
        collectionPopover?.close()
        folderPopover?.close()
    }
    @objc func handleActivation(_ notification: Notification) { showSettings() }
    @objc func handleRestoreRequest(_ notification: Notification) {
        restoreSystemDock()
        if let token = notification.userInfo?["token"] as? String {
            DistributedNotificationCenter.default().postNotificationName(SessionLifecycle.restoredNotification, object: applicationID, userInfo: ["token": token, "success": !dock.hasBackup], deliverImmediately: true)
        }
    }
    @objc private func handleVisibilityRequest(_ notification: Notification) {
        guard ownsSession, let token = notification.userInfo?["token"] as? String,
            UUID(uuidString: token) != nil, let snapshot = dockWindow?.diagnosticState else { return }
        DistributedNotificationCenter.default().postNotificationName(
            DockVisibilityDiagnostics.response, object: applicationID,
            userInfo: ["token": token, "snapshot": snapshot], deliverImmediately: true)
    }
    @objc func restoreSystemDock() {
        model.replaceDock = false
        dock.restore()
        updatePanel()
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        if let desktopObserver { NSWorkspace.shared.notificationCenter.removeObserver(desktopObserver) }
        for id in spaceHotKeys { HotKeys.shared.unregister(id) }
        dockWindow?.stop()
        badgePoller.stop(); appearanceObservation = nil
        for observer in lifecycleObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        if ownsSession {
            dock.restore()
            session.finish()
        }
        DistributedNotificationCenter.default().removeObserver(self)
    }
    @objc func showLauncher() {
        if searchPanel?.isVisible == true { closeLauncher(); return }
        closePopovers()
        let front = NSWorkspace.shared.frontmostApplication
        launcherPreviousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
        catalog.refresh()
        if searchPanel == nil {
            let window = SearchPanel(
                contentRect: NSRect(x: 0, y: 0, width: 590, height: 420), styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .floating
            window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.onClose = { [weak self] in self?.closeLauncher() }
            searchPanel = window
        }
        searchPanel?.contentView = NSHostingView(
            rootView: QuickLauncherView(
                model: model, catalog: catalog, close: { [weak self] in self?.closeLauncher() }))
        if let target = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? screen
        {
            let area = target.visibleFrame
            searchPanel?.setFrame(
                NSRect(
                    x: area.midX - min(590, area.width - 32) / 2,
                    y: area.midY - min(460, area.height - 40) / 2,
                    width: min(590, area.width - 32), height: min(460, area.height - 40)), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        searchPanel?.makeKeyAndOrderFront(nil)
    }
    func closeLauncher() {
        searchPanel?.orderOut(nil)
        let previous = launcherPreviousApp; launcherPreviousApp = nil
        if let previous, !previous.isTerminated { previous.activate(options: []) }
    }
    @objc func reveal() {
        if !model.barVisible { model.barVisible = true }
        dockWindow?.reveal()
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
            )
            window.title = "Panopticon"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .windowBackgroundColor
            let host = NSHostingView(
                rootView: SettingsView(
                    model: model, dock: dock, focus: focus, catalog: catalog, agenda: agenda))
            host.sizingOptions = []
            window.contentView = host
            window.contentMinSize = NSSize(width: 760, height: 540)
            window.setFrameAutosaveName("Panopticon.Settings")
            window.isReleasedWhenClosed = false
            window.delegate = self
            if !window.setFrameUsingName("Panopticon.Settings") { window.center() }
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 600), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = L("Добро пожаловать в Panopticon")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    model: model, agenda: agenda, dock: dock, login: LoginService(), ui: .shared,
                    onFinish: { [weak self] in self?.onboardingWindow?.orderOut(nil) }))
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
