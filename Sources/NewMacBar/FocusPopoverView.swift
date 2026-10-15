import SwiftUI

struct FocusPopoverView: View {
    @ObservedObject var focus: FocusTimer
    @ObservedObject var model: BarModel
    var body: some View {
        ScrollView {
        VStack(spacing: 18) {
            Label("Время для фокуса", systemImage: "timer").font(Studio.heading)
            ZStack {
                Circle().stroke(Studio.border, lineWidth: 5)
                Circle().trim(from: 0, to: focus.progress).stroke(
                    Studio.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)
                ).rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text(focus.text).font(.system(size: 34, weight: .medium, design: .monospaced))
                    Text(
                        focus.remaining <= 0
                            ? "Сессия завершена"
                            : focus.isRunning ? "Можно сосредоточиться" : "Готов к продолжению"
                    ).font(Studio.caption).foregroundStyle(.secondary)
                }
            }.frame(width: 190, height: 190).accessibilityElement(children: .combine).accessibilityLabel(
                "Осталось \(focus.text), \(focus.isRunning ? "таймер запущен" : "таймер остановлен")")
            HStack {
                Button(focus.isRunning ? "Пауза" : focus.remaining <= 0 ? "Новая сессия" : "Начать") {
                    focus.toggle(minutes: model.timerMinutes)
                }.buttonStyle(.borderedProminent)
                Button("Сбросить") { focus.reset(minutes: model.timerMinutes) }
            }
            Picker("Следующая сессия", selection: $model.timerMinutes) {
                ForEach(Array(Set([5.0, 15, 25, 45, 60, 90, model.timerMinutes])).sorted(), id: \.self) { Text(String(format: "%g минут", $0)).tag($0) }
            }
            Text(
                "Сессия сохраняется при перезапуске. Новая длительность применяется после сброса или к следующему запуску."
            ).font(Studio.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }        }.modifier(PopoverSurface())
    }
}
