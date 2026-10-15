import SwiftUI

struct MusicPopoverView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var music: MusicController
    @State private var seeking = false
    @State private var seekPosition = 0.0
    @State private var volumeEditing = false
    @State private var selectedVolume = 50.0
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 15) {
                ZStack { RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [.purple.opacity(0.6), .indigo.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)); if let image = music.artwork { Image(nsImage: image).resizable().scaledToFill() } else { Image(systemName: "music.note").font(.system(size: 25)).foregroundStyle(.white.opacity(0.8)) } }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) { Text(music.sourceName).font(.system(size: 7, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary); Text(music.title).font(.system(size: 14, weight: .semibold)).lineLimit(2); Text(music.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let current = seeking ? seekPosition : music.displayPosition(at: context.date)
                VStack(spacing: 2) {
                    Slider(value: Binding(get: { seeking ? seekPosition : min(current, max(music.duration, 1)) }, set: { seekPosition = $0 }), in: 0...max(music.duration, 1), onEditingChanged: { editing in if editing { seekPosition = music.displayPosition() }; seeking = editing; if !editing { music.seek(seekPosition) } }).disabled(music.duration <= 0).tint(.white.opacity(0.7)).controlSize(.small).accessibilityLabel(L("Позиция воспроизведения"))
                    HStack { Text(time(current)); Spacer(); Text("−" + time(max(0, music.duration - current))) }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 34) { control("backward.fill", L("Предыдущий трек"), "previous track", 18); control(music.playing ? "pause.fill" : "play.fill", music.playing ? L("Пауза") : L("Воспроизвести"), "playpause", 22).frame(width: 46, height: 46).background(.white.opacity(0.07), in: Circle()); control("forward.fill", L("Следующий трек"), "next track", 18) }
            HStack(spacing: 10) { Image(systemName: "speaker.fill").font(.system(size: 10)); Slider(value: Binding(get: { volumeEditing ? selectedVolume : music.volume }, set: { selectedVolume = $0 }), in: 0...100, onEditingChanged: { editing in if editing { selectedVolume = music.volume }; volumeEditing = editing; if !editing { music.setVolume(selectedVolume) } }).disabled(music.activePlayerID == nil || music.permissionDenied).controlSize(.small).accessibilityLabel(L("Громкость плеера")); Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)) }.foregroundStyle(.secondary)
            if music.permissionDenied { Button(L("Разрешить доступ в настройках macOS")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }.font(.system(size: 9)) }
        }.padding(22).frame(width: 350).background(Color(red: 0.085, green: 0.085, blue: 0.11)).preferredColorScheme(.dark).tint(.mint)
    }
    private func control(_ icon: String, _ label: String, _ command: String, _ size: CGFloat) -> some View { Button { music.command(command) } label: { Image(systemName: icon).font(.system(size: size)).frame(width: 32, height: 31) }.buttonStyle(.plain).accessibilityLabel(label) }
    private func time(_ seconds: Double) -> String { let value = max(0, Int(seconds)); return String(format: "%d:%02d", value / 60, value % 60) }
}

struct CollectionPopoverView: View {
    @ObservedObject private var localization = Localization.shared
    let collection: AppCollection
    let model: BarModel
    @State private var query = ""
    private var items: [DockItem] { collection.items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(collection.name).font(.system(size: 14, weight: .semibold)); Spacer(); Text(L("\(collection.items.count) приложений")).font(.system(size: 9)).foregroundStyle(.secondary) }
            if !collection.items.isEmpty { HStack { Button(L("Открыть всю коллекцию")) { collection.items.forEach { model.launch($0) } }.font(.system(size: 10)); Spacer() }; if collection.items.count > 6 { TextField(L("Поиск в коллекции"), text: $query).textFieldStyle(.roundedBorder).font(.system(size: 10)) } }
            if collection.items.isEmpty { Text(L("Добавь приложения в настройках коллекции.")).font(.system(size: 11)).foregroundStyle(.secondary) }
            else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) { ForEach(items) { item in Button { model.launch(item) } label: { VStack(spacing: 7) { Image(nsImage: item.icon).resizable().frame(width: 42, height: 42); Text(item.name).font(.system(size: 9)).lineLimit(2) }.frame(maxWidth: .infinity) }.buttonStyle(.plain) } } } }
        }.padding(20).frame(width: 330, height: 270).background(Color(red: 0.085, green: 0.085, blue: 0.11)).preferredColorScheme(.dark)
    }
}
