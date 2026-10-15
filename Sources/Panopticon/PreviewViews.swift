import SwiftUI

extension BarModel {
    var accent: Color {
        [
            "violet": Color.purple, "cyan": .cyan, "mint": .mint, "blue": .blue, "orange": .orange,
            "rose": .pink, "neutral": .gray,
        ][widgetAccent] ?? .purple
    }
}

struct StudioBackground: View {
    @ObservedObject var localization = Localization.shared
    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.035, blue: 0.16), Color(red: 0.1, green: 0.08, blue: 0.32),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color.blue.opacity(0.7)).frame(
                    width: g.size.width * 0.6, height: g.size.height * 1.6
                ).blur(radius: 24).offset(x: -g.size.width * 0.27, y: 25)
                Ellipse().fill(Color.indigo).frame(width: g.size.width * 0.24, height: g.size.height * 1.7)
                    .blur(radius: 18).rotationEffect(.degrees(35)).offset(x: g.size.width * 0.26, y: -25)
                Ellipse().fill(Color.purple.opacity(0.55)).frame(
                    width: g.size.width * 0.4, height: g.size.height * 0.7
                ).blur(radius: 24).offset(x: g.size.width * 0.4, y: 40)
            }.clipped()
        }
    }
}

struct MiniWidget: View {
    @ObservedObject var localization = Localization.shared
    var kind: String
    var compact = false
    var accent: Color = .purple
    var opacity = 0.38
    var clockText: String?
    var dateText: String?
    var body: some View {
        HStack(spacing: 9) {
            if kind == "music" {
                Image(systemName: "music.note").font(.system(size: 14)).frame(width: 29, height: 29)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                if !compact {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Название трека")).font(.system(size: 10, weight: .bold))
                        HStack {
                            Text(L("Исполнитель")).font(.system(size: 10)).opacity(0.6)
                            Spacer(minLength: 10)
                            Image(systemName: "backward.fill")
                            Image(systemName: "pause.fill")
                            Image(systemName: "forward.fill")
                        }.font(.system(size: 10))
                    }.frame(width: 91)
                }
            } else if kind == "calendar" {
                VStack(spacing: 1) {
                    Text(Date().formatted(.dateTime.month(.abbreviated).locale(localization.locale)).uppercased()).font(
                        .system(size: 6, weight: .bold)
                    ).foregroundStyle(.white.opacity(0.65))
                    Text(Date().formatted(.dateTime.day().locale(localization.locale))).font(.system(size: 20, weight: .semibold))
                }.frame(width: 28)
                if !compact {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Твой календарь")).font(.system(size: 10, weight: .semibold))
                        Text(L("Встречи и планы")).font(.system(size: 10)).opacity(0.6)
                    }.frame(width: 95, alignment: .leading)
                }
            } else if kind == "timer" {
                Image(systemName: "timer").font(.system(size: 16))
                if !compact {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("25:00").font(.system(size: 18, weight: .semibold, design: .monospaced))
                        Text(L("Время для фокуса")).font(.system(size: 10)).opacity(0.6)
                    }.frame(width: 93, alignment: .leading)
                }
            } else {
                if compact {
                    let parts = (clockText ?? "22:30").split(separator: ":")
                    VStack(spacing: 0) {
                        Text(parts.first.map(String.init) ?? "22").font(
                            .system(size: 14, weight: .semibold, design: .monospaced))
                        Text(parts.dropFirst().first.map(String.init) ?? "30").font(
                            .system(size: 11, weight: .medium, design: .monospaced)
                        ).opacity(0.65)
                    }.frame(width: 23, height: 27)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(clockText ?? "22:30").font(
                            .system(size: 18, weight: .semibold, design: .monospaced))
                        Text(dateText ?? L("Вторник, 13 октября")).font(.system(size: 10)).opacity(0.6)
                    }.frame(width: 127, alignment: .leading)
                }
            }
        }.padding(compact ? 9 : 7).foregroundStyle(.white).background(
            accent.opacity(opacity), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct DockPreview: View {
    @ObservedObject var localization = Localization.shared
    @ObservedObject var model: BarModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            StudioBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Circle().fill(.mint).frame(width: 5, height: 5)
                    Text(L("Предпросмотр")).font(Studio.caption.weight(.semibold))
                    Spacer()
                    Text("\(model.dockEdge.title) · \(Int(model.iconSize)) pt").font(
                        .system(size: 11, design: .monospaced)
                    ).opacity(0.5)
                }.foregroundStyle(.white.opacity(0.7))
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CGFloat(model.iconSpacing) * 0.6) {
                        ForEach(Array(model.pinned.prefix(model.widgetKinds.count > 1 ? 5 : 7))) { item in
                            VStack(spacing: 4) {
                                Image(nsImage: item.icon).resizable().frame(
                                    width: min(model.iconSize, 42), height: min(model.iconSize, 42))
                                Capsule().fill(.white.opacity(0.8)).frame(
                                    width: model.indicatorStyle == "dash" ? 7 : 3,
                                    height: model.indicatorStyle == "none" ? 0 : 2)
                            }
                        }
                        ForEach(model.widgetKinds, id: \.self) { kind in
                            if model.showSeparator {
                                Divider().frame(height: 28).overlay(.white.opacity(0.2)).padding(
                                    .horizontal, 5)
                            }
                            TimelineView(.periodic(from: .now, by: model.clockSeconds ? 1 : 60)) { context in
                                MiniWidget(
                                    kind: kind, compact: model.widgetStyle == "compact", accent: model.accent,
                                    opacity: model.widgetOpacity + 0.12,
                                    clockText: formatted(context.date, time: true),
                                    dateText: formatted(context.date, time: false))
                            }
                        }

                    }.padding(.horizontal, 12).padding(.vertical, 9).background(
                        model.dockTheme.isLight ? Color.white.opacity(0.35) : Color.black.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: model.cornerRadius)
                    ).overlay(
                        RoundedRectangle(cornerRadius: model.cornerRadius).stroke(
                            .white.opacity(0.25), lineWidth: 0.7)
                    ).frame(maxWidth: .infinity)
                }.frame(height: 80)
                Spacer()
            }.padding(17)
        }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private func formatted(_ date: Date, time: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.locale
        formatter.dateFormat =
            time
            ? (model.clockFormat == "12h" ? "h:mm" : "HH:mm") + (model.clockSeconds ? ":ss" : "")
                + (model.clockFormat == "12h" ? " a" : "") : "EEEE, d MMM"
        return formatter.string(from: date).capitalized
    }

}

struct OptionTile<Content: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    let content: Content
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.selected = selected
        self.action = action
        self.content = content()
    }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    StudioBackground()
                    content.scaleEffect(hovered && !reduceMotion ? 1.04 : 1).animation(
                        reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                }.frame(height: 92).clipShape(RoundedRectangle(cornerRadius: 13)).overlay(
                    RoundedRectangle(cornerRadius: 13).stroke(
                        selected ? Color.mint.opacity(0.9) : .white.opacity(0.07),
                        lineWidth: selected ? 1.8 : 1))
                HStack(spacing: 5) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                    Text(title).foregroundStyle(selected ? .primary : .secondary)
                }.font(.system(size: 10, weight: selected ? .semibold : .regular))
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).onHover { hovered = $0 }.accessibilityLabel(title).accessibilityAddTraits(
            selected ? [.isSelected] : [])
    }
}
