import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

enum IslandTab: String, CaseIterable {
    case home = "Inicio", music = "Música", focus = "Foco", notes = "Notas", files = "Archivos", calendar = "Calendario", clipboard = "Portapapeles", shortcuts = "Atajos"
    var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .music: "waveform"
        case .focus: "timer"
        case .notes: "note.text"
        case .files: "tray.fill"
        case .calendar: "calendar"
        case .clipboard: "doc.on.clipboard"
        case .shortcuts: "square.stack.3d.up.fill"
        }
    }
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var tab = IslandTab.music
    let data: IslandData
    var battery: BatteryReading { get { data.battery } set { data.battery = newValue } }
    var volume: Double { get { data.volume } set { data.volume = newValue } }
    var canChangeVolume: Bool { get { data.canChangeVolume } set { data.canChangeVolume = newValue } }
    var focus: FocusClock { get { data.focus } set { data.focus = newValue } }
    var now: Date { get { data.now } set { data.now = newValue } }
    var note: String { get { data.note } set { data.note = newValue } }
    var files: [URL] { get { data.files } set { data.files = newValue } }
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 0
    @Published var dropTargeted = false
    @Published var shortcutInput: URL?
    lazy var fileActions = FileActions(model: self)
    var fileDragInProgress: () -> Bool = {
        NSEvent.pressedMouseButtons & 1 != 0 && NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
    private var consumedClipboardCapture: Date?
    var interacting = false
    weak var panel: IslandPanel?
    var resize: (() -> Void)?
    var pointerIsWithinPanel: (() -> Bool)?
    var pointerLocation: (() -> NSPoint?)?
    private(set) var pointerInside = false
    var media: MediaService { data.media }
    var lyrics: LyricsService { data.lyrics }
    var phones: IPhoneBatteryService { data.phones }
    var calendar: CalendarService { data.calendar }
    var resignEditing: (() -> Void)?
    private var changes: AnyCancellable?
    private var persistenceEnabled: Bool { data.persistenceEnabled }
    private var opening: DispatchWorkItem?
    private var closing: DispatchWorkItem?
    private var suppressReopenUntilExit = false
    private var closedAtPointer: NSPoint?

    var hoverDiagnosticState: [String: Any] {
        ["expanded": expanded, "suppressed": suppressReopenUntilExit, "opening": opening != nil,
         "closing": closing != nil, "inside": pointerInside, "pinned": pinned, "interacting": interacting]
    }

    var hasNotch: Bool { notchHeight > 0 }
    var compactSideWidth: CGFloat { 70 }
    var compactWidth: CGFloat { hasNotch ? notchWidth + 18 + compactSideWidth * 2 : compactSideWidth * 2 + 28 }
    var compactHeight: CGFloat { hasNotch ? notchHeight + 1 : 28 }
    var topInset: CGFloat { hasNotch ? 0 : 10 }
    var toolbarHeight: CGFloat { hasNotch ? max(30, notchHeight + 2) : 24 }
    var contentHeight: CGFloat { [.calendar, .clipboard, .shortcuts, .files].contains(tab) ? 150 : 102 }
    var expandedWidth: CGFloat { max(740, notchWidth + 555) }
    var width: CGFloat { expanded ? expandedWidth : compactWidth }
    var height: CGFloat { expanded ? topInset + toolbarHeight + 8 + contentHeight + 12 : compactHeight }

    init(preview: Bool = false, data: IslandData? = nil) {
        self.data = data ?? IslandData(preview: preview)
        changes = self.data.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func setExpanded(_ value: Bool) {
        cancelOpening()
        cancelClosing()
        if value { resetHoverSuppression() }
        guard expanded != value else { return }
        if value && persistenceEnabled { refreshPower(); phones.refresh() }
        // The panel owns geometry animation; a second SwiftUI spring makes it
        // detach from the top edge while the native window is still resizing.
        expanded = value
        resize?()
    }

    func hover(_ inside: Bool, at position: NSPoint? = nil) {
        pointerInside = inside
        if inside {
            cancelClosing()
            if suppressReopenUntilExit, let origin = closedAtPointer, let point = position ?? pointerLocation?(),
               hypot(point.x - origin.x, point.y - origin.y) >= 12 {
                resetHoverSuppression()
            }
            guard !expanded, !suppressReopenUntilExit, opening == nil else { return }
            let pending = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.opening = nil
                guard self.pointerIsWithinPanel?() ?? self.pointerInside else { return }
                self.openFromHover()
            }
            opening = pending
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: pending)
            return
        }
        resetHoverSuppression()
        cancelOpening()
        guard expanded, !pinned, !interacting, !data.trackingMenu, !dropTargeted else { cancelClosing(); return }
        guard !(pointerIsWithinPanel?() ?? false), closing == nil else { return }
        let pending = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closing = nil
            guard !self.pinned, !self.interacting, !self.data.trackingMenu, !self.dropTargeted,
                  !(self.pointerIsWithinPanel?() ?? self.pointerInside) else { return }
            self.setExpanded(false)
        }
        closing = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: pending)
    }

    func openFromHover(now: Date = Date()) {
        guard !expanded else { return }
        if fileDragInProgress() { select(.files) }
        else if data.clipboard.enabled, !data.clipboard.entries.isEmpty, let captured = data.lastClipboardCapture,
                captured != consumedClipboardCapture, now.timeIntervalSince(captured) >= 0,
                now.timeIntervalSince(captured) <= 25 {
            consumedClipboardCapture = captured
            select(.clipboard)
        }
        setExpanded(true)
    }

    private func cancelOpening() { opening?.cancel(); opening = nil }
    private func cancelClosing() { closing?.cancel(); closing = nil }

    func resetHoverSuppression() {
        suppressReopenUntilExit = false
        closedAtPointer = nil
    }

    func close() {
        suppressReopenUntilExit = true
        closedAtPointer = pointerLocation?()
        pinned = false
        interacting = false
        resignEditing?()
        setExpanded(false)
    }

    func chooseLyricsFile() {
        guard media.track.exists else { return }
        interacting = true
        let track = media.track
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar letra"
        panel.message = "Elige un archivo LRC con tiempos para esta canción."
        panel.begin { [weak self] response in
            guard let self else { return }
            defer { self.interacting = false }
            guard response == .OK, let url = panel.url else { return }
            if let text = try? String(contentsOf: url, encoding: .utf8), self.lyrics.importLRC(text, for: track) { return }
            let alert = NSAlert()
            alert.messageText = "No se pudo leer la letra"
            alert.informativeText = "Usa un archivo LRC en UTF-8 con tiempos como [00:12.50] al inicio de cada línea."
            alert.runModal()
        }
    }

    func select(_ tab: IslandTab) {
        if tab == .shortcuts { data.shortcuts.refresh() }
        if tab == .calendar { calendar.refresh() }
        if tab == .home && persistenceEnabled { refreshPower(); phones.refresh() }
        withAnimation(.easeInOut(duration: 0.18)) { self.tab = tab }
        if expanded { resize?() }
    }

    func useInShortcut(_ url: URL) { shortcutInput = url; select(.shortcuts) }

    func setVolume(_ value: Double) {
        volume = value
        SystemAudio.set(value)
    }

    func connectCalendar() {
        interacting = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.calendar.connect()
            self.interacting = false
        }
    }

    func chooseFiles() {
        interacting = true
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Añadir a ISLA"
        panel.message = "Los archivos se quedan en su ubicación original."
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            if response == .OK { self.addFiles(panel.urls) }
            self.interacting = false
        }
    }

    func showIPhoneWiFiHelp() {
        interacting = true
        defer { interacting = false }
        let alert = NSAlert()
        alert.messageText = "Tu iPhone por Wi-Fi"
        alert.informativeText = "La primera vez, conecta el iPhone por USB y autoriza la confianza. En Finder, selecciona el iPhone → General → Mostrar este iPhone al estar en Wi-Fi y pulsa Aplicar.\n\nDespués puedes retirar el cable. Mantén ambos equipos en la misma red y permite el acceso a la red local si macOS lo solicita. ISLA mostrará la batería cuando el iPhone esté disponible."
        alert.addButton(withTitle: "Entendido")
        alert.addButton(withTitle: "Abrir Finder")
        if alert.runModal() == .alertSecondButtonReturn,
           let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            NSWorkspace.shared.openApplication(at: finder, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func addFiles(_ urls: [URL], reveal: Bool = true) {
        var existing = Set(files.map(\.standardizedFileURL))
        for url in urls where url.isFileURL {
            let normalized = url.standardizedFileURL
            if existing.insert(normalized).inserted { files.append(normalized) }
        }
        select(.files)
        if reveal { setExpanded(true) }
    }

    func drop(_ providers: [NSItemProvider]) -> Bool {
        let valid = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in valid {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = item as? URL }
                if let url { Task { @MainActor in
                    guard let self else { return }
                    self.addFiles([url], reveal: self.pointerInside || self.expanded)
                } }
            }
        }
        return !valid.isEmpty
    }

    func openFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let alert = NSAlert()
            alert.messageText = "Este archivo cambió de ubicación"
            alert.informativeText = "Vuelve a añadirlo desde su nueva ubicación. Quitar el acceso de ISLA no borra el archivo."
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshPower() { data.refreshPower() }
    func stopServices() { data.stop() }

    func stopInteraction() {
        cancelOpening()
        cancelClosing()
        pointerIsWithinPanel = nil
        pointerLocation = nil
        resize = nil
        resignEditing = nil
    }
}
