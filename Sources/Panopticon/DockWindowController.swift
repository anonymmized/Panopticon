import AppKit

final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

final class BarPanel: NSPanel {
    var permitsPresentation = false
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func orderFrontRegardless() {
        guard permitsPresentation else { return }
        super.orderFrontRegardless()
    }

    override func orderFront(_ sender: Any?) {
        guard permitsPresentation else { return }
        super.orderFront(sender)
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        guard place == .out || permitsPresentation else { return }
        super.order(place, relativeTo: otherWin)
    }

    func updateMousePassthrough(for bar: BarView, at screenPoint: NSPoint) {
        let point = bar.convert(convertPoint(fromScreen: screenPoint), from: nil)
        let ignores = !bar.containsInteractivePoint(point)
        if ignoresMouseEvents != ignores { ignoresMouseEvents = ignores }
    }
}

final class DockWindowController {
    let panel: BarPanel
    let bar: BarView
    private let model: BarModel
    private var selectedDisplayID: CGDirectDisplayID?
    private var lastScreenIndex: Int?
    private var transitionTimer: Timer?
    private var motion: DockRevealMotion?
    var isTransitioning: Bool { motion != nil }
    private var storedWindowSwitcher: WindowSwitcherController?
    var windowSwitcher: WindowSwitcherController {
        if let storedWindowSwitcher { return storedWindowSwitcher }
        let controller = WindowSwitcherController(model: model, bar: bar)
        storedWindowSwitcher = controller
        return controller
    }
    var windowsAreShown: Bool { storedWindowSwitcher?.isShown == true }
    func dismissWindows() { storedWindowSwitcher?.close() }
    var hoverBlocked: (() -> Bool)?
    private var targetFrame: NSRect?
    private var targetHidden = true
    private var visibility: DockVisibilityPolicy
    private let overviewActive: () -> Bool
    private var pointerIsDragging = false
    var hidden: Bool { visibility.isHidden }
    var requiresOverviewPolling: Bool { visibility.isOverviewActive }

    init(model: BarModel, bar: BarView, overviewActive: @escaping () -> Bool = MissionControlDetector.isActive) {
        self.model = model
        self.bar = bar
        self.overviewActive = overviewActive
        visibility = DockVisibilityPolicy(autoHide: model.autoHide)
        panel = BarPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.title = "Panopticon"
        let root = PassthroughView()
        root.addSubview(bar.surfaceShadow)
        root.addSubview(bar.glass)
        root.addSubview(bar)
        panel.contentView = root
        bar.openWindows = { [weak self] item, rect in
            guard let self, !self.hidden, !self.visibility.isOverviewActive else { return }
            self.windowSwitcher.showExplicit(item: item, anchor: self.bar.screenRect(rect))
        }
    }

    deinit { transitionTimer?.invalidate(); storedWindowSwitcher?.close() }

    var screen: NSScreen? {
        if lastScreenIndex != model.screenIndex {
            lastScreenIndex = model.screenIndex
            let screens = NSScreen.screens
            if !screens.isEmpty {
                selectedDisplayID = displayID(screens[min(max(0, model.screenIndex), screens.count - 1)])
            }
        }
        return NSScreen.screens.first { displayID($0) == selectedDisplayID } ?? NSScreen.screens.first
    }

    private func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var placement: PanelPlacement? {
        guard let screen else { return nil }
        let usable = PanelPlacement.usableFrame(screen: screen.frame, visible: screen.visibleFrame, insets: screen.safeAreaInsets)
        bar.availableLength = max(100, (model.dockEdge.isVertical ? usable.height : usable.width) - 12)
        return PanelPlacement(
            screen: screen.frame, visible: usable,
            content: NSSize(width: bar.preferredWidth, height: bar.preferredHeight),
            edge: model.dockEdge, offset: CGFloat(model.bottomOffset),
            reservesSystemDock: !model.replaceDock)
    }

    func update(animated: Bool = false) {
        guard let placement else { stop(); return }
        let now = ProcessInfo.processInfo.systemUptime
        visibility.configure(enabled: model.barVisible, autoHide: model.autoHide, now: now)
        if !hidden || panel.isVisible { visibility.setOverview(overviewActive(), now: now) }
        storedWindowSwitcher?.validateContext()
        apply(placement, animated: animated)
    }

