import AppKit
import SwiftUI

/// Explicit developer command: render generated fixtures without permissions or
/// changing the user's preferences, Dock, focus timer or layout.
func renderInterfaceFixtures() {
    _ = NSApplication.shared
    let suite = "app.panopticon.render.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["/System/Library/CoreServices/Finder.app", "/System/Applications/Calendar.app", "/System/Applications/Music.app"], forKey: "pinned")
    let model = BarModel(defaults: defaults, observe: false)
    model.showRunning = false; model.replaceDock = false
    let focus = FocusTimer(defaults: defaults)
    let agenda = CalendarController()
    let catalog = AppCatalog()
    let dock = DockIntegration(defaults: defaults, readDomain: { [:] }, execute: { _, _ in CommandResult(status: 0, output: "") })
    let ui = UIStateStore(defaults: defaults)
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/interface-review", isDirectory: true)
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    Localization.shared = Localization(defaults: defaults)
    for language in [AppLanguage.english, .russian] {
        Localization.shared.setLanguage(language)
        for appearance in ["light", "dark"] {
            ui.appearance = appearance; ui.section = "appearance"
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SettingsView(model: model, dock: dock, focus: focus, catalog: catalog, agenda: agenda, ui: ui))
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 1040, height: 760)
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("Settings bitmap unavailable") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = bitmap.representation(using: .png, properties: [:])!
            try! image.write(to: output.appendingPathComponent("settings-\(language.rawValue)-\(appearance).png"))
            window.close()
            for permission in [true, false] {
                let state = WindowSwitcherState()
                state.name = "Safari"
                state.icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
                state.phase = permission ? .permission : .unavailable
                let size = NSSize(width: 340, height: permission ? 278 : 268)
                let preview = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                preview.isReleasedWhenClosed = false
                let view = NSHostingView(rootView: WindowSwitcherView(state: state, connect: {}, retry: {}, select: { _ in }, openApp: {})
                    .frame(width: size.width, height: size.height)
                    .background(appearance == "dark" ? Color(nsColor: .windowBackgroundColor) : .white)
                    .preferredColorScheme(appearance == "dark" ? .dark : .light))
                preview.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                preview.contentView = view; preview.orderFront(nil)
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.12))
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("windows-\(permission ? "permission" : "unavailable")-\(language.rawValue)-\(appearance).png"))
                preview.close()
            }
        }
    }
    model.applyNativeDockStyle(); model.setMotionMode("reduced"); model.widget = "clock"; model.secondaryWidget = "calendar"; model.showSpaces = false
    let bar = BarView(model: model, music: MusicController(), focus: focus, agenda: agenda)
    bar.frame = NSRect(x: 0, y: 0, width: 900, height: 160)
    let window = NSWindow(contentRect: bar.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let container = NSView(frame: bar.bounds); container.wantsLayer = true
    container.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.3, alpha: 1).cgColor
    window.contentView = container; container.addSubview(bar.glass); container.addSubview(bar)
    bar.refresh()
    if let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) {
        container.cacheDisplay(in: container.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("panel.png"))
    }
    window.close()
    print("PASS: isolated interface fixtures rendered to build/interface-review")
}
