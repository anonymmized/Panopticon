import AppKit
import SwiftUI

struct StudioCard<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Studio.gap) {
            Text(title).font(Studio.heading)
            content
        }.padding(Studio.inset).frame(maxWidth: .infinity, alignment: .leading).modifier(SurfaceStyle())
    }
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
                Picker("Назначение", selection: $model.calendarDestination) {
                    Text("Календарь macOS").tag("system")
                    Text("Приложение").tag("app")
                    Text("Веб-календарь").tag("web")
                }.pickerStyle(.segmented)
                if model.calendarDestination == "app" {
                    HStack(spacing: 12) {
                        if !model.calendarAppPath.isEmpty {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: model.calendarAppPath))
                                .resizable().frame(width: 34, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.calendarAppPath.isEmpty ? "Выбери приложение" : model.calendarAppName)
                                .font(.system(size: 12, weight: .medium))
                            Text("Можно выбрать любое приложение на Mac.").font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Выбрать…", action: chooseCalendar).font(.system(size: 11))
                    }
                    if !apps.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(apps) { app in
                                    Button {
                                        model.calendarAppPath = app.id
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                                            Text(app.name).font(.system(size: 11))
                                        }.padding(7).background(
                                            model.calendarAppPath == app.id
                                                ? Color.mint.opacity(0.13) : Studio.surface,
                                            in: RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                if model.calendarDestination == "web" {
                    TextField("https://calendar.google.com", text: $model.calendarWebURL).textFieldStyle(
                        .roundedBorder)
                    HStack {
                        Button("Google Calendar") { model.calendarWebURL = "https://calendar.google.com" }
                        Button("Outlook") { model.calendarWebURL = "https://outlook.live.com/calendar" }
                    }.font(.system(size: 11))
                    Text("Откроется в браузере по умолчанию.").font(.system(size: 11)).foregroundStyle(
                        .secondary)
                }
                HStack {
                    Text("Нажатие на часы").font(.system(size: 11))
                    Spacer()
                    Picker("Нажатие на часы", selection: $model.clockAction) {
                        Text("Открыть приложение").tag("open")
                        Text("Показать календарь").tag("agenda")
                    }.labelsHidden().frame(width: 185)
                }
                Button("Открыть выбранный календарь") { model.openCalendar() }.font(.system(size: 11))
                    .disabled(model.calendarTarget == nil)
            }
            StudioCard("Ближайшие события") {
                Toggle("Показывать события календарей macOS", isOn: $model.calendarEventsEnabled).font(
                    .system(size: 11)
                ).toggleStyle(.switch)
                Text(
                    "События читаются из календарей, подключённых к macOS, например iCloud или Google. Выбор Notion Calendar, Outlook или другого приложения выше задаёт, что открывать; сам по себе он не импортирует события этого сервиса."
                ).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                if !agenda.authorized {
                    Button("Подключить календари…") {
                        model.calendarEventsEnabled = true
                        agenda.enabled = true
                        agenda.connect()
                    }.font(.system(size: 11))
                    Text(agenda.message).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Настройки доступа macOS") {
                        NSWorkspace.shared.open(
                            URL(
                                string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                            )!)
                    }.font(.system(size: 11))
                } else {
                    HStack {
                        Button("Все календари") {
                            model.selectedCalendarIDs = []
                            model.save()
                        }
                        Button("Снять выбор") {
                            model.selectedCalendarIDs = ["__none__"]
                            model.save()
                        }
                    }.font(.system(size: 11))
                    Label("Доступ подключён. События остаются на Mac.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.mint)
                    ForEach(agenda.calendarNames, id: \.id) { calendar in
                        Toggle(
                            calendar.name,
                            isOn: Binding(
                                get: {
                                    model.selectedCalendarIDs.isEmpty
                                        || model.selectedCalendarIDs.contains(calendar.id)
                                },
                                set: { enabled in
                                    var chosen = Set(
                                        model.selectedCalendarIDs.isEmpty
                                            ? agenda.calendarNames.map(\.id) : model.selectedCalendarIDs)
                                    if enabled {
                                        chosen.insert(calendar.id)
                                    } else {
                                        chosen.remove(calendar.id)
                                    }
                                    model.selectedCalendarIDs = chosen.isEmpty ? ["__none__"] : Array(chosen)
                                    model.save()
                                })
                        ).font(.system(size: 11))
                    }
                }
            }
            StudioCard("Папки и сайты на панели") {
                HStack {
                    Button("Добавить папку…", action: chooseFolder)
                    Button("Добавить файлы…", action: chooseFiles)
                    Button("Загрузки") {
                        _ = model.addQuickLink(
                            name: "Загрузки", kind: "folder", destination: NSHomeDirectory() + "/Downloads")
                    }
                    Spacer()
                    Text("\(model.quickLinks.count) ярлыков").foregroundStyle(.secondary)
                }.font(.system(size: 11))
                HStack {
                    TextField("Название сайта", text: $linkName).textFieldStyle(.roundedBorder).frame(
                        width: 135)
                    TextField("https://…", text: $linkURL).textFieldStyle(.roundedBorder)
                    Button("Добавить") {
                        message =
                            model.addQuickLink(name: linkName, kind: "web", destination: linkURL)
                            ? "Ярлык добавлен"
                            : "Нужны название и корректный адрес http/https без дубликатов."
                        if message == "Ярлык добавлен" {
                            linkName = ""
                            linkURL = ""
                        }
                    }.disabled(linkName.isEmpty || linkURL.isEmpty)
                }.font(.system(size: 11))
                ForEach(model.quickLinks) { link in
                    HStack(spacing: 10) {
                        Image(systemName: link.symbol).foregroundStyle(.mint).frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.name).font(.system(size: 11))
                            Text(link.destination).font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            model.moveQuickLink(link.id, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }.accessibilityLabel("Передвинуть \(link.name) выше").disabled(
                            model.quickLinks.first == link)
                        Button {
                            model.moveQuickLink(link.id, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }.accessibilityLabel("Передвинуть \(link.name) ниже").disabled(
                            model.quickLinks.last == link)
                        Button {
                            editingLink = link
                        } label: {
                            Image(systemName: "pencil")
                        }.accessibilityLabel("Редактировать \(link.name)")
                        Button {
                            if let url = link.url { ActionRouter.open(.resource(url)) }
                        } label: {
                            Image(systemName: "arrow.up.right")
                        }.accessibilityLabel("Открыть \(link.name)")
                        Button {
                            model.removeQuickLink(link.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }.accessibilityLabel("Убрать ярлык \(link.name)")
                    }.buttonStyle(.borderless)
                }
                if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }.sheet(item: $editingLink) { LinkEditor(model: model, link: $0) }.onAppear {
            apps = [
                "com.apple.iCal", "com.cron.electron", "com.microsoft.Outlook",
                "com.flexibits.fantastical2.mac", "com.busymac.busycal3",
            ].compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.map {
                DockItem(url: $0)
            }
        }
    }
    private func chooseCalendar() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        if panel.runModal() == .OK, let url = panel.url {
            model.calendarAppPath = url.standardizedFileURL.path
        }
    }
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { model.addFiles(panel.urls) }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = model.addQuickLink(
                    name: FileManager.default.displayName(atPath: url.path), kind: "folder",
                    destination: url.path)
            }
        }
    }
}
