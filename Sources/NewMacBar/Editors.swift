import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LinkEditor: View {
    @ObservedObject var model: BarModel
    @Environment(\.dismiss) private var dismiss
    @State var link: QuickLink
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Редактировать ярлык").font(.system(size: 20, weight: .semibold))
            TextField("Название", text: $link.name).textFieldStyle(.roundedBorder)
            HStack {
                TextField(
                    link.kind == "folder"
                        ? "Путь к папке" : (link.kind == "file" ? "Путь к файлу" : "https://…"),
                    text: $link.destination
                ).textFieldStyle(.roundedBorder)
                if link.kind == "folder" || link.kind == "file" {
                    Button("Выбрать…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = link.kind == "file"
                        panel.canChooseDirectories = link.kind == "folder"
                        if panel.runModal() == .OK, let url = panel.url { link.destination = url.path }
                    }
                }
            }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить") {
                    if model.updateQuickLink(link) {
                        dismiss()
                    } else {
                        error = "Проверь название, адрес и отсутствие дубликата."
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(25).frame(width: 470)
    }
}

struct RenameEditor: View {
    let title: String
    @State var name: String
    let save: (String) -> Bool
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 19, weight: .semibold))
            TextField("Название", text: $name).textFieldStyle(.roundedBorder)
            if failed {
                Text("Введи уникальное непустое название.").font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить") { if save(name) { dismiss() } else { failed = true } }.keyboardShortcut(
                    .defaultAction)
            }
        }.padding(25).frame(width: 380)
    }
}

struct ProfileRow: View {
    @ObservedObject var model: BarModel
    let profile: DockProfile
    @State private var renaming = false
    @State private var deleting = false
    @State private var previous: DockProfile?
    @State private var previousSpaceID = ""
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(
                    systemName: model.matchingProfileID == profile.id
                        ? "checkmark.circle.fill" : "rectangle.stack.fill"
                ).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(.system(size: 12, weight: .medium))
                    Text(
                        "\(profile.pinned.count) приложений · \(profile.collections.count) коллекций · \(profile.links.count) ярлыков"
                    ).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Применить") {
                    previousSpaceID = model.selectedSpaceID
                    previous = DockProfile(
                        name: "Предыдущая панель", pinned: model.pinned.map(\.id),
                        collections: model.collections, links: model.quickLinks, appearance: .init(model))
                    model.applyProfile(profile)
                }.font(.system(size: 11))
                Menu {
                    Button("Обновить текущей панелью") { model.updateProfile(profile.id) }
                    Button("Переименовать") { renaming = true }
                    Button("Экспортировать…", action: export)
                    Divider()
                    Button("Удалить профиль…", role: .destructive) { deleting = true }
                } label: {
                    Image(systemName: "ellipsis")
                }.menuStyle(.borderlessButton).frame(width: 22)
            }
            if let previous {
                Button("Отменить применение профиля") {
                    guard previousSpaceID == model.selectedSpaceID else { self.previous = nil; return }
                    model.applyProfile(previous)
                    self.previous = nil
                }.font(Studio.caption)
            }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
        }.alert("Удалить профиль «\(profile.name)»?", isPresented: $deleting) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { model.deleteProfile(profile.id) }
        } message: {
            Text("Текущая панель останется прежней. Удалится сохранённый снимок.")
        }
        .onChange(of: model.selectedSpaceID) { _ in previous = nil }
        .sheet(isPresented: $renaming) {
            RenameEditor(title: "Переименовать профиль", name: profile.name) {
                model.renameProfile(profile.id, to: $0)
            }
        }
    }
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = profile.name.replacingOccurrences(of: "/", with: "-") + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProfileArchive(profile: profile).data().write(to: url, options: .atomic)
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}

struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    @State private var draft: String
    @FocusState private var editing: Bool

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) {
        self.title = title
        _value = value
        self.range = range
        self.label = label
        let scale = label.contains("%") ? 100.0 : 1.0
        _draft = State(initialValue: Self.formatted(value.wrappedValue * scale))
    }
    private var scale: Double { label.contains("%") ? 100 : 1 }
    private var unit: String {
        label.contains("%")
            ? "%" : (label.hasPrefix("×") ? "×" : (label.split(separator: " ").last.map(String.init) ?? ""))
    }
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        return f
    }()
    private static func formatted(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    private func commit() {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if let number = Double(input) { value = SettingsRules.number(number / scale, range, fallback: value) }
        draft = Self.formatted(value * scale)
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(Studio.body)
                Spacer()
                TextField("Значение", text: $draft)
                    .focused($editing).onSubmit { commit() }
                    .onChange(of: editing) { if !$0 { commit() } }
                    .onChange(of: value) { draft = Self.formatted($0 * scale) }
                    .font(.system(size: 11, design: .monospaced)).textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing).frame(width: 58).accessibilityLabel(
                        title + " — точное значение")
                Text(unit).font(.system(size: 11)).foregroundStyle(.mint).frame(
                    minWidth: 16, alignment: .leading)
            }
            Slider(value: $value, in: range).controlSize(.small).accessibilityLabel(title)
        }
    }
}
