import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SpacesSettingsView: View {
    @ObservedObject var model: BarModel
    @State private var name = ""
    @State private var renaming: BarSpace?
    @State private var deleting: BarSpace?
    @State private var importAppearance = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StudioCard("Пространства для разных задач") {
                Text("У каждого пространства свои приложения, коллекции, папки и сайты. Оформление и подключённые сервисы общие.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("Показывать переключатель на панели", isOn: $model.showSpaces).font(.system(size: 11))
                HStack {
                    TextField("Название нового пространства", text: $name).textFieldStyle(.roundedBorder)
                    Button("Создать") { if model.addSpace(name: name) != nil { name = "" } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.spaces.count >= 30)
                }.font(.system(size: 11))
            }
            ForEach(Array(model.spaces.enumerated()), id: \.element.id) { index, space in
                StudioCard(space.name) {
                    HStack(spacing: 12) {
                        Image(systemName: space.symbol).foregroundStyle(.mint).font(.system(size: 21)).frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(space.paths.count) приложений · \(space.links.count) ярлыков · \(space.collections.count) коллекций").font(.system(size: 10)).foregroundStyle(.secondary)
                            if index < 9 { Text("⌃⌥\(index + 1)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.mint) }
                        }
                        Spacer()
                        Button(space.id == model.selectedSpaceID ? "Выбрано" : "Переключить") { model.selectSpace(space.id) }.disabled(space.id == model.selectedSpaceID)
                        Menu {
                            Button("Переименовать…") { renaming = space }
                            Button("Сдвинуть выше") { model.moveSpace(space.id, by: -1) }.disabled(index == 0)
                            Button("Сдвинуть ниже") { model.moveSpace(space.id, by: 1) }.disabled(index == model.spaces.count - 1)
                            Divider()
                            Button("Удалить пространство…") { deleting = space }.disabled(model.spaces.count < 2)
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 25)
                    }.font(.system(size: 11))
                    HStack {
                        Picker("Символ", selection: Binding(get: { space.symbol }, set: { model.changeSpaceSymbol(space.id, symbol: $0) })) {
                            ForEach(BarModel.spaceSymbols, id: \.self) { symbol in Label(symbol, systemImage: symbol).tag(symbol) }
                        }
                        Picker("Рабочий стол", selection: Binding(get: { space.desktop ?? 0 }, set: { model.bindSpace(space.id, desktop: $0 == 0 ? nil : $0) })) {
                            Text("Не привязано").tag(0)
                            ForEach(1...max(9, space.desktop ?? 0), id: \.self) { Text("Рабочий стол \($0)").tag($0) }
                        }
                    }.font(.system(size: 10))
                }
            }
            StudioCard("Переключение") {
                Toggle("Менять пространство прокруткой над панелью", isOn: $model.scrollToSwitch).font(.system(size: 11))
                Toggle("Следовать за рабочим столом macOS", isOn: $model.autoSwitchDesktops).font(.system(size: 11))
                Text(model.currentDesktop.map { "Сейчас рабочий стол \($0). Привяжи пространство к его номеру выше." } ?? "Определение рабочего стола сейчас недоступно. Ручное переключение продолжает работать.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text("⌃⌥1–9 — выбрать пространство. ⌃⌥D — показать или скрыть панель. Иконку приложения можно перетащить на символ другого пространства.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            }
            StudioCard("Настройки из FreeDock") {
                Text("Импорт добавит пространства из config.json. Текущие пространства и профили сохранятся.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Toggle("Также применить оформление и виджеты", isOn: $importAppearance).font(.system(size: 11))
                Button("Выбрать config.json FreeDock…", action: importConfig).font(.system(size: 11))
                if !message.isEmpty { Text(message).font(.system(size: 10)).foregroundStyle(.mint) }
            }
        }.sheet(item: $renaming) { space in
            RenameEditor(title: "Переименовать пространство", name: space.name) { model.renameSpace(space.id, name: $0) }
        }.alert("Удалить пространство?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Отмена", role: .cancel) { deleting = nil }
            Button("Удалить", role: .destructive) { if let deleting { model.removeSpace(deleting.id) }; deleting = nil }
        } message: { Text("Приложения и файлы останутся на Mac. Исчезнет только этот набор ярлыков.") }
    }
    private func importConfig() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/FreeDock")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else { throw FreeDockImport.ImportError.tooLarge }
            try model.importFreeDock(Data(contentsOf: url), appearance: importAppearance)
            message = "Пространства импортированы. Предыдущие наборы сохранены."
        } catch { message = error.localizedDescription }
    }
}
