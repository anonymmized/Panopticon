import AppKit
import SwiftUI

extension SettingsView {
    var recoveryCard: some View {
        StudioCard("Вернуть привычный Dock") {
            Text(dock.message).font(Studio.body).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Восстановить Dock") {
                    model.replaceDock = false
                    dock.restore()
                }.buttonStyle(.borderedProminent)
                Button("Продолжить с NewMacBar") {
                    model.replaceDock = true
                    dock.enable()
                }
            }
        }
    }
    var system: some View {
        VStack(alignment: .leading, spacing: 22) {
            StudioCard("Автозапуск") {
                Toggle(
                    "Открывать при входе в macOS",
                    isOn: Binding(get: { login.selected }, set: { login.setEnabled($0) }))
                Text(login.summary).font(Studio.caption).foregroundStyle(.secondary)
                if !login.error.isEmpty {
                    Label(login.error, systemImage: "exclamationmark.triangle").font(Studio.caption)
                        .foregroundStyle(.orange)
                }
                Button("Объекты входа в macOS…") { login.openSettings() }
            }
            StudioCard("Восстановление системного Dock") {
                Text(
                    "При обычном выходе NewMacBar возвращает прежние настройки Dock. После принудительного завершения восстановление доступно при следующем запуске и из строки меню."
                ).font(Studio.body).foregroundStyle(.secondary)
                Button("Вернуть системный Dock") {
                    model.replaceDock = false
                    dock.restore()
                }
                if !dock.message.isEmpty {
                    Text(dock.message).font(Studio.caption).foregroundStyle(.secondary)
                }
                Text("В Mission Control macOS показывает собственную панель, даже если замена Dock включена.")
                    .font(Studio.caption).foregroundStyle(.secondary)
            }
            StudioCard("Разрешения") {
                permissionRow(
                    "Универсальный доступ",
                    detail: AX.trusted
                        ? "Доступ подключён: окна и бейджи приложений"
                        : "Не подключён. Приложения и поиск работают без него.", symbol: "accessibility"
                ) { AX.requestTrust() }
                permissionRow(
                    "Календари",
                    detail: agenda.authorized
                        ? "Доступ подключён" : "Подключаются по кнопке в разделе «Связи и действия»",
                    symbol: "calendar"
                ) { section = "connections" }
                permissionRow(
                    "Управление плеером",
                    detail:
                        "Spotify и Music спрашивают доступ при первом управлении. Статус доступен в музыкальном виджете.",
                    symbol: "music.note"
                ) {
                    NSWorkspace.shared.open(
                        URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                    )
                }
            }
            StudioCard("Диагностика на этом Mac") {
                Text(
                    "Технический отчёт без содержимого календарей и личных путей. Перед сохранением можно проверить весь текст."
                ).font(Studio.body).foregroundStyle(.secondary)
                Button("Предпросмотр отчёта…") {
                    diagnosticReport = DiagnosticSnapshot(text: LocalDiagnostics.report(
                        model: model, dock: dock, agenda: agenda, login: login))
                }
                Text(
                    "Профили можно экспортировать в разделе «Стили и профили»; пространства FreeDock импортируются в разделе «Пространства»."
                ).font(Studio.caption).foregroundStyle(.secondary)
            }
        }
    }
    func permissionRow(_ title: String, detail: String, symbol: String, action: @escaping () -> Void)
        -> some View
    {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Studio.body)
                Text(detail).font(Studio.caption).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
            Spacer()
            Button("Настроить…", action: action).accessibilityLabel("Настроить " + title)
        }
    }
    var shortcuts: some View {
        VStack(alignment: .leading, spacing: 22) {
            StudioCard("Поиск") {
                Toggle("Включить глобальную клавишу", isOn: $model.launcherEnabled)
                Picker("Сочетание", selection: $model.launcherShortcutChoice) {
                    Text("⌃⌥Пробел").tag("controlOptionSpace")
                    Text("⌘⇧Пробел").tag("commandShiftSpace")
                    Text("⌥⇧Пробел").tag("optionShiftSpace")
                }
                Label(
                    model.launcherEnabled && model.launcherShortcutAvailable
                        ? "Клавиша подключена"
                        : "Поиск доступен в строке меню. Если сочетание занято, выбери другое.",
                    systemImage: model.launcherEnabled && model.launcherShortcutAvailable
                        ? "checkmark.circle" : "info.circle"
                ).font(Studio.caption).foregroundStyle(.secondary)
                Button("Открыть поиск") {
                    NotificationCenter.default.post(name: .openBarLauncher, object: nil)
                }
            }
            StudioCard("Панель и пространства") {
                shortcutRow("Выбрать пространство 1–9", "⌃⌥1–9")
                shortcutRow("Предыдущее / следующее", "⌃⌥← / →")
                shortcutRow("Показать / скрыть панель", "⌃⌥D")
                shortcutRow("Настройки в приложении", "⌘,")
                Text("В поиске: ↑ / ↓ — выбрать, Enter — открыть, ⌘Enter — закрепить, Escape — закрыть.")
                    .font(Studio.caption).foregroundStyle(.secondary)
            }
        }
    }
    func shortcutRow(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(key).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
    var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            StudioCard("NewMacBar") {
                Text("Панель для приложений, пространств и маленьких ежедневных дел.").font(.title3)
                Text(
                    "Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") · \(LocalDiagnostics.architecture) · macOS 13+"
                ).font(Studio.caption).foregroundStyle(.secondary)
                Text(
                    "Без подписки, телеметрии и облачной учётной записи. Календарь использует источники macOS, а кнопки открытия — выбранные тобой приложения."
                ).font(Studio.body).foregroundStyle(.secondary)
                Button("Настроить с самого начала…") { showOnboarding = true }
            }
            StudioCard("Интерфейс") {
                Picker("Оформление окон", selection: $ui.appearance) {
                    Text("Как в macOS").tag("system")
                    Text("Светлое").tag("light")
                    Text("Тёмное").tag("dark")
                }
                Text("Оформление самой панели выбирается отдельно в разделе «Внешний вид».").font(
                    Studio.caption
                ).foregroundStyle(.secondary)
            }
            DisclosureGroup("Компоненты интерфейса") { ComponentGallery().padding(.top, 16) }
        }
    }
}

extension Notification.Name {
    static let openBarLauncher = Notification.Name("NewMacBar.openLauncher")
    static let openBarOnboarding = Notification.Name("NewMacBar.openOnboarding")
}
