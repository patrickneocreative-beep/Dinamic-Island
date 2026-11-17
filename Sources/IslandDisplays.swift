import AppKit
import Quartz

struct IslandDisplay: Equatable {
    let id: UInt32
    let frame: NSRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    init(id: UInt32, frame: NSRect, notchWidth: CGFloat = 0, notchHeight: CGFloat = 0) {
        self.id = id; self.frame = frame; self.notchWidth = notchWidth; self.notchHeight = notchHeight
    }

    init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        id = number.uint32Value
        frame = screen.frame
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
            notchHeight = screen.safeAreaInsets.top
        } else { notchWidth = 0; notchHeight = 0 }
    }
}

final class IslandPanel: NSPanel {
    var onCancel: (() -> Void)?
    weak var previewController: FileActions?
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { previewController != nil }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { previewController?.beginPreview(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { previewController?.endPreview(panel) }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class ScreenIslandController {
    private(set) var display: IslandDisplay
    let model: IslandModel
    let panel: IslandPanel
    private var tracker: WindowPointerTracker?
    private var presentationGeneration = 0

    var activationFrame: NSRect {
        let width = min(display.frame.width, max(280, model.compactWidth + 16))
        let height = max(42, model.compactHeight + 14)
        return NSRect(x: display.frame.midX - width / 2, y: display.frame.maxY - height,
                      width: width, height: height).intersection(display.frame)
    }

    private var hiddenFrame: NSRect {
        NSRect(x: display.frame.midX - model.compactWidth / 2, y: display.frame.maxY - 1,
               width: model.compactWidth, height: 1)
    }

    init(display: IslandDisplay, data: IslandData, location: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.display = display
        model = IslandModel(data: data)
        model.notchWidth = display.notchWidth
        model.notchHeight = display.notchHeight
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        model.panel = panel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.contentView = IslandHostingView(model: model, media: data.media)
        panel.onCancel = { [weak model] in model?.close() }
        model.resize = { [weak self] in self?.resize(animated: true) }
        model.resignEditing = { [weak panel] in panel?.makeFirstResponder(nil) }
        resize(animated: false)
        tracker = WindowPointerTracker(window: panel, model: model,
                                       screenFrame: { [weak self] in self?.display.frame },
                                       activationFrame: { [weak self] in self?.activationFrame }, location: location)
        tracker?.start()
    }

    func update(_ display: IslandDisplay) {
        guard self.display != display else { return }
        self.display = display
        model.notchWidth = display.notchWidth
        model.notchHeight = display.notchHeight
        model.resetHoverSuppression()
        resize(animated: false)
    }

    private func resize(animated: Bool) {
        presentationGeneration += 1
        let generation = presentationGeneration
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !model.hasNotch && !model.expanded {
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            if animate && panel.isVisible {
                IslandWindowMotion.resize(panel, to: hiddenFrame, animated: true, opacity: 0) { [weak self] in
                    guard let self, generation == self.presentationGeneration, !self.model.expanded, !self.model.hasNotch else { return }
                    self.panel.orderOut(nil)
                }
            } else {
                panel.orderOut(nil)
                panel.setFrame(hiddenFrame, display: false)
                panel.alphaValue = 0
            }
            return
        }
        if !panel.isVisible && !model.hasNotch {
            panel.setFrame(hiddenFrame, display: false)
            panel.alphaValue = animate ? 0 : 1
        }
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        let frame = NSRect(x: display.frame.midX - model.width / 2, y: display.frame.maxY - model.height,
                           width: model.width, height: model.height)
        panel.hasShadow = model.expanded
        IslandWindowMotion.resize(panel, to: frame, animated: animate)
    }

    func samplePointer(at point: NSPoint? = nil) { tracker?.sample(at: point) }

    func restorePresentation() {
        model.resetHoverSuppression()
        resize(animated: false)
        tracker?.sample()
    }

    func stop() {
        presentationGeneration += 1
        tracker?.stop(); tracker = nil
        model.stopInteraction()
        panel.onCancel = nil
        panel.orderOut(nil)
        panel.close()
    }
}

@MainActor
final class IslandDisplayCoordinator {
    let data: IslandData
    private(set) var islands: [UInt32: ScreenIslandController] = [:]
    private let location: () -> NSPoint

    init(data: IslandData, location: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.data = data
        self.location = location
        data.anyPanelExpanded = { [weak self] in self?.islands.values.contains { $0.model.expanded } ?? false }
        data.onFocusCompletion = { [weak self] in
            guard let island = self?.preferredIsland() else { return }
            guard island.model.hasNotch || island.model.expanded else { return }
            island.model.select(.focus)
            island.model.pinned = true
            island.model.setExpanded(true)
        }
    }

    func reconcile(_ displays: [IslandDisplay]) {
        // Mirrored displays share a drawable rectangle and need only one island.
        var unique: [IslandDisplay] = []
        for display in displays where !unique.contains(where: { $0.frame == display.frame }) { unique.append(display) }
        let ids = Set(unique.map(\.id))
        for id in Array(islands.keys) where !ids.contains(id) { islands.removeValue(forKey: id)?.stop() }
        for display in unique {
            if let island = islands[display.id] { island.update(display) }
            else { islands[display.id] = ScreenIslandController(display: display, data: data, location: location) }
        }
    }

    func preferredIsland() -> ScreenIslandController? {
        islands.values.first(where: { ScreenPointerRegion.contains(location(), in: $0.display.frame) })
            ?? islands.values.first(where: { $0.panel.isKeyWindow })
            ?? islands.values.first(where: { $0.model.hasNotch })
            ?? islands.values.first
    }

    func samplePointer(at point: NSPoint? = nil) {
        for island in islands.values { island.samplePointer(at: point) }
    }

    func restorePresentations() {
        for island in islands.values { island.restorePresentation() }
    }

    func closeOutside(_ point: NSPoint) {
        guard !data.trackingMenu else { return }
        for island in islands.values where island.model.expanded && !island.model.pinned && !island.model.interacting {
            if !ScreenPointerRegion.contains(point, in: island.panel.frame) { island.model.close() }
        }
    }

    func stop() {
        for island in islands.values { island.stop() }
        islands.removeAll()
        data.anyPanelExpanded = { false }
        data.onFocusCompletion = nil
    }
}
