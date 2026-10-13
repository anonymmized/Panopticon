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
    var time: String { if allDay { return "Весь день" }; let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: start) }
}

final class CalendarController: ObservableObject {
    private let store = EKEventStore()
    @Published var events: [AgendaEvent] = []
    @Published var calendarNames: [(id: String, name: String)] = []
    @Published var authorized = false
    @Published var message = "Подключи календари macOS, чтобы видеть события здесь."
    var selectedIDs: [String] = []
    var enabled = false
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var lastRefresh = Date.distantPast
    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.refresh(force: true) }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func connect() {
        let completion: (Bool, Error?) -> Void = { [weak self] granted, error in
            DispatchQueue.main.async { guard let self else { return }; self.authorized = granted; self.message = error?.localizedDescription ?? (granted ? "Календари подключены" : "Доступ не предоставлен. Его можно включить в настройках macOS."); self.refresh(force: true) }
        }
        if #available(macOS 14.0, *) { store.requestFullAccessToEvents(completion: completion) }
        else { store.requestAccess(to: .event, completion: completion) }
    }
    func refresh(force: Bool = false) {
        guard enabled else { events = []; onChange?(); return }
        if !force && Date().timeIntervalSince(lastRefresh) < 60 { return }
        lastRefresh = Date()
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { authorized = status == .fullAccess }
        else { authorized = status == .authorized }
        guard authorized else { events = []; calendarNames = []; onChange?(); return }
        let calendars = store.calendars(for: .event)
        calendarNames = calendars.map { ($0.calendarIdentifier, $0.title) }
        let chosen = selectedIDs.isEmpty ? calendars : calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
        let now = Date(); let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        events = chosen.isEmpty ? [] : store.events(matching: predicate).filter { $0.endDate >= now }.sorted { $0.startDate < $1.startDate }.prefix(60).enumerated().map { index, event in
            AgendaEvent(id: (event.eventIdentifier ?? "event") + "-\(index)", title: event.title ?? "Без названия", start: event.startDate, end: event.endDate, allDay: event.isAllDay, calendar: event.calendar.title, color: NSColor(cgColor: event.calendar.cgColor) ?? .systemMint)
        }
        message = events.isEmpty ? "На ближайшие дни событий нет." : "События обновлены"
        onChange?()
    }
    var nextEvent: AgendaEvent? { events.first { !$0.allDay } ?? events.first }
}
