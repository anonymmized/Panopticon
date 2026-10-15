import AppKit

enum LaunchTarget: Equatable {
    case application(URL)
    case resource(URL)
}

struct ActionRouter {
    static func calendarTarget(kind: String, appPath: String, webURL: String) -> LaunchTarget? {
        switch kind {
        case "app":
            let url = URL(fileURLWithPath: appPath)
            guard !appPath.isEmpty, url.pathExtension.lowercased() == "app",
                Bundle(url: url)?.bundleIdentifier != nil
            else { return nil }
            return .application(url)
        case "web":
            guard let url = URL(string: webURL), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                url.host != nil
            else { return nil }
            return .resource(url)
        default:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal")
            else { return nil }
            return .application(url)
        }
    }
    static func open(_ target: LaunchTarget?) {
        guard let target else {
            showError("Приложение или ссылка недоступны. Проверь настройку в разделе «Связи и действия».")
            return
        }
        switch target {
        case .application(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { showError(error.localizedDescription) } }
            }
        case .resource(let url):
            if !NSWorkspace.shared.open(url) { showError("Не удалось открыть \(url.lastPathComponent).") }
        }
    }
    static func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Не получилось открыть"
        alert.informativeText = text
        alert.runModal()
    }
}
