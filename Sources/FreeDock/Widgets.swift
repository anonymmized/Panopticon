import AppKit
import EventKit
import SwiftUI

extension View {
    /// Rounded "card" every bar widget sits in.
    func widgetChrome(height: CGFloat, vertical: Bool) -> some View {
        padding(.horizontal, vertical ? 0 : 10)
            .padding(.vertical, vertical ? 8 : 0)
            .frame(minWidth: vertical ? height : nil, minHeight: vertical ? nil : height)
            .background(RoundedRectangle(cornerRadius: min(14, height * 0.3), style: .continuous)
                .fill(Color.primary.opacity(0.08)))
    }
}

struct WidgetsView: View {
    @ObservedObject var store: DockStore

    static func anyEnabled(_ config: DockConfig) -> Bool {
        config.showMusic || config.showTimer || config.showClock
    }

    var body: some View {
        let config = store.config
        stack(config.edge.isVertical, spacing: 8) {
            if config.showMusic { MusicWidget(store: store, music: store.music) }
            if config.showTimer { TimerWidget(store: store, focus: store.focus) }
            if config.showClock { ClockWidget(store: store) }
        }
    }
}

// MARK: - Clock and calendar

struct ClockWidget: View {
    @ObservedObject var store: DockStore
    @State private var showCalendar = false

    var body: some View {
        let config = store.config
        let vertical = config.edge.isVertical

        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 1) {
                Text(Self.time(context.date, h24: config.clock24h, seconds: config.clockSeconds && !vertical))
                    .font(.system(size: vertical ? 13 : 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(Self.date(context.date, short: vertical))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .widgetChrome(height: CGFloat(config.iconSize), vertical: vertical)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            showCalendar.toggle()
        }
        .popover(isPresented: $showCalendar, arrowEdge: config.edge.arrowEdge) {
            CalendarPopover(service: store.calendar)
        }
        .help("Календарь и события")
    }

    static func time(_ date: Date, h24: Bool, seconds: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = h24 ? (seconds ? "HH:mm:ss" : "HH:mm") : (seconds ? "h:mm:ss a" : "h:mm a")
        return formatter.string(from: date)
    }

    static func date(_ date: Date, short: Bool) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(short ? "dMMM" : "EEEdMMM")
        return formatter.string(from: date)
    }
}

struct CalendarPopover: View {
    @ObservedObject var service: CalendarService
    @State private var day = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

            Divider()

            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headline)

            if service.authorized {
                if service.events.isEmpty {
                    Text("Событий нет").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(service.events.enumerated()), id: \.offset) { _, event in
                                EventRow(event: event)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            } else {
                Text(service.denied
                     ? "Доступ к календарям выключен в Системных настройках → Конфиденциальность → Календари."
                     : "Подключи календари macOS, чтобы видеть здесь события. FreeDock их только читает.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !service.denied {
                    Button("Подключить календари") { service.requestAccess() }
                }
            }

            HStack {
                Spacer()
                Button("Открыть Календарь") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                }
                .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { service.load(day: day) }
        .onChange(of: day) { service.load(day: $0) }
    }
}

private struct EventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.calendar?.color ?? .systemBlue))
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Без названия").lineLimit(1)
                Text(event.isAllDay ? "Весь день"
                     : "\(event.startDate.formatted(date: .omitted, time: .shortened)) – "
                        + event.endDate.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Music

struct MusicWidget: View {
    @ObservedObject var store: DockStore
    @ObservedObject var music: MusicController
    @State private var showPlayer = false

    var body: some View {
        let config = store.config
        let size = CGFloat(config.iconSize)
        let vertical = config.edge.isVertical

        stack(vertical, spacing: 8) {
            Artwork(music: music, size: size * 0.72)
                .onTapGesture { togglePlayer() }

            if !vertical {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { togglePlayer() }

                ControlButton(symbol: "backward.fill") { music.send(.previous) }
            }
            ControlButton(symbol: music.track?.playing == true ? "pause.fill" : "play.fill") {
                music.send(.playPause)
            }
            if !vertical {
                ControlButton(symbol: "forward.fill") { music.send(.next) }
            }
        }
        .widgetChrome(height: size, vertical: vertical)
        .popover(isPresented: $showPlayer, arrowEdge: config.edge.arrowEdge) {
            PlayerPopover(music: music)
        }
    }

    private var title: String {
        if let track = music.track { return track.title }
        return music.playerID == nil ? "Музыка" : "Ничего не играет"
    }

    private var subtitle: String {
        if music.needsPermission { return "Нужен доступ: Автоматизация" }
        if let track = music.track { return track.artist }
        return music.playerID == nil ? "Spotify или Apple Music" : music.playerName
    }

    private func togglePlayer() {
        NSApp.activate(ignoringOtherApps: true)
        music.refresh()
        showPlayer.toggle()
    }
}

private struct Artwork: View {
    @ObservedObject var music: MusicController
    let size: CGFloat

    var body: some View {
        Group {
            if let image = music.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let id = music.playerID,
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                Image(nsImage: IconCache.shared.icon(for: url.path)).resizable().padding(size * 0.08)
            } else {
                ZStack {
                    LinearGradient(colors: [Color.pink, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.14), style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size * 1.8, height: size * 1.8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PlayerPopover: View {
    @ObservedObject var music: MusicController
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: 12) {
            Artwork(music: music, size: 240)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

            VStack(spacing: 2) {
                Text(music.track?.title ?? "Ничего не играет").font(.headline)
                Text(music.track?.artist ?? music.playerName).foregroundStyle(.secondary)
            }
            .lineLimit(1)

            if let track = music.track, track.duration > 0 {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let position = scrub ?? music.position(at: context.date)
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { position }, set: { scrub = $0 }),
                               in: 0...track.duration,
                               onEditingChanged: { editing in
                                   if !editing, let value = scrub {
                                       music.send(.seek(value))
                                       scrub = nil
                                   }
                               })
                        HStack {
                            Text(Self.format(position))
                            Spacer()
                            Text("−" + Self.format(track.duration - position))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 30) {
                ControlButton(symbol: "backward.fill", size: 20) { music.send(.previous) }
                ControlButton(symbol: music.track?.playing == true ? "pause.fill" : "play.fill", size: 28) {
                    music.send(.playPause)
                }
                ControlButton(symbol: "forward.fill", size: 20) { music.send(.next) }
            }

            if music.needsPermission {
                Text("Разреши FreeDock управлять плеером: Системные настройки → Конфиденциальность и безопасность → Автоматизация.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(music.playerID == nil ? "Открыть плеер" : "Открыть \(music.playerName)") { music.openPlayer() }
                .buttonStyle(.link)
        }
        .padding(18)
        .frame(width: 280)
    }

    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Focus timer

struct TimerWidget: View {
    @ObservedObject var store: DockStore
    @ObservedObject var focus: FocusTimer

    var body: some View {
        let config = store.config
        let size = CGFloat(config.iconSize)
        let vertical = config.edge.isVertical
        let ring = size * 0.62

        stack(vertical, spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: focus.progress)
                    .stroke(config.theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: focus.progress)
                Image(systemName: focus.running ? "pause.fill" : "play.fill")
                    .font(.system(size: ring * 0.3, weight: .bold))
            }
            .frame(width: ring, height: ring)

            if !vertical {
                Text(focus.text)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .widgetChrome(height: size, vertical: vertical)
        .contentShape(Rectangle())
        .onTapGesture { focus.toggle() }
        .overlay(RightClickMenu { store.timerMenu() })
        .help("Таймер фокуса \(focus.text) — клик: старт/пауза, правый клик: длительность")
    }
}
