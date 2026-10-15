import AppKit
import SwiftUI

extension SettingsView {
    var recoveryCard: some View {
        StudioCard(L("Вернуть привычный Dock")) {
            Text(localization.status(dock.message)).font(Studio.body).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("Восстановить Dock")) {
                    model.replaceDock = false
                    dock.restore()
                }.buttonStyle(.borderedProminent)
                Button(L("Продолжить с Panopticon")) {
                    model.replaceDock = true
                    dock.enable()
                }
            }
        }
    }
    var system: some View {
        VStack(alignment: .leading, spacing: 22) {
            StudioCard(L("Автозапуск")) {
                Toggle(
                    L("Открывать при входе в macOS"),
                    isOn: Binding(get: { login.selected }, set: { login.setEnabled($0) }))
                Text(login.summary).font(Studio.caption).foregroundStyle(.secondary)
                if !login.error.isEmpty {
                    Label(login.error, systemImage: "exclamationmark.triangle").font(Studio.caption)
                        .foregroundStyle(.orange)
                }
                Button(L("Объекты входа в macOS…")) { login.openSettings() }
            }
            StudioCard(L("Восстановление системного Dock")) {
                Text(
                    L("При обычном выходе Panopticon возвращает прежние настройки Dock. После принудительного завершения восстановление доступно при следующем запуске и из строки меню.")
                ).font(Studio.body).foregroundStyle(.secondary)
                Button(L("Вернуть системный Dock")) {
                    model.replaceDock = false
                    dock.restore()
                }
                if !dock.message.isEmpty {
                    Text(localization.status(dock.message)).font(Studio.caption).foregroundStyle(.secondary)
                }
                Text(L("В Mission Control macOS показывает собственную панель, даже если замена Dock включена."))
                    .font(Studio.caption).foregroundStyle(.secondary)
            }
            StudioCard(L("Разрешения")) {
                permissionRow(
                    L("Универсальный доступ"),
                    detail: AX.trusted
                        ? L("Доступ подключён: окна и бейджи приложений")
                        : L("Не подключён. Приложения и поиск работают без него."), symbol: "accessibility"
                ) { AX.requestTrust() }
                permissionRow(
                    L("Календари"),
                    detail: agenda.authorized
                        ? L("Доступ подключён") : L("Подключаются по кнопке в разделе «Связи и действия»"),
                    symbol: "calendar"
                ) { section = "connections" }
                permissionRow(
                    L("Управление плеером"),
                    detail:
                        L("Spotify и Music спрашивают доступ при первом управлении. Статус доступен в музыкальном виджете."),
                    symbol: "music.note"
                ) {
                    NSWorkspace.shared.open(
                        URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                    )
                }
            }
            StudioCard(L("Диагностика на этом Mac")) {
                Text(
                    L("Технический отчёт без содержимого календарей и личных путей. Перед сохранением можно проверить весь текст.")
                ).font(Studio.body).foregroundStyle(.secondary)
                Button(L("Предпросмотр отчёта…")) {
                    diagnosticReport = DiagnosticSnapshot(text: LocalDiagnostics.report(
                        model: model, dock: dock, agenda: agenda, login: login))
                }
                Text(
                    L("Профили можно экспортировать в разделе «Стили и профили»; пространства импортируются в разделе «Пространства».")
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
            Button(L("Настроить…"), action: action).accessibilityLabel(L("Настроить ") + title)
        }
    }
    var shortcuts: some View {
        VStack(alignment: .leading, spacing: 22) {
            StudioCard(L("Поиск")) {
                Toggle(L("Включить глобальную клавишу"), isOn: $model.launcherEnabled)
                Picker(L("Сочетание"), selection: $model.launcherShortcutChoice) {
                    Text(L("⌃⌥Пробел")).tag("controlOptionSpace")
                    Text(L("⌘⇧Пробел")).tag("commandShiftSpace")
                    Text(L("⌥⇧Пробел")).tag("optionShiftSpace")
                }
                Label(
                    model.launcherEnabled && model.launcherShortcutAvailable
                        ? L("Клавиша подключена")
                        : L("Поиск доступен в строке меню. Если сочетание занято, выбери другое."),
                    systemImage: model.launcherEnabled && model.launcherShortcutAvailable
                        ? "checkmark.circle" : "info.circle"
                ).font(Studio.caption).foregroundStyle(.secondary)
                Button(L("Открыть поиск")) {
                    NotificationCenter.default.post(name: .openBarLauncher, object: nil)
                }
            }
            StudioCard(L("Панель и пространства")) {
                shortcutRow(L("Выбрать пространство 1–9"), "⌃⌥1–9")
                shortcutRow(L("Предыдущее / следующее"), "⌃⌥← / →")
                shortcutRow(L("Показать / скрыть панель"), "⌃⌥D")
                shortcutRow(L("Настройки в приложении"), "⌘,")
                Text(L("В поиске: ↑ / ↓ — выбрать, Enter — открыть, ⌘Enter — закрепить, Escape — закрыть."))
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
            StudioCard("Panopticon") {
                Text(L("Панель для приложений, пространств и маленьких ежедневных дел.")).font(.title3)
                Text(
                    L("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") · \(LocalDiagnostics.architecture) · macOS 13+")
                ).font(Studio.caption).foregroundStyle(.secondary)
                Text(
                    L("Без подписки, телеметрии и облачной учётной записи. Календарь использует источники macOS, а кнопки открытия — выбранные тобой приложения.")
                ).font(Studio.body).foregroundStyle(.secondary)
                Button(L("Настроить с самого начала…")) { showOnboarding = true }
            }
            StudioCard(L("Интерфейс")) {
                Picker(L("Оформление окон"), selection: $ui.appearance) {
                    Text(L("Как в macOS")).tag("system")
                    Text(L("Светлое")).tag("light")
                    Text(L("Тёмное")).tag("dark")
                }
                Text(L("Оформление самой панели выбирается отдельно в разделе «Внешний вид».")).font(
                    Studio.caption
                ).foregroundStyle(.secondary)
            }
            DisclosureGroup(L("Компоненты интерфейса")) { ComponentGallery().padding(.top, 16) }
        }
    }
}

extension Notification.Name {
    static let openBarLauncher = Notification.Name("Panopticon.openLauncher")
    static let openBarOnboarding = Notification.Name("Panopticon.openOnboarding")
}
