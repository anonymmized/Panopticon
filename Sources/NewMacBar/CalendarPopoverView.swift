import SwiftUI

struct CalendarPopoverView: View {
    @ObservedObject var agenda: CalendarController
    @ObservedObject var model: BarModel
    @State private var month = Date()
    @State private var selected = Date()
    private var cal: Calendar { var value = Calendar.current; value.firstWeekday = 2; return value }
    private var days: [Date?] {
        let start = cal.dateInterval(of: .month, for: month)!.start
        let count = cal.range(of: .day, in: .month, for: month)!.count
        let offset = (cal.component(.weekday, from: start) - 2 + 7) % 7
        return Array(repeating: nil, count: offset) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: start) }
    }
    private var dayEvents: [AgendaEvent] { agenda.events.filter { let start = cal.startOfDay(for: selected); let end = cal.date(byAdding: .day, value: 1, to: start)!; return $0.start < end && $0.end > start } }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text(formatted(month, "LLLL yyyy").capitalized).font(.system(size: 18, weight: .semibold)); Text("ТВОЙ КАЛЕНДАРЬ").font(.system(size: 7, weight: .medium)).tracking(1.5).foregroundStyle(.secondary) }; Spacer(); Button { move(-1) } label: { Image(systemName: "chevron.left") }; Button("Сегодня") { month = Date(); selected = Date() }.font(.system(size: 10)); Button { move(1) } label: { Image(systemName: "chevron.right") } }.buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"], id: \.self) { Text($0).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).frame(height: 18) }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date { Button { selected = date } label: { VStack(spacing: 3) { Text("\(cal.component(.day, from: date))").font(.system(size: 11, weight: cal.isDateInToday(date) ? .bold : .regular)); Circle().fill(agenda.events.contains { cal.isDate($0.start, inSameDayAs: date) } ? .mint : .clear).frame(width: 3, height: 3) }.frame(maxWidth: .infinity).frame(height: 29).foregroundStyle(cal.isDate(date, inSameDayAs: selected) ? Color.black : (cal.isDateInToday(date) ? .mint : .white)).background(cal.isDate(date, inSameDayAs: selected) ? Color.mint : .clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel(formatted(date, "d MMMM")) }
                    else { Color.clear.frame(height: 29) }
                }
            }
            Divider().opacity(0.3)
            HStack { Text(formatted(selected, "EEEE, d MMMM").capitalized).font(.system(size: 11, weight: .medium)); Spacer(); if agenda.authorized && model.calendarEventsEnabled { Text("\(dayEvents.count)").font(.system(size: 9)).foregroundStyle(.secondary) } }
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if !model.calendarEventsEnabled || !agenda.authorized {
                        Text("События из календарей, подключённых к macOS. Выбранное приложение открывается кнопкой ниже.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                        if !agenda.authorized { Button("Подключить события календарей") { model.calendarEventsEnabled = true; agenda.enabled = true; agenda.connect() }.font(.system(size: 10)) }
                    } else if dayEvents.isEmpty { Label("На этот день событий нет", systemImage: "sun.max").font(.system(size: 11)).foregroundStyle(.secondary); Text("Показаны события на ближайшие 7 дней.").font(.system(size: 9)).foregroundStyle(.secondary) }
                    ForEach(dayEvents) { event in HStack(alignment: .top, spacing: 10) { RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: event.color)).frame(width: 3, height: 32); VStack(alignment: .leading, spacing: 4) { Text(event.title).font(.system(size: 11, weight: .medium)).lineLimit(2); Text(event.time + " · " + event.calendar).font(.system(size: 9)).foregroundStyle(.secondary) }; Spacer() } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 108)
            Button { model.openCalendar() } label: { HStack { Image(systemName: "arrow.up.forward.app"); Text("Открыть \(model.calendarAppName)"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 10, weight: .medium)).padding(11).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
        }.padding(20).frame(width: 350).background(Color(red: 0.075, green: 0.08, blue: 0.11)).preferredColorScheme(.dark).tint(.mint).onAppear { agenda.refresh(force: true) }
    }
    private func move(_ n: Int) { month = cal.date(byAdding: .month, value: n, to: month) ?? month }
    private func formatted(_ date: Date, _ format: String) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = format; return f.string(from: date) }
}
