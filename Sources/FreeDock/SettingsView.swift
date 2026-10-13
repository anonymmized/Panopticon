import AppKit
import ServiceManagement
import SwiftUI

final class SettingsWindowController {
    private let store: DockStore
    private var window: NSWindow?

    init(store: DockStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "FreeDock — настройки"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: DockStore

    var body: some View {
        TabView {
            AppearanceTab(store: store)
                .tabItem { Label("Вид", systemImage: "paintbrush") }
            WidgetsTab(store: store)
                .tabItem { Label("Виджеты", systemImage: "rectangle.3.group") }
            BehaviorTab(store: store)
                .tabItem { Label("Поведение", systemImage: "gearshape") }
            SpacesTab(store: store)
                .tabItem { Label("Пространства", systemImage: "square.stack.3d.up") }
            HotkeysTab()
                .tabItem { Label("Клавиши", systemImage: "keyboard") }
        }
        .padding(16)
        .frame(width: 680, height: 640)
    }
}

private struct AppearanceTab: View {
    @ObservedObject var store: DockStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        Form {
            Section("Тема") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(DockTheme.allCases) { theme in
                        ThemeCard(theme: theme, selected: store.config.theme == theme)
                            .onTapGesture { store.config.theme = theme }
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Насыщенность цвета") {
                    Slider(value: $store.config.tint, in: 0.1...1)
                }
                .disabled(store.config.theme.tint.isEmpty)
                LabeledContent("Скругление: \(Int(store.config.cornerRadius))") {
                    Slider(value: $store.config.cornerRadius, in: 6...32, step: 1)
                }
            }
            Section("Расположение") {
                Picker("Край экрана", selection: $store.config.edge) {
                    ForEach(DockEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Иконки") {
                LabeledContent("Размер: \(Int(store.config.iconSize)) pt") {
                    Slider(value: $store.config.iconSize, in: 28...96, step: 2)
                }
                LabeledContent("Интервал: \(Int(store.config.iconSpacing)) pt") {
                    Slider(value: $store.config.iconSpacing, in: 2...20, step: 1)
                }
                Toggle("Увеличение при наведении", isOn: $store.config.magnify)
                LabeledContent("Сила увеличения: ×\(String(format: "%.1f", store.config.magnification))") {
                    Slider(value: $store.config.magnification, in: 1.1...2.0, step: 0.1)
                }
                .disabled(!store.config.magnify)
                Picker("Индикатор запущенных", selection: $store.config.indicator) {
                    ForEach(IndicatorStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Выделять активное приложение цветом темы", isOn: $store.config.highlightActive)
                Toggle("Показывать открытые незакреплённые приложения", isOn: $store.config.showRunningApps)
                Toggle("Подписи при наведении", isOn: $store.config.showLabels)
                Toggle("Корзина на баре", isOn: $store.config.showTrash)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeCard: View {
    let theme: DockTheme
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: theme.preview, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 44)
                .overlay(
                    HStack(spacing: 5) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.75)).frame(width: 12, height: 12)
                        }
                    }
                )
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? theme.accent : Color.primary.opacity(0.15), lineWidth: selected ? 3 : 1))
            Text(theme.title)
                .font(.caption)
                .fontWeight(selected ? .semibold : .regular)
        }
        .contentShape(Rectangle())
    }
}

private struct WidgetsTab: View {
    @ObservedObject var store: DockStore
    @ObservedObject var calendar: CalendarService
    @ObservedObject var music: MusicController

    init(store: DockStore) {
        self.store = store
        calendar = store.calendar
        music = store.music
    }

