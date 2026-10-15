import AppKit
import SwiftUI

struct SpacesSettingsView: View {
    @ObservedObject var model: BarModel
    @State private var name = ""
    @State private var editingID: String?
    @State private var renaming: BarSpace?
    @State private var deleting: BarSpace?
    @State private var undoDeleted: (BarSpace, Int)?
    @State private var importAppearance = false
    @State private var message = ""
    private var edited: BarSpace? {
        model.spaces.first { $0.id == editingID } ?? model.spaces.first { $0.id == model.selectedSpaceID }
    }
    static let symbols = [
        "house": "Дом", "briefcase": "Работа", "gamecontroller": "Игры", "music.note": "Музыка",
        "paintbrush": "Творчество", "hammer": "Разработка", "book": "Чтение", "globe": "Интернет",
        "star": "Избранное", "heart": "Личное", "bolt": "Быстро", "camera": "Фото", "film": "Видео",
        "message": "Общение", "folder": "Файлы", "terminal": "Терминал", "graduationcap": "Учёба",
        "leaf": "Отдых",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StudioCard("Наборы для разных задач") {
                Text(
                    "У каждого пространства свои приложения, коллекции, папки и сайты. Профиль сохраняет снимок текущей панели и её оформления."
                ).font(Studio.body).foregroundStyle(.secondary)
                Toggle("Переключатель пространств на панели", isOn: $model.showSpaces)
                HStack {
                    TextField("Новое пространство", text: $name).textFieldStyle(.roundedBorder).onSubmit(
                        create)
                    Button("Создать", action: create).disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.spaces.count >= 30)
                }
            }
            StudioCard("Редактор пространства") {
                Picker("Пространство", selection: Binding(get: { edited?.id ?? "" }, set: { editingID = $0 }))
                {
                    ForEach(model.spaces) { space in
                        Text(space.name + (space.id == model.selectedSpaceID ? " · сейчас на панели" : ""))
                            .tag(space.id)
                    }
                }
                if let space = edited { editor(space) }
            }
            if let removed = undoDeleted {
                HStack {
                    Text("Пространство «\(removed.0.name)» удалено.").font(Studio.caption)
                    Spacer()
                    Button("Отменить") {
                        guard model.spaces.count < 30,
                            !model.spaces.contains(where: { $0.id == removed.0.id })
                        else { return }
                        model.batch { model.spaces.insert(removed.0, at: min(removed.1, model.spaces.count)) }
                        editingID = removed.0.id
                        undoDeleted = nil
                    }
                }
            }
            StudioCard("Переключение") {
                Toggle("Менять пространство прокруткой над панелью", isOn: $model.scrollToSwitch)
                Toggle("Следовать за рабочим столом macOS", isOn: $model.autoSwitchDesktops)
                Text(
                    model.currentDesktop.map {
                        "Сейчас рабочий стол \($0). Укажи его в привязке пространства."
                    } ?? "Номер рабочего стола недоступен. Ручное переключение продолжает работать."
                ).font(Studio.caption).foregroundStyle(.secondary)
                Text(
                    "⌃⌥1–9 — выбрать пространство. ⌃⌥D — показать панель. Приложения, ярлыки и коллекции можно перетаскивать на символ другого пространства."
                ).font(Studio.caption).foregroundStyle(.secondary)
            }
            StudioCard("Импорт из FreeDock") {
                Text(
                    "Добавит пространства из config.json. Перед импортом появится описание изменений. Текущие наборы и профили сохранятся."
                ).font(Studio.caption).foregroundStyle(.secondary)
                Toggle("Применить также оформление и виджеты", isOn: $importAppearance)
                Button("Выбрать config.json…", action: importConfig)
                if !message.isEmpty { Text(message).font(Studio.caption).foregroundStyle(.secondary) }
            }
        }.sheet(item: $renaming) { space in
            RenameEditor(title: "Переименовать пространство", name: space.name) {
                model.renameSpace(space.id, name: $0)
            }
        }
        .alert(
            "Удалить пространство?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Отмена", role: .cancel) { deleting = nil }
            Button("Удалить", role: .destructive) {
                if let space = deleting, let index = model.spaces.firstIndex(where: { $0.id == space.id }) {
                    model.snapshotSpace()
                    undoDeleted = (model.spaces[index], index)
                    model.removeSpace(space.id)
                    editingID = model.selectedSpaceID
                }
                deleting = nil
            }
        } message: {
            Text("Исчезнет только набор ярлыков. Приложения и файлы останутся на Mac.")
        }
        .onAppear { editingID = model.selectedSpaceID }
    }
    @ViewBuilder private func editor(_ space: BarSpace) -> some View {
        let index = model.spaces.firstIndex { $0.id == space.id } ?? 0
        HStack(spacing: 12) {
            Image(systemName: space.symbol).font(.system(size: 24)).foregroundStyle(Studio.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(space.name).font(Studio.heading)
                Text(
                    "\(space.paths.count) приложений · \(space.links.count) ярлыков · \(space.collections.count) коллекций"
                ).font(Studio.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(space.id == model.selectedSpaceID ? "На панели" : "Показать на панели") {
                model.selectSpace(space.id)
            }.disabled(space.id == model.selectedSpaceID)
        }
        HStack {
            Button("Переименовать…") { renaming = space }
            Button {
                model.moveSpace(space.id, by: -1)
            } label: {
                Image(systemName: "arrow.up")
            }.disabled(index == 0).accessibilityLabel("Передвинуть пространство выше")
            Button {
                model.moveSpace(space.id, by: 1)
            } label: {
                Image(systemName: "arrow.down")
            }.disabled(index == model.spaces.count - 1).accessibilityLabel("Передвинуть пространство ниже")
            Spacer()
            Button("Удалить…", role: .destructive) { deleting = space }.disabled(model.spaces.count < 2)
        }
        Picker(
            "Значок",
            selection: Binding(get: { space.symbol }, set: { model.changeSpaceSymbol(space.id, symbol: $0) })
        ) {
            ForEach(BarModel.spaceSymbols, id: \.self) { symbol in
                Label(Self.symbols[symbol] ?? "Значок", systemImage: symbol).tag(symbol)
            }
        }
        Picker(
            "Рабочий стол",
            selection: Binding(
                get: { space.desktop ?? 0 },
                set: { PanelActions.bind(space, desktop: $0 == 0 ? nil : $0, model: model) })
        ) {
            Text("Без привязки").tag(0)
            ForEach(1...30, id: \.self) { number in
                Text(
                    "Стол \(number)"
                        + (model.spaces.contains(where: { $0.desktop == number && $0.id != space.id })
                            ? " · занят" : "")
                ).tag(number)
            }
        }
        if index < 9 {
            Text("Быстрое переключение: ⌃⌥\(index + 1)").font(Studio.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup("Содержимое и недоступные ярлыки") {
            VStack(alignment: .leading, spacing: 10) {
                if space.paths.isEmpty && space.links.isEmpty && space.collections.isEmpty {
                    Text("Пустой набор. Покажи его на панели и добавь приложения или ярлыки.").font(
                        Studio.caption
                    ).foregroundStyle(.secondary)
                }
                ForEach(space.paths, id: \.self) { path in
                    HStack {
                        Image(
                            systemName: FileManager.default.fileExists(atPath: path)
                                ? "app" : "exclamationmark.triangle")
                        Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent).lineLimit(
                            1
                        ).help(path)
                        Spacer()
                        Button("Убрать ярлык") { remove(path, from: space) }.accessibilityLabel(
                            "Убрать ярлык " + URL(fileURLWithPath: path).lastPathComponent)
                    }.font(Studio.caption)
                }
                ForEach(space.links) { link in Label(link.name, systemImage: link.symbol).font(Studio.caption)
                }
                ForEach(space.collections) { group in
                    Label(group.name, systemImage: group.symbol).font(Studio.caption)
                }
                Button("Редактировать состав на панели") {
                    model.selectSpace(space.id)
                    UIStateStore.shared.section = "apps"
                }
            }.padding(.top, 12)
        }
    }
    private func create() {
        if let id = model.addSpace(name: name) {
            editingID = id
            name = ""
        }
    }
    private func remove(_ path: String, from space: BarSpace) {
        if space.id == model.selectedSpaceID {
            if let item = model.pinned.first(where: { $0.id == path }) { model.remove(item) }
        } else if let index = model.spaces.firstIndex(where: { $0.id == space.id }) {
            model.batch { model.spaces[index].paths.removeAll { $0 == path } }
        }
    }
    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else {
                throw FreeDockImport.ImportError.tooLarge
            }
            let data = try Data(contentsOf: url)
            let source = try FreeDockImport.decode(data)
            guard source.spaces.count + model.spaces.count <= 30 else {
                throw FreeDockImport.ImportError.capacity
            }
            let alert = NSAlert()
            alert.messageText = "Импортировать пространства?"
            alert.informativeText =
                "Будет добавлено \(source.spaces.count) пространств, \(source.spaces.reduce(0) { $0 + $1.items.count }) элементов. "
                + (importAppearance ? "Оформление и виджеты изменятся." : "Оформление останется прежним.")
                + " Текущие пространства сохранятся."
            alert.addButton(withTitle: "Импортировать")
            alert.addButton(withTitle: "Отмена")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try model.importFreeDock(data, appearance: importAppearance)
            editingID = model.selectedSpaceID
            message = "Импортировано \(source.spaces.count) пространств. Предыдущие наборы сохранены."
        } catch { message = error.localizedDescription }
    }
}
