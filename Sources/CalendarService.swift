import AppKit
import Combine
import EventKit

enum CalendarGrid {
    static func monthStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    static func days(in month: Date, calendar: Calendar) -> [Date] {
        let first = monthStart(month, calendar: calendar)
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: first)!
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func overlaps(start: Date, end: Date, day: Date, calendar: Calendar) -> Bool {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return false }
        return start < interval.end && (end > interval.start || (start == end && start >= interval.start))
    }
}

struct CalendarEntry: Identifiable {
    let id: String
    let title: String
    let calendarName: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: NSColor
}

@MainActor
final class CalendarService: ObservableObject {
    enum Status { case notConnected, loading, ready, denied, restricted, failed }
    @Published private(set) var selectedDate: Date
    @Published private(set) var month: Date
    @Published private(set) var today: Date
    @Published private(set) var entries: [CalendarEntry] = [] {
        didSet { eventDayCache.removeAll() }
    }
    @Published private(set) var status = Status.notConnected
    private(set) var systemCalendar: Calendar
    private let preview: Bool
    private lazy var store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var requesting = false
    private var eventDayCache: [Date: Bool] = [:]
    private var formatters: [String: DateFormatter] = [:]

    init(preview: Bool = false, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        self.preview = preview
        systemCalendar = calendar
        selectedDate = calendar.startOfDay(for: now)
        today = calendar.startOfDay(for: now)
        month = CalendarGrid.monthStart(now, calendar: calendar)
        if !preview {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    var days: [Date] { CalendarGrid.days(in: month, calendar: systemCalendar) }
    var dayEntries: [CalendarEntry] {
        entries.filter { CalendarGrid.overlaps(start: $0.start, end: $0.end, day: selectedDate, calendar: systemCalendar) }
            .sorted { a, b in a.allDay != b.allDay ? a.allDay : a.start < b.start }
    }
    var monthTitle: String { label(month, format: "LLLL yyyy") }
    var dayTitle: String { label(selectedDate, format: "EEEE d 'de' MMMM") }
    var weekdayLabels: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        let symbols = formatter.veryShortStandaloneWeekdaySymbols!
        return (0..<7).map { symbols[($0 + systemCalendar.firstWeekday - 1) % 7] }
    }

    func label(_ date: Date, format: String) -> String {
        let formatter: DateFormatter
        if let cached = formatters[format] { formatter = cached }
        else {
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es")
            formatter.calendar = systemCalendar
            formatter.timeZone = systemCalendar.timeZone
            formatter.dateFormat = format
            formatters[format] = formatter
        }
        return formatter.string(from: date)
    }

    func timeLabel(_ entry: CalendarEntry) -> String {
        if entry.allDay { return "Todo el día" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = systemCalendar.timeZone
        if entry.start < systemCalendar.startOfDay(for: selectedDate) { return "Continúa" }
        return formatter.string(from: entry.start)
    }

    func hasEvents(on day: Date) -> Bool {
        let key = systemCalendar.startOfDay(for: day)
        if let cached = eventDayCache[key] { return cached }
        let result = entries.contains { CalendarGrid.overlaps(start: $0.start, end: $0.end, day: key, calendar: systemCalendar) }
        eventDayCache[key] = result
        return result
    }

    func select(_ date: Date) {
        selectedDate = systemCalendar.startOfDay(for: date)
        let nextMonth = CalendarGrid.monthStart(date, calendar: systemCalendar)
        if nextMonth != month { month = nextMonth; refresh() }
    }

    func moveMonth(_ delta: Int) {
        guard let next = systemCalendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = next
        selectedDate = next
        refresh()
    }

    func goToToday() { select(Date()); refresh() }

    func connect() async {
        guard !preview, !requesting else { return }
        requesting = true
        status = .loading
        defer { requesting = false }
        do {
            _ = try await store.requestFullAccessToEvents()
            refresh()
        } catch {
            entries = []
            status = .failed
        }
    }

    func refresh() {
        formatters.removeAll()
        eventDayCache.removeAll()
        today = systemCalendar.startOfDay(for: Date())
        guard !preview else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: break
        case .denied: entries = []; status = .denied; return
        case .restricted: entries = []; status = .restricted; return
        default: entries = []; status = .notConnected; return
        }
        let range = days
        guard let first = range.first, let last = range.last,
              let end = systemCalendar.date(byAdding: .day, value: 1, to: last) else { return }
        let predicate = store.predicateForEvents(withStart: first, end: end, calendars: nil)
        entries = store.events(matching: predicate).enumerated().map { index, event in
            CalendarEntry(id: "\(event.eventIdentifier ?? "event")-\(event.startDate.timeIntervalSince1970)-\(index)",
                          title: event.title?.isEmpty == false ? event.title : "Sin título",
                          calendarName: event.calendar?.title ?? "Calendario", start: event.startDate, end: event.endDate,
                          allDay: event.isAllDay, color: event.calendar?.color ?? .white)
        }
        status = .ready
    }

    func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func setPreview(entries: [CalendarEntry], status: Status = .ready) {
        guard preview else { return }
        self.entries = entries
        self.status = status
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