    var body: some View {
        Form {
            Section {
                Toggle("Часы", isOn: $store.config.showClock)
                Toggle("24-часовой формат", isOn: $store.config.clock24h)
                    .disabled(!store.config.showClock)
                Toggle("Секунды", isOn: $store.config.clockSeconds)
                    .disabled(!store.config.showClock)
                HStack {
                    Image(systemName: calendar.authorized ? "checkmark.seal.fill" : "calendar")
                        .foregroundStyle(calendar.authorized ? Color.green : Color.secondary)
                    Text(calendar.authorized ? "Календари подключены" : "События календаря не подключены")
                    Spacer()
                    if !calendar.authorized && !calendar.denied {
                        Button("Подключить") { calendar.requestAccess() }
                    }
                }
            } header: {
                Text("Часы и календарь")
            } footer: {
                Text("Клик по часам открывает месяц и события дня. События только читаются.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Музыка", isOn: $store.config.showMusic)
                Picker("Плеер", selection: $store.config.musicSource) {
                    ForEach(MusicSource.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!store.config.showMusic)
                if music.needsPermission {
                    Label("Разреши управление в Системных настройках → Конфиденциальность → Автоматизация",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Музыка")
            } footer: {
                Text("Spotify и Apple Music: трек, обложка, пауза, переключение и перемотка. "
                     + "Плеер опрашивается, только когда он уже запущен.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Таймер фокуса", isOn: $store.config.showTimer)
                LabeledContent("Длительность: \(Int(store.config.timerMinutes)) мин") {
                    Slider(value: $store.config.timerMinutes, in: 5...90, step: 5)
                }
                .disabled(!store.config.showTimer)
            } header: {
                Text("Фокус")
            } footer: {
                Text("Клик — старт и пауза, правый клик — быстрый выбор длительности.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorTab: View {
    @ObservedObject var store: DockStore

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var axTrusted = AX.trusted

    var body: some View {
        Form {
            Section("Бар") {
                Toggle("Показывать бар (⌃⌥D)", isOn: $store.config.visible)
                Toggle("Автоматически скрывать", isOn: $store.config.autohide)
                Toggle("Переезжать на монитор с курсором", isOn: $store.config.followMouse)
                Toggle("Листать пространства прокруткой над баром", isOn: $store.config.scrollToSwitch)
                Toggle("Переключать пространство вместе с рабочим столом macOS",
                       isOn: $store.config.autoSwitchDesktops)
            }

            Section {
                Toggle("Бейджи уведомлений, как в Dock", isOn: $store.config.showBadges)
                HStack {
                    Image(systemName: axTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(axTrusted ? Color.green : Color.orange)
                    Text(axTrusted ? "Доступ выдан" : "Нужен «Универсальный доступ»")
                    Spacer()
                    if !axTrusted {
                        Button("Выдать доступ") { AX.requestTrust() }
                    }
                }
            } header: {
                Text("Универсальный доступ")
            } footer: {
                Text("Нужен для бейджей и списка окон приложения в меню по правому клику.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Заменить системный Dock", isOn: Binding(
                    get: { store.config.replaceSystemDock },
                    set: { store.setReplaceSystemDock($0) }))
                Toggle("Возвращать системный Dock при выходе из FreeDock", isOn: $store.config.restoreDockOnQuit)
                    .disabled(!store.config.replaceSystemDock)
                Toggle("Быстрый поиск по ⌃⌥Пробел", isOn: $store.config.launcherEnabled)
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enable in
                        do {
                            if enable {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            _ = NSAlert(error: error).runModal()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
            } header: {
                Text("Система")
            } footer: {
                Text("Системный Dock не удаляется: FreeDock запоминает его настройки и прячет его. "
                     + "Выключи переключатель, чтобы вернуть всё как было.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            axTrusted = AX.trusted
        }
    }
}

private struct SpacesTab: View {
    @ObservedObject var store: DockStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(store.config.spaces) { space in
                    SpaceRow(store: store, id: space.id)
                }
                .onMove { store.moveSpaces(from: $0, to: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Button {
                    store.addSpace()
                } label: {
                    Label("Новое", systemImage: "plus")
                }
                Button {
                    store.importSystemDock()
                } label: {
                    Label("Импорт из системного Dock", systemImage: "square.and.arrow.down")
                }
                Spacer()
                if let desktop = store.currentDesktop {
                    Text("Сейчас: рабочий стол \(desktop)").foregroundStyle(.secondary)
                }
            }
            Text("Перетаскивай строки, чтобы поменять порядок. Пространство, привязанное к рабочему столу, "
                 + "включается само, когда ты переходишь на этот стол.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }
}

private struct SpaceRow: View {
    @ObservedObject var store: DockStore
    let id: UUID

    var body: some View {
        if let index = store.index(of: id) {
            let space = store.config.spaces[index]
            HStack(spacing: 10) {
                Menu {
                    ForEach(DockStore.symbols, id: \.self) { symbol in
                        Button {
                            store.setSymbol(symbol, for: index)
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                } label: {
                    Image(systemName: space.symbol)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 44)

                TextField("Название", text: Binding(get: { space.name }, set: { store.rename(id, to: $0) }))
                    .textFieldStyle(.roundedBorder)

                Text("\(space.items.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .help("Элементов в пространстве")

                Picker("", selection: Binding(get: { space.desktop ?? 0 },
                                              set: { store.bind(id, desktop: $0 == 0 ? nil : $0) })) {
                    Text("Любой стол").tag(0)
                    ForEach(1...16, id: \.self) { Text("Стол \($0)").tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)

                Button {
                    store.deleteSpace(index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(store.config.spaces.count < 2)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct HotkeysTab: View {
    private let rows: [(String, String)] = [
        ("⌃⌥1 … ⌃⌥9", "Переключиться на пространство 1–9"),
        ("⌃⌥← / ⌃⌥→", "Предыдущее / следующее пространство"),
        ("⌃⌥D", "Показать / скрыть бар"),
        ("⌃⌥Пробел", "Быстрый поиск приложений, файлов, сайтов"),
        ("⌘↩ в поиске", "Закрепить найденное в текущем пространстве"),
        ("Прокрутка над баром", "Листать пространства"),
        ("Правый клик по иконке", "Окна, скрыть, завершить, переместить"),
        ("⌥ + правый клик → Завершить", "Завершить принудительно"),
        ("Перетащить иконку", "Поменять порядок / в другое пространство / в корзину — убрать"),
        ("Файл на иконку приложения", "Открыть файл в этом приложении"),
        ("Файл или ссылка на бар", "Добавить в текущее пространство"),
        ("Клик по часам", "Календарь и события дня"),
    ]

    var body: some View {
        Form {
            Section("Управление") {
                ForEach(rows.indices, id: \.self) { i in
                    LabeledContent(rows[i].1) {
                        Text(rows[i].0).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("FreeDock 3.0 — бесплатно и с открытым кодом.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
