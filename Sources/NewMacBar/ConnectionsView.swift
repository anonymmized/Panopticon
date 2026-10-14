import SwiftUI
import AppKit

struct StudioCard<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { VStack(alignment: .leading, spacing: 17) { Text(title).font(.system(size: 13, weight: .semibold)); content }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.027), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.055))) }
}

struct ConnectionsView: View {
    @ObservedObject var model: BarModel
    @ObservedObject var agenda: CalendarController
    @State private var apps: [DockItem] = []
    @State private var editingLink: QuickLink?
    @State private var linkName = ""
    @State private var linkURL = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            StudioCard("Какой календарь открывать") {
                Picker("Назначение", selection: $model.calendarDestination) { Text("Календарь macOS").tag("system"); Text("Приложение").tag("app"); Text("Веб-календарь").tag("web") }.pickerStyle(.segmented)
                if model.calendarDestination == "app" {
                    HStack(spacing: 12) { if !model.calendarAppPath.isEmpty { Image(nsImage: NSWorkspace.shared.icon(forFile: model.calendarAppPath)).resizable().frame(width: 34, height: 34) }; VStack(alignment: .leading, spacing: 4) { Text(model.calendarAppPath.isEmpty ? "Выбери приложение" : model.calendarAppName).font(.system(size: 12, weight: .medium)); Text("Можно выбрать любое приложение на Mac.").font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); Button("Выбрать…", action: chooseCalendar).font(.system(size: 10)) }
                    if !apps.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(apps) { app in Button { model.calendarAppPath = app.id } label: { HStack(spacing: 5) { Image(nsImage: app.icon).resizable().frame(width: 20, height: 20); Text(app.name).font(.system(size: 9)) }.padding(7).background(model.calendarAppPath == app.id ? Color.mint.opacity(0.13) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) } } } }
                }
                if model.calendarDestination == "web" { TextField("https://calendar.google.com", text: $model.calendarWebURL).textFieldStyle(.roundedBorder); HStack { Button("Google Calendar") { model.calendarWebURL = "https://calendar.google.com" }; Button("Outlook") { model.calendarWebURL = "https://outlook.live.com/calendar" } }.font(.system(size: 10)); Text("Откроется в браузере по умолчанию.").font(.system(size: 10)).foregroundStyle(.secondary) }
                HStack { Text("Нажатие на часы").font(.system(size: 11)); Spacer(); Picker("Нажатие на часы", selection: $model.clockAction) { Text("Открыть приложение").tag("open"); Text("Показать календарь").tag("agenda") }.labelsHidden().frame(width: 185) }
                Button("Открыть выбранный календарь") { model.openCalendar() }.font(.system(size: 10)).disabled(model.calendarTarget == nil)
            }
            StudioCard("Ближайшие события") {
                Toggle("Показывать события календарей macOS", isOn: $model.calendarEventsEnabled).font(.system(size: 11)).toggleStyle(.switch)
                Text("События читаются из календарей, подключённых к macOS, например iCloud или Google. Выбор Notion Calendar, Outlook или другого приложения выше задаёт, что открывать; сам по себе он не импортирует события этого сервиса.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                if !agenda.authorized { Button("Подключить календари…") { model.calendarEventsEnabled = true; agenda.enabled = true; agenda.connect() }.font(.system(size: 10)); Text(agenda.message).font(.system(size: 10)).foregroundStyle(.secondary); Button("Настройки доступа macOS") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }.font(.system(size: 10)) }
                else { HStack { Button("Все календари") { model.selectedCalendarIDs = []; model.save() }; Button("Снять выбор") { model.selectedCalendarIDs = ["__none__"]; model.save() } }.font(.system(size: 10)); Label("Доступ подключён. События остаются на Mac.", systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(.mint); ForEach(agenda.calendarNames, id: \.id) { calendar in Toggle(calendar.name, isOn: Binding(get: { model.selectedCalendarIDs.isEmpty || model.selectedCalendarIDs.contains(calendar.id) }, set: { enabled in var chosen = Set(model.selectedCalendarIDs.isEmpty ? agenda.calendarNames.map(\.id) : model.selectedCalendarIDs); if enabled { chosen.insert(calendar.id) } else { chosen.remove(calendar.id) }; model.selectedCalendarIDs = chosen.isEmpty ? ["__none__"] : Array(chosen); model.save() })).font(.system(size: 10)) } }
            }
            StudioCard("Мгновенный запуск") {
                Toggle("Глобальная клавиша быстрого поиска", isOn: $model.launcherEnabled).font(.system(size: 11))
                Picker("Сочетание", selection: $model.launcherShortcutChoice) { Text("⌃⌥Пробел").tag("controlOptionSpace"); Text("⌘⇧Пробел").tag("commandShiftSpace"); Text("⌥⇧Пробел").tag("optionShiftSpace") }.font(.system(size: 11))
                if model.launcherEnabled { Text(model.launcherShortcutAvailable ? "Горячая клавиша подключена" : "Сочетание недоступно. Выбери другое или используй поиск из строки меню.").font(.system(size: 10)).foregroundStyle(model.launcherShortcutAvailable ? .mint : .secondary) }
                Text("Ищи приложения, папки, сайты и сохранённые профили. Поиск также доступен в строке меню NewMacBar.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                Text("Файл можно перетащить прямо на иконку приложения, чтобы открыть его в нём. Папку можно перетащить на свободное место панели, чтобы создать ярлык.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }
            StudioCard("Папки и сайты на панели") {
                HStack { Button("Добавить папку…", action: chooseFolder); Button("Добавить файлы…", action: chooseFiles); Button("Загрузки") { _ = model.addQuickLink(name: "Загрузки", kind: "folder", destination: NSHomeDirectory() + "/Downloads") }; Spacer(); Text("\(model.quickLinks.count) ярлыков").foregroundStyle(.secondary) }.font(.system(size: 10))
                HStack { TextField("Название сайта", text: $linkName).textFieldStyle(.roundedBorder).frame(width: 135); TextField("https://…", text: $linkURL).textFieldStyle(.roundedBorder); Button("Добавить") { message = model.addQuickLink(name: linkName, kind: "web", destination: linkURL) ? "Ярлык добавлен" : "Нужны название и корректный адрес http/https без дубликатов."; if message == "Ярлык добавлен" { linkName = ""; linkURL = "" } }.disabled(linkName.isEmpty || linkURL.isEmpty) }.font(.system(size: 10))
                ForEach(model.quickLinks) { link in HStack(spacing: 10) { Image(systemName: link.symbol).foregroundStyle(.mint).frame(width: 20); VStack(alignment: .leading, spacing: 3) { Text(link.name).font(.system(size: 11)); Text(link.destination).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Button { model.moveQuickLink(link.id, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(model.quickLinks.first == link); Button { model.moveQuickLink(link.id, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(model.quickLinks.last == link); Button { editingLink = link } label: { Image(systemName: "pencil") }; Button { if let url = link.url { ActionRouter.open(.resource(url)) } } label: { Image(systemName: "arrow.up.right") }; Button { model.removeQuickLink(link.id) } label: { Image(systemName: "minus.circle") } }.buttonStyle(.borderless) }
                if !message.isEmpty { Text(message).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }.sheet(item: $editingLink) { LinkEditor(model: model, link: $0) }.onAppear { apps = ["com.apple.iCal", "com.cron.electron", "com.microsoft.Outlook", "com.flexibits.fantastical2.mac", "com.busymac.busycal3"].compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.map { DockItem(url: $0) } }
    }
    private func chooseCalendar() { let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.applicationBundle]; if panel.runModal() == .OK, let url = panel.url { model.calendarAppPath = url.standardizedFileURL.path } }
    private func chooseFiles() { let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseFiles = true; panel.canChooseDirectories = true; if panel.runModal() == .OK { model.addFiles(panel.urls) } }
    private func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true; if panel.runModal() == .OK { for url in panel.urls { _ = model.addQuickLink(name: FileManager.default.displayName(atPath: url.path), kind: "folder", destination: url.path) } } }
}

struct ProfilesView: View {
    @ObservedObject var model: BarModel
    @State private var profileName = ""
    @State private var message = ""
    private func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 { throw ProfileArchive.ArchiveError.tooLarge }; var profile = try ProfileArchive.decode(Data(contentsOf: url)); let base = profile.name; var count = 2; while model.profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(profile.name) == .orderedSame }) { profile.name = base + " (\(count))"; count += 1 }; model.profiles.append(profile); model.save(); message = "Профиль импортирован. Нажми «Применить», чтобы включить его." }
        catch { message = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            DockPreview(model: model)
            Text("Готовые стили").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 12) { ForEach([("aurora", "Aurora", Color.mint), ("electric", "Electric", .purple), ("graphite", "Graphite", .gray), ("frost", "Frost", .blue)], id: \.0) { id, name, color in OptionTile(name, selected: model.matchingPreset == id, action: { model.applyPreset(id); message = "Стиль \(name) применён" }) { HStack(spacing: 6) { ForEach(0..<3) { i in RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.9 - Double(i) * 0.2)).frame(width: 24, height: 24).shadow(color: color.opacity(id == "electric" ? 0.65 : 0.2), radius: 8) } }.padding(10).background(id == "frost" ? .white.opacity(0.4) : .black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12)) } } }
            StudioCard("Профили панели") {
                Text("Сохрани приложения, коллекции, ярлыки и оформление вместе. Переключайся между рабочей и личной панелью одним нажатием.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                HStack { TextField("Название, например «Работа»", text: $profileName).textFieldStyle(.roundedBorder); Button("Сохранить текущую") { model.saveProfile(name: profileName); profileName = "" }.disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.font(.system(size: 10))
                HStack { Button("Импортировать профиль…", action: importProfile).font(.system(size: 10)); Spacer(); Text("Локальный файл JSON").font(.system(size: 9)).foregroundStyle(.secondary) }
                ForEach(model.profiles) { ProfileRow(model: model, profile: $0) }

            }
            StudioCard("Движение и нагрузка") { Toggle("Подсветка при наведении", isOn: $model.hoverGlow).font(.system(size: 11)); Toggle("Уменьшить движение", isOn: $model.reduceMotion).font(.system(size: 11)); Text("В покое анимации не работают. Режим энергосбережения снижает частоту анимаций; системная настройка уменьшения движения учитывается автоматически.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4) }
            if !message.isEmpty { Text(message).font(.system(size: 10)).foregroundStyle(.mint) }
        }
    }
}
