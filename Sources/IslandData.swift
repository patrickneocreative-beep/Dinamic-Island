import AppKit
import Combine
import IOKit.ps

/// One data source for all displays; panel expansion and pointer state stay local.
@MainActor
final class IslandData: ObservableObject {
    @Published var battery = BatteryReading()
    @Published var volume: Double = 0.5
    @Published var canChangeVolume = false
    @Published var focus = FocusClock()
    @Published var now = Date()
    @Published var note: String {
        didSet { if persistenceEnabled { defaults.set(note, forKey: "note") } }
    }
    @Published var files: [URL] {
        didSet { if persistenceEnabled { defaults.set(files.map(\.path), forKey: "files") } }
    }
    let media: MediaService
    let lyrics = LyricsService()
    let phones = IPhoneBatteryService()
    let calendar: CalendarService
    let clipboard: ClipboardService
    let shortcuts: ShortcutsService
    private(set) var lastClipboardCapture: Date?
    private(set) var menuTrackingDepth = 0
    var trackingMenu: Bool { menuTrackingDepth > 0 }
    private var menuObservers: [NSObjectProtocol] = []
    let persistenceEnabled: Bool
    var anyPanelExpanded: () -> Bool = { false }
    var onFocusCompletion: (() -> Void)?
    private let defaults: UserDefaults
    private var timer: Timer?
    private var powerNotifications: CFRunLoopSource?
    private var ticks = 0

    init(preview: Bool = false, clipboard: ClipboardService? = nil, shortcuts: ShortcutsService? = nil) {
        defaults = .standard
        persistenceEnabled = !preview
        media = MediaService(preview: preview)
        calendar = CalendarService(preview: preview)
        self.clipboard = clipboard ?? ClipboardService(preview: preview)
        self.shortcuts = shortcuts ?? ShortcutsService(preview: preview)
        note = preview ? "Una idea, antes de que se te escape." : defaults.string(forKey: "note") ?? ""
        files = preview ? [] : (defaults.stringArray(forKey: "files") ?? []).map { URL(fileURLWithPath: $0) }
        self.clipboard.onCapture = { [weak self] date in self?.lastClipboardCapture = date }
        for (name, delta) in [(NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1)] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuTrackingDepth = max(0, self.menuTrackingDepth + delta)
                }
            })
        }
        media.onTrackChange = { [weak self] in
            guard let self else { return }
            self.lyrics.update(track: self.media.track)
        }
        guard !preview else {
            battery = BatteryReading(percent: 84, charging: true, pluggedIn: true)
            canChangeVolume = true
            return
        }
        refreshSystem()
        startPowerNotifications()
        phones.start()
        self.clipboard.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        ticks += 1
        if anyPanelExpanded() || ticks % 4 == 0 { now = Date() }
        if focus.tick(now: now) {
            NSSound(named: "Glass")?.play()
            onFocusCompletion?()
        }
        if ticks % (anyPanelExpanded() || media.track.exists ? 8 : 20) == 0 {
            media.refresh(); lyrics.update(track: media.track)
        }
        if ticks % 20 == 0 { refreshSystem(); phones.expire() }
        if ticks % 240 == 0 { calendar.refresh() }
    }

    func refreshPower() { battery = BatteryReading.read() }

    private func startPowerNotifications() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let data = Unmanaged<IslandData>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak data] in data?.refreshPower() }
        }
        powerNotifications = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerNotifications { CFRunLoopAddSource(CFRunLoopGetMain(), powerNotifications, .commonModes) }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let powerNotifications { CFRunLoopSourceInvalidate(powerNotifications) }
        powerNotifications = nil
        phones.stop()
        calendar.stop()
        clipboard.stop()
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers.removeAll()
    }

    private func refreshSystem() {
        refreshPower()
        let reading = SystemAudio.read()
        canChangeVolume = reading != nil
        if let reading { volume = reading }
    }
}
