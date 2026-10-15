import AppKit

enum DockMotionMode: String, CaseIterable, Identifiable {
    case system, full, reduced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L("Как в macOS")
        case .full: return L("Полные анимации")
        case .reduced: return L("Уменьшить движение")
        }
    }
    func isReduced(system: Bool, legacy: Bool) -> Bool {
        switch self {
        case .system: return system || legacy
        case .full: return false
        case .reduced: return true
        }
    }
}

/// A time-based, analytically integrated spring. The response is the same on
/// 30 Hz power-saving, 60 Hz and ProMotion displays; no idle display timer runs.
struct DockSpring {
    var value: CGFloat
    var velocity: CGFloat = 0

    @discardableResult mutating func advance(to target: CGFloat, elapsed: TimeInterval) -> Bool {
        let dt = CGFloat(min(max(elapsed, 0), 0.05))
        let omega: CGFloat = 2 * .pi / 0.26
        let damping: CGFloat = 0.78
        let decay = exp(-damping * omega * dt)
        let frequency = omega * sqrt(1 - damping * damping)
        let cosine = cos(frequency * dt)
        let sine = sin(frequency * dt)
        let offset = value - target
        let next = decay * (offset * cosine + (velocity + damping * omega * offset) / frequency * sine)
        velocity = decay * (velocity * cosine - (damping * omega * velocity + omega * omega * offset) / frequency * sine)
        value = target + next
        if abs(value - target) < 0.025 && abs(velocity) < 0.12 {
            value = target
            velocity = 0
            return false
        }
        return true
    }
}

enum DockMotion {
    static let launchDuration: TimeInterval = 0.42
    static let entryDuration: TimeInterval = 0.22

    static func magnifiedSize(base: CGFloat, magnification: CGFloat, distance: CGFloat, step: CGFloat) -> CGFloat {
        let radius = max(1, step * 2)
        guard distance < radius else { return base }
        let influence = (cos(.pi * distance / radius) + 1) / 2
        return base * (1 + (magnification - 1) * influence)
    }

    static func easeOut(_ progress: Double) -> CGFloat {
        let t = min(max(progress, 0), 1)
        return CGFloat(1 - pow(1 - t, 3))
    }

    static func bounce(at elapsed: TimeInterval) -> CGFloat {
        let t = min(max(elapsed / launchDuration, 0), 1)
        return CGFloat(sin(.pi * t) * 12)
    }
}
