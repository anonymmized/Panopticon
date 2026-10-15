import AppKit

func runNativeDockModelTests() {
    let suite = "app.newmacbar.native-dock-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let paths = ["/System/Library/CoreServices/Finder.app", "/System/Applications/Music.app", "/System/Applications/Calendar.app"]
    let source = paths.map { DockItem(url: URL(fileURLWithPath: $0)) }
    defaults.set([String](), forKey: "pinned")
    defaults.set(true, forKey: "replaceDock")
    let model = BarModel(defaults: defaults, observe: false, systemDockProvider: { source })
    precondition(model.pinned.map(\.id) == paths, "Repair the old running-only Dock before hiding macOS Dock")
    model.running = []
    model.save()
    precondition(model.items.map(\.id) == paths, "Closing every application must retain imported launchers")
    let second = BarModel(defaults: defaults, observe: false, systemDockProvider: { source })
    precondition(second.items.map(\.id) == paths, "Closed application launchers survive a relaunch")
    second.remove(source[1])
    let third = BarModel(defaults: defaults, observe: false, systemDockProvider: { source })
    precondition(!third.pinned.contains(source[1]), "One-time migration must not undo a later explicit removal")
    let custom = URL(fileURLWithPath: "/System/Applications/Messages.app")
    third.add(custom, at: 0)
    let before = third.pinned.map(\.id)
    precondition(third.importDock() == 1, "Repeated import adds only missing applications")
    precondition(Array(third.pinned.prefix(before.count)).map(\.id) == before, "Import preserves custom launchers and their order")
    precondition(third.importDock() == 0, "Import is idempotent")
    let missing = "/Volumes/Panopticon-Disconnected-Test/Offline.app"
    third.batch { third.pinned.append(DockItem(url: URL(fileURLWithPath: missing))) }
    let main = third.selectedSpaceID
    let other = third.addSpace(name: "Other")!
    third.selectSpace(main)
    precondition(third.pinned.contains { $0.id == missing }, "Space switches must retain temporarily unavailable launchers")
    let reloaded = BarModel(defaults: defaults, observe: false, systemDockProvider: { source })
    precondition(reloaded.pinned.contains { $0.id == missing }, "Unavailable launchers survive persistence")
    reloaded.running = [NSRunningApplication.current]
    precondition(reloaded.runningApplication(for: DockItem(url: URL(fileURLWithPath: missing))) == nil,
        "A missing app must not activate an unrelated process with no bundle identifier")
    third.selectSpace(other)
    third.importSystemDockIfNeeded()
    precondition(third.pinned.isEmpty, "Migration never fills every newly created space")
    third.applyNativeDockStyle()
    precondition(third.motionMode == "full" && third.magnification > 1.5 && third.launchStyle == "bounce", "Native preset enables visible motion")
    let styled = BarModel(defaults: defaults, observe: false, systemDockProvider: { source })
    precondition(styled.motionMode == "full" && ProfileAppearance(styled) == ProfileAppearance(third), "Motion policy survives relaunch and profile snapshots")
    defaults.removeObject(forKey: "motionMode")
    defaults.set(true, forKey: "reduceMotion")
    let legacy = BarModel(defaults: defaults, observe: false, systemDockProvider: { source })
    precondition(legacy.motionMode == "reduced", "Legacy reduced-motion preference retains its meaning")
    legacy.setMotionMode("system")
    precondition(legacy.motionMode == "system" && !legacy.reduceMotion, "Selecting system mode clears the old app-only override")
    var oldProfile = ProfileAppearance(legacy)
    oldProfile.motionMode = nil
    oldProfile.reduceMotion = true
    legacy.batch { oldProfile.apply(to: legacy) }
    precondition(legacy.motionMode == "reduced", "Profiles written before motionMode preserve their accessibility setting")

    func tile(_ path: String, bundle: String? = nil) -> [String: Any] {
        var data: [String: Any] = ["file-data": ["_CFURLString": path]]
        if let bundle { data["bundle-identifier"] = bundle }
        return ["tile-data": data, "tile-type": "file-tile"]
    }
    let music = URL(fileURLWithPath: paths[1])
    let parsed = SystemDockImport.items(from: ["persistent-apps": [
        tile("file:///moved/Music.app/", bundle: "com.apple.Music"),
        tile(URL(fileURLWithPath: paths[2]).absoluteString),
        tile(music.absoluteString, bundle: "com.apple.Music"),
        tile("https://example.com/Ignore.app"),
    ]], applicationURL: { $0 == "com.apple.Music" ? music : nil })
    precondition(parsed.map(\.id) == paths, "Native Dock parsing recovers moved apps, keeps order and deduplicates by bundle")
    precondition(!DockMotionMode.full.isReduced(system: true, legacy: true), "Explicit full motion applies only to this app")
    precondition(DockMotionMode.system.isReduced(system: true, legacy: false), "System mode respects accessibility")
    precondition(DockMotionMode.reduced.isReduced(system: false, legacy: false), "Reduced mode always remains available")
    for fps in [30, 60, 120] {
        var spring = DockSpring(value: 44)
        for _ in 0..<fps { spring.advance(to: 72.6, elapsed: 1 / Double(fps)) }
        precondition(abs(spring.value - 72.6) < 0.03, "Hover settles consistently at each refresh rate")
        for _ in 0..<fps { spring.advance(to: 44, elapsed: 1 / Double(fps)) }
        precondition(spring.value == 44 && spring.velocity == 0, "Hover settles completely and can stop its timer")
    }
    precondition(DockMotion.bounce(at: 0) == 0 && abs(DockMotion.bounce(at: DockMotion.launchDuration)) < 0.001, "Launch bounce returns exactly to its slot")
    print("PASS: native Dock import, closed-app persistence, additive import, missing volumes, migration and refresh-independent springs")
}

