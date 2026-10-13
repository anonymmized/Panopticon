import SwiftUI
import AppKit
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
            HStack { TextField(link.kind == "folder" ? "Путь к папке" : "https://…", text: $link.destination).textFieldStyle(.roundedBorder); if link.kind == "folder" { Button("Выбрать…") { let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; if panel.runModal() == .OK, let url = panel.url { link.destination = url.path } } } }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack { Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Сохранить") { if model.updateQuickLink(link) { dismiss() } else { error = "Проверь название, адрес и отсутствие дубликата." } }.keyboardShortcut(.defaultAction) }
        }.padding(25).frame(width: 470).preferredColorScheme(.dark)
    }
}

struct RenameEditor: View {
    let title: String
    @State var name: String
    let save: (String) -> Bool
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { Text(title).font(.system(size: 19, weight: .semibold)); TextField("Название", text: $name).textFieldStyle(.roundedBorder); if failed { Text("Введи уникальное непустое название.").font(.system(size: 11)).foregroundStyle(.orange) }; HStack { Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Сохранить") { if save(name) { dismiss() } else { failed = true } }.keyboardShortcut(.defaultAction) } }.padding(25).frame(width: 380).preferredColorScheme(.dark)
    }
}

struct ProfileRow: View {
    @ObservedObject var model: BarModel
    let profile: DockProfile
    @State private var renaming = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) { Image(systemName: model.matchingProfileID == profile.id ? "checkmark.circle.fill" : "rectangle.stack.fill").foregroundStyle(.mint); VStack(alignment: .leading, spacing: 3) { Text(profile.name).font(.system(size: 12, weight: .medium)); Text("\(profile.pinned.count) приложений · \(profile.collections.count) коллекций · \(profile.links.count) ярлыков").font(.system(size: 9)).foregroundStyle(.secondary) }; Spacer(); Button("Применить") { model.applyProfile(profile) }.font(.system(size: 10)); Menu { Button("Обновить текущей панелью") { model.updateProfile(profile.id) }; Button("Переименовать") { renaming = true }; Button("Экспортировать…", action: export); Divider(); Button("Удалить профиль") { model.deleteProfile(profile.id) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22) }
            if !error.isEmpty { Text(error).font(.system(size: 10)).foregroundStyle(.orange) }
        }.sheet(isPresented: $renaming) { RenameEditor(title: "Переименовать профиль", name: profile.name) { model.renameProfile(profile.id, to: $0) } }
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = profile.name.replacingOccurrences(of: "/", with: "-") + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ProfileArchive(profile: profile).data().write(to: url, options: .atomic); error = "" } catch { self.error = error.localizedDescription }
    }
}

struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    private var scale: Double { label.contains("%") ? 100 : 1 }
    private var unit: String { label.contains("%") ? "%" : (label.hasPrefix("×") ? "×" : (label.split(separator: " ").last.map(String.init) ?? "")) }
    private static let formatter: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2; f.usesGroupingSeparator = false; return f }()
    var body: some View {
        VStack(spacing: 10) {
            HStack { Text(title).font(.system(size: 11)); Spacer(); TextField("Значение", value: Binding(get: { value * scale }, set: { value = SettingsRules.number($0 / scale, range, fallback: value) }), formatter: Self.formatter).font(.system(size: 10, design: .monospaced)).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 58).accessibilityLabel(title + " — точное значение"); Text(unit).font(.system(size: 10)).foregroundStyle(.mint).frame(minWidth: 16, alignment: .leading) }
            Slider(value: $value, in: range).controlSize(.small).accessibilityLabel(title)
        }
    }
}
