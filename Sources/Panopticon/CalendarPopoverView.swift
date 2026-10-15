import SwiftUI

struct CalendarPopoverView: View {
    @ObservedObject var localization = Localization.shared
    @ObservedObject var agenda: CalendarController
    @ObservedObject var model: BarModel
    @State private var month = Date()
    @State private var selected = Date()
    private var cal: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }
    private var days: [Date?] { MonthGrid.days(for: month, calendar: cal) }
    private var dayEvents: [AgendaEvent] { agenda.events.filter { $0.overlaps(selected, in: cal) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(formatted(month, "LLLL yyyy").capitalized).font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button {
                        move(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }.accessibilityLabel(L("Предыдущий месяц"))
                    Button(L("Сегодня")) {
                        month = Date()
                        selected = Date()
                        agenda.showMonth(month)
                    }
                    Button {
                        move(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }.accessibilityLabel(L("Следующий месяц"))
                }.buttonStyle(.borderless)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4)
                {
                    ForEach([L("ПН"), L("ВТ"), L("СР"), L("ЧТ"), L("ПТ"), L("СБ"), L("ВС")], id: \.self) {
                        Text($0).font(Studio.caption.weight(.medium)).foregroundStyle(.secondary).frame(
                            height: 18
                        ).accessibilityHidden(true)
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                        if let date {
                            let isSelected = cal.isDate(date, inSameDayAs: selected)
                            let events =
                                model.calendarEventsEnabled && agenda.authorized
                                && agenda.events.contains { $0.overlaps(date, in: cal) }
                            Button {
                                selected = date
                            } label: {
                                VStack(spacing: 3) {
                                    Text("\(cal.component(.day, from: date))").font(
                                        .system(size: 13, weight: cal.isDateInToday(date) ? .bold : .regular))
                                    Circle().fill(
                                        events ? (isSelected ? Color.white : Studio.accent) : .clear
                                    ).frame(width: 3, height: 3)
                                }.frame(maxWidth: .infinity).frame(height: 32)
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .background(
                                        isSelected ? Studio.accent : .clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8).strokeBorder(
                                            cal.isDateInToday(date) ? Studio.accent : .clear, lineWidth: 1))
                            }.buttonStyle(.plain).accessibilityLabel(
                                formatted(date, "EEEE, d MMMM") + (events ? L(", есть события") : "")
                            ).accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        } else {
                            Color.clear.frame(height: 32).accessibilityHidden(true)
                        }
                    }
                }
                Divider()
                HStack {
                    Text(formatted(selected, "EEEE, d MMMM").capitalized).font(Studio.heading)
                    Spacer()
                    if agenda.authorized && model.calendarEventsEnabled {
                        Text("\(dayEvents.count)").foregroundStyle(.secondary)
                    }
                }
                if agenda.loading { ProgressView(L("Обновляю события…")).controlSize(.small) }
                if !model.calendarEventsEnabled || !agenda.authorized {
                    Text(agenda.authorized ? L("Показ событий выключен.") : agenda.message).font(Studio.caption)
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if agenda.authorized {
                        Button(L("Показывать события")) { model.calendarEventsEnabled = true }
                    } else {
                        Button(L("Подключить события календарей…")) {
                            model.calendarEventsEnabled = true
                            agenda.enabled = true
                            agenda.connect()
                        }.disabled(agenda.loading)
                    }
                } else if !agenda.loading && dayEvents.isEmpty {
                    Label(L("На этот день событий нет"), systemImage: "calendar").font(Studio.body)
                        .foregroundStyle(.secondary)
                    Text(localization.status(agenda.message)).font(Studio.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(dayEvents) { event in eventRow(event) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("Источник событий: календари macOS"), systemImage: "externaldrive").font(
                        Studio.caption
                    ).foregroundStyle(.secondary)
                    Button(L("Открыть \(model.calendarAppName)")) { model.openCalendar() }.disabled(
                        model.calendarTarget == nil)
                    Text(
                        L("Выбранное приложение задаёт, что открывать. События поступают из календарей, подключённых в macOS.")
                    ).font(Studio.caption).foregroundStyle(.secondary).fixedSize(
                        horizontal: false, vertical: true)
                }
            }.padding(Studio.inset)
        }.background(Studio.canvas).tint(Studio.accent)
            .onAppear { agenda.showMonth(month) }
            .onChange(of: month) { agenda.showMonth($0) }
    }
    private func eventRow(_ event: AgendaEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: event.color)).frame(width: 3, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(Studio.body.weight(.medium)).fixedSize(
                    horizontal: false, vertical: true)
                Text(event.time + " · " + event.calendar).font(Studio.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
    private func move(_ amount: Int) {
        guard let next = cal.date(byAdding: .month, value: amount, to: month),
            let first = cal.dateInterval(of: .month, for: next)?.start
        else { return }
        month = next
        selected = first
    }
    private func formatted(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = localization.locale
        f.setLocalizedDateFormatFromTemplate(format)
        return f.string(from: date)
    }
}
