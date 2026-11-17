import AppKit
import SwiftUI

@main struct VerifyPower {
    @MainActor static func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    @MainActor static func capture(_ model: IslandModel, to url: URL) async {
        let panel = NSPanel(contentRect: NSRect(x: 5000, y: 5000, width: model.width, height: model.height), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: IslandView(model: model, media: model.media))
        panel.contentView = view
        panel.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        await pause(0.4)
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        print("RENDER: \(url.lastPathComponent), \(view.bounds.size)")
        panel.close()
    }

    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let requiresWiFi = CommandLine.arguments.contains("--require-wifi")
        let renderStates = CommandLine.arguments.contains("--render-states")
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = IslandModel(preview: renderStates)
        model.notchWidth = 185; model.notchHeight = 32
        model.select(.home); model.setExpanded(true)
        Task { @MainActor in
            if renderStates {
                model.refreshPower()
                model.phones.apply([IPhoneReading(id: "fixture", name: "iPhone de prueba", battery: BatteryReading(percent: 85), state: .ready, transport: .wifi)])
                await capture(model, to: output.appendingPathComponent("wifi-preview.png"))
                model.phones.apply([IPhoneReading(id: "fixture", name: "iPhone de prueba", battery: BatteryReading(percent: 85, charging: true, pluggedIn: true), state: .ready, transport: .wifi)])
                await capture(model, to: output.appendingPathComponent("wifi-charging-preview.png"))
                model.phones.apply([IPhoneReading(id: "fixture", name: "iPhone de prueba", battery: nil, state: .unavailable, transport: .wifi)])
                await capture(model, to: output.appendingPathComponent("wifi-unavailable-preview.png"))
                model.phones.apply([])
                await capture(model, to: output.appendingPathComponent("wifi-setup-preview.png"))
                print("PASS: native layout states rendered with clearly named test phone; no hardware reading claimed")
                exit(0)
            }
            for _ in 0..<120 {
                await pause(0.25)
                if model.phones.devices.contains(where: { $0.state == .ready }) { break }
            }
            model.refreshPower()
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "batt"]
            process.standardOutput = pipe
            try! process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let system = String(data: data, encoding: .utf8)!
            let regex = try! NSRegularExpression(pattern: #"(\d+)%;"#)
            let range = NSRange(system.startIndex..., in: system)
            let match = regex.firstMatch(in: system, range: range)!
            let expected = Int((system as NSString).substring(with: match.range(at: 1)))!
            precondition(model.battery.percent == expected)
            print("PASS: Mac reading matches pmset: \(expected)%; charging=\(model.battery.charging), pluggedIn=\(model.battery.pluggedIn), fill=\(model.battery.fraction)")
            print("PHONE SERVICE: available=\(model.phones.available), devices=\(model.phones.devices.count)")
            guard let phone = model.phones.devices.first(where: { $0.state == .ready }) else {
                for item in model.phones.devices { print("PHONE STATE: \(item.state)") }
                print("FAIL: no readable iPhone for hardware verification")
                model.stopServices(); exit(2)
            }
            print("PASS: real \(phone.transport.label) iPhone: \(phone.name), \(phone.battery!.percent!)%, charging=\(phone.battery!.charging), pluggedIn=\(phone.battery!.pluggedIn)")
            if requiresWiFi { precondition(phone.transport == .wifi, "Expected an actual wireless connection") }
            await capture(model, to: output.appendingPathComponent("power-live.png"))
            await pause(11.0)
            model.phones.refresh()
            for _ in 0..<40 {
                await pause(0.25)
                if model.phones.devices.first?.sampledAt ?? .distantPast > phone.sampledAt { break }
            }
            precondition(model.phones.devices.first!.sampledAt > phone.sampledAt)
            if requiresWiFi { precondition(model.phones.devices.first!.transport == .wifi) }
            print("SECOND SAMPLE: \(model.phones.devices.first!.battery?.percent ?? -1)%, transport=\(model.phones.devices.first!.transport.label)")
            print("PASS: iPhone refreshed in background without blocking the native view")
            model.stopServices()
            await pause(0.3)
            let preview = IslandModel(preview: true)
            preview.notchWidth = 185; preview.notchHeight = 32; preview.expanded = true; preview.tab = .home
            preview.battery = model.battery
            await capture(preview, to: output.appendingPathComponent("power-no-phone.png"))
            preview.phones.apply([IPhoneReading(id: "fixture", name: "iPhone de prueba", battery: nil, state: .needsTrust)])
            await capture(preview, to: output.appendingPathComponent("power-needs-trust.png"))
            exit(0)
        }
        app.run()
    }
}
