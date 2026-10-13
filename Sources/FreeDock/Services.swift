import AppKit
import EventKit

// MARK: - Music

/// Reads and controls Spotify / Apple Music through AppleScript. Only talks to a player that is
/// already running (AppleScript would otherwise launch it) and only while the widget is shown.
final class MusicController: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var playing: Bool
        var position: Double
        var duration: Double
        var fetchedAt = Date()
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var playerID: String?
    @Published private(set) var needsPermission = false

    var source: MusicSource = .auto
    var active = false {
        didSet {
            guard active != oldValue else { return }
            if active {
                start()
            } else {
                stop()
            }
        }
    }

    static let spotify = "com.spotify.client"
    static let music = "com.apple.Music"

    private let queue = DispatchQueue(label: "FreeDock.music")
    private var busy = false
    private var timer: Timer?
    private var artworkURL: String?

    var playerName: String { playerID == Self.spotify ? "Spotify" : "Музыка" }

    /// Position extrapolated between polls so progress moves smoothly.
    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        guard track.playing else { return track.position }
        return min(track.duration, track.position + date.timeIntervalSince(track.fetchedAt))
    }

    private func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func runningPlayer() -> String? {
        let candidates: [String]
        switch source {
        case .auto: candidates = [Self.spotify, Self.music]
        case .spotify: candidates = [Self.spotify]
        case .music: candidates = [Self.music]
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return candidates.first { running.contains($0) }
    }

    func refresh() {
        guard !busy else { return }
        guard let id = runningPlayer() else {
            if playerID != nil || track != nil {
                playerID = nil
                track = nil
                artwork = nil
                artworkURL = nil
            }
            return
        }
        busy = true
        let spotify = id == Self.spotify
        let duration = spotify ? "((duration of current track) / 1000)" : "(duration of current track)"
        let art = spotify ? "(artwork url of current track)" : "\"\""
        let source = """
        tell application id "\(id)"
            if player state is stopped then return "-|||-|||stopped|||0|||0|||"
            return (name of current track) & "|||" & (artist of current track) & "|||" & (player state as string) & "|||" & (player position as string) & "|||" & (\(duration) as string) & "|||" & \(art)
        end tell
        """
        queue.async { [weak self] in
            var error: NSDictionary?
            let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
            let code = error?[NSAppleScript.errorNumber] as? Int
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.playerID = id
                self.needsPermission = code == -1743
                let parts = value?.components(separatedBy: "|||") ?? []
                guard parts.count >= 5, parts[2] != "stopped" else {
                    self.track = nil
                    return
                }
                func number(_ text: String) -> Double { Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                self.track = Track(title: parts[0], artist: parts[1], playing: parts[2] == "playing",
                                   position: number(parts[3]), duration: number(parts[4]))
                self.loadArtwork(parts.count > 5 ? parts[5] : "")
            }
        }
    }

    private func loadArtwork(_ address: String) {
        guard address != artworkURL else { return }
        artworkURL = address
        artwork = nil
        guard let url = URL(string: address), url.scheme == "https" else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let data, data.count < 8_000_000, (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.artworkURL == address else { return }
                self.artwork = image
            }
        }.resume()
    }

    enum Command {
        case playPause, next, previous
        case seek(Double)

        var script: String {
            switch self {
            case .playPause: return "playpause"
            case .next: return "next track"
            case .previous: return "previous track"
            case .seek(let seconds): return "set player position to \(Int(max(0, seconds)))"
            }
        }
    }

    func send(_ command: Command) {
        guard let id = runningPlayer() else {
            openPlayer()
            return
        }
        if case .playPause = command, var track {
            track.position = position(at: Date())
            track.playing.toggle()
            track.fetchedAt = Date()
            self.track = track
        }
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(id)\" to \(command.script)")?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.refresh() }
        }
    }

    func openPlayer() {
        let preferred = source == .music ? [Self.music] : [Self.spotify, Self.music]
        for id in preferred {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}

// MARK: - Focus timer

final class FocusTimer: ObservableObject {
    @Published private(set) var remaining: Double = 25 * 60
    @Published private(set) var running = false

    var minutes: Double = 25 {
        didSet {
            if !running && remaining == oldValue * 60 { remaining = minutes * 60 }
        }
    }
    var onFinish: (() -> Void)?

    private var endDate: Date?
    private var timer: Timer?

    var progress: Double { 1 - remaining / max(1, minutes * 60) }

    var text: String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func toggle() {
        if running {
            remaining = max(0, endDate?.timeIntervalSinceNow ?? remaining)
            stopTimer()
        } else {
            if remaining <= 0 { remaining = minutes * 60 }
            endDate = Date().addingTimeInterval(remaining)
            running = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
            timer?.tolerance = 0.1
        }
    }

    func reset() {
        stopTimer()
        remaining = minutes * 60
    }

    func start(minutes: Double) {
        self.minutes = minutes
        reset()
        toggle()
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining == 0 {
            stopTimer()
            NSSound(named: "Glass")?.play()
            onFinish?()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        running = false
    }
}

// MARK: - Calendar

/// Read-only access to the calendars configured in macOS.
final class CalendarService: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published private(set) var events: [EKEvent] = []

    private let store = EKEventStore()

    init() {
        updateStatus()
    }

    private func updateStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            authorized = status == .fullAccess
        } else {
            authorized = status == .authorized
        }
        denied = status == .denied || status == .restricted
    }

    func requestAccess() {
        let completion: (Bool, Error?) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateStatus()
                self?.load(day: Date())
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }

    func load(day: Date) {
        updateStatus()
        guard authorized else {
            events = []
            return
        }
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}
