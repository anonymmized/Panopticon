import AppKit

func runPlatformTests() {
    runDockVisibilityPolicyTests()
    let suite = "app.newmacbar.platformtest.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var commands: [[String]] = []
    let original: [String: Any] = ["autohide": false, "autohide-delay": 0.27]
    let dock = DockIntegration(defaults: defaults, readDomain: { original }) { executable, args in
        commands.append([executable] + args)
        return CommandResult(status: 0, output: "")
    }
    precondition(dock.enable() && dock.hasBackup, "Backup before replacement")
    let backup = defaults.dictionary(forKey: "systemDockBackup")! as NSDictionary
    precondition(
        dock.enable() && defaults.dictionary(forKey: "systemDockBackup")! as NSDictionary == backup,
        "Never overwrite backup")
    dock.prepareRecovery()
    precondition(dock.recoveryPending, "Interrupted-session recovery")
    commands.removeAll()
    precondition(dock.restore() && !dock.hasBackup && !dock.recoveryPending, "Restore session")
    precondition(
        commands.contains { $0.suffix(3) == ["autohide", "-bool", "false"] }, "Exact original boolean")
    precondition(
        commands.contains { $0.suffix(3) == ["autohide-delay", "-float", "0.27"] }, "Exact original number")
    precondition(
        commands.contains { $0.suffix(3) == ["delete", "com.apple.dock", "autohide-time-modifier"] },
        "Restore absent key")
    for invalid: Any in [
        ["autohide": true], ["autohide": true, "autohide-delay": "bad", "autohide-time-modifier": 0], "bad",
    ] {
        defaults.set(invalid, forKey: "systemDockBackup")
        commands.removeAll()
        precondition(
            !dock.enable() && !dock.restore() && commands.isEmpty && dock.hasBackup,
            "Corrupt backup must not modify system preferences")
    }
    defaults.removeObject(forKey: "systemDockBackup")
    let rollback = DockIntegration(defaults: defaults, readDomain: { original }) { _, args in
        CommandResult(status: args.contains("3600") ? 1 : 0, output: "")
    }
    precondition(!rollback.enable() && !rollback.hasBackup, "Failed enable rolls back original preferences")
    let lockDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("newmacbar-lock-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: lockDirectory) }
    let lock = lockDirectory.appendingPathComponent("session.lock")
    let firstOwner = SessionLifecycle(defaults: defaults, lockURL: lock)
    let contender = SessionLifecycle(defaults: defaults, lockURL: lock)
    precondition(firstOwner.claim() && !contender.claim(), "Only one process may own the session lock")
    firstOwner.finish(); precondition(contender.claim(), "Kernel lock is reusable after owner finishes"); contender.finish()
    let session = SessionLifecycle(defaults: defaults, lockURL: lock)
    precondition(!session.begin() && session.begin(), "Session detects unclean termination")
    session.finish()
    precondition(!session.begin(), "Normal exit clears session")
    session.finish()

    for screen in [
        NSRect(x: 0, y: 0, width: 1512, height: 982), NSRect(x: -1920, y: 400, width: 1920, height: 1080),
        NSRect(x: 0, y: 0, width: 320, height: 240),
    ] {
        let visible = NSRect(
            x: screen.minX, y: screen.minY + 60, width: screen.width, height: screen.height - 90)
        for edge in DockEdge.allCases {
            for content in [
                NSSize(width: 800, height: 180), NSSize(width: 2000, height: 3000),
                NSSize(width: CGFloat.nan, height: CGFloat.infinity),
            ] {
                let placement = PanelPlacement(
                    screen: screen, visible: visible, content: content, edge: edge, offset: 160,
                    reservesSystemDock: true)
                precondition(visible.contains(placement.shown), "Panel stays in usable display area")
                precondition(!screen.intersects(placement.hidden), "Hidden panel is wholly offscreen")
                precondition(
                    screen.intersects(placement.trigger), "Every edge has an on-screen reveal target")
            }
        }
    }
    let safe = PanelPlacement.usableFrame(screen: NSRect(x: 0, y: 0, width: 1512, height: 982), visible: NSRect(x: 0, y: 0, width: 1512, height: 982), insets: NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0))
    precondition(safe.maxY == 945, "Hidden menu bar must not put the panel under the camera area")
    let vertical = [NSRect(x: 10, y: 10, width: 40, height: 40), NSRect(x: 10, y: 50, width: 40, height: 40)]
    precondition(
        BarGeometry.nearest(NSPoint(x: 30, y: 52), frames: vertical) == 1,
        "Vertical overlap chooses nearest icon")
    print(
        "PASS: validated Dock backup, rollback, crash recovery, session lifecycle, four-edge display geometry"
    )
}