func runNativeDockHoverTests() {
    let suite = "app.newmacbar.native-hover-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["/System/Library/CoreServices/Finder.app", "/System/Applications/Calendar.app", "/System/Applications/Music.app"], forKey: "pinned")
    let model = BarModel(defaults: defaults, observe: false)
    model.applyNativeDockStyle()
    model.batch { model.showRunning = false; model.widget = "none"; model.showSpaces = false; model.showTrash = false }
    let bar = BarView(model: model, music: MusicController(), focus: FocusTimer(defaults: defaults), agenda: CalendarController())
    let controller = DockWindowController(model: model, bar: bar, overviewActive: { false })
    defer { controller.stop() }
    for edge in DockEdge.allCases {
        model.edge = edge.rawValue
        controller.reveal()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        precondition(controller.panel.acceptsMouseMovedEvents && !controller.panel.canBecomeKey, "A nonactivating Dock receives hover without stealing focus")
        controller.panel.ignoresMouseEvents = true
        let resting = bar.frames[1]
        let local = NSPoint(x: resting.midX, y: resting.midY)
        let screen = controller.panel.convertPoint(toScreen: bar.convert(local, to: nil))
        controller.updatePassthrough(at: screen)
        precondition(bar.pointer != nil && !controller.panel.ignoresMouseEvents, "Global tracking recovers hover from a click-through margin")
        let start = ProcessInfo.processInfo.systemUptime
        for frame in 1...60 { bar.animate(at: start + Double(frame) / 120) }
        precondition(bar.sizes[1] > CGFloat(model.iconSize) * 1.5, "The hovered app visibly magnifies on every edge")
        precondition(bar.sizes[0] > CGFloat(model.iconSize) && bar.sizes[0] < bar.sizes[1], "Neighbors follow a smooth Dock wave")
        precondition(bar.frames.allSatisfy { bar.bounds.contains($0) }, "Magnified icons are never clipped on any edge")
        controller.updatePassthrough(at: NSPoint(x: controller.panel.frame.maxX + 500, y: controller.panel.frame.maxY + 500))
        for frame in 1...120 { bar.animate(at: start + 0.5 + Double(frame) / 120) }
        precondition(bar.sizes.allSatisfy { $0 == CGFloat(model.iconSize) } && bar.animation == nil, "Leaving the Dock restores geometry and stops animation work")
        precondition(controller.panel.ignoresMouseEvents, "Empty panel margins stay click-through")
    }
    model.motionMode = "system"
    bar.systemReduceMotion = true
    let resting = bar.frames[1]
    bar.updatePointer(NSPoint(x: resting.midX, y: resting.midY))
    bar.animate()
    precondition(bar.sizes.allSatisfy { $0 == CGFloat(model.iconSize) }, "System Reduce Motion never displaces neighboring icons")
    model.batch { model.autoHide = true; model.motionMode = "full" }
    controller.reveal()
    let now = Date()
    let outside = NSPoint(x: -100_000, y: -100_000)
    controller.tick(keepVisible: false, now: now.addingTimeInterval(2), mouseLocation: outside)
    precondition(controller.hidden, "Auto-hide starts after leaving the Dock")
    RunLoop.main.run(until: Date().addingTimeInterval(0.28))
    precondition(!controller.panel.isVisible && controller.panel.ignoresMouseEvents && bar.animation == nil, "Auto-hide finishes and releases pointer/animation work")
    let trigger = controller.placement!.trigger
    controller.tick(keepVisible: false, now: now.addingTimeInterval(3), mouseLocation: NSPoint(x: trigger.midX, y: trigger.midY))
    controller.tick(keepVisible: false, now: now.addingTimeInterval(3.1), mouseLocation: NSPoint(x: trigger.midX, y: trigger.midY))
    precondition(!controller.hidden && controller.panel.isVisible, "Screen-edge trigger reveals the Dock")
    // A launch/termination notification during the slide must not reset it.
    controller.update()
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    precondition(controller.panel.frame == controller.placement!.shown && controller.panel.alphaValue == 1, "Reveal completes despite a concurrent model refresh")
    controller.tick(keepVisible: true, now: now.addingTimeInterval(10), mouseLocation: outside)
    precondition(!controller.hidden, "An open popover or settings window keeps the Dock visible")
    print("PASS: native hover tracking, magnification, neighbor wave, four-edge clipping, timer teardown and reduced motion")
}
