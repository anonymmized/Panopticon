import AppKit

/// Reads the Dock's launchers without ever writing its persistent-apps domain.
/// Bundle identifiers recover launchers whose path changed during an app update.
enum SystemDockImport {
    static func items(
        from domain: [String: Any],
        applicationURL: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) -> [DockItem] {
        var result: [DockItem] = []
        var paths = Set<String>()
        var bundles = Set<String>()
        func append(_ url: URL) {
            let url = url.resolvingSymlinksInPath().standardizedFileURL
            guard url.isFileURL, url.pathExtension.lowercased() == "app",
                FileManager.default.fileExists(atPath: url.path),
                let bundleID = Bundle(url: url)?.bundleIdentifier,
                !paths.contains(url.path), !bundles.contains(bundleID)
            else { return }
            paths.insert(url.path)
            bundles.insert(bundleID)
            result.append(DockItem(url: url))
        }
        // Finder is a permanent launcher in the native Dock, even on systems
        // where it is not included in persistent-apps.
        append(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        for tile in domain["persistent-apps"] as? [[String: Any]] ?? [] {
            guard let data = tile["tile-data"] as? [String: Any] else { continue }
            let file = data["file-data"] as? [String: Any]
            if let path = file?["_CFURLString"] as? String {
                let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(string: path)
                if let url { append(url) }
            }
            if let bundleID = data["bundle-identifier"] as? String,
                !bundles.contains(bundleID), let resolved = applicationURL(bundleID)
            {
                append(resolved)
            }
        }
        return result
    }
}