func runWindowControllerTests() {
    let suite = "app.newmacbar.windowtest.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = BarModel(defaults: defaults, observe: false)
    model.showRunning = false
    let bar = BarView(
        model: model, music: MusicController(), focus: FocusTimer(defaults: defaults),
        agenda: CalendarController())
    let controller = DockWindowController(model: model, bar: bar, overviewActive: { false })
    defer { controller.stop() }
    for edge in DockEdge.allCases {
        model.edge = edge.rawValue
        controller.reveal()
        precondition(
            !controller.panel.canBecomeKey && !controller.panel.canBecomeMain,
            "Reveal never captures keyboard")
        model.barVisible = false
        controller.update()
        RunLoop.main.run(until: Date().addingTimeInterval(0.26))
        precondition(
            !controller.panel.isVisible && controller.panel.ignoresMouseEvents,
            "Hidden panel cannot intercept clicks")
        model.barVisible = true
    }
    controller.stop()
    precondition(
        !controller.panel.isVisible && controller.panel.ignoresMouseEvents,
        "Stopped panel cannot intercept clicks")
    runInteractionTests()
    runNativeDockHoverTests()
    runDockVisibilityWindowTests()
    print("PASS: panel controller visibility, focus, teardown on every edge")
}

func runInteractionTests() {
    let suite = "app.newmacbar.interactiontest.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(
        ["/System/Library/CoreServices/Finder.app", "/System/Applications/Calendar.app"], forKey: "pinned")
    let model = BarModel(defaults: defaults, observe: false)
    model.showRunning = false
    model.showSpaces = true
    model.showTrash = true
    model.showSettingsButton = true
    model.widget = "clock"
    model.secondaryWidget = "calendar"
    model.batch {
        model.quickLinks = (0..<100).map {
            QuickLink(name: "Link \($0)", kind: "web", destination: "https://example.org/\($0)")
        }
    }
    let bar = BarView(
        model: model, music: MusicController(), focus: FocusTimer(defaults: defaults),
        agenda: CalendarController())
    let panel = BarPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    let root = PassthroughView()
    root.addSubview(bar.glass)
    root.addSubview(bar)
    panel.contentView = root
    defer { panel.orderOut(nil) }
    for edge in DockEdge.allCases {
        model.edge = edge.rawValue
        bar.availableLength = 320
        panel.setContentSize(NSSize(width: bar.preferredWidth, height: bar.preferredHeight))
        bar.frame = root.bounds
        bar.refresh()
        precondition(bar.bounds.contains(bar.barRect), "Overflow surface fits small display on every edge")
        let children = bar.accessibilityChildren() as! [BarAccessibilityButton]
        let more = children.first { $0.accessibilityLabel() == L("Все элементы и пространства") }
        precondition(more != nil, "Overflow is accessible")
        for element in children where element.accessibilityLabel()?.contains("Finder") == true {
            let rect = element.accessibilityFrame()
            precondition(
                min(rect.width, rect.height) >= model.iconSize * 0.9, "Overflow keeps icons readable")
        }
        let rect = more!.accessibilityFrame()
        let point = bar.convert(
            panel.convertPoint(fromScreen: NSPoint(x: rect.midX, y: rect.midY)), from: nil)
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown, location: bar.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let menu = bar.menu(for: event)!
        precondition(menu.items.contains { $0.title == "Link 99" }, "Every hidden shortcut remains reachable")
    }
    for available: CGFloat in [240, 320, 640] {
        for icon: Double in [28, 36, 60] {
            for spacing: Double in [4, 24] {
                model.batch { model.iconSize = icon; model.iconSpacing = spacing }
                for reduced in [true, false] {
                    let layout = PanelContentLayout(model: model, availableLength: available, reduceMotion: reduced)
                    precondition(layout.baseWidth + 8 <= available, "Overflow keeps controls within the display at every size")
                }
            }
        }
    }
    bar.availableLength = 900
    panel.setContentSize(NSSize(width: bar.preferredWidth, height: bar.preferredHeight)); bar.frame = root.bounds; bar.refresh()
    let clock = (bar.accessibilityChildren() as! [BarAccessibilityButton]).first { $0.accessibilityLabel() == L("Часы") }
    precondition((clock?.accessibilityValue() as? String)?.isEmpty == false, "VoiceOver receives the actual clock value")
    model.batch { model.widget = "none"; model.secondaryWidget = "none" }
    let noWidgets = BarModel(defaults: defaults, observe: false)
    precondition(noWidgets.widgetKinds.isEmpty, "Both disabled widgets reload without recursive didSet")
    let source = model.selectedSpaceID
    let target = model.spaces.first { $0.id != source }!.id
    let moved = model.quickLinks[0]
    precondition(
        PanelActions.moveLink(moved.id, toSpace: target, model: model), "Move shortcut across spaces")
    precondition(
        !model.quickLinks.contains(moved) && model.spaces.first { $0.id == target }!.links.contains(moved),
        "Shortcut transfer is lossless")
    precondition(!PanelActions.moveLink(moved.id, toSpace: target, model: model), "Reject stale drag payload")
    let group = AppCollection(name: "Test", paths: model.pinned.map(\.id))
    model.updateCollection(group)
    precondition(
        PanelActions.moveCollection(group.id, toSpace: target, model: model), "Move collection across spaces")
    precondition(
        !model.collections.contains(group)
            && model.spaces.first { $0.id == target }!.collections.contains(group),
        "Collection transfer is lossless")
    model.calendarAppPath = "/private/secret-user/Private Calendar.app"
    model.calendarWebURL = "https://secret-calendar.invalid"
    let report = LocalDiagnostics.report(
        model: model, dock: DockIntegration(defaults: defaults), agenda: CalendarController(),
        login: LoginService())
    precondition(
        !report.contains("secret-user") && !report.contains("secret-calendar") && !report.contains("Link 99"),
        "Diagnostics excludes user data")
    precondition(
        StableSelection.reconciled("b", in: ["c", "b", "a"]) == "b", "Async results preserve identity")
    precondition(
        StableSelection.reconciled("missing", in: []) == nil
            && StableSelection.moved("b", in: ["a", "b"], by: 1) == "b", "Selection bounds and empty state")
    precondition(
        SettingsSection.all.contains { SettingsSection.matches($0, query: L("размер иконки")) },
        "Settings search finds a control")
    let offlinePin = DockItem(url: URL(fileURLWithPath: "/Volumes/Disconnected/Example.app"))
    model.batch { model.pinned.insert(offlinePin, at: 0) }
    bar.removeAppWithUndo(offlinePin)
    precondition(!model.pinned.contains(offlinePin), "Remove an offline shortcut")
    bar.undoRemoval?()
    bar.undoRemoval?()
    precondition(model.pinned.first == offlinePin && model.pinned.filter { $0.id == offlinePin.id }.count == 1,
        "Undo restores offline pins in order without creating duplicates")
    runFolderPresentationTests()
    print(
        "PASS: readable four-edge overflow, hidden item access, link/collection transfer, stale payloads, diagnostics privacy, stable selection"
    )
}


