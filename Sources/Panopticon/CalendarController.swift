import AppKit
import EventKit

struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let calendar: String
    let color: NSColor
    var time: String { if allDay { return L("Весь день") }; let f = DateFormatter(); f.locale = Localization.shared.locale; f.dateFormat = "HH:mm"; return f.string(from: start) }
    func overlaps(_ day: Date, in calendar: Calendar = .current) -> Bool {
        let beginning = calendar.startOfDay(for: day)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: beginning) else { return false }
        return start < endOfDay && end > beginning
    }
}

enum MonthGrid {
    static func days(for month: Date, calendar: Calendar = .current) -> [Date?] {
        var calendar = calendar; calendar.firstWeekday = 2
        guard let start = calendar.dateInterval(of: .month, for: month)?.start, let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let offset = (calendar.component(.weekday, from: start) - 2 + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: offset) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}

final class CalendarController: ObservableObject {
    private let queue = DispatchQueue(label: "Panopticon.calendar", qos: .userInitiated)
    private lazy var store = EKEventStore() // Accessed only on the calendar queue.
    @Published var events: [AgendaEvent] = []
    @Published var upcoming: [AgendaEvent] = []
    @Published var calendarNames: [(id: String, name: String)] = []
    @Published var authorized = false
    @Published var loading = false
    @Published var message = L("Подключи календари macOS, чтобы видеть события здесь.")
    var selectedIDs: [String] = []
    var enabled = false
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var lastRefresh = Date.distantPast
    private var displayedMonth = Date()
    private var generation = 0
    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh(force: true) }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func connect() {
        loading = true
        queue.async { [weak self] in
            guard let self else { return }
            let completion: (Bool, Error?) -> Void = { [weak self] granted, error in
                DispatchQueue.main.async { guard let self else { return }; self.loading = false; self.authorized = granted; self.message = error?.localizedDescription ?? (granted ? L("Календари подключены") : L("Доступ не предоставлен. Открой настройки доступа macOS.")); self.refresh(force: true) }
            }
            if #available(macOS 14.0, *) { self.store.requestFullAccessToEvents(completion: completion) }
            else { self.store.requestAccess(to: .event, completion: completion) }
        }
    }
    func showMonth(_ date: Date) { displayedMonth = date; refresh(force: true) }
    func refresh(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastRefresh) >= 60 else { return }
        lastRefresh = now; generation += 1; let token = generation
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { authorized = status == .fullAccess }
        else { authorized = status == .authorized }
        guard enabled && authorized else {
            events = []; upcoming = []; loading = false
            if !authorized { calendarNames = []; if status == .denied || status == .restricted { message = L("Доступ к событиям закрыт. Его можно изменить в настройках macOS.") } }
            onChange?(); return
        }
        loading = true; let ids = selectedIDs; let month = displayedMonth
        queue.async { [weak self] in
            guard let self else { return }
            let calendars = self.store.calendars(for: .event)
            let chosen = ids.isEmpty ? calendars : calendars.filter { ids.contains($0.calendarIdentifier) }
            let names = calendars.map { (id: $0.calendarIdentifier, name: $0.title) }
            func query(_ start: Date, _ end: Date) -> [AgendaEvent] {
                guard !chosen.isEmpty else { return [] }
                let predicate = self.store.predicateForEvents(withStart: start, end: end, calendars: chosen)
                return self.store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(1000).map { event in
                    let color = event.calendar.cgColor.flatMap(NSColor.init(cgColor:)) ?? .systemMint
                    return AgendaEvent(id: (event.eventIdentifier ?? "event") + "-\(event.startDate.timeIntervalSince1970)", title: event.title ?? L("Без названия"), start: event.startDate, end: event.endDate, allDay: event.isAllDay, calendar: event.calendar.title, color: color)
                }
            }
            let interval = Calendar.current.dateInterval(of: .month, for: month)!
            let monthEvents = query(interval.start, interval.end)
            let day = Calendar.current.startOfDay(for: now)
            let next = query(day, Calendar.current.date(byAdding: .day, value: 7, to: day)!).filter { $0.end > now }
            DispatchQueue.main.async {
                guard self.generation == token, self.enabled else { return }
                self.events = monthEvents; self.upcoming = next; self.calendarNames = names; self.loading = false
                self.message = chosen.isEmpty ? L("Выбери календари для показа.") : (monthEvents.isEmpty ? L("В этом месяце событий нет.") : L("События обновлены"))
                self.onChange?()
            }
        }
    }
    var nextEvent: AgendaEvent? { upcoming.first { !$0.allDay } ?? upcoming.first }
}
