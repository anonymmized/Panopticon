import AppKit
import SwiftUI

extension SettingsView {
    var apps: some View {
        VStack(alignment: .leading, spacing: 23) {
            card("Закреплённые") {
                HStack {
                    Button("Добавить…") { chooseApps { model.add($0) } }
                    Button("Добавить из Dock macOS") { PanelActions.importSystemDock(model: model) }
                    Spacer()
                    Text("\(model.pinned.count)").foregroundStyle(.secondary)
                }.font(.system(size: 11))
                Text("Закреплённые приложения остаются на панели после закрытия. Повторный импорт добавляет недостающие и сохраняет текущий порядок.")
                    .font(Studio.caption).foregroundStyle(.secondary)
                ForEach(model.pinned) { item in
                    HStack(spacing: 10) {
                        Image(nsImage: item.icon).resizable().frame(width: 27, height: 27)
                        Text(item.name).font(.system(size: 11))
                        Spacer()
                        Button {
                            move(item, -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }.accessibilityLabel("Передвинуть \(item.name) выше").disabled(
                            model.pinned.first == item)
                        Button {
                            move(item, 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }.accessibilityLabel("Передвинуть \(item.name) ниже").disabled(
                            model.pinned.last == item)
                        Button {
                            model.remove(item)
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }.accessibilityLabel("Убрать ярлык \(item.name)")
                    }.buttonStyle(.borderless)
                }
            }
            sectionTitle("Все приложения", "Нажми на карточку, чтобы закрепить или убрать приложение.")
            if catalog.loading { ProgressView().controlSize(.small) }
            TextField("Поиск приложений", text: $search).textFieldStyle(.roundedBorder)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 12)], spacing: 12) {
                ForEach(
                    catalog.items.filter {
                        search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                    }
                ) { item in
                    Button {
                        if model.pinned.contains(item) { model.remove(item) } else { model.add(item.url) }
                    } label: {
                        VStack(spacing: 8) {
                            Image(nsImage: item.icon).resizable().frame(width: 38, height: 38)
                            Text(item.name).font(.system(size: 11)).lineLimit(1)
                            Image(
                                systemName: model.pinned.contains(item)
                                    ? "checkmark.circle.fill" : "plus.circle"
                            ).font(.system(size: 11)).foregroundStyle(
                                model.pinned.contains(item) ? .mint : .secondary)
                        }.padding(12).frame(maxWidth: .infinity).background(
                            Studio.surface, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    var collections: some View {
        VStack(alignment: .leading, spacing: 23) {
            card("Новая коллекция") {
                HStack {
                    TextField("Название, например «Работа»", text: $collectionName).textFieldStyle(
                        .roundedBorder)
                    Button("Создать") {
                        let group = AppCollection(
                            name: collectionName.trimmingCharacters(in: .whitespacesAndNewlines))
                        model.updateCollection(group)
                        selectedCollection = group.id
                        collectionName = ""
                    }.disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.font(.system(size: 11))
            }
            if model.collections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 34)).foregroundStyle(.purple)
                    Text("Место для твоих коллекций").font(.system(size: 15, weight: .medium))
                    Text("Группа появится на панели. Нажатие откроет сетку приложений.").font(
                        .system(size: 11)
                    ).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 48)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.collections) { group in
                            Button {
                                selectedCollection = group.id
                            } label: {
                                Label(group.name, systemImage: group.symbol).font(.system(size: 11)).padding(
                                    11
                                ).background(
                                    selectedCollection == group.id
                                        ? Color.purple.opacity(0.2) : Studio.surface,
                                    in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if let group = collection {
                    card(group.name) {
                        HStack {
                            Button("Переименовать") { renamingCollection = true }
                            Button("Добавить приложения…") {
                                chooseApps { url in
                                    var updated = model.collections.first { $0.id == group.id } ?? group
                                    if !updated.paths.contains(url.path) {
                                        updated.paths.append(url.path)
                                        model.updateCollection(updated)
                                    }
                                }
                            }
                            Spacer()
                            Button("Удалить коллекцию…") { deletingCollection = group }.foregroundStyle(
                                .secondary)
                        }.font(.system(size: 11))
                        Picker("Значок коллекции", selection: Binding(get: { group.symbol }, set: { symbol in
                            guard var latest = model.collections.first(where: { $0.id == group.id }) else { return }
                            latest.symbol = symbol; model.updateCollection(latest)
                        })) {
                            Label("Сетка", systemImage: "square.grid.2x2.fill").tag("square.grid.2x2.fill")
                            ForEach(BarModel.spaceSymbols, id: \.self) { symbol in Label(SpacesSettingsView.symbols[symbol] ?? "Значок", systemImage: symbol).tag(symbol) }
                        }
                        HStack {
                            Button("Передвинуть коллекцию выше") { moveCollection(group.id, by: -1) }.disabled(model.collections.first?.id == group.id)
                            Button("Ниже") { moveCollection(group.id, by: 1) }.disabled(model.collections.last?.id == group.id)
                        }.font(Studio.caption)
                        ForEach(group.items) { item in
                            HStack {
                                Image(nsImage: item.icon).resizable().frame(width: 28, height: 28)
                                Text(item.name).font(.system(size: 11))
                                Spacer()
                                Button {
                                    moveCollectionItem(item.id, in: group, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }.accessibilityLabel("Передвинуть \(item.name) выше").disabled(
                                    group.paths.first == item.id
                                ).buttonStyle(.borderless)
                                Button {
                                    moveCollectionItem(item.id, in: group, by: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }.accessibilityLabel("Передвинуть \(item.name) ниже").disabled(
                                    group.paths.last == item.id
                                ).buttonStyle(.borderless)
                                Button {
                                    var updated = group
                                    updated.paths.removeAll { $0 == item.id }
                                    model.updateCollection(updated)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }.buttonStyle(.borderless).accessibilityLabel(
                                    "Убрать \(item.name) из коллекции")
                            }
                        }
                        ForEach(group.paths.filter { !FileManager.default.fileExists(atPath: $0) || Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier == nil }, id: \.self) { path in
                            HStack {
                                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "exclamationmark.triangle").lineLimit(1).help(path)
                                Spacer()
                                Button("Убрать недоступный ярлык") {
                                    guard var latest = model.collections.first(where: { $0.id == group.id }) else { return }
                                    latest.paths.removeAll { $0 == path }; model.updateCollection(latest)
                                }
                            }.font(Studio.caption).foregroundStyle(.secondary)
                        }
                        if group.paths.isEmpty {
                            Text("Добавь приложения в коллекцию.").font(.system(size: 11)).foregroundStyle(
                                .secondary)
                        }
                    }
                }
            }
            if let removed = removedCollection {
                HStack {
                    Text("Коллекция удалена").font(Studio.caption)
                    Spacer()
                    Button("Отменить") {
                        guard removed.2 == model.selectedSpaceID, !model.collections.contains(where: { $0.id == removed.0.id }) else { removedCollection = nil; return }
                        model.batch {
                            model.collections.insert(removed.0, at: min(removed.1, model.collections.count))
                        }
                        selectedCollection = removed.0.id
                        removedCollection = nil
                    }
                }
            }
        }.alert(
            "Удалить коллекцию?",
            isPresented: Binding(
                get: { deletingCollection != nil }, set: { if !$0 { deletingCollection = nil } })
        ) {
            Button("Отмена", role: .cancel) { deletingCollection = nil }
            Button("Удалить", role: .destructive) {
                if let group = deletingCollection {
                    removedCollection = (
                        group, model.collections.firstIndex(where: { $0.id == group.id }) ?? 0, model.selectedSpaceID
                    )
                    model.removeCollection(group.id)
                    selectedCollection = model.collections.first?.id
                }
                deletingCollection = nil
            }
        } message: {
            Text("Исчезнет группа ярлыков. Приложения останутся на Mac.")
        }
        .sheet(isPresented: $renamingCollection) {
            if let group = collection {
                RenameEditor(title: "Название коллекции", name: group.name) { name in
                    let clean = SettingsRules.label(name)
                    guard !clean.isEmpty else { return false }
                    var copy = group
                    copy.name = clean
                    model.updateCollection(copy)
                    return true
                }
            }
        }.onAppear { if selectedCollection == nil { selectedCollection = model.collections.first?.id } }
    }
    func moveCollection(_ id: String, by delta: Int) {
        guard let index = model.collections.firstIndex(where: { $0.id == id }) else { return }
        _ = PanelActions.reorderCollection(id, before: delta < 0 ? index - 1 : index + 2, model: model)
    }
    func moveCollectionItem(_ path: String, in group: AppCollection, by offset: Int) {
        guard let i = group.paths.firstIndex(of: path) else { return }
        let target = min(max(0, i + offset), group.paths.count - 1)
        var copy = group
        copy.paths.swapAt(i, target)
        model.updateCollection(copy)
    }
    func move(_ item: DockItem, _ direction: Int) {
        guard let i = model.pinned.firstIndex(of: item) else { return }
        model.move(item.id, to: direction < 0 ? i - 1 : i + 2)
    }
    func chooseApps(_ action: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(action) }
    }
    func loadLibrary() { catalog.refresh(force: true) }
}
