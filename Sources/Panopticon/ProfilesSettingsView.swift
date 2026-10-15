import SwiftUI
import AppKit

struct ProfilesView: View {
    @ObservedObject var localization = Localization.shared
    @ObservedObject var model: BarModel
    private var panelMotionBinding: Binding<String> {
        Binding(get: { model.motionMode }, set: { model.setMotionMode($0) })
    }
    @State private var profileName = ""
    @State private var message = ""
    @State private var overwritten: DockProfile?
    private func saveCurrentProfile() {
        let name = SettingsRules.label(profileName)
        guard !name.isEmpty else { return }
        if let existing = model.profiles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            let alert = NSAlert(); alert.messageText = L("Обновить профиль «\(existing.name)»?")
            alert.informativeText = L("Сохранённый снимок будет заменён текущей панелью. После обновления доступна отмена.")
            alert.addButton(withTitle: L("Обновить")); alert.addButton(withTitle: L("Отмена"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            overwritten = existing
        }
        model.saveProfile(name: name); profileName = ""; message = L("Профиль сохранён.")
    }
    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 {
                throw ProfileArchive.ArchiveError.tooLarge
            }
            var profile = try ProfileArchive.decode(Data(contentsOf: url))
            let preview = NSAlert()
            preview.messageText = L("Импортировать профиль «\(profile.name)»?")
            preview.informativeText =
                L("\(profile.pinned.count) приложений, \(profile.collections.count) коллекций и \(profile.links.count) ярлыков. Профиль будет добавлен в список. Текущая панель изменится только после нажатия «Применить».")
            preview.addButton(withTitle: L("Добавить профиль"))
            preview.addButton(withTitle: L("Отмена"))
            guard preview.runModal() == .alertFirstButtonReturn else { return }
            let base = profile.name
            var count = 2
            while model.profiles.contains(where: {
                $0.name.localizedCaseInsensitiveCompare(profile.name) == .orderedSame
            }) {
                profile.name = base + " (\(count))"
                count += 1
            }
            model.profiles.append(profile)
            model.save()
            message = L("Профиль импортирован. Нажми «Применить», чтобы включить его.")
        } catch { message = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            DockPreview(model: model)
            Text(L("Готовые стили")).font(.system(size: 14, weight: .semibold))
            HStack(spacing: 12) {
                ForEach(
                    [
                        ("aurora", "Aurora", Color.mint), ("electric", "Electric", .purple),
                        ("graphite", "Graphite", .gray), ("frost", "Frost", .blue),
                    ], id: \.0
                ) { id, name, color in
                    OptionTile(
                        name, selected: model.matchingPreset == id,
                        action: {
                            model.applyPreset(id)
                            message = L("Стиль \(name) применён")
                        }
                    ) {
                        HStack(spacing: 6) {
                            ForEach(0..<3) { i in
                                RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.9 - Double(i) * 0.2))
                                    .frame(width: 24, height: 24).shadow(
                                        color: color.opacity(id == "electric" ? 0.65 : 0.2), radius: 8)
                            }
                        }.padding(10).background(
                            id == "frost" ? .white.opacity(0.4) : .black.opacity(0.2),
                            in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            StudioCard(L("Профили панели")) {
                Text(
                    L("Сохрани приложения, коллекции, ярлыки и оформление вместе. Переключайся между рабочей и личной панелью одним нажатием.")
                ).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                HStack {
                    TextField(L("Название, например «Работа»"), text: $profileName).textFieldStyle(
                        .roundedBorder)
                    Button(L("Сохранить текущую")) {
                        saveCurrentProfile()
                    }.disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.font(.system(size: 11))
                HStack {
                    Button(L("Импортировать профиль…"), action: importProfile).font(.system(size: 11))
                    Spacer()
                    Text(L("Локальный файл JSON")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(model.profiles) { ProfileRow(model: model, profile: $0) }
                if let original = overwritten {
                    Button(L("Отменить обновление профиля")) {
                        guard let index = model.profiles.firstIndex(where: { $0.id == original.id }) else { return }
                        model.profiles[index] = original; model.save(); overwritten = nil
                    }
                }

            }
            StudioCard(L("Движение и нагрузка")) {
                Toggle(L("Подсветка при наведении"), isOn: $model.hoverGlow).font(.system(size: 11))
                Picker(L("Анимации панели"), selection: panelMotionBinding) {
                    ForEach(DockMotionMode.allCases) { Text($0.title).tag($0.rawValue) }
                }.id(localization.code).font(.system(size: 11))
                Text(
                    L("В покое анимации не работают. В режиме «Как в macOS» учитывается системное уменьшение движения. «Полные анимации» включает увеличение и прыжки только для этой панели.")
                ).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
            if !message.isEmpty { Text(localization.status(message)).font(.system(size: 11)).foregroundStyle(.mint) }
        }
    }
}
