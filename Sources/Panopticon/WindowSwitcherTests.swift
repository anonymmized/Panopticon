import AppKit

func runRevealAndWindowSwitcherTests() {
    let suite = "app.panopticon.windows-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["/System/Library/CoreServices/Finder.app"], forKey: "pinned")
    let model = BarModel(defaults: defaults, observe: false, systemDockProvider: { [] })
    model.batch { model.showRunning = false; model.autoHide = true; model.motionMode = "full" }
    precondition(model.showWindowSwitcher, "Existing settings default to window selection")
    model.showWindowSwitcher = false
    precondition(!BarModel(defaults: defaults, observe: false).showWindowSwitcher, "Window preference persists")
    model.showWindowSwitcher = true
    let bar = BarView(model: model, music: MusicController(), focus: FocusTimer(defaults: defaults), agenda: CalendarController())
    var overview = false
    let dock = DockWindowController(model: model, bar: bar, overviewActive: { overview })
    defer { dock.stop() }
    for edge in DockEdge.allCases {
        model.edge = edge.rawValue
        dock.stop(); dock.update()
        let placement = dock.placement!
        dock.reveal()
        precondition(dock.panel.frame == placement.hidden && dock.isTransitioning, "Reveal starts behind \(edge): actual \(dock.panel.frame), expected \(placement.hidden), moving \(dock.isTransitioning)")
        dock.advanceTransition(at: ProcessInfo.processInfo.systemUptime + 0.14)
        let mid = dock.panel.frame
        precondition(mid != placement.hidden && mid != placement.shown && dock.isTransitioning,
            "Reveal must render an intermediate frame instead of jumping")
        dock.advanceTransition(at: ProcessInfo.processInfo.systemUptime + 1)
        precondition(dock.panel.frame == placement.shown && !dock.isTransitioning, "Reveal settles and stops its timer")
        let outside = NSPoint(x: -100_000, y: -100_000)
        dock.tick(keepVisible: false, now: Date().addingTimeInterval(5), mouseLocation: outside, buttonsPressed: false)
        dock.advanceTransition(at: ProcessInfo.processInfo.systemUptime + 0.1)
        let retreat = dock.panel.frame
        precondition(dock.hidden && retreat != placement.shown && retreat != placement.hidden, "Hide also slides through intermediate frames")
        dock.reveal()
        precondition(dock.panel.frame == retreat, "Reversing a hide preserves the current visible position")
        dock.advanceTransition(at: ProcessInfo.processInfo.systemUptime + 1)
        precondition(dock.panel.frame == placement.shown, "A reversed transition settles at the correct edge")
        overview = true; dock.update(animated: true)
        precondition(!dock.panel.isVisible && !dock.isTransitioning, "Mission Control suppresses presentation immediately")
        overview = false
    }
    let visible = NSRect(x: -1400, y: 300, width: 1400, height: 850)
    for edge in DockEdge.allCases {
        for anchor in [NSRect(x: -1390, y: 310, width: 40, height: 40), NSRect(x: -50, y: 1090, width: 40, height: 40)] {
            precondition(visible.contains(WindowSwitcherController.frame(anchor: anchor,
                size: NSSize(width: 340, height: 430), edge: edge, visible: visible)), "Window list stays on an offset display")
        }
    }
    let small = NSRect(x: 0, y: 0, width: 300, height: 230)
    precondition(small.contains(WindowSwitcherController.frame(anchor: .zero, size: NSSize(width: 340, height: 430), edge: .bottom, visible: small)), "Window list fits small screens")
    dock.reveal(); dock.advanceTransition(at: ProcessInfo.processInfo.systemUptime + 1)
    let switcher = WindowSwitcherController(model: model, bar: bar, trusted: { false })
    if let item = model.pinned.first, model.runningApplication(for: item) != nil {
        switcher.showExplicit(item: item, anchor: bar.screenRect(bar.frames[0]))
        precondition(switcher.isShown && switcher.state.phase == .permission, "Missing access has an explicit enable state, never a permission prompt")
        precondition(!switcher.panel.canBecomeKey && !switcher.panel.canBecomeMain, "Window selection does not capture keyboard focus")
        precondition(switcher.retainsDock(at: NSPoint(x: switcher.panel.frame.midX, y: switcher.panel.frame.midY)), "Moving into the list retains the Dock")
        let originalSpace = model.selectedSpaceID
        precondition(model.addSpace(name: "Window test") != nil)
        switcher.validateContext()
        precondition(!switcher.isShown, "Switching spaces closes a stale app window list even when panel geometry is unchanged")
        model.selectSpace(originalSpace)
        switcher.showExplicit(item: item, anchor: bar.screenRect(bar.frames[0]))
        model.showWindowSwitcher = false
        switcher.update(at: NSEvent.mouseLocation, permitted: true, dragging: false)
        precondition(!switcher.isShown && switcher.panel.ignoresMouseEvents, "Disabling previews closes their hit target")
    }
    switcher.close()
    let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    var reads = 0, received = 0
    let service = WindowListService(read: { _, cancelled in
        reads += 1
        if reads == 1 { started.signal(); _ = release.wait(timeout: .now() + 2) }
        return cancelled() ? .failure(.unavailable) : .success([])
    })
    service.load(.current) { _ in preconditionFailure("An obsolete hover must not publish its window list") }
    precondition(started.wait(timeout: .now() + 2) == .success, "Worker runs without blocking the main queue")
    service.load(.current) { result in if case .success = result { received += 1 } }
    release.signal()
    let deadline = Date().addingTimeInterval(3)
    while received == 0 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(received == 1, "Only the latest asynchronous window query can publish")
    service.cancel()
    print("PASS: progressive four-edge reveal, reversal, overview priority, window-panel focus/placement, permission fallback and stale-query cancellation")
}
