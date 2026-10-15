import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var model: BarModel
    @ObservedObject var dock: DockIntegration
    @ObservedObject var focus: FocusTimer
    @ObservedObject var catalog: AppCatalog
    @ObservedObject var agenda: CalendarController
    @State private var section = "appearance"
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var message = ""
    @State private var search = ""
    @State private var collectionName = ""
    @State private var renamingCollection = false
    @State private var selectedCollection: String?
    private let ink = Color(red: 0.1, green: 0.105, blue: 0.13)
    private var collection: AppCollection? { model.collections.first { $0.id == selectedCollection } }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) { Image(nsImage: NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "") ?? NSImage()).resizable().frame(width: 34, height: 34); VStack(alignment: .leading, spacing: 3) { Text("Panopticon").font(.system(size: 16, weight: .semibold)); Text(L("СВОЁ ПРОСТРАНСТВО")).font(.system(size: 7, weight: .medium)).tracking(1.5).foregroundStyle(.secondary) } }.padding(.vertical, 24)
                navGroup(L("ПАНЕЛЬ"))
                nav(L("Пространства"), "square.stack.3d.up.fill", "spaces", .mint)
                nav(L("Коллекции"), "square.grid.2x2.fill", "collections", .blue)
                nav(L("Виджеты"), "rectangle.3.group.fill", "widgets", .purple)
                nav(L("Приложения"), "app.fill", "apps", .indigo)
                navGroup(L("НАСТРОЙКИ")).padding(.top, 17)
                nav(L("Связи и действия"), "link", "connections", .teal)
                nav(L("Стили и профили"), "sparkles", "profiles", .orange)
                nav(L("Внешний вид"), "paintpalette.fill", "appearance", .pink)
                nav(L("Поведение"), "slider.horizontal.3", "behavior", .gray)
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Язык интерфейса")).font(.system(size: 10)).foregroundStyle(.secondary)
                    Picker(L("Язык интерфейса"), selection: Binding(get: { localization.language }, set: { localization.setLanguage($0) })) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().accessibilityLabel(L("Язык интерфейса")).help(L("Применяется сразу. Названия твоих пространств, профилей и файлов сохраняются."))
                }.padding(.vertical, 10)
                VStack(alignment: .leading, spacing: 10) { HStack { Circle().fill(.mint).frame(width: 6, height: 6); Text(model.replaceDock ? L("Основная панель") : L("Рядом с системным Dock")).font(.system(size: 10, weight: .medium)) }; Text(L("Локально на твоём Mac.\nБесплатно, без ограничений.")).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4) }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            }.padding(.horizontal, 16).padding(.bottom, 20).frame(width: 215).background(Color(red: 0.073, green: 0.078, blue: 0.095))
            VStack(spacing: 0) {
                HStack { VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 24, weight: .semibold)); Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Text(L("\(model.pinned.count) приложений")).font(.system(size: 10)).foregroundStyle(.secondary).padding(8).background(.white.opacity(0.04), in: Capsule()) }.padding(.horizontal, 28).padding(.vertical, 23)
                Divider().opacity(0.3)
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        if section != "apps" && section != "collections" && section != "profiles" { DockPreview(model: model) }
                        if section == "spaces" { SpacesSettingsView(model: model) }
                        if section == "appearance" { appearance }
                        if section == "apps" { apps }
                        if section == "widgets" { widgets }
                        if section == "behavior" { behavior }
                        if section == "collections" { collections }
                        if section == "connections" { ConnectionsView(model: model, agenda: agenda) }
                        if section == "profiles" { ProfilesView(model: model) }
                        if !message.isEmpty { Text(localization.status(message)).font(.system(size: 11)).foregroundStyle(.mint) }
                    }.padding(28)
                }
            }.background(ink)
        }.environment(\.locale, localization.locale).frame(minWidth: 920, minHeight: 680).preferredColorScheme(.dark).tint(.mint)
    }
    private var title: String { ["spaces": L("Пространства"), "appearance": L("Внешний вид"), "apps": L("Твои приложения"), "widgets": L("Виджеты"), "behavior": L("Поведение панели"), "collections": L("Коллекции"), "connections": L("Связи и действия"), "profiles": L("Стили и профили")][section]! }
    private var subtitle: String { ["spaces": L("Свои наборы для работы, отдыха и каждого рабочего стола."), "appearance": L("Стекло, движение и детали. Изменения видны сразу."), "apps": L("Закрепляй любимое. Перетаскивай иконки, чтобы менять порядок."), "widgets": L("Маленькие инструменты. Именно в твоём стиле."), "behavior": L("Один Dock, нужный экран и удобное положение."), "collections": L("Собери приложения для работы, общения или отдыха."), "connections": L("Любимые приложения, календари, папки и сайты."), "profiles": L("Характер панели. Настроения. Твои рабочие пространства.")][section]! }
    private func navGroup(_ label: String) -> some View { Text(label).font(.system(size: 8, weight: .medium)).tracking(1.2).foregroundStyle(.secondary.opacity(0.6)).padding(.leading, 10).padding(.bottom, 6) }
    private func nav(_ title: String, _ icon: String, _ id: String, _ color: Color) -> some View {
        Button { section = id; message = ""; if id == "apps" { loadLibrary() } } label: { HStack(spacing: 10) { Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).frame(width: 25, height: 25).background(color.gradient, in: RoundedRectangle(cornerRadius: 7)); Text(title).font(.system(size: 12, weight: .medium)); Spacer(); if id == "collections" && !model.collections.isEmpty { Text("\(model.collections.count)").font(.system(size: 10)).foregroundStyle(.secondary) } }.padding(.horizontal, 10).padding(.vertical, 9).background(section == id ? Color.white.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 17) { Text(title).font(.system(size: 13, weight: .semibold)); content() }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.027), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.055))) }
    private func sectionTitle(_ title: String, _ description: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 14, weight: .semibold)); Text(description).font(.system(size: 10)).foregroundStyle(.secondary) } }
    private func row(_ title: String, _ description: String, _ binding: Binding<Bool>) -> some View { HStack { VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 12)); Text(description).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }; Spacer(); Toggle(title, isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small) } }
    private func accentName(_ id: String) -> String {
        ["violet": L("Фиолетовый"), "blue": L("Синий"), "cyan": L("Голубой"),
         "mint": L("Мятный"), "orange": L("Оранжевый"), "rose": L("Розовый"), "neutral": L("Нейтральный")][id] ?? id
    }
    private func slider(_ title: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, _ value: String) -> some View { ParameterSlider(title: title, value: binding, range: range, label: value) }
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 23) {
            card(L("Размер и положение")) { slider(L("Размер иконок"), $model.iconSize, 28...60, "\(Int(model.iconSize)) px"); slider(L("Интервал между иконками"), $model.iconSpacing, 4...24, "\(Int(model.iconSpacing)) px"); slider(L("Отступ от края экрана"), $model.bottomOffset, 0...160, "\(Int(model.bottomOffset)) px"); Button(L("Рекомендуемый компактный размер")) { model.iconSize = 36; model.iconSpacing = 8; model.bottomOffset = 4; model.magnification = 1.35; model.hoverLift = 7; model.cornerRadius = 20; model.opacity = 0.08 }.font(.system(size: 10)).buttonStyle(.borderless).foregroundStyle(.mint) }
            sectionTitle(L("Стиль стекла"), L("Оформление панели поверх обоев и окон."))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 13) {
                ForEach(DockTheme.allCases) { theme in
                    OptionTile(theme.title, selected: model.theme == theme.rawValue, action: { model.theme = theme.rawValue }) {
                        HStack(spacing: 8) { previewIcon("/System/Library/CoreServices/Finder.app", 31); previewIcon("/System/Applications/Music.app", 31) }
                            .padding(10).background(LinearGradient(colors: theme.preview, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                    }
                }
            }
            card(L("Поверхность")) { slider(L("Плотность стекла"), $model.opacity, 0...0.65, "\(Int(model.opacity * 100))%"); slider(L("Скругление углов"), $model.cornerRadius, 8...30, "\(Int(model.cornerRadius)) px") }
            sectionTitle(L("При наведении"), L("Выбери характер движения иконок."))
            HStack(spacing: 13) { ForEach([("none", L("Спокойно")), ("lift", L("Подъём")), ("scale", L("Увеличение"))], id: \.0) { id, label in OptionTile(label, selected: model.hoverStyle == id, action: { model.hoverStyle = id }) { HStack(spacing: 8) { previewIcon("/System/Library/CoreServices/Finder.app", id == "none" ? 30 : 39).offset(y: id == "lift" ? -5 : 0); previewIcon("/Applications/Safari.app", 30) } } } }
            card(L("Движение")) { slider(L("Увеличение"), $model.magnification, 1...1.8, String(format: "×%.2f", model.magnification)); slider(L("Высота подъёма"), $model.hoverLift, 0...16, "\(Int(model.hoverLift)) px") }
            HStack(alignment: .top, spacing: 15) { card(L("При запуске")) { Picker(L("Анимация"), selection: $model.launchStyle) { Text(L("Прыжок")).tag("bounce"); Text(L("Пульс")).tag("pulse"); Text(L("Без анимации")).tag("none") }.labelsHidden() }; card(L("Индикатор запуска")) { Picker(L("Индикатор"), selection: $model.indicatorStyle) { Text(L("Точка")).tag("dot"); Text(L("Линия")).tag("dash"); Text(L("Скрыть")).tag("none") }.labelsHidden() } }
            card(L("Детали")) { row(L("Подписи при наведении"), L("Название приложения над иконкой"), $model.showLabels); row(L("Разделитель перед виджетом"), L("Тонкая линия между приложениями и виджетом"), $model.showSeparator); row(L("Кнопка настроек на панели"), L("Настройки также доступны в строке меню и по правой кнопке"), $model.showSettingsButton) }
        }
    }
    private func previewIcon(_ path: String, _ size: Double) -> some View { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: size, height: size) }
    private var displayedWidget: String { model.widgetKinds.first ?? "clock" }
    private var widgets: some View {
        VStack(alignment: .leading, spacing: 23) {
            sectionTitle(L("Что будет на панели"), L("Выбери виджет. Его оформление настраивается ниже."))
            HStack(spacing: 13) { ForEach([("music", L("Музыка")), ("clock", L("Часы")), ("calendar", L("Календарь")), ("timer", L("Фокус"))], id: \.0) { id, label in OptionTile(label, selected: model.widget == id, action: { model.widget = id }) { MiniWidget(kind: id, compact: true, accent: model.accent) } } }
            HStack { Text(L("Виджет на панели")).font(.system(size: 11)); Spacer(); Toggle(L("Виджет на панели"), isOn: Binding(get: { !model.widgetKinds.isEmpty }, set: { enabled in model.batch { if enabled { model.widget = "clock" } else { model.widget = "none"; model.secondaryWidget = "none" } } })).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            card(L("Второй виджет")) {
                Picker(L("Рядом с основным"), selection: $model.secondaryWidget) {
                    Text(L("Выключен")).tag("none")
                    ForEach([("clock", L("Часы")), ("calendar", L("Календарь")), ("music", L("Музыка")), ("timer", L("Фокус"))].filter { $0.0 != model.widget }, id: \.0) { id, name in Text(name).tag(id) }
                }.font(.system(size: 11))
                Text(L("Например, музыка и ближайшая встреча одновременно. Оформление общее для обоих виджетов.")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if !model.widgetKinds.isEmpty {
                sectionTitle(L("Размер виджета"), L("Компактная кнопка или подробная карточка."))
                HStack(spacing: 13) { ForEach([("compact", L("Компактный")), ("wide", L("Подробный"))], id: \.0) { id, label in OptionTile(label, selected: model.widgetStyle == id, action: { model.widgetStyle = id }) { MiniWidget(kind: displayedWidget, compact: id == "compact", accent: model.accent) } } }
                card(L("Оформление")) {
                    HStack(spacing: 14) { Text(L("Цвет")).font(.system(size: 11)); Spacer(); ForEach(["violet", "blue", "cyan", "mint", "orange", "rose", "neutral"], id: \.self) { id in Button { model.widgetAccent = id } label: { Circle().fill(color(id)).frame(width: 20, height: 20).padding(3).overlay(Circle().stroke(model.widgetAccent == id ? .white : .clear, lineWidth: 1.5)) }.buttonStyle(.plain).accessibilityLabel(L("Цвет \(accentName(id))")) } }
                    if model.widgetStyle == "wide" { slider(L("Ширина"), $model.widgetWidth, 130...250, "\(Int(model.widgetWidth)) px") }
                    slider(L("Насыщенность фона"), $model.widgetOpacity, 0.08...0.7, "\(Int(model.widgetOpacity * 100))%")
                }
                if displayedWidget == "music" { card(L("Музыкальный плеер")) { Picker(L("Источник"), selection: $model.playerPreference) { Text(L("Автоматически")).tag("auto"); Text("Spotify").tag("spotify"); Text("Apple Music").tag("music") }; Text(L("Обложка Spotify, название трека, исполнитель и управление. Нажми на обложку или название: откроется плеер с перемоткой. Автоматический выбор предпочитает Spotify.")).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4); Button(L("Настройки доступа к плееру")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }.font(.system(size: 10)); Text(L("Воспроизведение из браузера пока не поддерживается.")).font(.system(size: 10)).foregroundStyle(.secondary) } }
                if displayedWidget == "calendar" { card(L("Календарь и события")) {
                    Text(L("Дата и ближайшее событие на панели. Нажатие открывает месяц и список встреч.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button(L("Выбрать приложение и календари")) { section = "connections" }.font(.system(size: 10))
                } }
                if displayedWidget == "clock" { card(L("Часы")) { Picker(L("Формат времени"), selection: $model.clockFormat) { Text(L("24 часа")).tag("24h"); Text(L("12 часов")).tag("12h") }.pickerStyle(.segmented); row(L("Показывать секунды"), L("Для более подробного отображения времени"), $model.clockSeconds); Text(L("Нажатие открывает выбранное приложение или календарную карточку.")).font(.system(size: 10)).foregroundStyle(.secondary) } }
                if displayedWidget == "timer" { card(L("Таймер фокуса")) { slider(L("Длительность сессии"), $model.timerMinutes, 5...90, L("\(Int(model.timerMinutes)) мин")); HStack { Text(focus.text).font(.system(size: 24, weight: .medium, design: .monospaced)); Spacer(); Button(focus.isRunning ? L("Пауза") : L("Начать")) { focus.toggle(minutes: model.timerMinutes) }; Button(L("Сбросить")) { focus.reset(minutes: model.timerMinutes) } }; Text(L("Сессия сохраняется при перезапуске. Новая длительность применяется после сброса или к следующей сессии.")).font(.system(size: 10)).foregroundStyle(.secondary) } }
            }
        }
    }
    private func color(_ id: String) -> Color { ["violet": Color.purple, "blue": .blue, "cyan": .cyan, "mint": .mint, "orange": .orange, "rose": .pink, "neutral": .gray][id]! }
    private var behavior: some View {
        VStack(spacing: 23) {
            card(L("Один Dock")) { row(L("Заменить системный Dock"), L("Скрывает Dock на рабочем столе; в Mission Control видна панель macOS"), $model.replaceDock); Text(dock.message).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4); Text(L("При выходе из Panopticon прежние настройки Dock восстановятся. После аварийного завершения восстановить его можно этой кнопкой.")).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4); Button(L("Вернуть системный Dock")) { model.replaceDock = false; dock.restore() }.font(.system(size: 10)); if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier?.lowercased().contains("dockspace") == true || $0.localizedName == "Dockspace" }) { Button(L("Закрыть Dockspace")) { NSWorkspace.shared.runningApplications.first { $0.localizedName == "Dockspace" }?.terminate() }.font(.system(size: 10)) } }
            card(L("Положение и видимость")) {
                Picker(L("Край экрана"), selection: $model.edge) { ForEach(DockEdge.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) } }.font(.system(size: 11))
                row(L("Показывать панель"), L("Также переключается сочетанием ⌃⌥D"), $model.barVisible)
                row(L("Следовать за курсором"), L("Перемещать панель на экран, где находится курсор"), $model.followMouse)
                row(L("Корзина на панели"), L("Перетаскивание закреплённой иконки сюда убирает ярлык; файл из Finder отправляется в Корзину"), $model.showTrash)
                row(L("Бейджи приложений"), L("Считывать счётчики из системного Dock при разрешённом Универсальном доступе"), $model.showBadges)
                if model.showBadges && !AX.trusted { Button(L("Подключить Универсальный доступ…")) { AX.requestTrust() }.font(.system(size: 11)) }
 Picker(L("Экран"), selection: $model.screenIndex) { ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in Text(screen.localizedName).tag(index) } }.font(.system(size: 11)); row(L("Автоматически скрывать"), L("Появляется, когда курсор у выбранного края экрана"), $model.autoHide); row(L("Открытые приложения"), L("Показывать запущенные приложения рядом с закреплёнными"), $model.showRunning) }
            card(L("Запуск")) { Toggle(L("Открывать при входе в macOS"), isOn: $loginEnabled).font(.system(size: 12)).onChange(of: loginEnabled) { enabled in do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; message = SMAppService.mainApp.status == .requiresApproval ? L("Подтверди запуск в macOS → Основные → Объекты входа.") : L("Настройка сохранена.") } catch { message = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled } }; Text(L("Для автозапуска перенеси приложение в папку «Программы».")).font(.system(size: 10)).foregroundStyle(.secondary) }
            Button(L("Завершить Panopticon и восстановить Dock")) { NSApp.terminate(nil) }.font(.system(size: 11)).buttonStyle(.borderless).foregroundStyle(.secondary)
        }
    }
    private var apps: some View {
        VStack(alignment: .leading, spacing: 23) {
            card(L("Закреплённые")) { HStack { Button(L("Добавить…")) { chooseApps { model.add($0) } }; Button(L("Импортировать Dock")) { model.importDock() }; Spacer(); Text("\(model.pinned.count)").foregroundStyle(.secondary) }.font(.system(size: 10)); ForEach(model.pinned) { item in HStack(spacing: 10) { Image(nsImage: item.icon).resizable().frame(width: 27, height: 27); Text(item.name).font(.system(size: 11)); Spacer(); Button { move(item, -1) } label: { Image(systemName: "chevron.up") }.disabled(model.pinned.first == item); Button { move(item, 1) } label: { Image(systemName: "chevron.down") }.disabled(model.pinned.last == item); Button { model.remove(item) } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) } }.buttonStyle(.borderless) } }
            sectionTitle(L("Все приложения"), L("Нажми на карточку, чтобы закрепить или убрать приложение."))
            if catalog.loading { ProgressView().controlSize(.small) }
            TextField(L("Поиск приложений"), text: $search).textFieldStyle(.roundedBorder)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 12)], spacing: 12) { ForEach(catalog.items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { item in Button { if model.pinned.contains(item) { model.remove(item) } else { model.add(item.url) } } label: { VStack(spacing: 8) { Image(nsImage: item.icon).resizable().frame(width: 38, height: 38); Text(item.name).font(.system(size: 9)).lineLimit(1); Image(systemName: model.pinned.contains(item) ? "checkmark.circle.fill" : "plus.circle").font(.system(size: 10)).foregroundStyle(model.pinned.contains(item) ? .mint : .secondary) }.padding(12).frame(maxWidth: .infinity).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain) } }
        }
    }
    private var collections: some View {
        VStack(alignment: .leading, spacing: 23) {
            card(L("Новая коллекция")) { HStack { TextField(L("Название, например «Работа»"), text: $collectionName).textFieldStyle(.roundedBorder); Button(L("Создать")) { let group = AppCollection(name: collectionName.trimmingCharacters(in: .whitespacesAndNewlines)); model.updateCollection(group); selectedCollection = group.id; collectionName = "" }.disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.font(.system(size: 11)) }
            if model.collections.isEmpty { VStack(spacing: 12) { Image(systemName: "square.grid.2x2").font(.system(size: 34)).foregroundStyle(.purple); Text(L("Место для твоих коллекций")).font(.system(size: 15, weight: .medium)); Text(L("Группа появится на панели. Нажатие откроет сетку приложений.")).font(.system(size: 11)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 48) }
            else {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { ForEach(model.collections) { group in Button { selectedCollection = group.id } label: { Label(group.name, systemImage: group.symbol).font(.system(size: 11)).padding(11).background(selectedCollection == group.id ? Color.purple.opacity(0.2) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) } } }
                if let group = collection { card(group.name) { HStack { Button(L("Переименовать")) { renamingCollection = true }; Button(L("Добавить приложения…")) { chooseApps { url in var updated = model.collections.first { $0.id == group.id } ?? group; if !updated.paths.contains(url.path) { updated.paths.append(url.path); model.updateCollection(updated) } } }; Spacer(); Button(L("Удалить коллекцию")) { model.removeCollection(group.id); selectedCollection = model.collections.first?.id }.foregroundStyle(.secondary) }.font(.system(size: 10)); ForEach(group.items) { item in HStack { Image(nsImage: item.icon).resizable().frame(width: 28, height: 28); Text(item.name).font(.system(size: 11)); Spacer(); Button { moveCollectionItem(item.id, in: group, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(group.paths.first == item.id).buttonStyle(.borderless); Button { moveCollectionItem(item.id, in: group, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(group.paths.last == item.id).buttonStyle(.borderless); Button { var updated = group; updated.paths.removeAll { $0 == item.id }; model.updateCollection(updated) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) } }; if group.items.isEmpty { Text(L("Добавь приложения в коллекцию.")).font(.system(size: 11)).foregroundStyle(.secondary) } } }
            }
        }.sheet(isPresented: $renamingCollection) { if let group = collection { RenameEditor(title: L("Название коллекции"), name: group.name) { name in let clean = SettingsRules.label(name); guard !clean.isEmpty else { return false }; var copy = group; copy.name = clean; model.updateCollection(copy); return true } } }.onAppear { if selectedCollection == nil { selectedCollection = model.collections.first?.id } }
    }
    private func moveCollectionItem(_ path: String, in group: AppCollection, by offset: Int) { guard let i = group.paths.firstIndex(of: path) else { return }; let target = min(max(0, i + offset), group.paths.count - 1); var copy = group; copy.paths.swapAt(i, target); model.updateCollection(copy) }
    private func move(_ item: DockItem, _ direction: Int) { guard let i = model.pinned.firstIndex(of: item) else { return }; model.move(item.id, to: direction < 0 ? i - 1 : i + 2) }
    private func chooseApps(_ action: (URL) -> Void) { let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = true; if panel.runModal() == .OK { panel.urls.forEach(action) } }
    private func loadLibrary() { catalog.refresh(force: true) }
}
