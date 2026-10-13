import Foundation

/// One set of limits for saved preferences, imported profiles and UI controls.
enum SettingsRules {
    static func number(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
    static func choice(_ value: String, _ choices: [String], fallback: String) -> String {
        choices.contains(value) ? value : fallback
    }
    static func label(_ value: String) -> String { String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
}

extension ProfileAppearance {
    func sanitized() -> ProfileAppearance {
        var v = self
        v.iconSize = SettingsRules.number(v.iconSize, 28...60, fallback: 36)
        v.spacing = SettingsRules.number(v.spacing, 4...24, fallback: 8)
        v.opacity = SettingsRules.number(v.opacity, 0...0.65, fallback: 0.1)
        v.radius = SettingsRules.number(v.radius, 8...30, fallback: 20)
        v.magnification = SettingsRules.number(v.magnification, 1...1.8, fallback: 1.35)
        v.lift = SettingsRules.number(v.lift, 0...16, fallback: 7)
        v.bottom = SettingsRules.number(v.bottom, 0...160, fallback: 4)
        v.widgetWidth = SettingsRules.number(v.widgetWidth, 130...250, fallback: 158)
        v.widgetOpacity = SettingsRules.number(v.widgetOpacity, 0.08...0.7, fallback: 0.28)
        if let timerMinutes = v.timerMinutes { v.timerMinutes = SettingsRules.number(timerMinutes, 5...90, fallback: 25) }
        if let clockFormat = v.clockFormat { v.clockFormat = SettingsRules.choice(clockFormat, ["12h", "24h"], fallback: "24h") }
        v.theme = SettingsRules.choice(v.theme, ["dark", "light"], fallback: "dark")
        v.accent = SettingsRules.choice(v.accent, ["violet", "blue", "cyan", "mint", "orange", "rose", "neutral"], fallback: "violet")
        v.hover = SettingsRules.choice(v.hover, ["none", "lift", "scale"], fallback: "lift")
        v.launch = SettingsRules.choice(v.launch, ["none", "bounce", "pulse"], fallback: "bounce")
        v.indicator = SettingsRules.choice(v.indicator, ["none", "dot", "dash"], fallback: "dot")
        v.widget = SettingsRules.choice(v.widget, ["none", "clock", "calendar", "music", "timer"], fallback: "clock")
        v.secondaryWidget = SettingsRules.choice(v.secondaryWidget, ["none", "clock", "calendar", "music", "timer"], fallback: "none")
        if v.secondaryWidget == v.widget { v.secondaryWidget = "none" }
        v.widgetStyle = SettingsRules.choice(v.widgetStyle, ["compact", "wide"], fallback: "wide")
        return v
    }
}

struct ProfileArchive: Codable {
    let version: Int
    var profile: DockProfile
    init(profile: DockProfile) { version = 1; self.profile = profile }
    func data() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return try encoder.encode(self) }
    static func decode(_ data: Data) throws -> DockProfile {
        guard data.count <= 1_000_000 else { throw ArchiveError.tooLarge }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.version == 1 else { throw ArchiveError.version }
        var p = archive.profile
        p.id = UUID().uuidString; p.name = SettingsRules.label(p.name)
        guard !p.name.isEmpty else { throw ArchiveError.name }
        var paths = Set<String>()
        p.pinned = Array(p.pinned.filter { $0.hasPrefix("/") && $0.lowercased().hasSuffix(".app") && paths.insert($0).inserted }.prefix(200))
        p.collections = p.collections.prefix(50).compactMap { collection in
            var c = collection; c.id = UUID().uuidString; c.name = SettingsRules.label(c.name)
            guard !c.name.isEmpty else { return nil }
            c.paths = Array(c.paths.filter { $0.hasPrefix("/") && $0.lowercased().hasSuffix(".app") }.prefix(200)); return c
        }
        p.links = p.links.prefix(100).compactMap { link in
            var l = link; l.id = UUID().uuidString; l.name = SettingsRules.label(l.name)
            guard !l.name.isEmpty, ["web", "folder"].contains(l.kind), l.url != nil else { return nil }; return l
        }
        p.appearance = p.appearance.sanitized()
        return p
    }
    enum ArchiveError: LocalizedError {
        case tooLarge, version, name
        var errorDescription: String? { switch self { case .tooLarge: return "Файл профиля слишком большой."; case .version: return "Эта версия файла профиля не поддерживается."; case .name: return "У профиля нет названия." } }
    }
}
