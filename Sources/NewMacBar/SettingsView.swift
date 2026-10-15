import AppKit
import SwiftUI

struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let detail: String
    let keywords: String
    static let all: [SettingsSection] = [
        .init(
            id: "appearance", title: "Внешний вид", symbol: "paintpalette",
            detail: "Размер, стекло и движение. Изменения видны сразу.",
            keywords: "иконки размер интервал отступ цвет прозрачность анимация подписи"),
        .init(
            id: "spaces", title: "Пространства", symbol: "square.stack.3d.up",
            detail: "Отдельные наборы для работы и отдыха.",
            keywords: "рабочий стол привязка набор импорт FreeDock"),
        .init(
            id: "apps", title: "Приложения", symbol: "app",
            detail: "Закреплённые приложения и библиотека Mac.", keywords: "добавить удалить порядок Dock"),
        .init(
            id: "collections", title: "Коллекции", symbol: "square.grid.2x2",
            detail: "Группы приложений внутри текущего пространства.", keywords: "папка группа работа"),
        .init(
            id: "widgets", title: "Виджеты", symbol: "rectangle.3.group",
            detail: "Часы, календарь, музыка и фокус.",
            keywords: "таймер Spotify Music секунды дата ширина второй"),
        .init(
            id: "connections", title: "Связи и действия", symbol: "link",
            detail: "Выбери любимые приложения, календари и сайты.",
            keywords: "календарь календаря события разрешения ярлыки папки файлы Google Outlook Notion"),
        .init(
            id: "profiles", title: "Стили и профили", symbol: "sparkles",
            detail: "Оформление и снимки панели для разных задач.",
            keywords: "сохранить экспорт импорт профиль пресет"),
        .init(
            id: "behavior", title: "Поведение и экраны", symbol: "display",
            detail: "Край экрана, видимость и взаимодействие с macOS.",
            keywords: "Dock заменить скрывать монитор курсор бейджи корзина"),
        .init(
            id: "shortcuts", title: "Клавиши", symbol: "command", detail: "Быстрые действия с клавиатуры.",
            keywords: "поиск горячие сочетание конфликт"),
        .init(
            id: "system", title: "Система и восстановление", symbol: "shield.lefthalf.filled",
            detail: "Автозапуск, доступ и локальная диагностика.",
            keywords: "Dock вернуть ошибка backup резервная копия доступ"),
        .init(
            id: "about", title: "О программе", symbol: "info.circle",
            detail: "NewMacBar · собственное пространство на Mac.",
            keywords: "версия помощь начало onboarding компоненты"),
    ]
    static func matches(_ section: SettingsSection, query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy {
            (section.title + " " + section.detail + " " + section.keywords).localizedCaseInsensitiveContains(
                String($0))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: BarModel
    @ObservedObject var dock: DockIntegration
    @ObservedObject var focus: FocusTimer
    @ObservedObject var catalog: AppCatalog
    @ObservedObject var agenda: CalendarController
    @ObservedObject var ui = UIStateStore.shared
    @StateObject var login = LoginService()
    @State var navigationQuery = ""
    @State var displayRevision = 0
    @State var message = ""
    @State var search = ""
    @State var collectionName = ""
    @State var renamingCollection = false
    @State var deletingCollection: AppCollection?
    @State var removedCollection: (AppCollection, Int, String)?
    @State var selectedCollection: String?
    @State var editedWidget: String?
    @State var diagnosticReport: DiagnosticSnapshot?
    @State var showOnboarding = false
    var section: String {
        get { ui.section }
        nonmutating set { ui.section = newValue }
    }
    var collection: AppCollection? { model.collections.first { $0.id == selectedCollection } }
    var current: SettingsSection { SettingsSection.all.first { $0.id == section } ?? SettingsSection.all[0] }
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "dock.rectangle").font(.system(size: 25)).foregroundStyle(Studio.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NewMacBar").font(.headline)
                        Text("Твоё пространство").font(Studio.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(18)
                TextField("Найти настройку", text: $navigationQuery).textFieldStyle(.roundedBorder).padding(
                    .horizontal, 12
                ).padding(.bottom, 10).accessibilityLabel("Поиск раздела настроек")
                List(selection: $ui.section) {
                    ForEach(
                        SettingsSection.all.filter { SettingsSection.matches($0, query: navigationQuery) }
                    ) { item in
                        Label(item.id == "system" ? "Система" : item.title, systemImage: item.symbol).font(Studio.body).padding(.vertical, 4)
                            .tag(item.id)
                    }
                }.listStyle(.sidebar)
                if !navigationQuery.isEmpty
                    && !SettingsSection.all.contains(where: {
                        SettingsSection.matches($0, query: navigationQuery)
                    })
                {
                    Text("Раздел не найден").font(Studio.caption).foregroundStyle(.secondary).padding()
                }
                Text(model.replaceDock ? "Замена Dock включена" : "Работает рядом с Dock").font(
                    Studio.caption
                ).foregroundStyle(.secondary).padding(16)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        } detail: {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(current.title).font(Studio.title)
                        Text(current.detail).font(Studio.body).foregroundStyle(.secondary).fixedSize(
                            horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                }.padding(24)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if dock.recoveryPending { recoveryCard }
                        if ["appearance", "widgets", "behavior"].contains(section) {
                            DockPreview(model: model).accessibilityLabel(
                                "Предпросмотр панели. Изменения применяются сразу.")
                        }
                        page
                        if !message.isEmpty {
                            Label(message, systemImage: "info.circle").font(Studio.caption).foregroundStyle(
                                .secondary
                            ).textSelection(.enabled)
                        }
                    }.frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity).padding(24)
                }.id(section)
            }.background(Studio.canvas)
        }
        .frame(minWidth: 760, minHeight: 540).preferredColorScheme(ui.colorScheme).tint(Studio.accent)
        .onAppear {
            if !SettingsSection.all.contains(where: { $0.id == section }) { section = "appearance" }
            if section == "apps" { loadLibrary() }
            login.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in displayRevision &+= 1 }
        .onChange(of: model.selectedSpaceID) { _ in
            removedCollection = nil; deletingCollection = nil; renamingCollection = false
            selectedCollection = model.collections.first?.id
        }
        .onChange(of: section) { value in
            message = ""
            if value == "apps" { loadLibrary() }
        }
        .sheet(item: $diagnosticReport) { DiagnosticsView(report: $0.text) }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(model: model, agenda: agenda, dock: dock, login: login, ui: ui)
        }
    }
    @ViewBuilder var page: some View {
        switch section {
        case "spaces": SpacesSettingsView(model: model)
        case "apps": apps
        case "collections": collections
        case "widgets": widgets
        case "connections": ConnectionsView(model: model, agenda: agenda)
        case "profiles": ProfilesView(model: model)
        case "behavior": behavior
        case "shortcuts": shortcuts
        case "system": system
        case "about": about
        default: appearance
        }
    }
    func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        StudioCard(title, content: content)
    }
    func sectionTitle(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Studio.heading)
            Text(description).font(Studio.caption).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
        }
    }
    func row(_ title: String, _ description: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Studio.body)
                Text(description).font(Studio.caption).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
        }.toggleStyle(.switch)
    }
    func slider(_ title: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, _ value: String)
        -> some View
    { ParameterSlider(title: title, value: binding, range: range, label: value) }
}
