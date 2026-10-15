import AppKit
import OSLog

struct CommandResult {
    let status: Int32
    let output: String
}

/// The backup is deliberately separate from normal preferences. Never export it
/// as a user's panel configuration, overwrite it on relaunch, or discard a failed restore.
final class DockIntegration: ObservableObject {
    @Published private(set) var message = ""
    @Published private(set) var recoveryPending = false
    @Published private(set) var isReplacing = false
    func relocalizeStatus() { message = Localization.shared.status(message) }
    private let defaults: UserDefaults
    private let execute: (String, [String]) -> CommandResult
    private let readDomain: () -> [String: Any]
    private let backupKey = "systemDockBackup"
    private static let keys = ["autohide", "autohide-delay", "autohide-time-modifier"]
    private static let log = Logger(subsystem: "app.newmacbar.desktop", category: "SystemDock")

    init(
        defaults: UserDefaults = .standard,
        readDomain: @escaping () -> [String: Any] = {
            UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        },
        execute: @escaping (String, [String]) -> CommandResult = DockIntegration.command
    ) {
        self.defaults = defaults
        self.execute = execute
        self.readDomain = readDomain
    }
    var hasBackup: Bool { defaults.object(forKey: backupKey) != nil }
    static func command(_ executable: String, _ args: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(
                status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        } catch { return CommandResult(status: -1, output: error.localizedDescription) }
    }
    private func valid(_ backup: [String: Any]) -> Bool {
        guard Set(backup.keys) == Set(Self.keys) else { return false }
        return Self.keys.allSatisfy { key in
            if let string = backup[key] as? String { return string == "__absent__" }
            guard let number = backup[key] as? NSNumber, number.doubleValue.isFinite else { return false }
            return key != "autohide" || number.doubleValue == 0 || number.doubleValue == 1
        }
    }
    func prepareRecovery() {
        guard hasBackup else { return }
        recoveryPending = true
        message =
            L("Предыдущая сессия оставила копию настроек Dock. Верни системный Dock или продолжи использовать Panopticon.")
    }
    @discardableResult func enable() -> Bool {
        if !hasBackup {
            let domain = readDomain()
            let backup = Dictionary(uniqueKeysWithValues: Self.keys.map { ($0, domain[$0] ?? "__absent__") })
            guard valid(backup) else {
                message = L("Настройки системного Dock имеют неподдерживаемый формат. Изменения не внесены.")
                return false
            }
            defaults.set(backup, forKey: backupKey)
            defaults.synchronize()
        }
        guard let backup = defaults.dictionary(forKey: backupKey), valid(backup) else {
            message = L("Копия настроек Dock повреждена. Она сохранена; автоматическое изменение остановлено.")
            Self.log.error("Invalid Dock recovery backup; no system preferences changed")
            return false
        }
        guard defaults.synchronize() else {
            message = L("Не удалось сохранить копию настроек Dock. Системный Dock не изменён.")
            Self.log.error("Could not persist Dock backup; replacement skipped")
            return false
        }
        recoveryPending = false
        let ok =
            execute("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"]).status == 0
            && execute("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "3600"])
                .status == 0
            && execute(
                "/usr/bin/defaults", ["write", "com.apple.dock", "autohide-time-modifier", "-float", "0"]
            ).status == 0
        if ok {
            isReplacing = true
            _ = execute("/usr/bin/killall", ["Dock"])
            message = L("На рабочем столе работает Panopticon. В Mission Control новая панель скрывается и уступает место системному Dock.")
        } else {
            _ = restore()
            message =
                hasBackup
                ? L("Не удалось скрыть Dock. Копия сохранена; повтори восстановление.")
                : L("Не удалось скрыть Dock. Исходные настройки восстановлены.")
            Self.log.error("Dock replacement failed; attempted rollback")
        }
        return ok
    }
    @discardableResult func restore() -> Bool {
        guard hasBackup else {
            recoveryPending = false
            isReplacing = false
            return true
        }
        guard let backup = defaults.dictionary(forKey: backupKey), valid(backup) else {
            message = L("Копия настроек Dock повреждена. Она сохранена; восстановление остановлено.")
            Self.log.error("Invalid Dock backup; restore skipped")
            return false
        }
        var success = true
        for key in Self.keys {
            let value = backup[key]!
            if let string = value as? String, string == "__absent__" {
                let removed = execute("/usr/bin/defaults", ["delete", "com.apple.dock", key])
                if removed.status != 0 {
                    let check = execute("/usr/bin/defaults", ["read", "com.apple.dock", key])
                    success = (check.status == 1 && check.output.contains("does not exist")) && success
                }
            } else {
                let number = value as! NSNumber
                let arguments =
                    key == "autohide"
                    ? ["-bool", number.boolValue ? "true" : "false"] : ["-float", number.stringValue]
                success =
                    (execute("/usr/bin/defaults", ["write", "com.apple.dock", key] + arguments).status == 0)
                    && success
            }
        }
        if success {
            defaults.removeObject(forKey: backupKey)
            defaults.synchronize()
            recoveryPending = false
            isReplacing = false
        }
        _ = execute("/usr/bin/killall", ["Dock"])
        message =
            success
            ? L("Системный Dock восстановлен.")
            : L("Восстановление не завершено. Копия сохранена; повтори попытку.")
        if !success { Self.log.error("Dock restore incomplete; retained recovery backup") }
        return success
    }
}