func runFolderPresentationTests() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("newmacbar-folder-test-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0...FolderPresentationLoader.limit {
            _ = FileManager.default.createFile(atPath: directory.appendingPathComponent("File-\(index)").path, contents: Data())
        }
        let loader = FolderPresentationLoader()
        func awaitLoad() {
            let deadline = Date().addingTimeInterval(5)
            while loader.loading && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            precondition(!loader.loading, "Folder read must complete")
        }
        loader.load(directory); awaitLoad()
        precondition(loader.limited && loader.entries.count == FolderPresentationLoader.limit && loader.error.isEmpty, "Large folder exposes its limit")
        loader.load(directory)
        loader.load(directory.appendingPathComponent("missing", isDirectory: true)); awaitLoad()
        precondition(loader.entries.isEmpty && !loader.error.isEmpty, "Stale folder request cannot overwrite a missing-folder error")
        let empty = directory.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        loader.load(empty); awaitLoad()
        precondition(loader.entries.isEmpty && loader.error.isEmpty && !loader.limited, "Empty folder differs from unavailable folder")
        loader.load(directory)
        loader.cancel()
        precondition(!loader.loading, "Cancellation immediately releases the folder loading state")
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        precondition(loader.entries.isEmpty && !loader.loading, "A cancelled read cannot publish late contents")
        print("PASS: asynchronous folder limit, refresh, obsolete request rejection, missing and empty states")
    } catch { preconditionFailure("Disposable folder presentation test failed: \(error)") }
}
