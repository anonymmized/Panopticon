import AppKit
import SwiftUI

struct FolderEntry: Identifiable {
    let url: URL
    let modified: Date
    let directory: Bool
    var id: String { url.path }
}

/// All directory I/O stays off main; cancellation reaches the worker and
/// obsolete results cannot update a closed or refreshed popover.
final class FolderPresentationLoader: ObservableObject {
    @Published private(set) var entries: [FolderEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error = ""
    @Published private(set) var limited = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    static let limit = 500
    func load(_ folder: URL) {
        cancel()
        let token = UUID()
        generation = token
        loading = true
        entries = []; limited = false
        error = ""
        task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                () -> ([FolderEntry], Bool, LocalizedMessage?) in
                let manager = FileManager.default
                do {
                    let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
                    guard values.isDirectory == true else {
                        return ([], false, "Папка перемещена или удалена.")
                    }
                    var enumerationError: Error?
                    guard
                        let enumerator = manager.enumerator(
                            at: folder,
                            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                            options: [
                                .skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants,
                            ],
                            errorHandler: { _, error in
                                enumerationError = error
                                return false
                            })
                    else { return ([], false, "Папка недоступна. Проверь диск и доступ в Finder.") }
                    var entries: [FolderEntry] = []
                    while !Task.isCancelled, let url = enumerator.nextObject() as? URL {
                        if entries.count == FolderPresentationLoader.limit { return (entries, true, nil) }
                        let values = try? url.resourceValues(forKeys: [
                            .contentModificationDateKey, .isDirectoryKey,
                        ])
                        entries.append(
                            FolderEntry(
                                url: url, modified: values?.contentModificationDate ?? .distantPast,
                                directory: values?.isDirectory == true))
                    }
                    if enumerationError != nil {
                        return (
                            [], false,
                            "Не удалось прочитать папку. Проверь подключение диска и доступ в Finder."
                        )
                    }
                    return (entries, false, nil)
                } catch {
                    let code = (error as NSError).code
                    return (
                        [], false,
                        code == NSFileNoSuchFileError || code == NSFileReadNoSuchFileError
                            ? "Папка перемещена или удалена."
                            : "Нет доступа к папке. Открой её в Finder и проверь разрешения."
                    )
                }
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.entries = result.0
            self.limited = result.1
            self.error = result.2.map { L($0) } ?? ""
            self.loading = false
        }
    }
    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        loading = false
    }
    deinit { task?.cancel() }
}

