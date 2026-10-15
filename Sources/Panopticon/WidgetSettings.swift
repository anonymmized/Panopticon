import AppKit
import SwiftUI

extension SettingsView {
    var displayedWidget: String { if let editedWidget, model.widgetKinds.contains(editedWidget) { return editedWidget }; return model.widgetKinds.first ?? "clock" }
    var widgets: some View {
        VStack(alignment: .leading, spacing: 23) {
            sectionTitle(L("Что будет на панели"), L("Выбери виджет. Его оформление настраивается ниже."))
            HStack(spacing: 13) {
                ForEach(
                    [("music", L("Музыка")), ("clock", L("Часы")), ("calendar", L("Календарь")), ("timer", L("Фокус"))],
                    id: \.0
                ) { id, label in
                    OptionTile(label, selected: model.widget == id, action: { model.widget = id }) {
                        MiniWidget(kind: id, compact: true, accent: model.accent)
                    }
                }
            }
            HStack {
                Text(L("Виджет на панели")).font(.system(size: 11))
                Spacer()
                Toggle(
                    L("Виджет на панели"),
                    isOn: Binding(
                        get: { !model.widgetKinds.isEmpty },
                        set: { enabled in
                            model.batch {
                                if enabled {
                                    model.widget = "clock"
                                } else {
                                    model.widget = "none"
                                    model.secondaryWidget = "none"
                                }
                            }
                        })
                ).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            card(L("Второй виджет")) {
                Picker(L("Рядом с основным"), selection: $model.secondaryWidget) {
                    Text(L("Выключен")).tag("none")
                    ForEach(
                        [
                            ("clock", L("Часы")), ("calendar", L("Календарь")), ("music", L("Музыка")),
                            ("timer", L("Фокус")),
                        ].filter { $0.0 != model.widget }, id: \.0
                    ) { id, name in Text(name).tag(id) }
                }.font(.system(size: 11))
                Text(
                    L("Например, музыка и ближайшая встреча одновременно. Оформление общее для обоих виджетов.")
                ).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if model.widgetKinds.count > 1 {
                Picker(L("Настроить виджет"), selection: Binding(get: { displayedWidget }, set: { editedWidget = $0 })) {
                    ForEach(model.widgetKinds, id: \.self) { kind in
                        Text(["music": L("Музыка"), "clock": L("Часы"), "calendar": L("Календарь"), "timer": L("Фокус")][kind] ?? L("Виджет")).tag(kind)
                    }
                }
            }
            if !model.widgetKinds.isEmpty {
                sectionTitle(L("Размер виджета"), L("Компактная кнопка или подробная карточка."))
                HStack(spacing: 13) {
                    ForEach([("compact", L("Компактный")), ("wide", L("Подробный"))], id: \.0) { id, label in
                        OptionTile(
                            label, selected: model.widgetStyle == id, action: { model.widgetStyle = id }
                        ) {
                            MiniWidget(kind: displayedWidget, compact: id == "compact", accent: model.accent)
                        }
                    }
                }
                card(L("Оформление")) {
                    HStack(spacing: 14) {
                        Text(L("Цвет")).font(.system(size: 11))
                        Spacer()
                        ForEach(["violet", "blue", "cyan", "mint", "orange", "rose", "neutral"], id: \.self) {
                            id in
                            Button {
                                model.widgetAccent = id
                            } label: {
                                Circle().fill(color(id)).frame(width: 20, height: 20).padding(3).overlay(
                                    Circle().stroke(
                                        model.widgetAccent == id ? Color.primary : .clear, lineWidth: 1.5))
                            }.buttonStyle(.plain).accessibilityLabel(accentName(id)).help(accentName(id)).accessibilityAddTraits(model.widgetAccent == id ? [.isSelected] : [])
                        }
                    }
                    if model.widgetStyle == "wide" {
                        slider(L("Ширина"), $model.widgetWidth, 130...250, "\(Int(model.widgetWidth)) pt")
                    }
                    slider(
                        L("Насыщенность фона"), $model.widgetOpacity, 0.08...0.7,
                        "\(Int(model.widgetOpacity * 100))%")
                }
                if displayedWidget == "music" {
                    card(L("Музыкальный плеер")) {
                        Picker(L("Источник"), selection: $model.playerPreference) {
                            Text(L("Автоматически")).tag("auto")
                            Text("Spotify").tag("spotify")
                            Text("Apple Music").tag("music")
                        }
                        Text(
                            L("Обложка Spotify, название трека, исполнитель и управление. Нажми на обложку или название: откроется плеер с перемоткой. Автоматический выбор предпочитает Spotify.")
                        ).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                        Button(L("Настройки доступа к плееру")) {
                            NSWorkspace.shared.open(
                                URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                                )!)
                        }.font(.system(size: 11))
                        Text(L("Воспроизведение из браузера пока не поддерживается.")).font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if displayedWidget == "calendar" {
                    card(L("Календарь и события")) {
                        Text(L("Дата и ближайшее событие на панели. Нажатие открывает месяц и список встреч."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Button(L("Выбрать приложение и календари")) { section = "connections" }.font(
                            .system(size: 11))
                    }
                }
                if displayedWidget == "clock" {
                    card(L("Часы")) {
                        Picker(L("Формат времени"), selection: $model.clockFormat) {
                            Text(L("24 часа")).tag("24h")
                            Text(L("12 часов")).tag("12h")
                        }.pickerStyle(.segmented)
                        row(
                            L("Показывать секунды"), L("Для более подробного отображения времени"),
                            $model.clockSeconds)
                        Text(L("Нажатие открывает выбранное приложение или календарную карточку.")).font(
                            .system(size: 11)
                        ).foregroundStyle(.secondary)
                    }
                }
                if displayedWidget == "timer" {
                    card(L("Таймер фокуса")) {
                        slider(
                            L("Длительность сессии"), $model.timerMinutes, 5...90,
                            L("\(Int(model.timerMinutes)) мин"))
                        HStack {
                            Text(focus.text).font(.system(size: 24, weight: .medium, design: .monospaced))
                            Spacer()
                            Button(focus.isRunning ? L("Пауза") : L("Начать")) {
                                focus.toggle(minutes: model.timerMinutes)
                            }
                            Button(L("Сбросить")) { focus.reset(minutes: model.timerMinutes) }
                        }
                        Text(
                            L("Сессия сохраняется при перезапуске. Новая длительность применяется после сброса или к следующей сессии.")
                        ).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    func accentName(_ id: String) -> String { ["violet": L("Фиолетовый"), "blue": L("Синий"), "cyan": L("Голубой"), "mint": L("Мятный"), "orange": L("Оранжевый"), "rose": L("Розовый"), "neutral": L("Нейтральный")][id] ?? L("Цвет") }
    func color(_ id: String) -> Color {
        [
            "violet": Color.purple, "blue": .blue, "cyan": .cyan, "mint": .mint, "orange": .orange,
            "rose": .pink, "neutral": .gray,
        ][id]!
    }

}
