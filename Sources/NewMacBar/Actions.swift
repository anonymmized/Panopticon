import AppKit

struct QuickLink: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var kind: String
    var destination: String
    var symbol: String { kind == "folder" ? "folder.fill" : "globe" }
    var url: URL? {
        if kind == "folder" { return destination.hasPrefix("/") ? URL(fileURLWithPath: destination).standardizedFileURL : nil }
        guard let url = URL(string: destination), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
}

enum LaunchTarget: Equatable {
    case application(URL)
    case resource(URL)
}

struct ActionRouter {
    static func calendarTarget(kind: String, appPath: String, webURL: String) -> LaunchTarget? {
        switch kind {
        case "app":
            let url = URL(fileURLWithPath: appPath)
            guard !appPath.isEmpty, url.pathExtension.lowercased() == "app", Bundle(url: url)?.bundleIdentifier != nil else { return nil }
            return .application(url)
        case "web":
            guard let url = URL(string: webURL), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
            return .resource(url)
        default:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return nil }
            return .application(url)
        }
    }
    static func open(_ target: LaunchTarget?) {
        guard let target else { showError("Приложение или ссылка недоступны. Проверь настройку в разделе «Связи и действия»."); return }
        switch target {
        case .application(let url): NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in if let error { DispatchQueue.main.async { showError(error.localizedDescription) } } }
        case .resource(let url): if !NSWorkspace.shared.open(url) { showError("Не удалось открыть \(url.lastPathComponent).") }
        }
    }
    static func showError(_ text: String) { let alert = NSAlert(); alert.messageText = "Не получилось открыть"; alert.informativeText = text; alert.runModal() }
}

struct DockProfile: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var pinned: [String]
    var collections: [AppCollection]
    var links: [QuickLink]
    var appearance: ProfileAppearance
}

struct ProfileAppearance: Codable, Equatable {
    var iconSize: Double
    var spacing: Double
    var opacity: Double
    var radius: Double
    var magnification: Double
    var lift: Double
    var bottom: Double
    var theme: String
    var accent: String
    var hover: String
    var launch: String
    var indicator: String
    var widget: String
    var secondaryWidget: String
    var widgetStyle: String
    var widgetWidth: Double
    var widgetOpacity: Double
    var glow: Bool
    var clockFormat: String?
    var clockSeconds: Bool?
    var timerMinutes: Double?
    var labels: Bool?
    var separator: Bool?
    var settingsButton: Bool?
    var showRunning: Bool?
    var autoHide: Bool?
    var reduceMotion: Bool?
    init(_ model: BarModel) {
        iconSize = model.iconSize; spacing = model.iconSpacing; opacity = model.opacity; radius = model.cornerRadius
        magnification = model.magnification; lift = model.hoverLift; bottom = model.bottomOffset
        theme = model.theme; accent = model.widgetAccent; hover = model.hoverStyle; launch = model.launchStyle
        indicator = model.indicatorStyle; widget = model.widget; secondaryWidget = model.secondaryWidget
        widgetStyle = model.widgetStyle; widgetWidth = model.widgetWidth; widgetOpacity = model.widgetOpacity; glow = model.hoverGlow
        clockFormat = model.clockFormat; clockSeconds = model.clockSeconds; timerMinutes = model.timerMinutes
        labels = model.showLabels; separator = model.showSeparator; settingsButton = model.showSettingsButton; showRunning = model.showRunning; autoHide = model.autoHide; reduceMotion = model.reduceMotion
    }
    func apply(to model: BarModel) {
        model.iconSize = iconSize; model.iconSpacing = spacing; model.opacity = opacity; model.cornerRadius = radius
        model.magnification = magnification; model.hoverLift = lift; model.bottomOffset = bottom
        model.theme = theme; model.widgetAccent = accent; model.hoverStyle = hover; model.launchStyle = launch
        model.indicatorStyle = indicator; model.widget = widget; model.secondaryWidget = secondaryWidget
        model.widgetStyle = widgetStyle; model.widgetWidth = widgetWidth; model.widgetOpacity = widgetOpacity; model.hoverGlow = glow
        if let clockFormat { model.clockFormat = clockFormat }; if let clockSeconds { model.clockSeconds = clockSeconds }
        if let timerMinutes { model.timerMinutes = timerMinutes }; if let labels { model.showLabels = labels }
        if let separator { model.showSeparator = separator }; if let settingsButton { model.showSettingsButton = settingsButton }
        if let showRunning { model.showRunning = showRunning }; if let autoHide { model.autoHide = autoHide }; if let reduceMotion { model.reduceMotion = reduceMotion }
    }
}