struct FolderStackView: View {
    @ObservedObject var localization = Localization.shared
    let folder: URL
    @StateObject private var loader = FolderPresentationLoader()
    @State private var query = ""
    @State private var sort = "name"
    @State private var list = false
    @State private var selectedID: String?
    @FocusState private var focused: Bool
    private var visible: [FolderEntry] {
        loader.entries.filter {
            query.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
        }.sorted {
            if sort == "modified", $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                == .orderedAscending
        }
    }
    var body: some View {
        let entries = visible
        let ids = entries.map(\.id)
        let selected = StableSelection.reconciled(selectedID, in: ids)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(Studio.accent).accessibilityHidden(true)
                Text(folder.lastPathComponent).font(Studio.heading).lineLimit(1).help(
                    folder.lastPathComponent)
                Spacer()
                Button(L("В Finder")) { NSWorkspace.shared.open(folder) }
            }
            TextField(L("Найти в папке"), text: $query).textFieldStyle(.roundedBorder).focused($focused)
            HStack {
                Picker(L("Сортировка"), selection: $sort) {
                    Text(L("По имени")).tag("name")
                    Text(L("Сначала новые")).tag("modified")
                }.labelsHidden()
                Spacer()
                Toggle(isOn: $list) { Image(systemName: list ? "list.bullet" : "square.grid.2x2") }
                    .toggleStyle(.button).accessibilityLabel(L("Показать списком"))
                Button {
                    loader.load(folder)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.accessibilityLabel(L("Обновить папку")).disabled(loader.loading)
            }
            if loader.loading {
                ProgressView(L("Читаю папку…")).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if !loader.error.isEmpty {
                EmptyState(
                    symbol: "folder.badge.questionmark", title: L("Папка недоступна"), detail: localization.status(loader.error))
                Button(L("Повторить")) { loader.load(folder) }
            } else if entries.isEmpty {
                EmptyState(
                    symbol: "folder", title: query.isEmpty ? L("Папка пуста") : L("Ничего не найдено"),
                    detail: query.isEmpty ? L("Скрытые файлы здесь не показаны.") : L("Попробуй изменить запрос."))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if list {
                        LazyVStack(spacing: 4) {
                            ForEach(entries) { entry in
                                fileButton(entry, selected: entry.id == selected, list: true)
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], spacing: 12) {
                            ForEach(entries) { entry in
                                fileButton(entry, selected: entry.id == selected, list: false)
                            }
                        }
                    }
                }.onChange(of: selectedID) { value in if let value { proxy.scrollTo(value, anchor: .center) }
                }
            }
            Text(
                loader.limited
                    ? L("Показаны первые \(FolderPresentationLoader.limit) элементов. Все файлы доступны в Finder.")
                    : L("\(loader.entries.count) элементов · скрытые файлы не показаны")
            ).font(Studio.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.modifier(PopoverSurface()).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                KeyboardCommands { event in
                    switch event.keyCode {
                    case 125:
                        selectedID = StableSelection.moved(selected, in: ids, by: 1)
                        return true
                    case 126:
                        selectedID = StableSelection.moved(selected, in: ids, by: -1)
                        return true
                    case 123, 124:
                    guard !focused else { return false }
                    selectedID = StableSelection.moved(selected, in: ids, by: event.keyCode == 124 ? 1 : -1)
                    return true
                case 36, 76:
                        if let entry = entries.first(where: { $0.id == selected }) {
                            ActionRouter.open(.resource(entry.url))
                        }
                        return true
                    default: return false
                    }
                }
            )
            .onAppear {
                loader.load(folder)
                focused = true
            }
            .onDisappear { loader.cancel() }
            .onChange(of: query) { _ in selectedID = nil }
            .onChange(of: ids) { selectedID = StableSelection.reconciled(selectedID, in: $0) }
    }
    func fileButton(_ entry: FolderEntry, selected: Bool, list: Bool) -> some View {
        Button {
            selectedID = entry.id
            ActionRouter.open(.resource(entry.url))
        } label: {
            Group {
                if list {
                    HStack(spacing: 10) {
                        fileIcon(entry).frame(width: 24, height: 24)
                        Text(entry.url.lastPathComponent).lineLimit(1)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 7) {
                        fileIcon(entry).frame(width: 38, height: 38)
                        Text(entry.url.lastPathComponent).lineLimit(2).frame(height: 32)
                    }.frame(maxWidth: .infinity)
                }
            }.font(Studio.caption).padding(8).background(
                selected ? Studio.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10)
            ).contentShape(Rectangle())
        }.buttonStyle(.plain).id(entry.id).help(entry.url.lastPathComponent).accessibilityLabel(
            entry.url.lastPathComponent + (entry.directory ? L(", папка") : L(", файл"))
        ).accessibilityAddTraits(selected ? [.isSelected] : [])
            .contextMenu {
                Button(L("Открыть")) { ActionRouter.open(.resource(entry.url)) }
                Button(L("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            }
    }
    func fileIcon(_ entry: FolderEntry) -> some View {
        // Symbol fallback remains immediate on disconnected/network volumes.
        Image(systemName: entry.directory ? "folder.fill" : "doc.fill").resizable().scaledToFit()
            .foregroundStyle(entry.directory ? Color.accentColor : .secondary).accessibilityHidden(true)
    }
}
