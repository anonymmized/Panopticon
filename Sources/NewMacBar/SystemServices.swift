import AppKit
import EventKit
import OSLog
import ServiceManagement
import SwiftUI

final class LoginService: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error = ""
    private var observer: NSObjectProtocol?
    private let log = Logger(subsystem: "app.newmacbar.desktop", category: "LoginItem")
    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    var selected: Bool { status == .enabled || status == .requiresApproval }
    var summary: String {
        switch status {
        case .enabled: return "Включён в macOS"
        case .requiresApproval: return "Нужно подтверждение в настройках macOS"
        case .notFound: return "Приложение недоступно для автозапуска. Перенеси его в «Программы»."
        case .notRegistered: return "Выключен"
        @unknown default: return "Статус macOS недоступен"
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = ""
        } catch {
            self.error = "Не удалось изменить автозапуск. Проверь «Объекты входа» в macOS."
            log.error("Login item change failed: \(error.localizedDescription, privacy: .private)")
        }
        refresh()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

enum LocalDiagnostics {
    static func report(
        model: BarModel, dock: DockIntegration, agenda: CalendarController, login: LoginService
    ) -> String {
        let report: [String: Any] = [
            "schema": 1,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "development",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": architecture,
            "displays": NSScreen.screens.map {
                [
                    "width": Int($0.frame.width), "height": Int($0.frame.height),
                    "scale": Int($0.backingScaleFactor),
                ]
            },
            "panel": [
                "edge": model.edge, "visible": model.barVisible, "autoHide": model.autoHide,
                "followMouse": model.followMouse,
            ] as [String: Any],
            "systemDock": [
                "replacementRequested": model.replaceDock, "replacementActive": dock.isReplacing,
                "backupPresent": dock.hasBackup, "recoveryPending": dock.recoveryPending,
            ],
            "permissions": [
                "accessibility": AX.trusted,
                "calendar": EKEventStore.authorizationStatus(for: .event).rawValue,
            ],
            "sources": [
                "calendarEnabled": model.calendarEventsEnabled, "calendarAuthorized": agenda.authorized,
                "playerPreference": model.playerPreference,
            ] as [String: Any],
            "shortcuts": [
                "launcherEnabled": model.launcherEnabled,
                "launcherRegistered": model.launcherShortcutAvailable,
                "launcherChoice": model.launcherShortcutChoice,
            ] as [String: Any],
            "loginStatus": login.status.rawValue,
            "accessibility": [
                "reduceMotion": Studio.reduceMotion,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                "increaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            ],
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
    /// Avoid BarModel.init here: initialization migrates/saves preferences.
    static func commandReport(defaults: UserDefaults = .standard) -> String {
        let report: [String: Any] = [
            "schema": 1,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
            "architecture": architecture,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "displays": NSScreen.screens.map { ["width": Int($0.frame.width), "height": Int($0.frame.height), "scale": Int($0.backingScaleFactor)] },
            "permissions": ["accessibility": AX.trusted, "calendar": EKEventStore.authorizationStatus(for: .event).rawValue] as [String: Any],
            "loginStatus": SMAppService.mainApp.status.rawValue,
            "systemDockBackupPresent": defaults.object(forKey: "systemDockBackup") != nil,
            "sessionMarkerPresent": defaults.object(forKey: "platform.activeSession") != nil,
            "panelEdge": SettingsRules.choice(defaults.string(forKey: "edge") ?? "bottom", DockEdge.allCases.map(\.rawValue), fallback: "bottom"),
            "launcherRegistration": "Available in the running application's report",
            "runningInstances": NSRunningApplication.runningApplications(withBundleIdentifier: "app.newmacbar.desktop").filter { !$0.isTerminated }.count
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
    static var architecture: String {
        #if arch(arm64)
            return "arm64"
        #else
            return "x86_64"
        #endif
    }
}

struct DiagnosticSnapshot: Identifiable { let id = UUID(); let text: String }

struct DiagnosticsView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Локальная диагностика").font(.title2.bold())
            Text(
                "Проверь содержимое перед сохранением. Здесь нет имён файлов, путей, событий, адресов сайтов и идентификаторов экранов. Отправки данных нет."
            ).foregroundStyle(.secondary)
            ScrollView {
                Text(report).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(
                    maxWidth: .infinity, alignment: .leading
                ).padding(12)
            }.background(Studio.surface, in: RoundedRectangle(cornerRadius: 10))
            if !message.isEmpty { Text(message).foregroundStyle(.orange) }
            HStack {
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить файл…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "NewMacBar-diagnostics.json"
                    panel.allowedContentTypes = [.json]
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    do {
                        try Data(report.utf8).write(to: url, options: .atomic)
                        message = "Файл сохранён."
                    } catch { message = "Не удалось сохранить файл. Выбери другую папку." }
                }.keyboardShortcut(.defaultAction)
            }
        }.font(Studio.body).padding(24).frame(width: 600, height: 500)
    }
}
