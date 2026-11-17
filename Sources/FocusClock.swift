import Foundation

struct FocusClock {
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var deadline: Date?
    private(set) var completed = false

    var running: Bool { deadline != nil }
    var progress: Double { duration > 0 ? 1 - remaining / duration : 0 }
    var label: String {
        let seconds = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    mutating func select(minutes: Int) {
        duration = TimeInterval(minutes * 60)
        reset()
    }

    mutating func toggle(now: Date = Date()) {
        if running {
            _ = tick(now: now)
            deadline = nil
        } else {
            if remaining <= 0 { remaining = duration }
            completed = false
            deadline = now.addingTimeInterval(remaining)
        }
    }

    mutating func reset() {
        deadline = nil
        remaining = duration
        completed = false
    }

    @discardableResult
    mutating func tick(now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        remaining = max(0, min(duration, deadline.timeIntervalSince(now)))
        if remaining <= 0 {
            self.deadline = nil
            completed = true
            return true
        }
        return false
    }
}
