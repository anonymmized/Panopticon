import Foundation

/// Only an edge hover or an explicit command may reveal an autohidden Dock.
/// Model updates, app activation and unrelated windows never change this state.
struct DockVisibilityPolicy {
    private(set) var isHidden: Bool
    private var enabled = true
    private var autoHide: Bool
    private var overview = false
    private var edgeEntered: TimeInterval?
    private var edgeMustBeExited = false
    private var lastInteraction: TimeInterval = 0
    private var explicitUntil: TimeInterval = 0
    var isOverviewActive: Bool { overview }

    init(autoHide: Bool) {
        self.autoHide = autoHide
        isHidden = autoHide
    }

    mutating func configure(enabled: Bool, autoHide: Bool, now: TimeInterval) {
        let changed = self.autoHide != autoHide || self.enabled != enabled
        self.enabled = enabled
        self.autoHide = autoHide
        guard enabled, !overview else { hide(); return }
        if !autoHide {
            isHidden = false
        } else if changed {
            hide()
            lastInteraction = now
        }
    }

    mutating func setOverview(_ active: Bool, now: TimeInterval) {
        guard overview != active else { return }
        overview = active
        hide()
        edgeMustBeExited = true
        lastInteraction = now
        if !active && enabled && !autoHide { isHidden = false }
    }

    mutating func reveal(now: TimeInterval) {
        guard enabled, !overview else { return }
        isHidden = false
        explicitUntil = now + 1
        lastInteraction = now
        edgeEntered = nil
    }

    mutating func suspend() {
        hide()
        edgeMustBeExited = true
    }

    mutating func tick(
        now: TimeInterval, nearEdge: Bool, inside: Bool, keepVisible: Bool,
        buttonsPressed: Bool, dragging: Bool
    ) {
        guard enabled, !overview else { hide(); return }
        if !autoHide { isHidden = false; return }
        if !nearEdge {
            edgeEntered = nil
            edgeMustBeExited = false
        }
        if isHidden {
            // Holding a mouse button is not a hover. A deliberate drag may
            // reveal after a longer dwell so a file can still be dropped.
            guard nearEdge, !edgeMustBeExited, !buttonsPressed || dragging else {
                edgeEntered = nil
                return
            }
            if edgeEntered == nil { edgeEntered = now }
            let dwell: TimeInterval = dragging ? 0.25 : 0.08
            if now - (edgeEntered ?? now) >= dwell {
                isHidden = false
                lastInteraction = now
                edgeEntered = nil
            }
            return
        }
        // A popover can retain an already visible panel, never summon a hidden one.
        if inside || nearEdge || keepVisible || dragging {
            lastInteraction = now
        } else if now >= explicitUntil && now - lastInteraction >= 0.28 {
            hide()
        }
    }

    private mutating func hide() {
        isHidden = true
        edgeEntered = nil
        explicitUntil = 0
    }
}
