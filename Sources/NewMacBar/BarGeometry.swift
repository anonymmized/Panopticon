import AppKit

enum BarGeometry {
    static func frames(sizes: [CGFloat], spacing: CGFloat, origin: NSPoint, scale: CGFloat, base: CGFloat, lift: CGFloat) -> [NSRect] {
        var x = origin.x
        return sizes.map { size in
            let side = size * scale
            defer { x += (size + spacing) * scale }
            let y = origin.y + max(0, size / max(base, 1) - 1) * lift * 2 * scale
            return NSRect(x: x, y: y, width: side, height: side)
        }
    }
    static func nearest(_ point: NSPoint, frames: [NSRect]) -> Int? {
        frames.indices.filter { frames[$0].insetBy(dx: -4, dy: -6).contains(point) }.min { abs(frames[$0].midX - point.x) < abs(frames[$1].midX - point.x) }
    }
}
