import AppKit

struct PanelPlacement {
    let shown: NSRect
    let hidden: NSRect
    let trigger: NSRect
    static func usableFrame(screen: NSRect, visible: NSRect, insets: NSEdgeInsets) -> NSRect {
        let safe = NSRect(x: screen.minX + insets.left, y: screen.minY + insets.bottom,
                          width: max(1, screen.width - insets.left - insets.right),
                          height: max(1, screen.height - insets.top - insets.bottom))
        let result = visible.intersection(safe)
        return result.isEmpty ? safe : result
    }

    init(
        screen: NSRect, visible: NSRect, content: NSSize, edge: DockEdge, offset: CGFloat,
        reservesSystemDock: Bool
    ) {
        let area =
            reservesSystemDock
            ? visible
            : NSRect(
                x: screen.minX, y: screen.minY, width: screen.width, height: visible.maxY - screen.minY)
        let width = min(max(1, content.width.isFinite ? content.width : 1), max(1, area.width - 12))
        let height = min(max(1, content.height.isFinite ? content.height : 1), max(1, area.height - 12))
        let gap = max(0, min(offset.isFinite ? offset : 0, 160))
        var frame = NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
        switch edge {
        case .bottom: frame.origin.y = min(area.maxY - height, area.minY + gap)
        case .top: frame.origin.y = max(area.minY, area.maxY - height - gap)
        case .left: frame.origin.x = min(area.maxX - width, area.minX + gap)
        case .right: frame.origin.x = max(area.minX, area.maxX - width - gap)
        }
        // Use the same integral size on and off screen. AppKit rounds window
        // frames; deriving the hidden frame from fractional sizes causes a jump.
        frame = frame.integral
        shown = frame
        switch edge {
        case .bottom:
            hidden = frame.offsetBy(dx: 0, dy: screen.minY - frame.maxY - 2)
            trigger = NSRect(x: frame.minX, y: screen.minY, width: width, height: 6)
        case .top:
            hidden = frame.offsetBy(dx: 0, dy: screen.maxY - frame.minY + 2)
            trigger = NSRect(
                x: frame.minX, y: visible.maxY - 6, width: width, height: screen.maxY - visible.maxY + 6)
        case .left:
            hidden = frame.offsetBy(dx: screen.minX - frame.maxX - 2, dy: 0)
            trigger = NSRect(x: screen.minX, y: frame.minY, width: 6, height: height)
        case .right:
            hidden = frame.offsetBy(dx: screen.maxX - frame.minX + 2, dy: 0)
            trigger = NSRect(x: screen.maxX - 6, y: frame.minY, width: 6, height: height)
        }
    }
}
