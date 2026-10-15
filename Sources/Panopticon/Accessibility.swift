import AppKit
import ApplicationServices

/// Accessibility-based extras: Dock badges and per-app window lists.
/// Everything degrades to "nothing" until the user grants access.
enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// Notification badges shown by the system Dock, keyed by canonical paths of the app path.
    static func dockBadges() -> [String: String] {
        guard trusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var result: [String: String] = [:]
        for list in attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            for tile in attribute(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                guard let label = attribute(tile, "AXStatusLabel") as? String, !label.isEmpty,
                      let url = attribute(tile, kAXURLAttribute) as? URL
                else { continue }
                result[url.resolvingSymlinksInPath().standardizedFileURL.path] = label
            }
        }
        return result
    }

    struct Window {
        let title: String
        let minimized: Bool
        fileprivate let element: AXUIElement
    }

    static func windows(of app: NSRunningApplication) -> [Window] {
        guard trusted else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        return (attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []).prefix(30).compactMap { window in
            guard (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole else { return nil }
            let title = attribute(window, kAXTitleAttribute) as? String ?? ""
            return Window(title: title.isEmpty ? L("Без названия") : title,
                          minimized: attribute(window, kAXMinimizedAttribute) as? Bool ?? false,
                          element: window)
        }
    }

    static func focus(_ window: Window, of app: NSRunningApplication) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        app.unhide()
        app.activate(options: [])
    }
}
