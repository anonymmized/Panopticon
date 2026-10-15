import AppKit
import SwiftUI

/// Opt-in developer review with an isolated preference suite. It neither replaces
/// the real Dock nor edits the user's existing panel. No synthetic input is used.
final class UIReviewHarness: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let suite = "app.newmacbar.uireview.\(UUID().uuidString)"
    private var window: NSWindow?
    private var model: BarModel?
    private let presenter = AppDelegate()
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults(suiteName: suite)!
        Localization.shared = Localization(defaults: defaults)
        defaults.set(
            [
                "/System/Library/CoreServices/Finder.app", "/System/Applications/Calendar.app",
                "/System/Applications/Music.app",
            ], forKey: "pinned")
        let model = BarModel(defaults: defaults, observe: false)
        self.model = model
        model.showRunning = false
        model.theme = "aurora"
        // Reuse the real window presenter with isolated state. Never start the
        // AppDelegate lifecycle (Dock, global shortcuts and session ownership).
        let catalog = AppCatalog()
        presenter.model = model; presenter.catalog = catalog
        observers.append(NotificationCenter.default.addObserver(forName: .openBarLauncher, object: nil, queue: .main) { [weak self] _ in self?.presenter.showLauncher() })
        observers.append(NotificationCenter.default.addObserver(forName: .openBarSettings, object: nil, queue: .main) { [weak self] _ in self?.window?.makeKeyAndOrderFront(nil) })
        let dock = DockIntegration(
            defaults: defaults, readDomain: { [:] }, execute: { _, _ in CommandResult(status: 0, output: "") }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: CommandLine.arguments.contains("--small-window") ? 760 : 1040, height: CommandLine.arguments.contains("--small-window") ? 540 : 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("Panopticon — изолированная проверка")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 760, height: 540)
        window.contentView = NSHostingView(
            rootView: SettingsView(
                model: model, dock: dock, focus: FocusTimer(defaults: defaults), catalog: catalog,
                agenda: CalendarController(), ui: UIStateStore(defaults: defaults)))
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = ApplicationMenus.reviewMenu()
        observers.append(NotificationCenter.default.addObserver(forName: Localization.didChange, object: nil, queue: .main) { _ in NSApp.mainMenu = ApplicationMenus.reviewMenu() })
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { if notification.object as? NSWindow === window { NSApp.terminate(nil) } }
    func applicationWillTerminate(_ notification: Notification) {
        presenter.searchPanel?.orderOut(nil)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    static func run() {
        let app = NSApplication.shared
        let delegate = UIReviewHarness()
        app.delegate = delegate
        app.run()
    }
}
