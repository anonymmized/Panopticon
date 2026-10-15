import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: BarModel
    @ObservedObject var agenda: CalendarController
    @ObservedObject var dock: DockIntegration
    @ObservedObject var login: LoginService
    @ObservedObject var ui: UIStateStore
    var onFinish: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    private let titles = [
        "Твоё пространство на Mac", "Выбери положение и стиль", "Любимые приложения рядом",
        "Подключи только нужное",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("NewMacBar", systemImage: "dock.rectangle").font(.headline)
                Spacer()
                Text("\(step + 1) из 4").font(Studio.caption).foregroundStyle(.secondary)
                Button("Позже") { finish() }.keyboardShortcut(.cancelAction)
            }
            ProgressView(value: Double(step + 1), total: 4).accessibilityLabel(
                "Шаг настройки \(step + 1) из 4")
            Text(titles[step]).font(.system(size: 28, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if step == 0 {
                        DockPreview(model: model)
                        Text(
                            "Приложения, папки, сайты и виджеты в одной панели. Пространства помогают переключаться между задачами."
                        ).font(.title3)
                        Text(
                            "Все подключения необязательны. Открыть настройки можно из значка NewMacBar в строке меню или правой кнопкой на панели."
                        ).foregroundStyle(.secondary)
                        Label(
                            "Системный Dock остаётся доступным, пока ты сам не включишь замену.",
                            systemImage: "shield.lefthalf.filled")
                    } else if step == 1 {
                        DockPreview(model: model)
                        Picker("Край экрана", selection: $model.edge) {
                            ForEach(DockEdge.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }.pickerStyle(.segmented)
                        Picker("Тема панели", selection: $model.theme) {
                            ForEach(DockTheme.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        ParameterSlider(
                            title: "Размер иконок", value: $model.iconSize, range: 28...60,
                            label: "\(Int(model.iconSize)) px")
                    } else if step == 2 {
                        Text(
                            "Текущий набор содержит \(model.pinned.count) приложений. Их можно дополнить и переставить в настройках."
                        )
                        Button("Взять приложения из системного Dock") {
                            PanelActions.importSystemDock(model: model)
                        }
                        Text(
                            "Импорт добавляет приложения к текущему набору. Реальные приложения и настройки macOS не удаляются."
                        ).font(Studio.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 16) {
                            ForEach(model.pinned.prefix(24)) { item in
                                VStack(spacing: 6) {
                                    Image(nsImage: item.icon).resizable().frame(width: 40, height: 40)
                                    Text(item.name).font(Studio.caption).lineLimit(1)
                                }
                            }
                        }
                    } else {
                        StudioCard("События календарей") {
                            Text(
                                "Виджет читает события из календарей macOS после твоего согласия. Приложение для открытия можно выбрать отдельно в настройках."
                            ).font(Studio.caption).foregroundStyle(.secondary)
                            Button(agenda.authorized ? "Календари подключены" : "Подключить календари…") {
                                model.calendarEventsEnabled = true
                                agenda.enabled = true
                                agenda.connect()
                            }.disabled(agenda.authorized || agenda.loading)
                        }
                        Toggle(
                            "Открывать при входе в macOS",
                            isOn: Binding(get: { login.selected }, set: { login.setEnabled($0) }))
                        Text(login.summary).font(Studio.caption).foregroundStyle(.secondary)
                        StudioCard("Один Dock") {
                            Text(
                                "Замена скрывает системный Dock на рабочем столе. В Mission Control macOS показывает свою панель. Вернуть Dock можно из строки меню, настроек или обычным выходом из NewMacBar."
                            ).font(Studio.caption).foregroundStyle(.secondary)
                            Toggle("Заменить системный Dock", isOn: $model.replaceDock)
                        }
                    }
                }.padding(.vertical, 4)
            }
            HStack {
                if step > 0 { Button("Назад") { step -= 1 } }
                Spacer()
                Button(step == 3 ? "Готово" : "Продолжить") { if step == 3 { finish() } else { step += 1 } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.font(Studio.body).padding(28).frame(width: 620, height: 600).background(Studio.canvas)
            .preferredColorScheme(ui.colorScheme)
    }
    private func finish() {
        ui.onboardingCompleted = true
        if let onFinish { onFinish() } else { dismiss() }
    }
}
