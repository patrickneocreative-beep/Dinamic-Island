import AppKit
import SwiftUI
import Combine

@main struct VerifyCalendarDisplays {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(2) }
        print("PASS: \(message)")
    }
    @MainActor static func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    @MainActor static func accessible(_ object: Any, identifier: String, depth: Int = 0) -> NSObject? {
        guard depth < 25, let element = object as? NSObject else { return nil }
        let selector = NSSelectorFromString("accessibilityIdentifier")
        if element.responds(to: selector), element.perform(selector)?.takeUnretainedValue() as? String == identifier { return element }
        let childrenSelector = NSSelectorFromString("accessibilityChildren")
        let children = element.responds(to: childrenSelector) ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] ?? [] : []
        for child in children { if let found = accessible(child, identifier: identifier, depth: depth + 1) { return found } }
        return nil
    }
    @MainActor static func press(_ window: NSWindow, _ id: String) {
        if let element = accessible(window.contentView!, identifier: id) {
            element.accessibilityPerformAction(.press)
            return
        }
        // AppKit can defer building accessibility children for an offscreen host.
        // Exercise the same native buttons via window-local clicks in that case.
        let points: [String: NSPoint] = ["tab-Calendario": NSPoint(x: 186.5, y: 22),
                                        "calendar-next": NSPoint(x: 223, y: 52),
                                        "calendar-today": NSPoint(x: 200, y: 52)]
        guard let topPoint = points[id] else { print("FAIL: missing control \(id)"); exit(2) }
        let point = NSPoint(x: topPoint.x, y: window.frame.height - topPoint.y)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
    }
    @MainActor static func capture(_ window: NSWindow, to url: URL) {
        let view = window.contentView!
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
    @MainActor static func calendarTests() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day))! }
        for month in 1...12 {
            let days = CalendarGrid.days(in: date(2026, month, 15), calendar: calendar)
            let count = days.filter { calendar.component(.month, from: $0) == month && calendar.component(.year, from: $0) == 2026 }.count
            require(days.count == 42 && calendar.component(.weekday, from: days[0]) == 2 && count == calendar.range(of: .day, in: .month, for: date(2026, month, 1))!.count, "complete six-week grid with Monday first, month \(month)")
        }
        require(CalendarGrid.days(in: date(2024, 2, 1), calendar: calendar).contains(date(2024, 2, 29)), "leap-day calendar")
        let service = CalendarService(preview: true, now: date(2026, 12, 31), calendar: calendar)
        service.moveMonth(1)
        require(calendar.component(.year, from: service.month) == 2027 && calendar.component(.month, from: service.month) == 1, "month navigation crosses the year boundary")
        service.moveMonth(-1)
        service.select(date(2026, 11, 16))
        require(calendar.component(.month, from: service.month) == 11 && service.selectedDate == date(2026, 11, 16), "selecting a neighboring month changes its agenda and grid")
        let start = date(2026, 11, 16), end = date(2026, 11, 17)
        require(CalendarGrid.overlaps(start: start, end: end, day: start, calendar: calendar), "all-day event belongs to its day")
        require(!CalendarGrid.overlaps(start: start, end: end, day: end, calendar: calendar), "midnight event end is exclusive")
        require(CalendarGrid.overlaps(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(3600), day: start, calendar: calendar), "zero-duration event remains visible")
        var dst = calendar
        dst.timeZone = TimeZone(identifier: "America/New_York")!
        let spring = dst.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let interval = dst.dateInterval(of: .day, for: spring)!
        require(interval.duration == 23 * 3600 && CalendarGrid.overlaps(start: interval.start, end: interval.end, day: spring, calendar: dst), "calendar uses local-day boundaries across daylight saving time")
        service.setPreview(entries: [
            CalendarEntry(id: "timed", title: "Prueba con hora", calendarName: "Prueba", start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200), allDay: false, color: .white),
            CalendarEntry(id: "all-day", title: "Prueba de día completo", calendarName: "Prueba", start: start, end: end, allDay: true, color: .white)
        ])
        require(service.dayEntries.map(\.id) == ["all-day", "timed"], "agenda sorts all-day events before timed events")
        service.select(end)
        require(service.dayEntries.isEmpty, "changing the selected day clears the previous day's agenda")
    }

    @MainActor static func run(output: URL) async {
        calendarTests()
        let data = IslandData(preview: true)
        var pointer = NSPoint.zero
        let coordinator = IslandDisplayCoordinator(data: data, location: { pointer })
        let builtIn = IslandDisplay(id: 1, frame: NSRect(x: 4000, y: 4000, width: 1512, height: 982), notchWidth: 185, notchHeight: 32)
        let external = IslandDisplay(id: 2, frame: NSRect(x: 5512, y: 4000, width: 1920, height: 1080))
        coordinator.reconcile([builtIn, external])
        require(coordinator.islands.count == 2, "one native island per extended display")
        let internalIsland = coordinator.islands[1]!, externalIsland = coordinator.islands[2]!
        let a = internalIsland.model, b = externalIsland.model
        require(!externalIsland.panel.isVisible && externalIsland.panel.ignoresMouseEvents && externalIsland.panel.alphaValue == 0,
                "closed external island is removed from the screen and cannot intercept menu clicks")
        require(internalIsland.panel.isVisible, "the physical notch retains its compact status")
        pointer = NSPoint(x: external.frame.midX, y: external.frame.midY)
        data.onFocusCompletion?()
        require(!b.expanded && !externalIsland.panel.isVisible, "timer completion does not reveal a hidden external island")
        require(a.data === b.data && a.media === b.media && a.phones === b.phones && a.calendar === b.calendar, "displays share a single set of services")
        var changes = 0
        let observation = b.objectWillChange.sink { changes += 1 }
        a.note = "Nota de prueba compartida"
        a.focus.select(minutes: 5)
        a.files = [URL(fileURLWithPath: "/tmp/isla-display-test.txt")]
        a.battery = BatteryReading(percent: 63, charging: false, pluggedIn: false)
        require(b.note == a.note && b.focus.duration == 300 && b.files == a.files && b.battery.percent == 63 && changes > 0, "notes, timer, files and battery propagate to the other view")
        observation.cancel()
        for island in [internalIsland, externalIsland] {
            let top = NSPoint(x: island.display.frame.midX, y: island.display.frame.maxY)
            pointer = top
            require(island.model.pointerIsWithinPanel?() == true, "the exact top edge is inside the hover target, display \(island.display.id)")
            require(coordinator.preferredIsland() === island, "menu routing includes the exact top edge, display \(island.display.id)")
            await pause(0.8)
            require(island.model.expanded, "hover opens at the exact top boundary, display \(island.display.id)")
            coordinator.closeOutside(top)
            await pause(0.6)
            require(island.model.expanded, "the top edge is not mistaken for an outside click, display \(island.display.id)")
            pointer.y += 0.5
            require(island.model.pointerIsWithinPanel?() == false, "top-edge inclusion does not spill into the monitor above, display \(island.display.id)")
            pointer = NSPoint(x: external.frame.midX, y: external.frame.midY)
            await pause(0.9)
            require(!island.model.expanded, "leaving closes after an exact-edge opening, display \(island.display.id)")
        }
        require(!externalIsland.panel.isVisible, "external island remains hidden after exact-edge regression checks")
        pointer = NSPoint(x: external.frame.midX + 120, y: external.frame.maxY - 20)
        await pause(0.8)
        require(b.expanded && externalIsland.panel.isVisible && !externalIsland.panel.ignoresMouseEvents,
                "a wider screen-based approach area opens the fully hidden panel")
        b.close()
        await pause(0.6)
        require(!b.expanded && !externalIsland.panel.isVisible, "manual close hides the external panel beneath a stationary pointer")
        pointer.x += 2
        await pause(0.4)
        require(!b.expanded, "tiny pointer jitter does not undo a manual close")
        pointer.x -= 24
        await pause(0.7)
        require(b.expanded && externalIsland.panel.isVisible, "moving within the approach area re-arms hover without requiring an invisible boundary exit")
        b.close()
        await pause(0.6)
        coordinator.samplePointer(at: NSPoint(x: external.frame.midX, y: external.frame.midY))
        coordinator.samplePointer(at: pointer)
        await pause(0.7)
        require(b.expanded, "mouse events catch a fast leave-and-return between polling samples")
        b.setExpanded(false)
        await pause(0.06)
        b.setExpanded(true)
        await pause(0.5)
        require(b.expanded && externalIsland.panel.isVisible && externalIsland.panel.alphaValue > 0.99,
                "a stale hide completion cannot dismiss a panel reopened during its closing animation")
        pointer = NSPoint(x: external.frame.midX, y: external.frame.midY)
        await pause(0.9)
        require(!externalIsland.panel.isVisible && externalIsland.panel.ignoresMouseEvents, "leaving removes the external panel completely")
        internalIsland.panel.orderOut(nil)
        coordinator.restorePresentations()
        require(internalIsland.panel.isVisible && !externalIsland.panel.isVisible, "Space or wake recovery restores the notch while keeping the external island hidden")
        pointer = NSPoint(x: external.frame.midX, y: external.frame.maxY - 1)
        await pause(0.8)
        require(b.expanded && !a.expanded, "hover at the external monitor's top center opens only its island")
        require(externalIsland.panel.frame.maxY == external.frame.maxY, "external island is attached to its own top edge")
        pointer = NSPoint(x: externalIsland.panel.frame.maxX - 15, y: externalIsland.panel.frame.minY + 10)
        await pause(0.7)
        require(b.expanded, "external island stays open across its content")
        pointer = NSPoint(x: builtIn.frame.midX, y: builtIn.frame.maxY - 41)
        await pause(0.9)
        require(a.expanded && !b.expanded, "moving to the built-in notch closes the external island and opens the built-in one")
        require(!externalIsland.panel.isVisible, "the external monitor's menu bar is uncovered after switching screens")
        a.pinned = true
        pointer = NSPoint(x: external.frame.midX, y: external.frame.maxY - 1)
        await pause(0.8)
        require(a.expanded && b.expanded, "a pinned island can remain open independently on the other screen")
        require(coordinator.preferredIsland() === externalIsland, "menu commands follow the pointer's display")
        a.pinned = false
        coordinator.closeOutside(pointer)
        await pause(0.4)
        require(!a.expanded && b.expanded, "outside click only dismisses unpinned panels outside the pointer")
        press(externalIsland.panel, "tab-Calendario")
        await pause(0.5)
        require(b.tab == .calendar && b.expanded && externalIsland.panel.frame.height == 204, "native calendar tab opens with room for a full month")
        capture(externalIsland.panel, to: output.appendingPathComponent("calendar-connect-external.png"))
        let originalMonth = data.calendar.month
        press(externalIsland.panel, "calendar-next")
        await pause(0.2)
        require(data.calendar.month > originalMonth && b.expanded, "native next-month control navigates without closing the island")
        press(externalIsland.panel, "calendar-today")
        await pause(0.2)
        require(data.calendar.systemCalendar.isDateInToday(data.calendar.selectedDate), "native Today control returns to today's agenda")
        let today = data.calendar.systemCalendar.startOfDay(for: Date())
        data.calendar.setPreview(entries: [
            CalendarEntry(id: "fixture1", title: "Revisión de diseño · prueba", calendarName: "Calendario de prueba", start: today.addingTimeInterval(10 * 3600), end: today.addingTimeInterval(11 * 3600), allDay: false, color: .systemBlue),
            CalendarEntry(id: "fixture2", title: "Entrega de prueba", calendarName: "Calendario de prueba", start: today, end: data.calendar.systemCalendar.date(byAdding: .day, value: 1, to: today)!, allDay: true, color: .systemGreen)
        ])
        await pause(0.2)
        capture(externalIsland.panel, to: output.appendingPathComponent("calendar-events-fixture.png"))
        data.calendar.setPreview(entries: [], status: .denied)
        await pause(0.2)
        capture(externalIsland.panel, to: output.appendingPathComponent("calendar-denied.png"))
        coordinator.reconcile([builtIn])
        require(coordinator.islands.count == 1 && !externalIsland.panel.isVisible && coordinator.islands[1] === internalIsland, "disconnect removes only that monitor's island")
        require(a.note == "Nota de prueba compartida" && a.focus.duration == 300, "screen removal preserves shared state")
        coordinator.reconcile([builtIn, external])
        await pause(0.8)
        require(coordinator.islands.count == 2 && coordinator.islands[2] !== externalIsland && coordinator.islands[2]!.model.expanded, "reconnecting creates a fresh island that responds to hover")
        let moved = IslandDisplay(id: 2, frame: NSRect(x: 5512, y: 4200, width: 1920, height: 1080))
        coordinator.reconcile([builtIn, moved])
        require(coordinator.islands[2]!.panel.frame.maxY == moved.frame.maxY, "rearranged monitor updates its top anchor")
        coordinator.reconcile([builtIn, moved, IslandDisplay(id: 3, frame: builtIn.frame)])
        require(coordinator.islands.count == 2 && coordinator.islands[3] == nil, "mirrored display rectangles do not create duplicate overlapping islands")
        coordinator.stop()
        data.stop()
        require(coordinator.islands.isEmpty, "all window trackers stop on shutdown")
        print("Calendar and multi-display verification complete; no real calendar access requested.")
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        Task { @MainActor in await run(output: output); exit(0) }
        app.run()
    }
}
