import AppKit

struct MusicSnapshot {
    var title: String
    var artist: String
    var playing: Bool
    var position: Double
    var duration: Double
    var volume: Double
    var artworkURL: String?
    var artworkData: Data?
    static func parse(_ descriptor: NSAppleEventDescriptor) -> MusicSnapshot? {
        guard descriptor.numberOfItems >= 7 else { return nil }
        let title = descriptor.atIndex(1)?.stringValue ?? "Музыка"
        let artist = descriptor.atIndex(2)?.stringValue ?? ""
        let duration = SettingsRules.number(descriptor.atIndex(5)?.doubleValue ?? 0, 0...86400, fallback: 0)
        let rawPosition = descriptor.atIndex(4)?.doubleValue ?? 0
        return MusicSnapshot(title: title, artist: artist, playing: descriptor.atIndex(3)?.stringValue == "playing",
                             position: SettingsRules.number(rawPosition, 0...max(duration, 1), fallback: 0), duration: duration,
                             volume: SettingsRules.number(descriptor.atIndex(7)?.doubleValue ?? 50, 0...100, fallback: 50),
                             artworkURL: descriptor.atIndex(6)?.stringValue, artworkData: descriptor.atIndex(6)?.data)
    }
    func displayPosition(at now: Date, sampledAt: Date) -> Double {
        min(duration, max(0, position + (playing ? max(0, now.timeIntervalSince(sampledAt)) : 0)))
    }
}

final class MusicController: ObservableObject {
    @Published var title = "Музыка"
    @Published var artist = "Открой Spotify или Music"
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 50
    @Published var artwork: NSImage?
    @Published var activePlayerID: String?
    @Published var permissionDenied = false
    var onChange: (() -> Void)?
    var preference = "auto" { didSet { if preference != oldValue { generation = UUID(); inFlight = nil; clear(); } } }
    private let queue = DispatchQueue(label: "NewMacBar.music")
    private var generation = UUID()
    private var inFlight: UUID?
    private var artworkTask: URLSessionDataTask?
    private var artworkURL: String?
    private var artworkRetry = Date.distantPast
    private var sampledAt = Date()
    private var retryAfter = Date.distantPast
    deinit { artworkTask?.cancel() }

    var playerID: String? {
        let apps = NSWorkspace.shared.runningApplications
        let candidates = preference == "spotify" ? ["com.spotify.client"] : (preference == "music" ? ["com.apple.Music"] : ["com.spotify.client", "com.apple.Music"])
        return candidates.first { id in apps.contains { $0.bundleIdentifier == id && !$0.isTerminated } }
    }
    var sourceName: String { activePlayerID == "com.spotify.client" ? "SPOTIFY" : (activePlayerID == "com.apple.Music" ? "APPLE MUSIC" : "МУЗЫКА") }
    func displayPosition(at now: Date = Date()) -> Double {
        MusicSnapshot(title: title, artist: artist, playing: playing, position: position, duration: duration, volume: volume).displayPosition(at: now, sampledAt: sampledAt)
    }
    private func clear() {
        artworkTask?.cancel(); artworkTask = nil; artworkURL = nil; artwork = nil
        playing = false; position = 0; duration = 0; activePlayerID = nil; permissionDenied = false
        title = "Музыка"; artist = "Открой Spotify или Music"; retryAfter = .distantPast; onChange?()
    }
    func refresh(force: Bool = false) {
        guard inFlight == nil, force || Date() >= retryAfter else { return }
        guard let id = playerID else { if activePlayerID != nil || playing { clear() }; return }
        let request = UUID(); inFlight = request; let currentGeneration = generation
        let durationExpression = id == "com.spotify.client" ? "((duration of current track) / 1000)" : "(duration of current track)"
        let artExpression = id == "com.spotify.client" ? "artwork url of current track" : "raw data of artwork 1 of current track"
        let source = """
        tell application id "\(id)"
            if player state is stopped then return {"Музыка", "Ничего не играет", "stopped", 0.0, 0.0, "", sound volume}
            set art to ""
            try
                set art to \(artExpression)
            end try
            return {name of current track, artist of current track, player state as string, player position, \(durationExpression), art, sound volume}
        end tell
        """
        queue.async { [weak self] in
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let snapshot = descriptor.flatMap(MusicSnapshot.parse)
            let code = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            DispatchQueue.main.async {
                guard let self, self.generation == currentGeneration, self.inFlight == request else { return }
                self.inFlight = nil; self.activePlayerID = id
                if let snapshot {
                    self.title = snapshot.title; self.artist = snapshot.artist; self.playing = snapshot.playing
                    self.position = snapshot.position; self.duration = snapshot.duration; self.volume = snapshot.volume
                    self.sampledAt = Date(); self.permissionDenied = false; self.retryAfter = .distantPast
                    if id == "com.apple.Music" { self.artworkTask?.cancel(); self.artworkURL = nil; self.artwork = snapshot.artworkData.flatMap { $0.count < 8_000_000 ? NSImage(data: $0) : nil } }
                    else { self.loadArtwork(snapshot.artworkURL ?? "") }
                } else {
                    self.playing = false; self.position = 0; self.duration = 0; self.artwork = nil
                    self.permissionDenied = code == -1743
                    self.title = self.permissionDenied ? "Нет доступа к плееру" : "Плеер пока недоступен"
                    self.artist = self.permissionDenied ? "Разреши Автоматизацию в macOS" : "Открой трек и попробуй снова"
                    self.retryAfter = Date().addingTimeInterval(self.permissionDenied ? 30 : 5)
                }
                self.onChange?()
            }
        }
    }
    private func loadArtwork(_ path: String) {
        if artworkURL == path, artwork != nil || Date() < artworkRetry { return }
        artworkTask?.cancel(); artworkURL = path; artwork = nil
        guard let url = URL(string: path), url.scheme == "https" else { return }
        artworkRetry = Date().addingTimeInterval(30)
        let token = generation
        artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let data, data.count < 8_000_000, let response = response as? HTTPURLResponse, response.statusCode == 200 else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.artworkURL == path else { return }
                self.artwork = NSImage(data: data); self.onChange?()
            }
        }; artworkTask?.resume()
    }
    func seek(_ seconds: Double) {
        let target = SettingsRules.number(seconds, 0...max(0, duration), fallback: 0)
        position = target; sampledAt = Date(); command("set player position to \(target)")
    }
    func setVolume(_ value: Double) { volume = SettingsRules.number(value, 0...100, fallback: 50); command("set sound volume to \(Int(volume))") }
    func command(_ command: String) {
        guard let id = playerID else {
            let preferred = preference == "music" ? "com.apple.Music" : "com.spotify.client"
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferred) ?? (preference == "auto" ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") : nil) { ActionRouter.open(.application(url)) }
            return
        }
        let token = generation
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(id)\" to \(command)")?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { guard let self, self.generation == token else { return }; self.refresh(force: true) }
        }
    }
}