    private func apply(_ placement: PanelPlacement, animated: Bool) {
        let hiding = hidden || !model.barVisible
        let reduced = bar.motionReduced
        let target = hiding && !reduced ? placement.hidden : placement.shown
        bar.frame = NSRect(origin: .zero, size: placement.shown.size)
        bar.refresh()
        panel.permitsPresentation = !hiding
        if targetFrame == target, targetHidden == hiding, panel.isVisible || hiding {
            updatePassthrough()
            return
        }
        transitionTimer?.invalidate()
        transitionTimer = nil
        motion = nil
        targetFrame = target
        targetHidden = hiding
        let appearing = !hiding && !panel.isVisible
        let shouldAnimate = !visibility.isOverviewActive && (animated || appearing || (!model.barVisible && panel.isVisible))
        dismissWindows()
        if appearing {
            panel.setFrame(shouldAnimate && !reduced ? placement.hidden : placement.shown, display: true)
            panel.alphaValue = shouldAnimate ? (reduced ? 0 : 0.35) : 1
            panel.orderFrontRegardless()
        }
        if shouldAnimate && panel.isVisible {
            motion = DockRevealMotion(from: panel.frame, to: target, fromAlpha: panel.alphaValue,
                toAlpha: hiding ? 0 : 1, started: ProcessInfo.processInfo.systemUptime,
                duration: reduced ? 0.1 : hiding ? 0.24 : 0.32)
            let fps = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : min(120, max(60, screen?.maximumFramesPerSecond ?? 60))
            let timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in self?.advanceTransition() }
            timer.tolerance = 0.001
            transitionTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            panel.setFrame(target, display: true)
            panel.alphaValue = hiding ? 0 : 1
            if hiding { panel.orderOut(nil); bar.finishAnimations() }
        }
        updatePassthrough()
    }

    func advanceTransition(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let motion else { return }
        let sample = motion.sample(at: time)
        panel.setFrame(sample.frame, display: true)
        panel.alphaValue = sample.alpha
        guard sample.finished else { return }
        transitionTimer?.invalidate()
        transitionTimer = nil
        self.motion = nil
        if targetHidden {
            panel.orderOut(nil)
            panel.ignoresMouseEvents = true
            bar.finishAnimations()
        } else { updatePassthrough() }
    }

    func updatePassthrough(at screenPoint: NSPoint? = nil) {
        guard model.barVisible, !hidden, panel.isVisible else {
            panel.ignoresMouseEvents = true
            bar.updatePointer(nil)
            return
        }
        let point = screenPoint ?? NSEvent.mouseLocation
        panel.updateMousePassthrough(for: bar, at: point)
        bar.updatePointer(isTransitioning ? nil : bar.convert(panel.convertPoint(fromScreen: point), from: nil))
    }

    func reveal() {
        let now = ProcessInfo.processInfo.systemUptime
        visibility.configure(enabled: model.barVisible, autoHide: model.autoHide, now: now)
        visibility.setOverview(overviewActive(), now: now)
        visibility.reveal(now: now)
        update(animated: true)
    }

    func pointerEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: pointerIsDragging = true
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp, .mouseMoved: pointerIsDragging = false
        default: break
        }
        updatePassthrough()
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            storedWindowSwitcher?.mouseDown(at: NSEvent.mouseLocation)
        }
        if event.type == .keyDown && event.keyCode == 53 { storedWindowSwitcher?.dismissUntilExit() }
        updateWindowSwitcher(at: NSEvent.mouseLocation)
    }

    private func updateWindowSwitcher(at point: NSPoint) {
        let permitted = model.barVisible && model.showWindowSwitcher && !hidden && !isTransitioning
            && !visibility.isOverviewActive && hoverBlocked?() != true
        guard permitted else { dismissWindows(); return }
        let local = bar.convert(panel.convertPoint(fromScreen: point), from: nil)
        guard storedWindowSwitcher != nil || bar.containsInteractivePoint(local) else { return }
        windowSwitcher.update(at: point, permitted: true, dragging: bar.hasActiveDrag || NSEvent.pressedMouseButtons != 0)
    }

    func tick(
        keepVisible: Bool, now: Date = Date(), mouseLocation: NSPoint = NSEvent.mouseLocation,
        buttonsPressed: Bool? = nil
    ) {
        guard let placement else { return }
        // Date is injectable for deterministic panel regressions; the visibility
        // clock remains monotonic during real sessions.
        let time = ProcessInfo.processInfo.systemUptime + now.timeIntervalSinceNow
        let wasHidden = hidden
        visibility.configure(enabled: model.barVisible, autoHide: model.autoHide, now: time)
        let nearEdge = placement.trigger.contains(mouseLocation)
        let pressed = buttonsPressed ?? ((nearEdge || !hidden || bar.hasActiveDrag) && NSEvent.pressedMouseButtons != 0)
        if !hidden || nearEdge || panel.isVisible || visibility.isOverviewActive {
            visibility.setOverview(overviewActive(), now: time)
        }
        let inside = !hidden && bar.containsInteractivePoint(
            bar.convert(panel.convertPoint(fromScreen: mouseLocation), from: nil))
        visibility.tick(now: time, nearEdge: nearEdge, inside: inside,
            keepVisible: keepVisible || storedWindowSwitcher?.retainsDock(at: mouseLocation) == true,
            buttonsPressed: pressed, dragging: bar.hasActiveDrag || (pressed && pointerIsDragging && nearEdge))
        if wasHidden != hidden || targetHidden != (hidden || !model.barVisible) {
            apply(placement, animated: true)
        }
        updatePassthrough(at: mouseLocation)
        updateWindowSwitcher(at: mouseLocation)
    }

    func stop() {
        visibility.suspend()
        transitionTimer?.invalidate()
        transitionTimer = nil
        motion = nil
        dismissWindows()
        targetFrame = nil
        panel.permitsPresentation = false
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
        bar.finishAnimations()
    }

    func resume() { update() }

    var diagnosticState: [String: Any] {
        ["pid": Int(ProcessInfo.processInfo.processIdentifier), "hidden": hidden,
         "panelVisible": panel.isVisible, "permitsPresentation": panel.permitsPresentation,
         "autoHide": model.autoHide, "enabled": model.barVisible,
         "overviewDetected": overviewActive(), "overviewSuppressed": visibility.isOverviewActive,
         "pinnedCount": model.pinned.count]
    }
}
