import AppKit
import SwiftUI

extension SettingsView {
    var panelMotionBinding: Binding<String> {
        Binding(get: { model.motionMode }, set: { model.setMotionMode($0) })
    }
    var appearance: some View {
        VStack(alignment: .leading, spacing: 23) {
            card(L("Как Dock macOS")) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Стеклянная панель и живые иконки")).font(Studio.body.weight(.medium))
                        Text(L("Плавная волна увеличения, подъём при наведении и прыжок при запуске."))
                            .font(Studio.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Применить")) { model.applyNativeDockStyle() }.buttonStyle(.borderedProminent)
                }
            }
            card(L("Размер и положение")) {
                slider(L("Размер иконок"), $model.iconSize, 28...60, "\(Int(model.iconSize)) pt")
                slider(L("Интервал между иконками"), $model.iconSpacing, 4...24, "\(Int(model.iconSpacing)) pt")
                slider(L("Отступ от края экрана"), $model.bottomOffset, 0...160, "\(Int(model.bottomOffset)) pt")
                Button(L("Рекомендуемый компактный размер")) {
                    model.iconSize = 36
                    model.iconSpacing = 8
                    model.bottomOffset = 4
                    model.magnification = 1.35
                    model.hoverLift = 7
                    model.cornerRadius = 20
                    model.opacity = 0.08
                }.font(.system(size: 11)).buttonStyle(.borderless).foregroundStyle(.mint)
            }
            sectionTitle(L("Стиль стекла"), L("Оформление панели поверх обоев и окон."))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 13) {
                ForEach(DockTheme.allCases) { theme in
                    OptionTile(
                        theme.title, selected: model.theme == theme.rawValue,
                        action: { model.theme = theme.rawValue }
                    ) {
                        HStack(spacing: 8) {
                            previewIcon("/System/Library/CoreServices/Finder.app", 31)
                            previewIcon("/System/Applications/Music.app", 31)
                        }
                        .padding(10).background(
                            LinearGradient(
                                colors: theme.preview, startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 13))
                    }
                }
            }
            card(L("Поверхность")) {
                slider(L("Плотность стекла"), $model.opacity, 0...0.65, "\(Int(model.opacity * 100))%")
                slider(L("Скругление углов"), $model.cornerRadius, 8...30, "\(Int(model.cornerRadius)) pt")
            }
            sectionTitle(L("При наведении"), L("Выбери характер движения иконок."))
            HStack(spacing: 13) {
                ForEach([("none", L("Спокойно")), ("lift", L("Подъём")), ("scale", L("Увеличение"))], id: \.0) {
                    id, label in
                    OptionTile(label, selected: model.hoverStyle == id, action: { model.hoverStyle = id }) {
                        HStack(spacing: 8) {
                            previewIcon("/System/Library/CoreServices/Finder.app", id == "none" ? 30 : 39)
                                .offset(y: id == "lift" ? -5 : 0)
                            previewIcon("/Applications/Safari.app", 30)
                        }
                    }
                }
            }
            card(L("Движение")) {
                Picker(L("Анимации панели"), selection: panelMotionBinding) {
                    ForEach(DockMotionMode.allCases) { Text($0.title).tag($0.rawValue) }
                }.id(localization.code)
                if model.motionMode == "system", NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.reduceMotion {
                    Label(L("Включено уменьшение движения: иконки подсвечиваются без увеличения. Выбери «Полные анимации», чтобы включить волну и прыжки."), systemImage: "figure.stand")
                        .font(Studio.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                slider(
                    L("Увеличение"), $model.magnification, 1...1.8, String(format: "×%.2f", model.magnification))
                slider(L("Высота подъёма"), $model.hoverLift, 0...16, "\(Int(model.hoverLift)) pt")
            }
            HStack(alignment: .top, spacing: 15) {
                card(L("При запуске")) {
                    Picker(L("Анимация"), selection: $model.launchStyle) {
                        Text(L("Прыжок")).tag("bounce")
                        Text(L("Пульс")).tag("pulse")
                        Text(L("Без анимации")).tag("none")
                    }.labelsHidden()
                }
                card(L("Индикатор запуска")) {
                    Picker(L("Индикатор"), selection: $model.indicatorStyle) {
                        Text(L("Точка")).tag("dot")
                        Text(L("Линия")).tag("dash")
                        Text(L("Скрыть")).tag("none")
                    }.labelsHidden()
                }
            }
            card(L("Детали")) {
                row(L("Подписи при наведении"), L("Название приложения над иконкой"), $model.showLabels)
                row(
                    L("Разделитель перед виджетом"), L("Тонкая линия между приложениями и виджетом"),
                    $model.showSeparator)
                row(
                    L("Кнопка настроек на панели"), L("Настройки также доступны в строке меню и по правой кнопке"),
                    $model.showSettingsButton)
            }
        }
    }
    func previewIcon(_ path: String, _ size: Double) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: size, height: size)
    }

}
