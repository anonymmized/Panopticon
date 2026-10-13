import AppKit
import Combine
import SwiftUI

private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on an inactive bar go straight to the icon.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the floating panel: placement, auto-hide, monitor following, scroll switching
/// and tracking the active macOS desktop.
final class DockWindowController {
    private let store: DockStore
    private let panel: DockPanel
    private var contentSize: CGSize = .zero
    private var screen: NSScreen?
    private var revealed = true
    private var lastHovered = Date()
    private var wasVisible = true
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollSwitch = Date.distantPast
    private var timer: Timer?
    private var scrollMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    init(store: DockStore) {
        self.store = store
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        let host = FirstMouseHostingView(rootView: DockView(store: store) { _ in })
        host.sizingOptions = []
        panel.contentView = host
        host.rootView = DockView(store: store) { [weak self] size in
            self?.contentSize = size
            self?.layout()
        }

        screen = NSScreen.screens.first
        wasVisible = store.config.visible

        store.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in self?.configChanged(config) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                if let screen = self.screen, !NSScreen.screens.contains(screen) {
                    self.screen = NSScreen.screens.first
                }
                self.layout()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.desktopChanged() }
            .store(in: &cancellables)

        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.tick() }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event)
        }

        layout()
        desktopChanged()
    }

    deinit {
        timer?.invalidate()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    private func configChanged(_ config: DockConfig) {
        // Showing the bar from the menu or a hotkey reveals it even in auto-hide mode.
        if config.visible && !wasVisible { revealed = true; lastHovered = Date() }
        if !config.autohide { revealed = true }
        wasVisible = config.visible
        let appearance = config.theme.appearance
        if panel.appearance?.name != appearance?.name { panel.appearance = appearance }
        layout()
    }

    private func desktopChanged() {
        store.desktopChanged(Desktops.current(for: screen ?? NSScreen.screens.first))
    }

    // MARK: Placement

    private func frames() -> (shown: NSRect, hidden: NSRect)? {
        guard let screen = screen ?? NSScreen.screens.first else { return nil }
        let config = store.config
        let size = contentSize == .zero ? CGSize(width: 700, height: 160) : contentSize

        var area = screen.visibleFrame
        if config.autohide {
            // Hug the real screen edge so the mouse can hit it; stay below the menu bar.
            area = screen.frame
            area.size.height = screen.visibleFrame.maxY - area.minY
        }

        let origin: CGPoint
        let away: CGVector
        switch config.edge {
        case .bottom:
            origin = CGPoint(x: area.midX - size.width / 2, y: area.minY)
            away = CGVector(dx: 0, dy: -size.height / 3)
        case .top:
            origin = CGPoint(x: area.midX - size.width / 2, y: area.maxY - size.height)
            away = CGVector(dx: 0, dy: size.height / 3)
        case .left:
            origin = CGPoint(x: area.minX, y: area.midY - size.height / 2)
            away = CGVector(dx: -size.width / 3, dy: 0)
        case .right:
            origin = CGPoint(x: area.maxX - size.width, y: area.midY - size.height / 2)
            away = CGVector(dx: size.width / 3, dy: 0)
        }
        let shown = NSRect(origin: origin, size: size).integral
        return (shown, shown.offsetBy(dx: away.dx, dy: away.dy))
    }

    private func layout() {
        guard store.config.visible, let frames = frames() else {
            panel.orderOut(nil)
            return
        }
        guard revealed else { return }
        panel.alphaValue = 1
        if panel.frame != frames.shown {
            panel.setFrame(frames.shown, display: true)
        }
        panel.orderFrontRegardless()
    }

    private func setRevealed(_ value: Bool) {
        guard value != revealed, let frames = frames() else { return }
        revealed = value
        if value {
            panel.setFrame(frames.hidden, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: value ? .easeOut : .easeIn)
            panel.animator().setFrame(value ? frames.shown : frames.hidden, display: true)
            panel.animator().alphaValue = value ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self, !self.revealed else { return }
            self.panel.orderOut(nil)
        })
    }

    // MARK: Mouse tracking

    private func tick() {
        let mouse = NSEvent.mouseLocation

        // A drag that ended outside the bar never reaches a drop delegate.
        if store.dragging != nil && NSEvent.pressedMouseButtons == 0 {
            store.dragging = nil
        }

        if store.config.followMouse,
           let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           mouseScreen != screen {
            screen = mouseScreen
            layout()
            desktopChanged()
        }

        guard store.config.visible, store.config.autohide, let frames = frames() else { return }

        let shown = frames.shown
        let trigger: NSRect
        switch store.config.edge {
        case .bottom: trigger = NSRect(x: shown.minX, y: shown.minY - 2, width: shown.width, height: 4)
        case .top: trigger = NSRect(x: shown.minX, y: shown.maxY - 3, width: shown.width, height: 4)
        case .left: trigger = NSRect(x: shown.minX - 2, y: shown.minY, width: 4, height: shown.height)
        case .right: trigger = NSRect(x: shown.maxX - 3, y: shown.minY, width: 4, height: shown.height)
        }

        let hovering = revealed && shown.insetBy(dx: -6, dy: -6).contains(mouse)
        let busy = store.dragging != nil || (revealed && NSEvent.pressedMouseButtons != 0)
        if trigger.contains(mouse) || hovering || busy {
            lastHovered = Date()
            setRevealed(true)
        } else if revealed && Date().timeIntervalSince(lastHovered) > 0.7 {
            setRevealed(false)
        }
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, store.config.scrollToSwitch else { return event }
        if event.momentumPhase != [] { return nil } // ignore trackpad inertia

        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        let delta = horizontal ? -event.scrollingDeltaX : event.scrollingDeltaY
        scrollAccumulator += event.hasPreciseScrollingDeltas ? delta : delta * 12

        if abs(scrollAccumulator) > 40, Date().timeIntervalSince(lastScrollSwitch) > 0.3 {
            store.cycle(scrollAccumulator > 0 ? -1 : 1)
            scrollAccumulator = 0
            lastScrollSwitch = Date()
        }
        if event.phase == .ended || event.phase == .cancelled {
            scrollAccumulator = 0
        }
        return nil
    }
}
