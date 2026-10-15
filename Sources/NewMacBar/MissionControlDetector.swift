import AppKit

/// A permission-free hint used in addition to AppKit's .transient behavior.
/// Reads only the Dock's window owner/layer/bounds, never titles or window images.
/// Dock overlay metadata is undocumented; .transient remains the system fallback.
enum MissionControlDetector {
    private static var sampledAt: TimeInterval = -.infinity
    private static var cached = false

    static func isActive() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - sampledAt >= 0.15 else { return cached }
        sampledAt = now
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { cached = false; return false }
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(id.uint32Value)
        }
        cached = detectsOverview(windows, dockPID: dock.processIdentifier, displays: displays)
        return cached
    }

    static func detectsOverview(_ windows: [[String: Any]], dockPID: pid_t, displays: [CGRect]) -> Bool {
        windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dockPID,
                (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 18,
                (window[kCGWindowSharingState as String] as? NSNumber)?.intValue == 0,
                let value = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: value),
                bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0
            else { return false }
            return displays.contains { display in
                guard display.width > 0, display.height > 0 else { return false }
                let overlap = display.intersection(bounds)
                return !overlap.isNull && overlap.width * overlap.height >= display.width * display.height * 0.7
            }
        }
    }
}
