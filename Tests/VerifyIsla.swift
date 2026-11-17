import AppKit
import SwiftUI

private final class VerificationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@main struct VerifyIsla {
    @MainActor static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @MainActor static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("FAIL: \(message)"); exit(2) }
        print("PASS: \(message)")
    }

    @MainActor static func accessible(_ object: Any, identifier: String, depth: Int = 0) -> NSObject? {
        guard depth < 20, let element = object as? NSObject else { return nil }
        let idSelector = NSSelectorFromString("accessibilityIdentifier")
        if element.responds(to: idSelector), element.perform(idSelector)?.takeUnretainedValue() as? String == identifier { return element }
        let childrenSelector = NSSelectorFromString("accessibilityChildren")
        let children = element.responds(to: childrenSelector) ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] ?? [] : []
        for child in children {
            if let found = accessible(child, identifier: identifier, depth: depth + 1) { return found }
        }
        return nil
    }

    @MainActor static func textEditor(_ view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        for child in view.subviews { if let found = textEditor(child) { return found } }
        return nil
    }

    @MainActor static func capture(_ window: NSWindow, _ model: IslandModel, _ media: MediaService, to url: URL) async {
        let host = IslandHostingView(model: model, media: media)
        window.setContentSize(NSSize(width: model.width, height: model.height))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        await pause(0.4)
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        print("RENDER: \(url.lastPathComponent) \(host.bounds.size)")
    }

    @MainActor static func hoverTests(model: IslandModel, window: NSWindow) async {
        let display = NSRect(x: -1512, y: 53, width: 1512, height: 982)
        let closed = NSRect(x: -857.5, y: 1002, width: 203, height: 33)
        let region = WindowPointerTracker.interactionFrame(panelFrame: closed, expanded: false, screenFrame: display)
        let approach = NSPoint(x: -756, y: 994)
        require(!closed.contains(approach) && region.contains(approach), "approaching below the physical camera activates the invisible target")
        require(region.contains(NSPoint(x: closed.minX - 5, y: closed.midY)), "approaching from the side reaches the target")
        require(!region.contains(NSPoint(x: closed.midX, y: closed.minY - 20)), "content farther below the notch does not activate it")
        require(!region.contains(NSPoint(x: closed.minX - 20, y: closed.midY)), "nearby menu items outside the target do not activate it")
        require(!region.contains(NSPoint(x: closed.midX, y: display.maxY + 5)), "the activation area cannot spill onto a display above")
        require(!region.contains(NSPoint(x: 960, y: 1040)), "the external display cannot activate the built-in notch")
        let open = NSRect(x: -1066, y: 879, width: 740, height: 156)
        require(WindowPointerTracker.interactionFrame(panelFrame: open, expanded: true, screenFrame: display) == open,
                "the expanded target stays exactly the visible panel")
        let plainDisplay = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let plainPanel = NSRect(x: 928, y: 1068, width: 64, height: 7)
        let plainRegion = WindowPointerTracker.interactionFrame(panelFrame: plainPanel, expanded: false, screenFrame: plainDisplay)
        require(plainRegion.contains(NSPoint(x: 960, y: 1079)) && plainRegion.contains(NSPoint(x: 960, y: 1060)),
                "a display without a notch opens from its top edge and from below")

        model.expanded = false
        model.resize = {
            window.setFrame(NSRect(x: 5000 - model.width / 2, y: 5000 - model.height, width: model.width, height: model.height), display: true)
        }
        model.resize?()
        window.contentView = IslandHostingView(model: model, media: model.media)
        window.orderFrontRegardless()
        let belowCamera = NSPoint(x: 5000, y: 5000 - model.compactHeight - 8)
        var pointer = NSPoint(x: 6000, y: 4000)
        let tracker = WindowPointerTracker(window: window, model: model, location: { pointer })
        tracker.start()
        pointer = belowCamera
        tracker.sample()
        await pause(0.1)
        pointer = NSPoint(x: 6000, y: 4000)
        tracker.sample()
        await pause(0.4)
        require(!model.expanded, "a brief pass below the camera does not open the panel")
        pointer = belowCamera
        await pause(0.6)
        require(model.expanded, "hover opens from below the camera without entering the closed window")
        await pause(0.8)
        require(model.expanded, "repeated inside samples never start a collapse")
        pointer = NSPoint(x: window.frame.minX + 126, y: window.frame.maxY - 17)
        await pause(0.15)
        if let notes = accessible(window.contentView!, identifier: "tab-Notas") {
            notes.accessibilityPerformAction(.press)
        } else {
            let point = NSPoint(x: 126.5, y: window.frame.height - 17)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: true)
            window.sendEvent(down)
        }
        await pause(0.7)
        require(model.tab == .notes && model.expanded, "selecting Notes keeps the panel open")
        pointer = NSPoint(x: window.frame.midX, y: window.frame.midY - 10)
        if let editor = textEditor(window.contentView!) {
            window.makeFirstResponder(editor)
            editor.selectAll(nil)
            editor.insertText("Nota original de verificación.", replacementRange: NSRange(location: NSNotFound, length: 0))
            await pause(0.6)
            require(model.note == "Nota original de verificación." && model.expanded, "native note editing updates the note without closing")
        } else { print("FAIL: native note editor unavailable"); exit(2) }
        for point in [NSPoint(x: window.frame.minX + 15, y: window.frame.midY), NSPoint(x: window.frame.maxX - 15, y: window.frame.midY), NSPoint(x: window.frame.midX, y: window.frame.minY + 5)] {
            pointer = point
            model.hover(false) // The former false-exit regression from nested SwiftUI controls.
            await pause(0.6)
            require(model.expanded, "inside expanded window remains open across controls and false exits")
        }
        pointer = NSPoint(x: window.frame.maxX + 20, y: window.frame.midY)
        await pause(0.7)
        require(!model.expanded, "leaving the actual window closes after delay, even after editing Notes")
        pointer = belowCamera
        await pause(0.4)
        model.pinned = true
        pointer = NSPoint(x: 6000, y: 4000)
        await pause(0.7)
        require(model.expanded, "pin retains the expanded panel outside")
        model.pinned = false
        await pause(0.7)
        require(!model.expanded, "unpin outside closes")
        pointer = belowCamera
        await pause(0.4)
        model.close()
        await pause(0.7)
        require(!model.expanded, "manual close does not reopen beneath a stationary pointer")
        pointer.x += 4
        await pause(0.4)
        require(!model.expanded, "small pointer jitter preserves manual close")
        pointer.x += 16
        await pause(0.6)
        require(model.expanded, "moving within the notch's approach area re-enables hover")
        model.close()
        pointer = NSPoint(x: 6000, y: 4000)
        await pause(0.15)
        pointer = belowCamera
        await pause(0.4)
        require(model.expanded, "leaving and returning re-enables hover")
        pointer = NSPoint(x: 6000, y: 4000)
        await pause(0.7)
        window.orderOut(nil)
        pointer = belowCamera
        await pause(0.4)
        require(!model.expanded, "a hidden panel never activates")
        window.orderFrontRegardless()
        await pause(0.6)
        require(model.expanded, "hover resumes when the panel is shown again")
        tracker.stop()
        model.pointerIsWithinPanel = nil
        model.resize = nil
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = IslandModel(preview: true)
        model.notchWidth = 185
        model.notchHeight = 32
        let media = MediaService()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        Task { @MainActor in
            let window = VerificationPanel(contentRect: NSRect(x: 5000, y: 5000, width: 740, height: 156), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            await hoverTests(model: model, window: window)
            if CommandLine.arguments.contains("--hover-only") {
                window.close()
                print("Hover verification complete; no media or phone services started.")
                exit(0)
            }
            media.connect(.music)
            for _ in 0..<40 {
                await pause(0.5)
                if media.track.exists && media.artwork != nil { break }
            }
            require(media.track.exists, "Apple Music returns current metadata")
            let first = media.track
            print("SOURCE: \(media.player!.rawValue); TRACK: \(first.title); TIME: \(first.position)/\(first.duration); playing=\(first.playing); ART: \(String(describing: media.artwork?.size))")
            model.lyrics.update(track: first)
            for _ in 0..<60 {
                await pause(0.5)
                if model.lyrics.status != .loading { break }
            }
            print("LIVE LYRICS: status=\(model.lyrics.status), lines=\(model.lyrics.lines.count), activeIndex=\(String(describing: model.lyrics.activeIndex(at: first.elapsed(at: Date()))))")
            // Test timed playback using original local text; never print or capture third-party lyric text.
            var localTrack = first
            localTrack.id = "local-verification"
            localTrack.duration = 0
            model.lyrics.update(track: localTrack)
            model.lyrics.importLRC("[00:01]Una línea de prueba\n[00:03]La letra sigue la canción\n[00:05]\n[00:07]El tiempo sigue su curso", for: localTrack)
            require(model.lyrics.activeIndex(at: 0) == nil, "lyric introduction before first timestamp")
            require(model.lyrics.activeIndex(at: 3.1) == 1, "lyric advances with playback position")
            require(model.lyrics.activeIndex(at: 1.1) == 0, "lyric follows a seek backwards")
            model.lyrics.adjustment = 2
            require(model.lyrics.activeIndex(at: 1.1) == 1, "manual timing adjustment")
            model.lyrics.update(track: TrackState())
            require(model.lyrics.lines.isEmpty && model.lyrics.status == .idle, "old lyrics clear on track removal")
            let position = first.elapsed(at: Date())
            model.lyrics.setVerificationLines([
                LyricLine(time: max(0, position - 3), text: "Una línea de prueba"),
                LyricLine(time: max(0, position - 1), text: "La letra sigue la canción"),
                LyricLine(time: position + 1000, text: "Junto a tu música, a su tiempo")
            ])
            model.expanded = true
            for tab in IslandTab.allCases {
                model.tab = tab
                model.now = Date()
                await capture(window, model, media, to: output.appendingPathComponent("native-\(tab.rawValue).png"))
            }
            model.expanded = false
            await capture(window, model, media, to: output.appendingPathComponent("native-compact.png"))
            model.expanded = true
            model.tab = .music
            model.lyrics.update(track: TrackState())
            await capture(window, model, model.media, to: output.appendingPathComponent("native-empty.png"))
            media.refresh()
            await pause(1)
            print("SECOND SAMPLE: position=\(media.track.position), delta=\(media.track.position - first.position)")
            window.close()
            exit(media.artwork == nil ? 4 : 0)
        }
        app.run()
    }
}
