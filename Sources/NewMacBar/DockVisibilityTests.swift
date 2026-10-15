import AppKit

func runDockVisibilityPolicyTests() {
    var policy = DockVisibilityPolicy(autoHide: true)
    precondition(policy.isHidden, "An autohidden Dock starts hidden")
    for i in 0..<300 {
        let now = Double(i)
        policy.configure(enabled: true, autoHide: true, now: now)
        policy.tick(now: now, nearEdge: false, inside: false, keepVisible: true,
            buttonsPressed: i % 2 == 0, dragging: false)
        precondition(policy.isHidden, "App activation, settings and arbitrary clicks cannot summon the Dock")
    }
    for now: Double in [300, 301, 302] {
        policy.tick(now: now, nearEdge: true, inside: false, keepVisible: false, buttonsPressed: true, dragging: false)
        precondition(policy.isHidden, "A held click is not an edge hover")
    }
    policy.tick(now: 303, nearEdge: true, inside: false, keepVisible: false, buttonsPressed: false, dragging: false)
    precondition(policy.isHidden, "The edge needs an intentional dwell")
    policy.tick(now: 303.1, nearEdge: true, inside: false, keepVisible: false, buttonsPressed: false, dragging: false)
    precondition(!policy.isHidden, "A genuine edge hover reveals the Dock")
    policy.tick(now: 303.2, nearEdge: false, inside: true, keepVisible: false, buttonsPressed: false, dragging: false)
    policy.tick(now: 303.3, nearEdge: false, inside: false, keepVisible: false, buttonsPressed: false, dragging: false)
    precondition(!policy.isHidden, "Moving between enlarged icons does not flicker")
    policy.tick(now: 303.6, nearEdge: false, inside: false, keepVisible: false, buttonsPressed: false, dragging: false)
    precondition(policy.isHidden, "The panel hides after the pointer leaves")
    policy.tick(now: 304, nearEdge: false, inside: false, keepVisible: true, buttonsPressed: false, dragging: false)
    precondition(policy.isHidden, "A visible settings window must never resurrect a hidden panel")
    policy.reveal(now: 305)
    policy.tick(now: 305.2, nearEdge: false, inside: false, keepVisible: false, buttonsPressed: false, dragging: false)
    precondition(!policy.isHidden, "An explicit menu command briefly reveals the panel")
    policy.tick(now: 306.1, nearEdge: false, inside: false, keepVisible: false, buttonsPressed: false, dragging: false)
    precondition(policy.isHidden, "An explicit reveal eventually expires")
    policy.reveal(now: 307)
    policy.setOverview(true, now: 307.1)
    policy.reveal(now: 307.2)
    precondition(policy.isHidden, "Mission Control takes priority over an explicit reveal")
    policy.setOverview(false, now: 308)
    for now: Double in [308, 309] {
        policy.tick(now: now, nearEdge: true, inside: false, keepVisible: true, buttonsPressed: false, dragging: false)
        precondition(policy.isHidden, "Exiting Mission Control cannot replay a stale edge hover")
    }
    policy.tick(now: 310, nearEdge: false, inside: false, keepVisible: false, buttonsPressed: false, dragging: false)
    policy.tick(now: 311, nearEdge: true, inside: false, keepVisible: false, buttonsPressed: true, dragging: true)
    precondition(policy.isHidden, "A drag has its own deliberate dwell")
    policy.tick(now: 311.3, nearEdge: true, inside: false, keepVisible: false, buttonsPressed: true, dragging: true)
    precondition(!policy.isHidden, "Files can still be dragged to the Dock")
    policy.suspend()
    policy.configure(enabled: true, autoHide: true, now: 312)
    precondition(policy.isHidden, "Wake and screen updates do not summon an autohidden Dock")
    policy.configure(enabled: true, autoHide: false, now: 313)
    precondition(!policy.isHidden, "An explicit always-visible setting still works")
    policy.setOverview(true, now: 314)
    precondition(policy.isHidden, "Always-visible mode also avoids a second Dock in Mission Control")
    policy.setOverview(false, now: 315)
    precondition(!policy.isHidden, "Always-visible mode resumes after Mission Control")
    policy.configure(enabled: false, autoHide: false, now: 316)
    policy.reveal(now: 317)
    precondition(policy.isHidden, "A disabled panel cannot be revealed by background events")

    let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
    func overlay(pid: Int = 42, layer: Int = 18, sharing: Int = 0, bounds: CGRect = screen) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
         kCGWindowSharingState as String: sharing, kCGWindowBounds as String: bounds.dictionaryRepresentation]
    }
    precondition(MissionControlDetector.detectsOverview([overlay()], dockPID: 42, displays: [screen]), "Detect the Dock's overview overlay on an offset display")
    for invalid in [overlay(pid: 99), overlay(layer: 20), overlay(sharing: 1),
        overlay(bounds: CGRect(x: 5000, y: 0, width: 1920, height: 1080)),
        overlay(bounds: CGRect(x: -1900, y: 220, width: 80, height: 60))] {
        precondition(!MissionControlDetector.detectsOverview([invalid], dockPID: 42, displays: [screen]), "Do not mistake an ordinary Dock or offscreen helper for Mission Control")
    }
    print("PASS: strict Dock reveal policy, click suppression, edge dwell, drag reveal, wake and Mission Control handoff")
}

