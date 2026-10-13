import AppKit

/// Saves exact prior preference values before changing the Dock. Restoration also
/// works after an interrupted session because the backup lives in our own domain.
final class DockIntegration: ObservableObject {
    @Published var message = ""
    private let defaults = UserDefaults.standard
    private let backupKey = "systemDockBackup"
    private let keys = ["autohide", "autohide-delay", "autohide-time-modifier"]
    private func run(_ executable: String, _ args: [String]) -> Bool {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
    }
    func enable() {
        if defaults.dictionary(forKey: backupKey) == nil {
            let domain = defaults.persistentDomain(forName: "com.apple.dock") ?? [:]
            var backup: [String: Any] = [:]
            for key in keys { backup[key] = domain[key] ?? "__absent__" }
            defaults.set(backup, forKey: backupKey)
        }
        let ok = run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
            && run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "3600"])
            && run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-time-modifier", "-float", "0"])
        if ok { _ = run("/usr/bin/killall", ["Dock"]); message = "Системный Dock скрыт. Прежние настройки вернутся при выходе." }
        else { restore(); message = "Не удалось скрыть Dock. Включи его автоматическое скрытие в настройках macOS." }
    }
    func restore() {
        guard let backup = defaults.dictionary(forKey: backupKey) else { return }
        var success = true
        for key in keys {
            guard let value = backup[key] else { continue }
            if let string = value as? String, string == "__absent__" {
                // Deleting an absent key is successful even if defaults returns 1.
                _ = run("/usr/bin/defaults", ["delete", "com.apple.dock", key])
            } else if key == "autohide" {
                success = run("/usr/bin/defaults", ["write", "com.apple.dock", key, "-bool", (value as? NSNumber)?.boolValue == true ? "true" : "false"]) && success
            } else {
                success = run("/usr/bin/defaults", ["write", "com.apple.dock", key, "-float", "\(value)"]) && success
            }
        }
        if success { defaults.removeObject(forKey: backupKey) }
        _ = run("/usr/bin/killall", ["Dock"])
        message = success ? "Системный Dock восстановлен." : "Не удалось полностью восстановить Dock. Повтори восстановление."
    }
}

struct AppCollection: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var symbol = "square.grid.2x2.fill"
    var paths: [String] = []
    var items: [DockItem] { paths.map { DockItem(url: URL(fileURLWithPath: $0)) }.filter { FileManager.default.fileExists(atPath: $0.id) } }
}

final class FocusTimer: ObservableObject {
    @Published var remaining: Double = 25 * 60
    @Published var isRunning = false
    private var endDate: Date?
    private var timer: Timer?
    deinit { timer?.invalidate() }
    func toggle(minutes: Double) {
        if isRunning { remaining = max(0, endDate?.timeIntervalSinceNow ?? remaining); endDate = nil; isRunning = false; timer?.invalidate(); timer = nil }
        else {
            if remaining <= 0 { remaining = minutes * 60 }
            endDate = Date().addingTimeInterval(remaining); isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let end = self.endDate else { return }
                self.remaining = max(0, end.timeIntervalSinceNow)
                if self.remaining == 0 { self.endDate = nil; self.isRunning = false; self.timer?.invalidate(); self.timer = nil; NSSound(named: "Glass")?.play() }
            }
            timer?.tolerance = 0.1
        }
    }
    func reset(minutes: Double) { timer?.invalidate(); timer = nil; endDate = nil; remaining = minutes * 60; isRunning = false }
    var text: String { let seconds = max(0, Int(ceil(remaining))); return String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
