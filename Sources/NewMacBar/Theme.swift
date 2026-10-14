import AppKit
import SwiftUI

enum DockTheme: String, Codable, CaseIterable, Identifiable {
    case glass, dark, light, aurora, electric, sunset, graphite, frost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return "Стекло"
        case .dark: return "Тёмная"
        case .light: return "Светлая"
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
    var tint: [Color] {
        switch self {
        case .glass, .dark, .light: return []
        case .aurora: return [Color(red: 0.42, green: 0.25, blue: 0.95), Color(red: 0.05, green: 0.75, blue: 0.7)]
        case .electric: return [Color(red: 0.05, green: 0.45, blue: 1.0), Color(red: 0.95, green: 0.15, blue: 0.75)]
        case .sunset: return [Color(red: 1.0, green: 0.45, blue: 0.2), Color(red: 0.85, green: 0.15, blue: 0.45)]
        case .graphite: return [Color(white: 0.22), Color(white: 0.08)]
        case .frost: return [Color(red: 0.85, green: 0.95, blue: 1.0), Color(red: 0.6, green: 0.8, blue: 1.0)]
        }
    }

    var accent: Color {
        switch self {
        case .glass, .dark, .light: return .accentColor
        case .aurora: return Color(red: 0.35, green: 0.85, blue: 0.75)
        case .electric: return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .sunset: return Color(red: 1.0, green: 0.5, blue: 0.3)
        case .graphite: return Color(white: 0.55)
        case .frost: return Color(red: 0.25, green: 0.55, blue: 0.95)
        }
    }

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
