import AppKit
import SwiftUI

enum DockTheme: String, Codable, CaseIterable, Identifiable {
    case glass, dark, light, aurora, electric, sunset, graphite, frost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return L("Стекло")
        case .dark: return L("Тёмная")
        case .light: return L("Светлая")
        case .aurora: return "Aurora"
        case .electric: return "Electric"
        case .sunset: return "Sunset"
        case .graphite: return "Graphite"
        case .frost: return "Frost"
        }
    }

    /// nil follows the system appearance.
    var appearance: NSAppearance? {
        switch self {
        case .glass: return nil
        case .light, .frost: return NSAppearance(named: .aqua)
        default: return NSAppearance(named: .darkAqua)
        }
    }

    /// Gradient laid over the blur. Empty for plain themes.
    var palette: PanelPalette { PanelPalette.resolve(self, light: isLight) }
    var tint: [Color] { palette.gradient.map { Color(nsColor: $0) } }
    var accent: Color { palette.accent.map { Color(nsColor: $0) } ?? .accentColor }

    /// Swatch used by the theme picker.
    var preview: [Color] {
        switch self {
        case .glass: return [Color(white: 0.75), Color(white: 0.45)]
        case .dark: return [Color(white: 0.25), Color(white: 0.1)]
        case .light: return [Color(white: 0.98), Color(white: 0.85)]
        default: return tint
        }
    }
}

extension DockTheme {
    var isLight: Bool {
        self == .light || self == .frost ||
            (self == .glass && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }
    var nsTint: [NSColor] { tint.map { NSColor($0) } }
}
