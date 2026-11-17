import AppKit
import CoreGraphics

struct PanelSample { let frame: CGRect; let alpha: Double }

@main struct HiddenDisplayLiveCheck {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.isla.prototype")
        guard apps.count == 1, let app = apps.first,
              let primary = NSScreen.screens.first,
              let builtIn = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let external = NSScreen.screens.first(where: { $0.safeAreaInsets.top == 0 }) else {
            print("FAIL: one ISLA instance and both displays required"); exit(2)
        }
        // Opt-in desktop test: moves the cursor, never clicks, then restores it.
        let saved = NSEvent.mouseLocation
        func move(_ point: NSPoint) {
            let result = CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primary.frame.maxY - point.y))
            guard result == .success else {
                print("FAIL: cursor movement unavailable (\(result.rawValue))"); exit(2)
            }
        }
        func panels() -> [PanelSample] {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String:Any]] ?? []
            return list.compactMap { item in
                guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                      let data = item[kCGWindowBounds as String] as? [String:Any],
                      let frame = CGRect(dictionaryRepresentation: data as CFDictionary), frame.width > 60, frame.height < 350 else { return nil }
                return PanelSample(frame: frame, alpha: (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? -1)
            }
        }
        func panel(for screen: NSScreen, in samples: [PanelSample]) -> PanelSample? {
            samples.first { abs($0.frame.midX - screen.frame.midX) < 3 }
        }
        var maxTopDrift = 0.0
        var samples = 0
        func sample(_ label: String, at point: NSPoint, internalOpen: Bool, externalOpen: Bool) async -> Bool {
            move(point)
            var pointerMoved = 0
            for _ in 0..<65 {
                try? await Task.sleep(nanoseconds: 16_000_000)
                let actual = NSEvent.mouseLocation
                if hypot(actual.x - point.x, actual.y - point.y) > 3 { pointerMoved += 1 }
                let all = panels()
                for screen in [builtIn, external] {
                    if let p = panel(for: screen, in: all) {
                        maxTopDrift = max(maxTopDrift, abs(p.frame.minY - (primary.frame.maxY - screen.frame.maxY)))
                        samples += 1
                    }
                }
            }
            let all = panels()
            let a = panel(for: builtIn, in: all), b = panel(for: external, in: all)
            let internalOK = a != nil && a!.alpha > 0.99 && (a!.frame.width > 500) == internalOpen
            let externalOK = externalOpen ? (b != nil && b!.frame.width > 500 && b!.alpha > 0.99) : b == nil
            let pass = internalOK && externalOK && pointerMoved == 0
            print("\(pass ? "PASS" : "FAIL"): \(label), builtIn=\(String(describing: a?.frame)), external=\(String(describing: b?.frame)), externalAlpha=\(String(describing: b?.alpha)), unexpectedPointerSamples=\(pointerMoved)")
            return pass
        }
        let outside = NSPoint(x: external.frame.midX, y: external.frame.midY)
        let externalTop = NSPoint(x: external.frame.midX, y: external.frame.maxY - 1)
        let notch = NSPoint(x: builtIn.frame.midX, y: builtIn.frame.maxY - builtIn.safeAreaInsets.top - 9)
        var results: [Bool] = []
        results.append(await sample("external completely absent", at: outside, internalOpen: false, externalOpen: false))
        results.append(await sample("wide approach, 120 points from center", at: NSPoint(x: external.frame.midX + 120, y: external.frame.maxY - 20), internalOpen: false, externalOpen: true))
        results.append(await sample("external left content", at: NSPoint(x: external.frame.midX - 250, y: external.frame.maxY - 80), internalOpen: false, externalOpen: true))
        results.append(await sample("external right content", at: NSPoint(x: external.frame.midX + 250, y: external.frame.maxY - 80), internalOpen: false, externalOpen: true))
        results.append(await sample("physical notch opens, external disappears", at: notch, internalOpen: true, externalOpen: false))
        results.append(await sample("exit both", at: outside, internalOpen: false, externalOpen: false))
        results.append(await sample("nearby menu bar stays clear outside trigger", at: NSPoint(x: external.frame.midX + 180, y: external.frame.maxY - 10), internalOpen: false, externalOpen: false))
        results.append(await sample("external approach from below", at: NSPoint(x: external.frame.midX, y: external.frame.maxY - 36), internalOpen: false, externalOpen: true))
        results.append(await sample("external hidden again", at: outside, internalOpen: false, externalOpen: false))
        results.append(await sample("external edge reopens from hidden", at: externalTop, internalOpen: false, externalOpen: true))
        results.append(await sample("external hidden after third opening", at: outside, internalOpen: false, externalOpen: false))
        results.append(await sample("notch reopens", at: notch, internalOpen: true, externalOpen: false))
        results.append(await sample("final menu bar uncovered", at: outside, internalOpen: false, externalOpen: false))
        results.append(await sample("exact external top pixel opens from hidden", at: NSPoint(x: external.frame.midX, y: external.frame.maxY), internalOpen: false, externalOpen: true))
        results.append(await sample("exact top edge stays open over left content", at: NSPoint(x: external.frame.midX - 250, y: external.frame.maxY), internalOpen: false, externalOpen: true))
        results.append(await sample("exact top edge stays open over right content", at: NSPoint(x: external.frame.midX + 250, y: external.frame.maxY), internalOpen: false, externalOpen: true))
        results.append(await sample("exact built-in top pixel opens and external hides", at: NSPoint(x: builtIn.frame.midX, y: builtIn.frame.maxY), internalOpen: true, externalOpen: false))
        results.append(await sample("exit both after exact-edge openings", at: outside, internalOpen: false, externalOpen: false))
        move(saved)
        print("MOTION: samples=\(samples), maximum top drift=\(maxTopDrift)")
        print("RESULT: \(results.filter { $0 }.count)/\(results.count)")
        if results.contains(false) || maxTopDrift >= 1 { exit(2) }
    }
}