extension BarModel {
    var launcherShortcutLabel: String { ["controlOptionSpace": "⌃⌥ пробел", "commandShiftSpace": "⌘⇧ пробел", "optionShiftSpace": "⌥⇧ пробел"][launcherShortcutChoice] ?? "⌃⌥ пробел" }
    var calendarTarget: LaunchTarget? { ActionRouter.calendarTarget(kind: calendarDestination, appPath: calendarAppPath, webURL: calendarWebURL) }
    var calendarAppName: String { calendarDestination == "web" ? URL(string: calendarWebURL)?.host ?? "Веб-календарь" : (calendarDestination == "app" ? FileManager.default.displayName(atPath: calendarAppPath).replacingOccurrences(of: ".app", with: "") : "Календарь macOS") }
    var widgetKinds: [String] { var result: [String] = []; for kind in [widget, secondaryWidget] where kind != "none" && !result.contains(kind) { result.append(kind) }; return result }
    func openCalendar() { ActionRouter.open(calendarTarget) }
    @discardableResult func addQuickLink(name: String, kind: String, destination: String) -> Bool {
        let link = QuickLink(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, destination: destination.trimmingCharacters(in: .whitespacesAndNewlines))
        guard ["folder", "web"].contains(kind), !link.name.isEmpty, link.url != nil, !quickLinks.contains(where: { $0.kind == link.kind && $0.destination == link.destination }) else { return false }
        quickLinks.append(link); save(); return true
    }
    @discardableResult func updateQuickLink(_ link: QuickLink) -> Bool {
        var updated = link; updated.name = SettingsRules.label(updated.name)
        guard !updated.name.isEmpty, updated.url != nil, ["web", "folder"].contains(updated.kind),
              !quickLinks.contains(where: { $0.id != link.id && $0.kind == link.kind && $0.destination == link.destination }),
              let i = quickLinks.firstIndex(where: { $0.id == link.id }) else { return false }
        quickLinks[i] = updated; save(); return true
    }
    func moveQuickLink(_ id: String, by offset: Int) {
        guard let i = quickLinks.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, i + offset), quickLinks.count - 1)
        if target != i { quickLinks.swapAt(i, target); save() }
    }
    @discardableResult func renameProfile(_ id: String, to name: String) -> Bool {
        let name = SettingsRules.label(name)
        guard !name.isEmpty, let i = profiles.firstIndex(where: { $0.id == id }),
              !profiles.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return false }
        profiles[i].name = name; save(); return true
    }
    func updateProfile(_ id: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i] = DockProfile(id: id, name: profiles[i].name, pinned: pinned.map(\.id), collections: collections, links: quickLinks, appearance: .init(self)); save()
    }
    var matchingProfileID: String? {
        profiles.first { $0.pinned == pinned.map(\.id) && $0.collections == collections && $0.links == quickLinks && $0.appearance == ProfileAppearance(self) }?.id
    }
    func removeQuickLink(_ id: String) { quickLinks.removeAll { $0.id == id }; save() }
    func saveProfile(name: String) {
        let name = SettingsRules.label(name); guard !name.isEmpty else { return }
        let profile = DockProfile(name: name, pinned: pinned.map(\.id), collections: collections, links: quickLinks, appearance: .init(self))
        if let index = profiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            var replacement = profile; replacement.id = profiles[index].id; profiles[index] = replacement
        } else { profiles.append(profile) }
        save()
    }
    func applyProfile(_ profile: DockProfile) {
        batch {
            pinned = profile.pinned.filter { FileManager.default.fileExists(atPath: $0) && Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier != nil }.map { DockItem(url: URL(fileURLWithPath: $0)) }
            collections = profile.collections; quickLinks = profile.links; profile.appearance.sanitized().apply(to: self)
        }
    }
    func deleteProfile(_ id: String) { profiles.removeAll { $0.id == id }; save() }
    var matchingPreset: String? {
        guard iconSize == 36, iconSpacing == 8, cornerRadius == 20, hoverStyle == "lift" else { return nil }
        if theme == "light" && widgetAccent == "blue" && opacity == 0.22 { return "frost" }
        if theme == "dark" && widgetAccent == "mint" && magnification == 1.4 && hoverGlow { return "aurora" }
        if theme == "dark" && widgetAccent == "violet" && magnification == 1.55 && hoverLift == 10 { return "electric" }
        if theme == "dark" && widgetAccent == "neutral" && magnification == 1.2 && !hoverGlow { return "graphite" }
        return nil
    }
    func applyPreset(_ preset: String) {
        batch {
            iconSize = 36; iconSpacing = 8; magnification = 1.4; hoverLift = 7; hoverStyle = "lift"
            cornerRadius = 20; opacity = 0.1; hoverGlow = true; launchStyle = "bounce"; theme = "dark"
            if preset == "aurora" { widgetAccent = "mint"; widgetOpacity = 0.22 }
            if preset == "electric" { widgetAccent = "violet"; widgetOpacity = 0.4; hoverLift = 10; magnification = 1.55 }
            if preset == "graphite" { widgetAccent = "neutral"; widgetOpacity = 0.16; hoverGlow = false; hoverLift = 3; magnification = 1.2 }
            if preset == "frost" { theme = "light"; widgetAccent = "blue"; widgetOpacity = 0.2; opacity = 0.22; hoverGlow = false }
        }
    }
}
