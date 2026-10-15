import SwiftUI
import AppKit

struct FolderStackView: View {
    @ObservedObject private var localization = Localization.shared
    let folder: URL
    @State private var files: [URL] = []
    @State private var query = ""
    @State private var loading = true
    @State private var message = ""
    private var visible: [URL] { files.filter { query.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(.mint)
                Text(FileManager.default.displayName(atPath: folder.path)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                Button(L("В Finder")) { NSWorkspace.shared.open(folder) }.font(.system(size: 10))
            }
            TextField(L("Найти в папке"), text: $query).textFieldStyle(.roundedBorder)
            if loading { ProgressView().frame(maxWidth: .infinity) }
            else if !message.isEmpty { Text(localization.status(message)).font(.system(size: 11)).foregroundStyle(.secondary) }
            else if visible.isEmpty { Text(query.isEmpty ? L("Папка пуста") : L("Ничего не найдено")).font(.system(size: 11)).foregroundStyle(.secondary) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                    ForEach(visible, id: \.self) { url in
                        Button { ActionRouter.open(.resource(url)) } label: {
                            VStack(spacing: 7) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 38, height: 38)
                                Text(url.lastPathComponent).font(.system(size: 9)).lineLimit(2).frame(height: 25)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).help(url.lastPathComponent)
                    }
                }
            }
            Text(L("\(files.count) элементов · скрытые файлы не показаны")).font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(20).frame(width: 370, height: 410)
            .background(Color(red: 0.085, green: 0.085, blue: 0.11)).preferredColorScheme(.dark)
            .task {
                let result = await Task.detached(priority: .userInitiated) { () -> (files: [URL], message: String) in
                    do {
                        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
                        return (Array(urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.prefix(500)), "")
                    } catch { return ([], L("Не удалось прочитать папку. Открой её в Finder и проверь доступ.")) }
                }.value
                guard !Task.isCancelled else { return }; files = result.files; message = result.message; loading = false
            }
    }
}
