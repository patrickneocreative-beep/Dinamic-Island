import AppKit
import SwiftUI

@main struct VerifyPresentation {
    @MainActor static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    static func check(_ value: Bool, _ message: String) {
        guard value else { print("FAIL: \(message)"); exit(2) }
        print("PASS: \(message)")
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        Task { @MainActor in
            let model = IslandModel(preview: true)
            model.notchWidth = 185
            model.notchHeight = 32
            model.battery = BatteryReading(percent: 80, charging: false, pluggedIn: true)
            let phone = IPhoneReading(id: "fixture", name: "iPhone de prueba", battery: BatteryReading(percent: 100, charging: true, pluggedIn: true), state: .ready)
            let macOnly = CompactBatteryState(mac: model.battery, phones: [])
            check(!macOnly.isPhone && macOnly.percentage == "80%" && !macOnly.charging, "Mac percentage and plugged-but-not-charging state")
            let connected = CompactBatteryState(mac: model.battery, phones: [phone])
            check(connected.isPhone && connected.percentage == "100%" && connected.charging, "connected iPhone takes priority and shows charging")
            var unavailable = phone
            unavailable.state = .unavailable
            let unknown = CompactBatteryState(mac: model.battery, phones: [unavailable])
            check(unknown.isPhone && unknown.percentage == "—" && !unknown.charging, "unavailable phone never shows stale percentage or Mac percentage under an iPhone icon")
            let another = IPhoneReading(id: "second", name: "Otro iPhone de prueba", battery: BatteryReading(percent: 42, charging: false, pluggedIn: false), state: .ready, transport: .wifi)
            check(CompactBatteryState(mac: model.battery, phones: [unavailable, another]).percentage == "42%", "a readable phone is preferred when multiple phones are present")
            check(model.compactWidth == 343 && model.compactHeight == 33, "compact status keeps the camera height and clear central area")

            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.animationBehavior = .none
            let host = IslandHostingView(model: model, media: model.media)
            window.contentView = host
            @MainActor func frame() -> NSRect { NSRect(x: 5000 - model.width / 2, y: 5000 - model.height, width: model.width, height: model.height) }
            window.setFrame(frame(), display: true)
            window.orderFrontRegardless()
            model.resize = { IslandWindowMotion.resize(window, to: frame(), animated: true) }
            check(host.sizingOptions.isEmpty && host.safeAreaRegions.isEmpty, "hosting view does not impose a second resize or a safe-area gap")

            @MainActor func capture(_ name: String) {
                host.layoutSubtreeIfNeeded()
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            }
            var track = TrackState(id: "fixture-song", title: "Canción de prueba", artist: "ISLA", playing: true, duration: 180)
            model.media.setPreview(track: track, player: .music, artwork: nil)
            await pause(0.3)
            capture("compact-mac-playing")
            model.phones.apply([phone])
            await pause(0.2)
            capture("compact-iphone-charging")
            track.playing = false
            model.media.setPreview(track: track, player: .music, artwork: nil)
            await pause(0.2)
            capture("compact-paused")
            model.phones.apply([unavailable])
            await pause(0.2)
            capture("compact-iphone-unavailable")
            model.phones.apply([])
            check(CompactBatteryState(mac: model.battery, phones: model.phones.devices).percentage == "80%", "disconnect returns immediately to the Mac")
            model.media.setPreview(track: TrackState(), player: .music, artwork: nil)
            await pause(0.2)
            capture("compact-idle")
            model.tab = .home

            var frames: [[String: Double]] = []
            var maxTopDrift: CGFloat = 0
            var maxCenterDrift: CGFloat = 0
            var transparentTopSamples = 0
            var sampledWidths = Set<Int>()
            for cycle in 0..<4 {
                model.setExpanded(cycle % 2 == 0)
                for step in 0..<25 {
                    await pause(0.016)
                    host.layoutSubtreeIfNeeded()
                    let f = window.frame
                    maxTopDrift = max(maxTopDrift, abs(f.maxY - 5000))
                    maxCenterDrift = max(maxCenterDrift, abs(f.midX - 5000))
                    sampledWidths.insert(Int(f.width))
                    frames.append(["cycle": Double(cycle), "step": Double(step), "width": f.width, "height": f.height, "top": f.maxY, "center": f.midX])
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    for x in [bitmap.pixelsWide / 4, bitmap.pixelsWide / 2, bitmap.pixelsWide * 3 / 4] {
                        if (bitmap.colorAt(x: x, y: 0)?.alphaComponent ?? 0) < 0.99 { transparentTopSamples += 1 }
                    }
                    if step % 3 == 0 {
                        try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(String(format: "motion-%02d-%02d.png", cycle, step)))
                    }
                }
                check(abs(window.frame.width - model.width) < 1 && abs(window.frame.height - model.height) < 1, "animation reaches its final dimensions, cycle \(cycle)")
            }
            print("MOTION: \(frames.count) samples, \(sampledWidths.count) distinct widths, top drift \(maxTopDrift), center drift \(maxCenterDrift), transparent top samples \(transparentTopSamples)")
            check(sampledWidths.count > 8, "resize has intermediate frames rather than jumping between endpoints")
            // Native window coordinates are rounded to pixels; an odd compact
            // width can shift its reported midpoint by at most one screen point.
            check(maxTopDrift < 1 && maxCenterDrift <= 1, "top stays attached and horizontal center stays within native pixel rounding")
            check(transparentTopSamples == 0, "rendered panel has no transparent strip along its top edge during animation")
            try! JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("motion.json"))
            // A fast reversal must settle at the last requested state.
            model.setExpanded(true)
            await pause(0.09)
            model.setExpanded(false)
            await pause(0.5)
            check(abs(window.frame.width - model.compactWidth) < 1 && abs(window.frame.maxY - 5000) < 1, "interrupted animation settles closed and attached")
            model.resize = nil
            window.close()
            print("Presentation verification complete; fixture data only.")
            exit(0)
        }
        app.run()
    }
}
