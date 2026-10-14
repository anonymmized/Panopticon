import AppKit

// Never called by startup, background refresh or automated tests.
enum TrashActions {
    static func confirmEmpty() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "Очистить Корзину?"
        alert.informativeText = "Все файлы в Корзине будут удалены без возможности восстановления."
        alert.addButton(withTitle: "Отмена"); alert.addButton(withTitle: "Очистить Корзину")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"com.apple.finder\" to empty trash")?.executeAndReturnError(&error)
            if let message = error?[NSAppleScript.errorMessage] as? String {
                DispatchQueue.main.async { ActionRouter.showError(message) }
            }
        }
    }
}
