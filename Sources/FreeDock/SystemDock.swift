import AppKit

/// Talks to the system Dock: imports its apps and can hide it so FreeDock replaces it.
/// The original values are backed up in FreeDock's own preferences, so they can be
/// restored even after a crash.
enum SystemDock {
    private static let domain = "com.apple.dock" as CFString
    private static let defaults = UserDefaults.standard
    private static let backupKey = "systemDockBackup"
    private static let absent = "__absent__"
    private static let keys = ["autohide", "autohide-delay", "autohide-time-modifier"]

    /// Apps and folders pinned in the system Dock.
    static func persistentItems() -> [URL] {
        ["persistent-apps", "persistent-others"].flatMap { key -> [URL] in
            let tiles = CFPreferencesCopyAppValue(key as CFString, domain) as? [[String: Any]] ?? []
            return tiles.compactMap { tile in
                let data = tile["tile-data"] as? [String: Any]
                let file = data?["file-data"] as? [String: Any]
                guard let string = file?["_CFURLString"] as? String,
                      let url = URL(string: string), url.isFileURL,
                      FileManager.default.fileExists(atPath: url.path) else { return nil }
                return url
            }
        }
    }

    static var isHiddenByUs: Bool { defaults.dictionary(forKey: backupKey) != nil }

    /// Makes the system Dock auto-hide with a one-hour delay and no animation, so it never shows up.
    static func hide() {
        if !isHiddenByUs {
            var backup: [String: Any] = [:]
            for key in keys { backup[key] = value(key) ?? absent }
            defaults.set(backup, forKey: backupKey)
        }
        set("autohide", true as NSNumber)
        set("autohide-delay", 3600.0 as NSNumber)
        set("autohide-time-modifier", 0.0 as NSNumber)
        restart()
    }

    static func restore() {
        guard let backup = defaults.dictionary(forKey: backupKey) else { return }
        for key in keys {
            let saved = backup[key]
            if saved == nil || (saved as? String) == absent {
                set(key, nil)
            } else {
                set(key, saved as? NSNumber)
            }
        }
        defaults.removeObject(forKey: backupKey)
        restart()
    }

    private static func value(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }

    private static func set(_ key: String, _ value: NSNumber?) {
        CFPreferencesSetAppValue(key as CFString, value, domain)
        CFPreferencesAppSynchronize(domain)
    }

    private static func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }
}
