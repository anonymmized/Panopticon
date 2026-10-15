import AppKit

/// Finds out which macOS desktop (Mission Control space) is active. There is no public API for
/// this, so the private SkyLight calls are looked up at runtime: if Apple removes them, only the
/// auto-switching feature stops working.
enum Desktops {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ names: String...) -> T? {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        for name in names {
            if let pointer = dlsym(skyLight ?? defaultHandle, name) ?? dlsym(defaultHandle, name) {
                return unsafeBitCast(pointer, to: T.self)
            }
        }
        return nil
    }

    private static let mainConnection: MainConnection? = symbol("SLSMainConnectionID", "CGSMainConnectionID")
    private static let copyDisplaySpaces: CopyDisplaySpaces? =
        symbol("SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces")

    /// Number (1-based) of the active desktop on `screen` and how many desktops it has.
    /// Returns nil when a full-screen app is in front or the API is unavailable.
    static func current(for screen: NSScreen?) -> (number: Int, count: Int)? {
        guard let mainConnection, let copyDisplaySpaces,
              let displays = copyDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
        else { return nil }

        let wanted = screen.flatMap(uuid(of:))
        let display = displays.first { ($0["Display Identifier"] as? String) == wanted } ?? displays.first
        guard let display,
              let spaces = display["Spaces"] as? [[String: Any]],
              let active = display["Current Space"] as? [String: Any],
              let activeID = active["ManagedSpaceID"] as? Int
        else { return nil }

        // type 0 — a regular desktop, 4 — a full-screen app.
        let desktops = spaces.filter { ($0["type"] as? Int) == 0 }
        guard let index = desktops.firstIndex(where: { ($0["ManagedSpaceID"] as? Int) == activeID }) else { return nil }
        return (index + 1, desktops.count)
    }

    private static func uuid(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
