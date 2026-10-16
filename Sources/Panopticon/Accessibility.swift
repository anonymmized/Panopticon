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
        let element: AXUIElement
    }

    enum WindowError: Error { case permission, unavailable }

    static func windows(of app: NSRunningApplication) -> [Window] {
        (try? windowList(of: app).get()) ?? []
    }

    static func windowList(of app: NSRunningApplication, cancelled: () -> Bool = { false }) -> Result<[Window], WindowError> {
        guard trusted else { return .failure(.permission) }
        guard !app.isTerminated, !cancelled() else { return .failure(.unavailable) }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { return .failure(.unavailable) }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        var result: [Window] = []
        for window in windows.prefix(30) {
            guard !cancelled(), ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(window, 0.15)
            guard (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole else { continue }
            let title = attribute(window, kAXTitleAttribute) as? String ?? ""
            result.append(Window(title: title,
                minimized: attribute(window, kAXMinimizedAttribute) as? Bool ?? false, element: window))
        }
        return .success(result)
    }

    @discardableResult static func focus(_ window: Window, of app: NSRunningApplication) -> Bool {
        guard trusted, !app.isTerminated else { return false }
        AXUIElementSetMessagingTimeout(window.element, 0.2)
        if (attribute(window.element, kAXMinimizedAttribute) as? Bool) ?? window.minimized {
            guard AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { return false }
        }
        _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success
    }
}
