import AppKit
import SwiftUI

/// Scoped to the hosting window; removed as soon as the view goes away. Command
/// modifiers are taken from the actual key event, never NSApp.currentEvent.
struct KeyboardCommands: NSViewRepresentable {
    let handle: (NSEvent) -> Bool
    func makeNSView(context: Context) -> KeyMonitorView { KeyMonitorView(handle: handle) }
    func updateNSView(_ view: KeyMonitorView, context: Context) { view.handle = handle }
    static func dismantleNSView(_ view: KeyMonitorView, coordinator: ()) { view.stop() }
}
final class KeyMonitorView: NSView {
    var handle: (NSEvent) -> Bool
    private var monitor: Any?
    init(handle: @escaping (NSEvent) -> Bool) {
        self.handle = handle
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.isKeyWindow else {
                return event
            }
            // Let input methods finish composing before treating Return as an action.
            if let text = window.firstResponder as? NSTextView, text.hasMarkedText() { return event }
            return self.handle(event) ? nil : event
        }
    }
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    deinit { stop() }
}

struct StableSelection {
    static func reconciled(_ selected: String?, in ids: [String]) -> String? {
        if let selected, ids.contains(selected) { return selected }
        return ids.first
    }
    static func moved(_ selected: String?, in ids: [String], by delta: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        let index = ids.firstIndex(of: selected ?? "") ?? 0
        return ids[min(max(0, index + delta), ids.count - 1)]
    }
}
