import AppKit

/// A transition starts at the current frame, including a mid-flight reversal.
struct DockRevealMotion {
    let from: NSRect
    let to: NSRect
    let fromAlpha: CGFloat
    let toAlpha: CGFloat
    let started: TimeInterval
    let duration: TimeInterval

    func sample(at time: TimeInterval) -> (frame: NSRect, alpha: CGFloat, finished: Bool) {
        let progress = min(1, max(0, (time - started) / max(0.001, duration)))
        let t = CGFloat(progress * progress * (3 - 2 * progress))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return (NSRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY),
                       width: mix(from.width, to.width), height: mix(from.height, to.height)),
                mix(fromAlpha, toAlpha), progress >= 1)
    }
}