func runDockVisibilityWindowTests() {
    let suite = "app.newmacbar.visibility-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["/System/Library/CoreServices/Finder.app"], forKey: "pinned")
    defaults.set(true, forKey: "autoHide")
    let model = BarModel(defaults: defaults, observe: false)
    model.batch { model.showRunning = false; model.motionMode = "reduced" }
    let bar = BarView(model: model, music: MusicController(), focus: FocusTimer(defaults: defaults), agenda: CalendarController())
    var overview = false
    let controller = DockWindowController(model: model, bar: bar, overviewActive: { overview })
    defer { model.onChange = nil; controller.stop() }
    model.onChange = { [weak controller] in controller?.update() }
    controller.update()
    precondition(controller.hidden && !controller.panel.isVisible, "An autohidden panel must not flash on startup")
    let outside = NSPoint(x: -100_000, y: -100_000)
    let now = Date()
    for i in 0..<10 {
        model.refreshRunning()
        controller.tick(keepVisible: true, now: now.addingTimeInterval(Double(i)), mouseLocation: outside, buttonsPressed: true)
        controller.panel.orderFrontRegardless()
        controller.panel.orderFront(nil)
        controller.panel.order(.above, relativeTo: 0)
        precondition(controller.hidden && !controller.panel.isVisible, "App activation and system window ordering cannot resurrect a hidden Dock")
    }
    let trigger = controller.placement!.trigger
    let edge = NSPoint(x: trigger.midX, y: trigger.midY)
    controller.tick(keepVisible: false, now: now.addingTimeInterval(11), mouseLocation: edge, buttonsPressed: true)
    precondition(controller.hidden, "An edge click alone cannot summon the Dock")
    controller.tick(keepVisible: false, now: now.addingTimeInterval(12), mouseLocation: edge, buttonsPressed: false)
    controller.tick(keepVisible: false, now: now.addingTimeInterval(12.1), mouseLocation: edge, buttonsPressed: false)
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    precondition(!controller.hidden && controller.panel.isVisible, "An edge hover can present the gated panel")
    overview = true
    controller.tick(keepVisible: true, now: now.addingTimeInterval(13), mouseLocation: edge, buttonsPressed: false)
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    controller.reveal()
    precondition(controller.hidden && !controller.panel.isVisible, "The system Dock has exclusive Mission Control presentation")
    overview = false
    controller.tick(keepVisible: false, now: now.addingTimeInterval(14), mouseLocation: edge, buttonsPressed: false)
    precondition(controller.hidden, "Returning from Mission Control does not replay the hover")
    controller.tick(keepVisible: false, now: now.addingTimeInterval(15), mouseLocation: outside, buttonsPressed: false)
    controller.tick(keepVisible: false, now: now.addingTimeInterval(16), mouseLocation: edge, buttonsPressed: false)
    controller.tick(keepVisible: false, now: now.addingTimeInterval(16.1), mouseLocation: edge, buttonsPressed: false)
    precondition(!controller.hidden && controller.panel.isVisible, "A fresh edge hover works after Mission Control")
    overview = true
    controller.tick(keepVisible: false, now: now.addingTimeInterval(17), mouseLocation: outside, buttonsPressed: false)
    overview = false
    controller.tick(keepVisible: false, now: now.addingTimeInterval(18), mouseLocation: outside, buttonsPressed: false)
    precondition(!controller.requiresOverviewPolling && controller.hidden,
        "Overview exit is observed while the pointer is away from the hidden Dock")
    controller.tick(keepVisible: false, now: now.addingTimeInterval(19), mouseLocation: edge, buttonsPressed: false)
    controller.tick(keepVisible: false, now: now.addingTimeInterval(19.1), mouseLocation: edge, buttonsPressed: false)
    precondition(!controller.hidden, "The first new edge hover works after exiting overview elsewhere")
    controller.stop()
    controller.resume()
    precondition(controller.hidden && !controller.panel.isVisible, "Wake does not force a Dock reveal")
    print("PASS: live AppKit hidden startup, activation/order gating, edge reveal, Mission Control handoff and quiet resume")
}
