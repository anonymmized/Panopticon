import AppKit
import Combine

struct DockItem: Identifiable, Equatable {
    let url: URL
    let id: String
    let bundleID: String?
    let name: String
    let icon: NSImage
    init(url: URL) {
        self.url = url; id = url.standardizedFileURL.path; bundleID = Bundle(url: url)?.bundleIdentifier
        name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
    static func == (lhs: DockItem, rhs: DockItem) -> Bool { lhs.id == rhs.id }
}

final class BarModel: ObservableObject {
    static let shared = BarModel()
    private let defaults: UserDefaults
    @Published var pinned: [DockItem] = []
    @Published var running: [NSRunningApplication] = []
    @Published var iconSize: Double { didSet { save() } }
    @Published var magnification: Double { didSet { save() } }
    @Published var bottomOffset: Double { didSet { save() } }
    @Published var opacity: Double { didSet { save() } }
    @Published var showRunning: Bool { didSet { save() } }
    @Published var autoHide: Bool { didSet { save() } }
    @Published var widget: String { didSet { if secondaryWidget == widget && widget != "none" { batch { secondaryWidget = "none" } } else { save() } } }
    @Published var theme: String { didSet { save() } }
    @Published var screenIndex: Int { didSet { save() } }
    @Published var iconSpacing: Double { didSet { save() } }
    @Published var cornerRadius: Double { didSet { save() } }
    @Published var hoverLift: Double { didSet { save() } }
    @Published var widgetWidth: Double { didSet { save() } }
    @Published var widgetOpacity: Double { didSet { save() } }
    @Published var timerMinutes: Double { didSet { save() } }
    @Published var widgetAccent: String { didSet { save() } }
    @Published var widgetStyle: String { didSet { save() } }
    @Published var hoverStyle: String { didSet { save() } }
    @Published var launchStyle: String { didSet { save() } }
    @Published var indicatorStyle: String { didSet { save() } }
    @Published var playerPreference: String { didSet { save() } }
    @Published var clockFormat: String { didSet { save() } }
    @Published var clockSeconds: Bool { didSet { save() } }
    @Published var replaceDock: Bool { didSet { save() } }
    @Published var showLabels: Bool { didSet { save() } }
    @Published var showSettingsButton: Bool { didSet { save() } }
    @Published var showSeparator: Bool { didSet { save() } }
    @Published var collections: [AppCollection] = []
    @Published var calendarDestination: String { didSet { save() } }
    @Published var calendarAppPath: String { didSet { save() } }
    @Published var calendarWebURL: String { didSet { save() } }
    @Published var clockAction: String { didSet { save() } }
    @Published var secondaryWidget: String { didSet { if secondaryWidget == widget { secondaryWidget = "none" }; save() } }
    @Published var calendarEventsEnabled: Bool { didSet { save() } }
    @Published var launcherShortcutChoice: String { didSet { save() } }
    @Published var launcherShortcutAvailable = false
    @Published var launcherEnabled: Bool { didSet { save() } }
    @Published var hoverGlow: Bool { didSet { save() } }
    @Published var reduceMotion: Bool { didSet { save() } }
    @Published var quickLinks: [QuickLink] = []
    @Published var profiles: [DockProfile] = []
    @Published var selectedCalendarIDs: [String] = []
    @Published private(set) var items: [DockItem] = []
    @Published var spaces: [BarSpace] = []
    @Published var selectedSpaceID = ""
    @Published var edge: String { didSet { save() } }
    @Published var showSpaces: Bool { didSet { save() } }
    @Published var showTrash: Bool { didSet { save() } }
    @Published var showBadges: Bool { didSet { save() } }
    @Published var autoSwitchDesktops: Bool { didSet { save() } }
    @Published var scrollToSwitch: Bool { didSet { save() } }
    @Published var followMouse: Bool { didSet { save() } }
    @Published var barVisible: Bool { didSet { save() } }
    @Published var badges: [String: String] = [:]
    @Published var currentDesktop: Int?
    var activeBundleID: String?
    private var batchDepth = 0
    @Published private(set) var recentAppPaths: [String] = []
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, observe: Bool = true) {
        self.defaults = defaults
        edge = SettingsRules.choice(defaults.string(forKey: "edge") ?? "bottom", DockEdge.allCases.map(\.rawValue), fallback: "bottom")
        showSpaces = defaults.object(forKey: "showSpaces") as? Bool ?? true
        showTrash = defaults.object(forKey: "showTrash") as? Bool ?? true
        showBadges = defaults.bool(forKey: "showBadges")
        autoSwitchDesktops = defaults.object(forKey: "autoSwitchDesktops") as? Bool ?? true
        scrollToSwitch = defaults.object(forKey: "scrollToSwitch") as? Bool ?? true
        followMouse = defaults.bool(forKey: "followMouse")
        barVisible = defaults.object(forKey: "barVisible") as? Bool ?? true
        iconSize = defaults.object(forKey: "iconSize") as? Double ?? 36
        magnification = defaults.object(forKey: "magnification") as? Double ?? 1.35
        bottomOffset = defaults.object(forKey: "bottomOffset") as? Double ?? 10
        opacity = defaults.object(forKey: "opacity") as? Double ?? 0.08
        showRunning = defaults.object(forKey: "showRunning") as? Bool ?? true
        autoHide = defaults.bool(forKey: "autoHide")
        widget = defaults.string(forKey: "widget") ?? "clock"
        theme = defaults.string(forKey: "theme") ?? "dark"
        screenIndex = defaults.integer(forKey: "screenIndex")
        iconSpacing = defaults.object(forKey: "iconSpacing") as? Double ?? 8
        cornerRadius = defaults.object(forKey: "cornerRadius") as? Double ?? 20
        hoverLift = defaults.object(forKey: "hoverLift") as? Double ?? 7
        widgetWidth = defaults.object(forKey: "widgetWidth") as? Double ?? 158
        widgetOpacity = defaults.object(forKey: "widgetOpacity") as? Double ?? 0.28
        timerMinutes = defaults.object(forKey: "timerMinutes") as? Double ?? 25
        widgetAccent = defaults.string(forKey: "widgetAccent") ?? "violet"
        widgetStyle = defaults.string(forKey: "widgetStyle") ?? "wide"
        hoverStyle = defaults.string(forKey: "hoverStyle") ?? "lift"
        launchStyle = defaults.string(forKey: "launchStyle") ?? "bounce"
        indicatorStyle = defaults.string(forKey: "indicatorStyle") ?? "dot"
        playerPreference = defaults.string(forKey: "playerPreference") ?? "auto"
        clockFormat = defaults.string(forKey: "clockFormat") ?? "24h"
        clockSeconds = defaults.object(forKey: "clockSeconds") as? Bool ?? false
        replaceDock = defaults.object(forKey: "replaceDock") as? Bool ?? false
        showLabels = defaults.object(forKey: "showLabels") as? Bool ?? true
        showSettingsButton = defaults.object(forKey: "showSettingsButton") as? Bool ?? false
        showSeparator = defaults.object(forKey: "showSeparator") as? Bool ?? true
        calendarDestination = defaults.string(forKey: "calendarDestination") ?? "system"
        calendarAppPath = defaults.string(forKey: "calendarAppPath") ?? ""
        calendarWebURL = defaults.string(forKey: "calendarWebURL") ?? "https://calendar.google.com"
        clockAction = defaults.string(forKey: "clockAction") ?? "open"
        secondaryWidget = defaults.string(forKey: "secondaryWidget") ?? "none"
        calendarEventsEnabled = defaults.object(forKey: "calendarEventsEnabled") as? Bool ?? false
        launcherShortcutChoice = defaults.string(forKey: "launcherShortcutChoice") ?? "controlOptionSpace"
        launcherEnabled = defaults.object(forKey: "launcherEnabled") as? Bool ?? true
        hoverGlow = defaults.object(forKey: "hoverGlow") as? Bool ?? true
        reduceMotion = defaults.object(forKey: "reduceMotion") as? Bool ?? false
        if let data = defaults.data(forKey: "quickLinks"), let stored = try? JSONDecoder().decode([QuickLink].self, from: data) { quickLinks = stored }
        if let data = defaults.data(forKey: "profiles"), let stored = try? JSONDecoder().decode([DockProfile].self, from: data) { profiles = stored }
        selectedCalendarIDs = defaults.stringArray(forKey: "selectedCalendarIDs") ?? []
        if let data = defaults.data(forKey: "collections"), let stored = try? JSONDecoder().decode([AppCollection].self, from: data) { collections = stored }
        if let paths = defaults.array(forKey: "pinned") as? [String] {
            pinned = paths.map { DockItem(url: URL(fileURLWithPath: $0)) }.filter { FileManager.default.fileExists(atPath: $0.id) }
        } else {
            pinned = Self.systemDockItems()
        }
        if let data = defaults.data(forKey: "spaces"), let saved = try? JSONDecoder().decode([BarSpace].self, from: data), !saved.isEmpty {
            var ids = Set<String>()
            spaces = saved.filter { ids.insert($0.id).inserted }.prefix(30).map { space in
                var space = space; space.name = SettingsRules.label(space.name)
                if space.name.isEmpty { space.name = "Пространство" }
                return space
            }
            selectedSpaceID = defaults.string(forKey: "selectedSpaceID") ?? spaces[0].id
            if !spaces.contains(where: { $0.id == selectedSpaceID }) { selectedSpaceID = spaces[0].id }
            if let current = spaces.first(where: { $0.id == selectedSpaceID }) {
                pinned = current.paths.map { DockItem(url: URL(fileURLWithPath: $0)) }.filter { $0.bundleID != nil && FileManager.default.fileExists(atPath: $0.id) }
                quickLinks = current.links; collections = current.collections
            }
        } else {
            let primary = BarSpace(name: "Главное", paths: pinned.map(\.id), links: quickLinks, collections: collections)
            spaces = [primary, BarSpace(name: "Работа", symbol: "briefcase"), BarSpace(name: "Отдых", symbol: "gamecontroller")]
            selectedSpaceID = primary.id
        }
        recentAppPaths = defaults.stringArray(forKey: "recentAppPaths") ?? []
        batch {
            ProfileAppearance(self).sanitized().apply(to: self)
            timerMinutes = SettingsRules.number(timerMinutes, 5...90, fallback: 25)
            screenIndex = max(0, screenIndex)
            clockFormat = SettingsRules.choice(clockFormat, ["12h", "24h"], fallback: "24h")
            playerPreference = SettingsRules.choice(playerPreference, ["auto", "spotify", "music"], fallback: "auto")
            clockAction = SettingsRules.choice(clockAction, ["open", "agenda"], fallback: "open")
            calendarDestination = SettingsRules.choice(calendarDestination, ["system", "app", "web"], fallback: "system")
            launcherShortcutChoice = SettingsRules.choice(launcherShortcutChoice, ["controlOptionSpace", "commandShiftSpace", "optionShiftSpace"], fallback: "controlOptionSpace")
        }
        if observe {
            let nc = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
                observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshRunning() })
            }
            refreshRunning()
        } else { rebuildItems() }
    }
    static func systemDockItems() -> [DockItem] {
        let dock = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")
        let tiles = dock?["persistent-apps"] as? [[String: Any]] ?? []
        var result: [DockItem] = []
        for tile in tiles {
            guard let data = tile["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any], let path = file["_CFURLString"] as? String, let url = URL(string: path), url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { continue }
            let item = DockItem(url: url)
            guard item.bundleID != nil, url.pathExtension.lowercased() == "app" else { continue }
            if !result.contains(where: { $0.id == item.id }) { result.append(item) }
        }
        if result.isEmpty {
            result = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/Messages.app", "/System/Applications/System Settings.app"].filter { FileManager.default.fileExists(atPath: $0) }.map { DockItem(url: URL(fileURLWithPath: $0)) }
        }
        return result
    }
    private func rebuildItems() {
        var list = pinned
        var paths = Set(pinned.map(\.id)); var bundleIDs = Set(pinned.compactMap(\.bundleID))
        if showRunning {
            for app in running {
                guard let url = app.bundleURL, app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      !paths.contains(url.standardizedFileURL.path), app.bundleIdentifier.map({ !bundleIDs.contains($0) }) ?? true else { continue }
                let item = DockItem(url: url); list.append(item); paths.insert(item.id)
                if let id = item.bundleID { bundleIDs.insert(id) }
            }
        }
        if list != items { items = list }
        activeBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    func batch(_ body: () -> Void) {
        batchDepth += 1; body(); batchDepth -= 1
        if batchDepth == 0 { save() }
    }
    deinit { for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    func refreshRunning() {
        running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        rebuildItems(); onChange?()
    }
    func isRunning(_ item: DockItem) -> Bool { running.contains { $0.bundleIdentifier == item.bundleID } }
    func add(_ url: URL, at index: Int? = nil) {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url), bundle.bundleIdentifier != nil else { return }
        let item = DockItem(url: url)
        guard !pinned.contains(where: { $0.id == item.id || ($0.bundleID != nil && $0.bundleID == item.bundleID) }) else { return }
        pinned.insert(item, at: min(max(index ?? pinned.count, 0), pinned.count))
        save()
    }
    func remove(_ item: DockItem) { pinned.removeAll { $0.id == item.id }; save() }
    // Destination is an insertion boundary in the original list.
    func move(_ id: String, to boundary: Int) {
        guard let source = pinned.firstIndex(where: { $0.id == id }) else { return }
        let item = pinned.remove(at: source)
        let target = boundary > source ? boundary - 1 : boundary
        pinned.insert(item, at: min(max(target, 0), pinned.count))
        save()
    }
    func updateCollection(_ collection: AppCollection) {
        var collection = collection; collection.name = SettingsRules.label(collection.name)
        guard !collection.name.isEmpty else { return }
        var seen = Set<String>()
        collection.paths = collection.paths.filter { seen.insert($0).inserted }
        if let index = collections.firstIndex(where: { $0.id == collection.id }) { collections[index] = collection }
        else { collections.append(collection) }
        save()
    }
    func removeCollection(_ id: String) { collections.removeAll { $0.id == id }; save() }
    func importDock() { pinned = Self.systemDockItems(); save() }
    func save() {
        guard batchDepth == 0 else { return }
        snapshotSpace()
        if let data = try? JSONEncoder().encode(spaces) { defaults.set(data, forKey: "spaces") }
        defaults.set(selectedSpaceID, forKey: "selectedSpaceID")
        defaults.set(edge, forKey: "edge"); defaults.set(showSpaces, forKey: "showSpaces")
        defaults.set(showTrash, forKey: "showTrash"); defaults.set(showBadges, forKey: "showBadges")
        defaults.set(autoSwitchDesktops, forKey: "autoSwitchDesktops")
        defaults.set(scrollToSwitch, forKey: "scrollToSwitch"); defaults.set(followMouse, forKey: "followMouse")
        defaults.set(barVisible, forKey: "barVisible")
        rebuildItems()
        defaults.set(calendarDestination, forKey: "calendarDestination")
        defaults.set(calendarAppPath, forKey: "calendarAppPath")
        defaults.set(calendarWebURL, forKey: "calendarWebURL")
        defaults.set(clockAction, forKey: "clockAction")
        defaults.set(secondaryWidget, forKey: "secondaryWidget")
        defaults.set(calendarEventsEnabled, forKey: "calendarEventsEnabled")
        defaults.set(launcherShortcutChoice, forKey: "launcherShortcutChoice")
        defaults.set(launcherEnabled, forKey: "launcherEnabled")
        defaults.set(hoverGlow, forKey: "hoverGlow")
        defaults.set(reduceMotion, forKey: "reduceMotion")
        if let data = try? JSONEncoder().encode(quickLinks) { defaults.set(data, forKey: "quickLinks") }
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "profiles") }
        defaults.set(selectedCalendarIDs, forKey: "selectedCalendarIDs")

        defaults.set(pinned.map(\.id), forKey: "pinned")
        defaults.set(iconSpacing, forKey: "iconSpacing")
        defaults.set(cornerRadius, forKey: "cornerRadius")
        defaults.set(hoverLift, forKey: "hoverLift")
        defaults.set(widgetWidth, forKey: "widgetWidth")
        defaults.set(widgetOpacity, forKey: "widgetOpacity")
        defaults.set(timerMinutes, forKey: "timerMinutes")
        defaults.set(widgetAccent, forKey: "widgetAccent")
        defaults.set(widgetStyle, forKey: "widgetStyle")
        defaults.set(hoverStyle, forKey: "hoverStyle")
        defaults.set(launchStyle, forKey: "launchStyle")
        defaults.set(indicatorStyle, forKey: "indicatorStyle")
        defaults.set(playerPreference, forKey: "playerPreference")
        defaults.set(clockFormat, forKey: "clockFormat")
        defaults.set(clockSeconds, forKey: "clockSeconds")
        defaults.set(replaceDock, forKey: "replaceDock")
        defaults.set(showLabels, forKey: "showLabels")
        defaults.set(showSettingsButton, forKey: "showSettingsButton")
        defaults.set(showSeparator, forKey: "showSeparator")
        if let data = try? JSONEncoder().encode(collections) { defaults.set(data, forKey: "collections") }
        for (key, value) in ["iconSize": iconSize, "magnification": magnification, "bottomOffset": bottomOffset, "opacity": opacity] { defaults.set(value, forKey: key) }
        defaults.set(showRunning, forKey: "showRunning"); defaults.set(autoHide, forKey: "autoHide")
        defaults.set(widget, forKey: "widget"); defaults.set(theme, forKey: "theme"); defaults.set(screenIndex, forKey: "screenIndex")
        onChange?()
    }
    func launch(_ item: DockItem) {
        recentAppPaths.removeAll { $0 == item.id }; recentAppPaths.insert(item.id, at: 0)
        recentAppPaths = Array(recentAppPaths.prefix(12)); defaults.set(recentAppPaths, forKey: "recentAppPaths")
        if let app = running.first(where: { $0.bundleIdentifier == item.bundleID }) { if app.activate(options: [.activateAllWindows]) { return } }
        NSWorkspace.shared.openApplication(at: item.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { DispatchQueue.main.async { let alert = NSAlert(error: error); alert.runModal() } }
        }
    }
}
