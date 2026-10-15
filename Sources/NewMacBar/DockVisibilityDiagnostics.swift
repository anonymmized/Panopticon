import AppKit

/// Local read-only diagnostics for reproducing visibility problems in the real
/// running process. No app names, window titles, paths or pointer coordinates.
enum DockVisibilityDiagnostics {
    static let request = Notification.Name("app.newmacbar.desktop.visibility.request")
    static let response = Notification.Name("app.newmacbar.desktop.visibility.response")

    static func query() -> Int32 {
        let id = Bundle.main.bundleIdentifier ?? "app.newmacbar.desktop"
        let center = DistributedNotificationCenter.default()
        let token = UUID().uuidString
        var snapshot: [String: Any]?
        let observer = center.addObserver(forName: response, object: id, queue: nil) { notification in
            guard notification.userInfo?["token"] as? String == token else { return }
            snapshot = notification.userInfo?["snapshot"] as? [String: Any]
        }
        defer { center.removeObserver(observer) }
        center.postNotificationName(request, object: id, userInfo: ["token": token], deliverImmediately: true)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while snapshot == nil && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard let snapshot,
            let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
            let json = String(data: data, encoding: .utf8)
        else { print("Running NewMacBar did not answer the visibility query."); return 1 }
        print(json)
        return 0
    }
}
