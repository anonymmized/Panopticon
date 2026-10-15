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
    static let title = Font.system(size: 24, weight: .semibold)
    static let heading = Font.system(size: 14, weight: .semibold)
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
    var body: some View {
        VStack(alignment: .leading, spacing: Studio.gap) {
            StudioCard("Типографика и управление") {
                Text("Заголовок").font(Studio.title)
                Text("Основной текст и пояснение").font(Studio.body)
                HStack {
                    Button("Основное действие") {}.buttonStyle(.borderedProminent)
                    Button("Дополнительное") {}
                    Button("Недоступно") {}.disabled(true)
                }
                Label("Действие выполнено", systemImage: "checkmark.circle").foregroundStyle(.green)
                Label("Нужно подключение", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            StudioCard("Пустое состояние") {
                EmptyState(
                    symbol: "square.grid.2x2", title: "Здесь появятся элементы",
                    detail: "Добавь приложение, папку или сайт.")
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
        section = defaults.string(forKey: "ui.settingsSection") ?? "appearance"
        appearance = defaults.string(forKey: "ui.appearance") ?? "system"
        onboardingCompleted = defaults.bool(forKey: "ui.onboardingCompleted")
    }
    var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
}
