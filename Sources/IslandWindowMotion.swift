import AppKit
import QuartzCore

@MainActor
enum IslandWindowMotion {
    static func resize(_ window: NSWindow, to frame: NSRect, animated: Bool,
                       opacity: CGFloat = 1, completion: (() -> Void)? = nil) {
        guard animated else {
            window.setFrame(frame, display: true)
            window.alphaValue = opacity
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = opacity
        } completionHandler: { Task { @MainActor in completion?() } }
    }
}
