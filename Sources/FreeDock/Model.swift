import AppKit
import Combine
import SwiftUI

struct DockItem: Codable, Identifiable, Hashable {
    var id = UUID()
    /// File system path, or an http(s) address for website links.
    var path: String

    var isWeb: Bool { path.hasPrefix("https://") || path.hasPrefix("http://") }

    var url: URL {
        if isWeb, let url = URL(string: path) { return url }
        return URL(fileURLWithPath: path)
    }

    var name: String {
        if isWeb {
            let host = url.host ?? path
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let name = FileManager.default.displayName(atPath: path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    var exists: Bool { isWeb || FileManager.default.fileExists(atPath: path) }

    var isApp: Bool { !isWeb && (path.hasSuffix(".app") || path.hasSuffix(".app/")) }

    /// A plain folder (not a bundle) — opens as a stack like in the Dock.
    var isFolder: Bool {
        guard !isWeb else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue && !NSWorkspace.shared.isFilePackage(atPath: path)
    }
}

struct DockSpace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var items: [DockItem]
    /// macOS desktop number (1-based) this space follows automatically.
    var desktop: Int? = nil
}

enum DockEdge: String, Codable, CaseIterable {
    case bottom, top, left, right

    var title: String {
        switch self {
        case .bottom: return "Снизу"
        case .top: return "Сверху"
        case .left: return "Слева"
        case .right: return "Справа"
        }
    }

    var isVertical: Bool { self == .left || self == .right }
}

enum IndicatorStyle: String, Codable, CaseIterable {
    case dot, line, hidden

    var title: String {
        switch self {
        case .dot: return "Точка"
        case .line: return "Линия"
        case .hidden: return "Нет"
        }
    }
}

enum MusicSource: String, Codable, CaseIterable {
    case auto, spotify, music

    var title: String {
        switch self {
        case .auto: return "Авто"
        case .spotify: return "Spotify"
        case .music: return "Apple Music"
        }
    }
}

struct DockConfig: Codable {
    var spaces: [DockSpace]
    var current = 0
    var visible = true

    // Look
    var edge: DockEdge = .bottom
    var theme: DockTheme = .glass
    var tint: Double = 0.55
    var cornerRadius: Double = 20
    var iconSize: Double = 48
    var iconSpacing: Double = 8
    var magnify = true
    var magnification: Double = 1.4
    var indicator: IndicatorStyle = .dot
    var showLabels = true
    var showTrash = true
    var showRunningApps = true
    var highlightActive = true
    var showBadges = false

    // Behaviour
    var autohide = false
    var followMouse = false
    var scrollToSwitch = true
    var autoSwitchDesktops = true
    var launcherEnabled = true
    var replaceSystemDock = false
    var restoreDockOnQuit = true

    // Widgets
    var showClock = true
    var clock24h = true
    var clockSeconds = false
    var showMusic = false
    var musicSource: MusicSource = .auto
    var showTimer = false
    var timerMinutes: Double = 25

    init(spaces: [DockSpace]) {
        self.spaces = spaces
    }

    // Every key is optional so that config files from older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let d = DockConfig(spaces: [])
        spaces = value(.spaces, d.spaces)
        current = value(.current, d.current)
        visible = value(.visible, d.visible)
        edge = value(.edge, d.edge)
        theme = value(.theme, d.theme)
        tint = value(.tint, d.tint)
        cornerRadius = value(.cornerRadius, d.cornerRadius)
        iconSize = value(.iconSize, d.iconSize)
        iconSpacing = value(.iconSpacing, d.iconSpacing)
        magnify = value(.magnify, d.magnify)
        magnification = value(.magnification, d.magnification)
        indicator = value(.indicator, d.indicator)
        showLabels = value(.showLabels, d.showLabels)
        showTrash = value(.showTrash, d.showTrash)
        showRunningApps = value(.showRunningApps, d.showRunningApps)
        highlightActive = value(.highlightActive, d.highlightActive)
        showBadges = value(.showBadges, d.showBadges)
        autohide = value(.autohide, d.autohide)
        followMouse = value(.followMouse, d.followMouse)
        scrollToSwitch = value(.scrollToSwitch, d.scrollToSwitch)
        autoSwitchDesktops = value(.autoSwitchDesktops, d.autoSwitchDesktops)
        launcherEnabled = value(.launcherEnabled, d.launcherEnabled)
        replaceSystemDock = value(.replaceSystemDock, d.replaceSystemDock)
        restoreDockOnQuit = value(.restoreDockOnQuit, d.restoreDockOnQuit)
        showClock = value(.showClock, d.showClock)
        clock24h = value(.clock24h, d.clock24h)
        clockSeconds = value(.clockSeconds, d.clockSeconds)
        showMusic = value(.showMusic, d.showMusic)
        musicSource = value(.musicSource, d.musicSource)
        showTimer = value(.showTimer, d.showTimer)
        timerMinutes = value(.timerMinutes, d.timerMinutes)
    }

    static var initial: DockConfig {
        func items(_ paths: [String]) -> [DockItem] {
            paths.filter { FileManager.default.fileExists(atPath: $0) }.map { DockItem(path: $0) }
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
        let fromDock = SystemDock.persistentItems().map { DockItem(path: $0.standardizedFileURL.path) }
        let main = fromDock.isEmpty ? items([
            "/System/Library/CoreServices/Finder.app",
            "/Applications/Safari.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/System Settings.app",
            downloads,
        ]) : fromDock
        return DockConfig(spaces: [
            DockSpace(name: "Главное", symbol: "house", items: main),
            DockSpace(name: "Работа", symbol: "briefcase", items: items([
                "/System/Applications/Utilities/Terminal.app",
                "/System/Applications/Mail.app",
                "/System/Applications/Reminders.app",
            ])),
            DockSpace(name: "Отдых", symbol: "gamecontroller", items: items([
                "/System/Applications/Music.app",
                "/System/Applications/TV.app",
                "/System/Applications/Photos.app",
            ])),
        ])
    }
}

final class DockStore: ObservableObject {
    @Published var config: DockConfig {
        didSet {
            save()
            if oldValue.spaces.indices.contains(oldValue.current),
               oldValue.spaces[oldValue.current].id != current.id {
                flash(current.name)
            }
        }
    }
    @Published private(set) var runningApps: [NSRunningApplication] = []
    @Published private(set) var runningPaths: Set<String> = []
    @Published private(set) var frontmostPath: String?
    @Published private(set) var launching: Set<String> = []
    @Published private(set) var badges: [String: String] = [:]
    @Published private(set) var currentDesktop: Int?
    @Published private(set) var desktopCount = 0
    @Published private(set) var toast: String?
    /// Bumped when an asynchronously loaded icon (website favicon) arrives.
    @Published private(set) var iconsVersion = 0
    /// Item being dragged inside the bar.
    @Published var dragging: UUID?

    let music = MusicController()
    let focus = FocusTimer()
    let calendar = CalendarService()

    static let symbols = [
        "house", "briefcase", "gamecontroller", "music.note", "paintbrush", "hammer",
        "book", "globe", "star", "heart", "bolt", "camera", "film", "message",
        "folder", "terminal", "cart", "graduationcap", "chevron.left.forwardslash.chevron.right",
        "flame", "leaf", "airplane", "sportscourt", "theatermasks",
    ]

    static let folderURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var fileURL: URL { folderURL.appendingPathComponent("config.json") }

    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var badgeTimer: Timer?
    private var toastToken = 0
    private var transientIDs: [String: UUID] = [:]

    init() {
        var loaded = DockConfig.initial
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(DockConfig.self, from: data),
           !decoded.spaces.isEmpty {
            loaded = decoded
        }
        loaded.current = min(max(loaded.current, 0), loaded.spaces.count - 1)
        config = loaded

        refreshRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshRunning()
            })
        }
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshBadges()
        }

        // Widgets re-render the bar when their state changes.
        for publisher in [music.objectWillChange, focus.objectWillChange, calendar.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        focus.onFinish = { [weak self] in self?.flash("Фокус-сессия завершена") }
        IconCache.shared.onUpdate = { [weak self] in self?.iconsDidChange() }
        applyWidgetSettings()
    }

    private func save() {
        applyWidgetSettings()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    private func applyWidgetSettings() {
        music.source = config.musicSource
        music.active = config.showMusic && config.visible
        focus.minutes = config.timerMinutes
    }

    func flash(_ text: String) {
        toastToken += 1
        let token = toastToken
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }

    // MARK: Running apps and badges

    static func key(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func refreshRunning() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleURL != nil && $0 != NSRunningApplication.current
        }
        runningApps = apps
        runningPaths = Set(apps.compactMap { $0.bundleURL.map(Self.key) })
        frontmostPath = NSWorkspace.shared.frontmostApplication?.bundleURL.map(Self.key)
        launching.subtract(runningPaths)
    }

    private func refreshBadges() {
        let fresh = config.showBadges ? AX.dockBadges() : [:]
        if fresh != badges { badges = fresh }
    }

    func isRunning(_ item: DockItem) -> Bool { item.isApp && runningPaths.contains(Self.key(item.url)) }

    func isActive(_ item: DockItem) -> Bool { item.isApp && frontmostPath == Self.key(item.url) }

    func isLaunching(_ item: DockItem) -> Bool { launching.contains(Self.key(item.url)) }

    func badge(for item: DockItem) -> String? {
        config.showBadges && item.isApp ? badges[Self.key(item.url)] : nil
    }

    func runningApp(for item: DockItem) -> NSRunningApplication? {
        guard item.isApp else { return nil }
        let key = Self.key(item.url)
        return runningApps.first { $0.bundleURL.map(Self.key) == key }
    }

    /// Running apps that are not pinned in the current space, shown after the pinned ones.
    var unpinnedRunning: [DockItem] {
        guard config.showRunningApps else { return [] }
        let pinned = Set(current.items.filter(\.isApp).map { Self.key($0.url) })
        return runningApps.compactMap { app in
            guard let url = app.bundleURL else { return nil }
            let key = Self.key(url)
            guard !pinned.contains(key) else { return nil }
            let id = transientIDs[key] ?? UUID()
            transientIDs[key] = id
            return DockItem(id: id, path: url.path)
        }
    }

    func isPinned(_ item: DockItem) -> Bool { current.items.contains { $0.id == item.id } }

    func iconsDidChange() { iconsVersion += 1 }

    // MARK: Desktops

    func desktopChanged(_ info: (number: Int, count: Int)?) {
        currentDesktop = info?.number
        desktopCount = info?.count ?? 0
        guard config.autoSwitchDesktops, let number = info?.number,
              let index = config.spaces.firstIndex(where: { $0.desktop == number }) else { return }
        select(index)
    }

    func bind(_ id: UUID, desktop: Int?) {
        guard let index = index(of: id) else { return }
        var updated = config
        if let desktop {
            for i in updated.spaces.indices where updated.spaces[i].desktop == desktop {
                updated.spaces[i].desktop = nil
            }
        }
        updated.spaces[index].desktop = desktop
        config = updated
    }

    // MARK: Spaces

    var current: DockSpace {
        get { config.spaces[config.current] }
        set { config.spaces[config.current] = newValue }
    }

    func index(of id: UUID) -> Int? { config.spaces.firstIndex { $0.id == id } }

    func select(_ index: Int) {
        guard config.spaces.indices.contains(index), index != config.current else { return }
        config.current = index
    }

    func cycle(_ delta: Int) {
        let n = config.spaces.count
        config.current = ((config.current + delta) % n + n) % n
    }

    func addSpace() {
        guard let name = Prompt.text("Новое пространство", value: "Пространство \(config.spaces.count + 1)") else { return }
        appendSpace(DockSpace(name: name, symbol: Self.symbols[config.spaces.count % Self.symbols.count], items: []))
    }

    private func appendSpace(_ space: DockSpace) {
        var updated = config
        updated.spaces.append(space)
        updated.current = updated.spaces.count - 1
        config = updated
    }

    func renameSpace(_ index: Int) {
        guard config.spaces.indices.contains(index),
              let name = Prompt.text("Переименовать пространство", value: config.spaces[index].name) else { return }
        config.spaces[index].name = name
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = index(of: id) else { return }
        config.spaces[index].name = name
    }

    func setSymbol(_ symbol: String, for index: Int) {
        guard config.spaces.indices.contains(index) else { return }
        config.spaces[index].symbol = symbol
    }

    func deleteSpace(_ index: Int) {
        guard config.spaces.count > 1, config.spaces.indices.contains(index),
              Prompt.confirm("Удалить «\(config.spaces[index].name)»?", info: "Сами приложения и файлы не удаляются.")
        else { return }
        var updated = config
        updated.spaces.remove(at: index)
        if updated.current >= index && updated.current > 0 { updated.current -= 1 }
        config = updated
    }

    func moveSpaces(from source: IndexSet, to destination: Int) {
        var updated = config
        let currentID = updated.spaces[updated.current].id
        updated.spaces.move(fromOffsets: source, toOffset: destination)
        updated.current = updated.spaces.firstIndex { $0.id == currentID } ?? 0
        config = updated
    }

    func importSystemDock() {
        let urls = SystemDock.persistentItems()
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        appendSpace(DockSpace(name: "Системный Dock", symbol: "dock.rectangle",
                              items: urls.map { DockItem(path: $0.standardizedFileURL.path) }))
    }

    // MARK: Items

    /// Accepts file URLs and http(s) links.
    func add(urls: [URL], to spaceIndex: Int? = nil, before target: UUID? = nil) {
        let index = spaceIndex ?? config.current
        guard config.spaces.indices.contains(index) else { return }
        var items = config.spaces[index].items
        var position = target.flatMap { id in items.firstIndex { $0.id == id } } ?? items.count
        for url in urls {
            let path: String
            if url.isFileURL {
                path = url.standardizedFileURL.path
            } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                path = url.absoluteString
            } else {
                continue
            }
            guard !items.contains(where: { $0.path == path }) else { continue }
            items.insert(DockItem(path: path), at: position)
            position += 1
        }
        config.spaces[index].items = items
    }

    func addLink() {
        guard var text = Prompt.text("Ссылка на сайт", value: "https://") else { return }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.host != nil else {
            NSSound.beep()
            return
        }
        add(urls: [url])
    }

    func remove(_ id: UUID) {
        current.items.removeAll { $0.id == id }
    }

    func reorder(_ id: UUID, before target: UUID) {
        var items = current.items
        guard let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == target }), from != to else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        current.items = items
    }

    func move(_ id: UUID, by delta: Int) {
        var items = current.items
        guard let from = items.firstIndex(where: { $0.id == id }), items.indices.contains(from + delta) else { return }
        items.swapAt(from, from + delta)
        current.items = items
    }

    func move(_ id: UUID, toSpace index: Int) {
        guard index != config.current, config.spaces.indices.contains(index),
              let item = current.items.first(where: { $0.id == id }) else { return }
        var updated = config
        updated.spaces[updated.current].items.removeAll { $0.id == id }
        if !updated.spaces[index].items.contains(where: { $0.path == item.path }) {
            updated.spaces[index].items.append(item)
        }
        config = updated
    }

    func open(_ item: DockItem) {
        guard item.exists else {
            NSSound.beep()
            return
        }
        if item.isApp, !isRunning(item) {
            let key = Self.key(item.url)
            launching.insert(key)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.launching.remove(key)
            }
        }
        NSWorkspace.shared.open(item.url)
    }

    /// Dropping files on an app icon opens them in that app.
    func open(_ urls: [URL], with item: DockItem) {
        guard item.isApp, !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: item.url, configuration: NSWorkspace.OpenConfiguration())
    }

    func chooseFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Добавить в «\(current.name)»"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    // MARK: Trash

    static let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")

    var trashIsFull: Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.trashURL.path)) ?? []
        return names.contains { !$0.hasPrefix(".") }
    }

    func moveToTrash(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        NSSound(named: "Funk")?.play()
        objectWillChange.send()
    }

    func emptyTrash() {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        objectWillChange.send()
    }

    // MARK: System Dock

    func setReplaceSystemDock(_ replace: Bool) {
        config.replaceSystemDock = replace
        if replace {
            SystemDock.hide()
        } else {
            SystemDock.restore()
        }
    }
}
