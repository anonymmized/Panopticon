import AppKit

/// Saves exact prior preference values before changing the Dock. Restoration also
/// works after an interrupted session because the backup lives in our own domain.
struct CommandResult { let status: Int32; let output: String }

final class DockIntegration: ObservableObject {
    @Published var message = ""
    private let defaults: UserDefaults
    private let execute: (String, [String]) -> CommandResult
    private let backupKey = "systemDockBackup"
    private let keys = ["autohide", "autohide-delay", "autohide-time-modifier"]
    init(defaults: UserDefaults = .standard, execute: @escaping (String, [String]) -> CommandResult = DockIntegration.command) {
        self.defaults = defaults; self.execute = execute
    }
    static func command(_ executable: String, _ args: [String]) -> CommandResult {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "C"; process.environment = environment
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return CommandResult(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "") }
        catch { return CommandResult(status: -1, output: error.localizedDescription) }
    }
    func enable() {
        if defaults.dictionary(forKey: backupKey) == nil {
            let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
            var backup: [String: Any] = [:]
            for key in keys { backup[key] = domain[key] ?? "__absent__" }
            defaults.set(backup, forKey: backupKey); defaults.synchronize()
        }
        let ok = execute("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"]).status == 0
            && execute("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "3600"]).status == 0
            && execute("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-time-modifier", "-float", "0"]).status == 0
        if ok { _ = execute("/usr/bin/killall", ["Dock"]); message = L("Dock скрыт на рабочем столе. В Mission Control видна системная панель macOS.") }
        else { restore(); message = L("Не удалось скрыть Dock. Исходные настройки сохранены для восстановления.") }
    }
    func restore() {
        guard let backup = defaults.dictionary(forKey: backupKey) else { return }
        var success = true
        for key in keys {
            guard let value = backup[key] else { success = false; continue }
            if let string = value as? String, string == "__absent__" {
                let removed = execute("/usr/bin/defaults", ["delete", "com.apple.dock", key])
                if removed.status != 0 {
                    let check = execute("/usr/bin/defaults", ["read", "com.apple.dock", key])
                    success = (check.status == 1 && check.output.contains("does not exist")) && success
                }
            } else if key == "autohide" {
                success = (execute("/usr/bin/defaults", ["write", "com.apple.dock", key, "-bool", (value as? NSNumber)?.boolValue == true ? "true" : "false"]).status == 0) && success
            } else {
                success = (execute("/usr/bin/defaults", ["write", "com.apple.dock", key, "-float", "\(value)"]).status == 0) && success
            }
        }
        if success { defaults.removeObject(forKey: backupKey); defaults.synchronize() }
        _ = execute("/usr/bin/killall", ["Dock"])
        message = success ? L("Системный Dock восстановлен.") : L("Восстановление не завершено. Копия прежних настроек сохранена; повтори попытку.")
    }
}

struct AppCollection: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var symbol = "square.grid.2x2.fill"
    var paths: [String] = []
    var items: [DockItem] { paths.map { DockItem(url: URL(fileURLWithPath: $0)) }.filter { $0.url.pathExtension.lowercased() == "app" && $0.bundleID != nil && FileManager.default.fileExists(atPath: $0.id) } }
}

final class FocusTimer: ObservableObject {
    @Published var remaining: Double = 25 * 60
    @Published var isRunning = false
    @Published private(set) var sessionDuration: Double = 25 * 60
    var soundEnabled = true
    var onChange: (() -> Void)?
    private var endDate: Date?
    private var timer: Timer?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.dictionary(forKey: "focusSession") {
            remaining = SettingsRules.number(saved["remaining"] as? Double ?? 1500, 0...5400, fallback: 1500)
            sessionDuration = SettingsRules.number(saved["duration"] as? Double ?? 1500, 1...5400, fallback: 1500)
            if let end = saved["end"] as? Date { remaining = SettingsRules.number(end.timeIntervalSinceNow, 0...sessionDuration, fallback: 0); endDate = Date().addingTimeInterval(remaining); isRunning = remaining > 0; if isRunning { startTicker() } else { endDate = nil; persist() } }
        }
    }
    deinit { timer?.invalidate() }
    func toggle(minutes: Double) {
        if isRunning { remaining = max(0, endDate?.timeIntervalSinceNow ?? remaining); endDate = nil; isRunning = false; timer?.invalidate(); timer = nil }
        else { if remaining <= 0 { remaining = minutes * 60; sessionDuration = remaining }; endDate = Date().addingTimeInterval(remaining); isRunning = true; startTicker() }
        persist(); onChange?()
    }
    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let end = self.endDate else { return }
            self.remaining = max(0, end.timeIntervalSinceNow)
            if self.remaining == 0 { self.endDate = nil; self.isRunning = false; self.timer?.invalidate(); self.timer = nil; self.persist(); if self.soundEnabled { NSSound(named: "Glass")?.play() } }
            self.onChange?()
        }; timer?.tolerance = 0.1
    }
    private func persist() { var state: [String: Any] = ["remaining": remaining, "duration": sessionDuration]; if let endDate { state["end"] = endDate }; defaults.set(state, forKey: "focusSession") }
    func reset(minutes: Double) { timer?.invalidate(); timer = nil; endDate = nil; remaining = minutes * 60; sessionDuration = remaining; isRunning = false; persist(); onChange?() }
    var progress: Double { min(1, max(0, 1 - remaining / max(sessionDuration, 1))) }
    var text: String { let seconds = max(0, Int(ceil(remaining))); return String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
