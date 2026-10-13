import AppKit
import SwiftUI

enum Prompt {
    static func text(_ title: String, value: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Отмена")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func confirm(_ title: String, info: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

final class IconCache {
    static let shared = IconCache()
    /// Called on the main thread when a website icon finishes loading.
    var onUpdate: (() -> Void)?

    private var cache: [String: NSImage] = [:]
    private var loadingSites: Set<String> = []

    func icon(for path: String) -> NSImage {
        if let image = cache[path] { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }

    func icon(for item: DockItem) -> NSImage {
        guard item.isWeb, let host = item.url.host else { return icon(for: item.path) }
        if let image = cache[host] { return image }
        loadSiteIcon(host: host)
        let browser = NSWorkspace.shared.urlForApplication(toOpen: item.url)
        return browser.map { icon(for: $0.path) } ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            ?? NSImage()
    }

    /// Asks the site itself for its touch icon, then favicon. Nothing goes to third parties.
    private func loadSiteIcon(host: String) {
        guard !loadingSites.contains(host) else { return }
        loadingSites.insert(host)
        let candidates = ["https://\(host)/apple-touch-icon.png", "https://\(host)/favicon.ico"].compactMap(URL.init(string:))
        func attempt(_ index: Int) {
            guard index < candidates.count else { return }
            URLSession.shared.dataTask(with: candidates[index]) { [weak self] data, response, _ in
                if let data, data.count < 2_000_000, (response as? HTTPURLResponse)?.statusCode == 200,
                   let image = NSImage(data: data), image.size.width >= 16 {
                    DispatchQueue.main.async {
                        self?.cache[host] = image
                        self?.onUpdate?()
                    }
                } else {
                    attempt(index + 1)
                }
            }.resume()
        }
        attempt(0)
    }
}

/// Collects URLs (files or web links) from a drop, keeping their order.
func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls = [URL?](repeating: nil, count: providers.count)
    let group = DispatchGroup()
    for (i, provider) in providers.enumerated() {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            DispatchQueue.main.async {
                urls[i] = url
                group.leave()
            }
        }
    }
    group.notify(queue: .main) { completion(urls.compactMap { $0 }) }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [],
         checked: Bool = false, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: enabled ? #selector(fire) : nil, keyEquivalent: key)
        target = self
        keyEquivalentModifierMask = modifiers
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

extension NSMenuItem {
    static func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static func nested(_ title: String, symbol: String? = nil, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }
}

extension DockEdge {
    /// Point icons grow from — the screen edge.
    var anchor: UnitPoint {
        switch self {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    /// Side facing away from the screen edge.
    var inward: Edge.Set {
        switch self {
        case .bottom: return .top
        case .top: return .bottom
        case .left: return .trailing
        case .right: return .leading
        }
    }

    var inwardAlignment: Alignment {
        switch self {
        case .bottom: return .top
        case .top: return .bottom
        case .left: return .trailing
        case .right: return .leading
        }
    }

    var outerAlignment: Alignment {
        switch self {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var arrowEdge: Edge {
        switch self {
        case .bottom: return .top
        case .top: return .bottom
        case .left: return .trailing
        case .right: return .leading
        }
    }

    /// Offset of `distance` points away from the screen edge.
    func inwardOffset(_ distance: CGFloat) -> CGSize {
        switch self {
        case .bottom: return CGSize(width: 0, height: -distance)
        case .top: return CGSize(width: 0, height: distance)
        case .left: return CGSize(width: distance, height: 0)
        case .right: return CGSize(width: -distance, height: 0)
        }
    }
}

/// Sits a view just outside its parent, on the side facing away from the screen edge.
/// Use inside `.overlay(alignment: edge.inwardAlignment)`.
private struct OutsidePlacement: ViewModifier {
    let edge: DockEdge
    let distance: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        switch edge {
        case .bottom:
            content.alignmentGuide(VerticalAlignment.top) { $0[.bottom] }.offset(y: -distance)
        case .top:
            content.alignmentGuide(VerticalAlignment.bottom) { $0[.top] }.offset(y: distance)
        case .left:
            content.alignmentGuide(HorizontalAlignment.trailing) { $0[.leading] }.offset(x: distance)
        case .right:
            content.alignmentGuide(HorizontalAlignment.leading) { $0[.trailing] }.offset(x: -distance)
        }
    }
}

extension View {
    func outside(_ edge: DockEdge, distance: CGFloat) -> some View {
        modifier(OutsidePlacement(edge: edge, distance: distance))
    }
}

func stack(_ vertical: Bool, spacing: CGFloat) -> AnyLayout {
    vertical ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
}

struct BlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Shows an AppKit menu, built at click time, on right click (or control-click).
/// Ordinary clicks, drags and hovering pass straight through to SwiftUI.
struct RightClickMenu: NSViewRepresentable {
    let build: () -> NSMenu

    func makeNSView(context: Context) -> RightClickView { RightClickView() }

    func updateNSView(_ view: RightClickView, context: Context) { view.build = build }
}

final class RightClickView: NSView {
    var build: (() -> NSMenu)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        let contextClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        return contextClick ? super.hitTest(point) : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) { popUp(event) }

    override func mouseDown(with event: NSEvent) { popUp(event) }

    private func popUp(_ event: NSEvent) {
        guard let menu = build?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
