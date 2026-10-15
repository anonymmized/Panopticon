import Foundation

/// Reads the other branch's on-disk schema without sharing its executable/model types.
struct FreeDockImport: Decodable {
    struct Item: Decodable { var path: String }
    struct Space: Decodable { var name: String; var symbol: String?; var items: [Item]; var desktop: Int? }
    var spaces: [Space]
    var current: Int?
    var theme: String?
    var edge: String?
    var iconSize: Double?
    var iconSpacing: Double?
    var magnification: Double?
    var tint: Double?
    var cornerRadius: Double?
    var showClock: Bool?
    var showMusic: Bool?
    var showTimer: Bool?
    var clock24h: Bool?
    var clockSeconds: Bool?
    var timerMinutes: Double?
    var musicSource: String?

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 5_000_000 else { throw ImportError.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard !value.spaces.isEmpty, value.spaces.count <= 30,
              value.spaces.allSatisfy({ $0.items.count <= 500 }) else { throw ImportError.invalidSpaces }
        return value
    }
    func convertedSpaces() -> [BarSpace] {
        spaces.map { source in
            var result = BarSpace(name: SettingsRules.label(source.name), symbol: source.symbol ?? "house")
            if result.name.isEmpty { result.name = L("Пространство FreeDock") }
            result.desktop = source.desktop.flatMap { (1...30).contains($0) ? $0 : nil }
            var paths = Set<String>()
            for item in source.items where paths.insert(item.path).inserted {
                if let url = URL(string: item.path), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                    result.links.append(QuickLink(name: url.host ?? L("Сайт"), kind: "web", destination: item.path))
                } else if item.path.hasPrefix("/") {
                    let url = URL(fileURLWithPath: item.path).standardizedFileURL
                    if url.pathExtension.lowercased() == "app" { result.paths.append(url.path) }
                    else {
                        let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                        result.links.append(QuickLink(name: url.lastPathComponent, kind: directory ? "folder" : "file", destination: url.path))
                    }
                }
            }
            return result
        }
    }
    enum ImportError: LocalizedError {
        case tooLarge, invalidSpaces, capacity
        var errorDescription: String? {
            switch self {
            case .tooLarge: return L("Размер файла должен быть меньше 5 МБ.")
            case .invalidSpaces: return L("В файле должен быть список из 1–30 пространств, до 500 элементов в каждом.")
            case .capacity: return L("На панели может быть не более 30 пространств. Удали лишние перед импортом.")
            }
        }
    }
}

extension BarModel {
    func importFreeDock(_ data: Data, appearance: Bool) throws {
        let source = try FreeDockImport.decode(data)
        let additions = source.convertedSpaces()
        guard spaces.count + additions.count <= 30 else { throw FreeDockImport.ImportError.capacity }
        batch {
            snapshotSpace()
            spaces += additions
            if appearance {
                theme = SettingsRules.choice(source.theme ?? theme, DockTheme.allCases.map(\.rawValue), fallback: theme)
                edge = SettingsRules.choice(source.edge ?? edge, DockEdge.allCases.map(\.rawValue), fallback: edge)
                iconSize = SettingsRules.number(source.iconSize ?? iconSize, 28...60, fallback: iconSize)
                iconSpacing = SettingsRules.number(source.iconSpacing ?? iconSpacing, 4...24, fallback: iconSpacing)
                magnification = SettingsRules.number(source.magnification ?? magnification, 1...1.8, fallback: magnification)
                cornerRadius = SettingsRules.number(source.cornerRadius ?? cornerRadius, 8...30, fallback: cornerRadius)
                clockFormat = source.clock24h == false ? "12h" : "24h"
                clockSeconds = source.clockSeconds ?? clockSeconds
                timerMinutes = SettingsRules.number(source.timerMinutes ?? timerMinutes, 5...90, fallback: timerMinutes)
                playerPreference = SettingsRules.choice(source.musicSource ?? playerPreference, ["auto", "music", "spotify"], fallback: playerPreference)
                let widgets = [("clock", source.showClock), ("music", source.showMusic), ("timer", source.showTimer)].filter { $0.1 == true }.map(\.0)
                widget = widgets.first ?? "none"; secondaryWidget = widgets.dropFirst().first ?? "none"
            }
            let index = min(max(source.current ?? 0, 0), additions.count - 1)
            selectSpace(additions[index].id)
        }
    }
}
