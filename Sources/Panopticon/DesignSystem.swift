import AppKit
import SwiftUI

/// Semantic implementation tokens. Gemini can replace these values without
/// rewriting service logic or individual screens.
enum Studio {
    static let gap: CGFloat = 16
    static let inset: CGFloat = 20
    static let radius: CGFloat = 16
    static let controlHeight: CGFloat = 32
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let secondarySurface = Color(nsColor: .underPageBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let accent = Color.accentColor
    static let title = Font.system(size: 20, weight: .semibold)
    static let heading = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

struct SurfaceStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(Studio.surface.opacity(opaque ? 1 : 0.94))
            .clipShape(RoundedRectangle(cornerRadius: Studio.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Studio.radius).strokeBorder(
                    Studio.border, lineWidth: contrast == .increased ? 2 : 0.5))
    }
}

struct PopoverSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.font(Studio.body).padding(Studio.inset).background(Studio.canvas).tint(Studio.accent)
    }
}

struct EmptyState: View {
    @ObservedObject var localization = Localization.shared
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.secondary).accessibilityHidden(
                true)
            Text(title).font(Studio.heading)
            Text(detail).font(Studio.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.vertical, 24).accessibilityElement(children: .combine)
    }
}

struct ComponentGallery: View {
    @ObservedObject var localization = Localization.shared
    var body: some View {
        VStack(alignment: .leading, spacing: Studio.gap) {
            StudioCard(L("Типографика и управление")) {
                Text(L("Заголовок")).font(Studio.title)
                Text(L("Основной текст и пояснение")).font(Studio.body)
                HStack {
                    Button(L("Основное действие")) {}.buttonStyle(.borderedProminent)
                    Button(L("Дополнительное")) {}
                    Button(L("Недоступно")) {}.disabled(true)
                }
                Label(L("Действие выполнено"), systemImage: "checkmark.circle").foregroundStyle(.green)
                Label(L("Нужно подключение"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            StudioCard(L("Пустое состояние")) {
                EmptyState(
                    symbol: "square.grid.2x2", title: L("Здесь появятся элементы"),
                    detail: L("Добавь приложение, папку или сайт."))
            }
        }
    }
}

/// Only presentation preferences live here. Domain data remains in BarModel.
final class UIStateStore: ObservableObject {
    static let shared = UIStateStore()
    private let defaults: UserDefaults
    @Published var section: String { didSet { defaults.set(section, forKey: "ui.settingsSection") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "ui.appearance") } }
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: "ui.onboardingCompleted") }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        section = SettingsRules.choice(defaults.string(forKey: "ui.settingsSection") ?? "appearance",
            ["appearance", "spaces", "apps", "collections", "widgets", "connections", "profiles", "behavior", "shortcuts", "system", "about"], fallback: "appearance")
        appearance = SettingsRules.choice(defaults.string(forKey: "ui.appearance") ?? "system",
            ["system", "light", "dark"], fallback: "system")
        onboardingCompleted = defaults.bool(forKey: "ui.onboardingCompleted")
    }
    var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
}
