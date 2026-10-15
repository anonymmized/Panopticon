import AppKit
import SwiftUI

func runSettingsLayoutTests() {
    let suite = "app.panopticon.settings-layout.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = BarModel(defaults: defaults, observe: false, systemDockProvider: { [] })
    let ui = UIStateStore(defaults: defaults)
    let dock = DockIntegration(defaults: defaults, readDomain: { [:] }, execute: { _, _ in
        CommandResult(status: 0, output: "")
    })
    func splitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        return view.subviews.lazy.compactMap { splitView(in: $0) }.first
    }
    for language in [AppLanguage.english, .russian] {
        Localization.shared.withTemporaryLanguage(language) {
            for section in ["appearance", "connections"] {
                for size in [NSSize(width: 760, height: 540), NSSize(width: 1040, height: 760)] {
                    ui.section = section
                    ui.appearance = size.width == 760 ? "light" : "dark"
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    let host = NSHostingView(rootView: SettingsView(model: model, dock: dock,
                        focus: FocusTimer(defaults: defaults), catalog: AppCatalog(),
                        agenda: CalendarController(), ui: ui))
                    host.sizingOptions = []
                    window.contentView = host
                    window.contentMinSize = NSSize(width: 760, height: 540)
                    window.orderFront(nil)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                    host.layoutSubtreeIfNeeded()
                    guard let split = splitView(in: host) else {
                        preconditionFailure("Native settings split view was not created")
                    }
                    let frame = host.convert(split.bounds, from: split)
                    precondition(host.bounds.insetBy(dx: -1, dy: -1).contains(frame),
                        "Settings must fit the content area without hiding the heading or language footer")
                    window.close()
                }
            }
        }
    }
    print("PASS: minimum and regular settings windows fit in both languages and appearances")
}
