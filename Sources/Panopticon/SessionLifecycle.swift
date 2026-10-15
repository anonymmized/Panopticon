import AppKit
import Darwin

/// Written only by the winning instance, before services and UI are created.
final class SessionLifecycle {
    static let restoreNotification = Notification.Name("app.newmacbar.desktop.restoreSystemDock")
    static let restoredNotification = Notification.Name("app.newmacbar.desktop.restoredSystemDock")
    private let defaults: UserDefaults
    private let key = "platform.activeSession"
    private let lockURL: URL
    private var descriptor: Int32?
    private(set) var claimError: String?
    static var defaultLockURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.newmacbar.desktop", isDirectory: true).appendingPathComponent("session.lock")
    }
    init(defaults: UserDefaults = .standard, lockURL: URL = SessionLifecycle.defaultLockURL) { self.defaults = defaults; self.lockURL = lockURL }
    /// Launch Services does not list every directly executed accessory process.
    /// The kernel releases this lock even after SIGKILL; the recovery marker stays.
    func claim() -> Bool {
        if descriptor != nil { return true }
        claimError = nil
        do { try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { claimError = L("Не удалось открыть папку сессии в Application Support."); return false }
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { claimError = L("Не удалось открыть файл сессии. Проверь доступ к Application Support."); return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let busy = errno == EWOULDBLOCK || errno == EAGAIN; close(fd)
            if !busy { claimError = L("Не удалось заблокировать файл сессии.") }
            return false
        }
        descriptor = fd; return true
    }
    private func release() { if let descriptor { flock(descriptor, LOCK_UN); close(descriptor); self.descriptor = nil } }
    deinit { release() }
    static var runningUnderLock: Bool {
        let fd = open(defaultLockURL.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return errno != ENOENT }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { flock(fd, LOCK_UN); return false }
        return true
    }
    @discardableResult func begin() -> Bool {
        let interrupted = defaults.dictionary(forKey: key) != nil
        defaults.set(["pid": Int(ProcessInfo.processInfo.processIdentifier), "started": Date()], forKey: key)
        defaults.synchronize()
        return interrupted
    }
    func finish() {
        defaults.removeObject(forKey: key)
        defaults.synchronize()
        release()
    }

    static func restoreFromCommandLine() -> Int32 {
        let id = Bundle.main.bundleIdentifier ?? "app.newmacbar.desktop"
        if runningUnderLock || NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
        }) {
            let center = DistributedNotificationCenter.default()
            let token = UUID().uuidString
            var outcome: Bool?
            let observer = center.addObserver(forName: restoredNotification, object: id, queue: nil) { notification in
                guard notification.userInfo?["token"] as? String == token else { return }
                outcome = notification.userInfo?["success"] as? Bool
            }
            defer { center.removeObserver(observer) }
            center.postNotificationName(restoreNotification, object: id, userInfo: ["token": token], deliverImmediately: true)
            let deadline = Date().addingTimeInterval(3)
            while outcome == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            if let outcome { print(outcome ? L("Системный Dock восстановлен.") : L("Восстановление не завершено. Копия сохранена; проверь сообщение в настройках.")); return outcome ? 0 : 1 }
            print(L("Работающий экземпляр не подтвердил восстановление. Заверши Panopticon из строки меню и повтори команду."))
            return 1
        }
        let dock = DockIntegration()
        let result = dock.restore()
        print(dock.message.isEmpty ? L("Сохранённой копии настроек Dock нет.") : dock.message)
        return result ? 0 : 1
    }
}
