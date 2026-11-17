import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let data = IslandData()
    private lazy var displays = IslandDisplayCoordinator(data: data)
    private var status: NSStatusItem?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupKeyboardMenu()
        setupMenu()
        screenChanged()
        data.media.refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            let point = NSEvent.mouseLocation
            let clicked = event.type == .leftMouseDown || event.type == .rightMouseDown
            Task { @MainActor in
                if clicked { self?.displays.closeOutside(point) }
                else { self?.displays.samplePointer(at: point) }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if let island = self.displays.islands.values.first(where: { $0.panel === event.window }), event.keyCode == 53 {
                    island.model.close()
                    return nil
                }
            } else if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.displays.closeOutside(NSEvent.mouseLocation)
            } else { self.displays.samplePointer() }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        displays.stop()
        data.stop()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }

    @objc private func screenChanged() { displays.reconcile(NSScreen.screens.compactMap { IslandDisplay(screen: $0) }) }
    @objc private func spaceChanged() { screenChanged(); displays.restorePresentations() }
    @objc private func wake() { spaceChanged(); data.refreshPower(); data.phones.refresh(); data.calendar.refresh() }
    @objc private func toggle() {
        guard let island = displays.preferredIsland() else { return }
        if island.model.expanded { island.model.close() } else { island.model.setExpanded(true) }
    }
    @objc private func showNotes() {
        guard let island = displays.preferredIsland() else { return }
        island.model.select(.notes); island.model.pinned = true; island.model.setExpanded(true); island.panel.makeKey()
    }
    @objc private func showFiles() {
        guard let island = displays.preferredIsland() else { return }
        island.model.select(.files); island.model.setExpanded(true)
    }
    @objc private func showCalendar() {
        guard let island = displays.preferredIsland() else { return }
        island.model.select(.calendar); island.model.setExpanded(true)
    }
    @objc private func showClipboard() {
        guard let island = displays.preferredIsland() else { return }
        island.model.select(.clipboard); island.model.setExpanded(true)
    }
    @objc private func showShortcuts() {
        guard let island = displays.preferredIsland() else { return }
        island.model.select(.shortcuts); island.model.setExpanded(true)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func setupKeyboardMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Salir de ISLA", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem(title: "Edición", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edición")
        for (label, selector, key) in [("Deshacer", "undo:", "z"), ("Cortar", "cut:", "x"),
                                      ("Copiar", "copy:", "c"), ("Pegar", "paste:", "v"),
                                      ("Seleccionar todo", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: label, action: Selector(selector), keyEquivalent: key))
        }
        let redo = NSMenuItem(title: "Rehacer", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.insertItem(redo, at: 1)
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "ISLA")
        let menu = NSMenu()
        let title = NSMenuItem(title: "ISLA · Tu espacio, a mano", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        for (label, selector, key) in [("Mostrar / contraer", #selector(toggle), "i"),
                                      ("Nota rápida", #selector(showNotes), "n"),
                                      ("Bandeja de archivos", #selector(showFiles), ""),
                                      ("Calendario", #selector(showCalendar), ""),
                                      ("Portapapeles", #selector(showClipboard), ""),
                                      ("Atajos", #selector(showShortcuts), ""),
                                      ("Salir de ISLA", #selector(quit), "q")] {
            let entry = NSMenuItem(title: label, action: selector, keyEquivalent: key)
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        status = item
    }
}

@main
struct IslaEntry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") {
            selfTest()
            return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            _ = NSApplication.shared
            print("Available screens: \(NSScreen.screens.count)")
            print("Internal battery: \(BatteryReading.read().percent.map(String.init) ?? "unavailable")")
            print("Adjustable audio output: \(SystemAudio.read() != nil)")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
            render(to: CommandLine.arguments[index + 1])
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func render(to path: String) {
        let model = IslandModel(preview: true)
        model.expanded = true
        if CommandLine.arguments.contains("--compact") { model.expanded = false }
        if CommandLine.arguments.contains("--notched") { model.notchWidth = 180; model.notchHeight = 32 }
        if let i = CommandLine.arguments.firstIndex(of: "--tab"), CommandLine.arguments.count > i + 1,
           let tab = IslandTab(rawValue: CommandLine.arguments[i + 1]) { model.tab = tab }
        let preview: AnyView
        if CommandLine.arguments.contains("--presentation") {
            preview = AnyView(LiquidGlassPreview(model: model))
        } else {
            preview = AnyView(IslandView(model: model, media: model.media, snapshot: true))
        }
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { fputs("Unable to render preview\n", stderr); exit(1) }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: path)); print("Rendered \(path)") }
        catch { fputs("\(error)\n", stderr); exit(1) }
    }

    @MainActor private static func selfTest() {
        let start = Date(timeIntervalSince1970: 10_000)
        var clock = FocusClock()
        precondition(clock.label == "25:00")
        clock.toggle(now: start)
        clock.tick(now: start.addingTimeInterval(90))
        precondition(clock.label == "23:30")
        clock.toggle(now: start.addingTimeInterval(90))
        precondition(!clock.running && clock.remaining == 1410)
        clock.tick(now: start.addingTimeInterval(900))
        precondition(clock.remaining == 1410)
        clock.toggle(now: start.addingTimeInterval(900))
        precondition(clock.tick(now: start.addingTimeInterval(3000)))
        precondition(clock.completed && clock.label == "00:00")
        precondition(!clock.tick(now: start.addingTimeInterval(4000)))
        clock.select(minutes: 5)
        precondition(clock.label == "05:00" && !clock.completed)
        clock.toggle(now: start)
        precondition(clock.tick(now: start.addingTimeInterval(10_000)))
        clock.reset()
        precondition(clock.remaining == 300 && !clock.running && !clock.completed)
        print("PASS: timer start, pause, resume, elapsed sleep, completion once, preset, reset")
        let model = IslandModel(preview: true)
        model.notchWidth = 180
        model.notchHeight = 32
        precondition(model.compactWidth == model.notchWidth + 18 + model.compactSideWidth * 2)
        precondition(model.compactHeight == model.notchHeight + 1)
        precondition(model.toolbarHeight >= model.notchHeight)
        let one = URL(fileURLWithPath: "/tmp/isla-check-a.txt")
        let two = URL(fileURLWithPath: "/tmp/isla-check-b.txt")
        model.addFiles([one, one, two, URL(string: "https://example.com")!])
        precondition(model.files == [one, two])
        precondition(model.tab == .files && model.expanded)
        model.files.removeAll { $0 == one }
        precondition(model.files == [two])
        print("PASS: camera clearance, duplicate drops, local file filtering, shelf removal")
        let sample = TrackState(id: "test", title: "Track", playing: true, position: 10, duration: 60, sampledAt: start)
        precondition(sample.elapsed(at: start.addingTimeInterval(5)) == 15)
        precondition(sample.elapsed(at: start.addingTimeInterval(100)) == 60)
        var paused = sample
        paused.playing = false
        precondition(paused.elapsed(at: start.addingTimeInterval(20)) == 10)
        precondition(TrackState.timeLabel(125.9) == "2:05")
        precondition(TrackState.timeLabel(.nan) == "—:—")
        precondition(TrackState.timeLabel(1e100) == "99:59:59")
        let descriptor = NSAppleEventDescriptor.list()
        let fields: [NSAppleEventDescriptor] = [.init(string: "playing"), .init(string: "id-1"), .init(string: "Track"), .init(string: "Artist"), .init(string: "Album"), .init(double: 250.85), .init(double: 20.5), .init(string: "")]
        for (index, value) in fields.enumerated() { descriptor.insert(value, at: index + 1) }
        let decoded = PlayerScript.decode(descriptor, at: start)!
        precondition(decoded.id == TrackState.identity("id-1", title: "Track", artist: "Artist", album: "Album") && decoded.album == "Album" && decoded.duration == 250.85 && decoded.position == 20.5 && decoded.playing)
        precondition(TrackState.identity("0", title: "First", artist: "Artist", album: "Album") != TrackState.identity("0", title: "Second", artist: "Artist", album: "Album"))
        print("PASS: playback interpolation, pause, duration clamp, time labels, metadata decoding")
        let lines = LRCParser.parse("[ar:ISLA test]\n[offset:500]\n[00:02.50][00:04.500]Texto original\n[00:03.00]\n[00:99.00]Invalid\n[00:06]Final")
        precondition(lines.map(\.time) == [2, 2.5, 4, 5.5])
        precondition(lines[1].text.isEmpty)
        precondition(LRCParser.activeIndex(in: lines, at: 1.9) == nil)
        precondition(LRCParser.activeIndex(in: lines, at: 4.1) == 2)
        precondition(LRCParser.activeIndex(in: lines, at: 2) == 0)
        precondition(LRCParser.activeIndex(in: lines, at: .nan) == nil)
        let lyricTrack = TrackState(id: "lyric-check", title: "Canción", artist: "Artista & Invitado", album: "Disco", duration: 123.4)
        let record = LyricsRecord(id: 1, trackName: "CANCION", artistName: "Artista", albumName: "Disco", duration: 124, instrumental: false, syncedLyrics: nil)
        precondition(record.matches(lyricTrack))
        var differentVersion = lyricTrack
        differentVersion.duration = 140
        precondition(!record.matches(differentVersion))
        model.tab = .music
        model.expanded = true
        precondition(model.width == 740 && model.height == 156)
        print("PASS: timestamp fractions, repeated lines, gaps, offset, seek backwards, track matching, horizontal geometry")
        for percent in 0...100 { precondition(BatteryReading.percentage(current: Double(percent), maximum: 100) == percent) }
        precondition(BatteryReading.percentage(current: 58, maximum: 100) == 58)
        precondition(BatteryReading.percentage(current: 3170, maximum: 5000) == 63)
        precondition(BatteryReading.percentage(current: -1, maximum: 100) == nil)
        precondition(BatteryReading.percentage(current: 80, maximum: 0) == nil)
        precondition(BatteryReading.percentage(current: .nan, maximum: 100) == nil)
        let plugged = BatteryReading(percent: 80, charging: false, pluggedIn: true)
        precondition(plugged.status == "Conectado · sin cargar" && plugged.fraction == 0.8)
        precondition(BatteryReading(percent: 100, pluggedIn: true).status == "Carga completa")
        let phoneBattery = IPhoneReading.battery(from: ["BatteryCurrentCapacity": 69, "BatteryIsCharging": true, "ExternalConnected": true])!
        precondition(phoneBattery.percent == 69 && phoneBattery.charging && phoneBattery.pluggedIn)
        precondition(IPhoneReading.battery(from: [:]) == nil)
        precondition(IPhoneReading.battery(from: ["BatteryCurrentCapacity": true]) == nil)
        precondition(IPhoneReading.battery(from: ["BatteryCurrentCapacity": 101]) == nil)
        let service = IPhoneBatteryService()
        let phone = IPhoneReading(id: "test", name: "iPhone de prueba", battery: phoneBattery, state: .ready, sampledAt: start)
        service.apply([phone])
        precondition(service.devices.first?.battery?.percent == 69)
        service.expire(at: start.addingTimeInterval(46))
        precondition(service.devices.first?.battery == nil && service.devices.first?.state == .unavailable)
        service.apply([IPhoneReading(id: "test", name: "iPhone de prueba", battery: nil, state: .needsTrust)])
        precondition(service.devices.first?.battery == nil)
        service.apply([])
        precondition(service.devices.isEmpty)
        print("PASS: all integer battery percentages, rounding, invalid readings, actual fill, charging states, phone decoding, stale reading removal, disconnect")
        var connections = IPhoneConnections<String>()
        connections.insert("wireless", id: "phone", transport: .wifi, token: 2)
        connections.insert("wired", id: "phone", transport: .usb, token: 1)
        precondition(connections.deviceIDs.count == 1)
        precondition(connections.candidates(for: "phone").map { $0.0.transport } == [.usb, .wifi])
        connections.remove(token: 1)
        precondition(connections.candidates(for: "phone").map { $0.0.transport } == [.wifi])
        connections.insert("reconnected", id: "phone", transport: .usb, token: 3)
        connections.remove(token: 1)
        precondition(connections.candidates(for: "phone").count == 2)
        connections.remove(token: 2)
        precondition(connections.candidates(for: "phone").map { $0.0.transport } == [.usb])
        connections.insert("wifi-after-reconnect", id: "phone", transport: .wifi, token: 4)
        connections.insert("second-phone", id: "other", transport: .wifi, token: 5)
        precondition(connections.deviceIDs.count == 2)
        connections.remove(token: 4)
        precondition(connections.candidates(for: "other").count == 1)
        connections.remove(token: 3)
        precondition(!connections.deviceIDs.contains("phone"))
        var wireless = phone
        wireless.transport = .wifi
        wireless.battery = BatteryReading(percent: 84, charging: false, pluggedIn: false)
        precondition(wireless.status == "Con batería")
        service.apply([wireless])
        service.expire(at: start.addingTimeInterval(46))
        precondition(service.devices.first?.battery == nil && service.devices.first?.status == "Sin respuesta por Wi-Fi")
        print("PASS: USB/Wi-Fi deduplication, preference, route handover, late disconnects, independent phones, wireless discharge and expiry")
    }
}
