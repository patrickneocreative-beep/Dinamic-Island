import AppKit
import SwiftUI

/// AppKit owns the window's animated size. SwiftUI fills that size from the top
/// instead of imposing a second intrinsic size and centering it mid-animation.
@MainActor
final class IslandHostingView: NSHostingView<IslandView> {
    init(model: IslandModel, media: MediaService) {
        super.init(rootView: IslandView(model: model, media: media))
        sizingOptions = []
        safeAreaRegions = []
    }

    @MainActor required init(rootView: IslandView) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
