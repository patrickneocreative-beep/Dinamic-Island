import AppKit

/// Polls screen coordinates without intercepting clicks in the invisible approach area.
/// Once open, the whole panel remains interactive, independent of its nested controls.
@MainActor
final class WindowPointerTracker {
    private weak var window: NSWindow?
    private weak var model: IslandModel?
    private var timer: Timer?
    private let location: () -> NSPoint
    private let screenFrame: () -> NSRect?
    private let activationFrame: (() -> NSRect?)?
    private var lastDiagnostic = Date.distantPast

    init(window: NSWindow, model: IslandModel,
         screenFrame: @escaping () -> NSRect? = { nil },
         activationFrame: (() -> NSRect?)? = nil,
         location: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.window = window
        self.model = model
        self.screenFrame = screenFrame
        self.activationFrame = activationFrame
        self.location = location
        model.pointerIsWithinPanel = { [weak self] in self?.containsPointer() ?? false }
        model.pointerLocation = { [weak self] in self?.location() }
    }

    static func interactionFrame(panelFrame: NSRect, expanded: Bool, screenFrame: NSRect?) -> NSRect {
        // The closed panel extends only 1 pt below the physical camera. Give it
        // a reachable target without adding any visible height, border or window.
        let region = expanded ? panelFrame : panelFrame.insetBy(dx: -8, dy: -14)
        // A display placed above or beside this one must not activate this notch.
        return screenFrame.map { region.intersection($0) } ?? region
    }

    func containsPointer(at point: NSPoint? = nil) -> Bool {
        guard let window, let model else { return false }
        let point = point ?? location()
        if let activation = activationFrame?() {
            // Screen geometry remains valid when the external panel is ordered out.
            let region = model.expanded && window.isVisible ? activation.union(window.frame) : activation
            let clipped = screenFrame().map { region.intersection($0) } ?? region
            return ScreenPointerRegion.contains(point, in: clipped)
        }
        guard window.isVisible else { return false }
        return ScreenPointerRegion.contains(point, in: Self.interactionFrame(
            panelFrame: window.frame, expanded: model.expanded, screenFrame: screenFrame()))
    }

    func sample(at point: NSPoint? = nil) {
        let point = point ?? location()
        model?.hover(containsPointer(at: point), at: point)
        if Date().timeIntervalSince(lastDiagnostic) > 0.2 {
            lastDiagnostic = Date()
            HoverDiagnostics.record(["time": Date().timeIntervalSince1970, "window": window?.windowNumber ?? -1,
                                     "point": NSStringFromPoint(point), "visible": window?.isVisible ?? false,
                                     "frame": NSStringFromRect(window?.frame ?? .zero),
                                     "activation": NSStringFromRect(activationFrame?() ?? .zero),
                                     "state": model?.hoverDiagnosticState ?? [:]])
        }
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = 0.025
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate(); timer = nil }
}
