import UIKit

/// The stall spinner overlaid on the play/pause button's glyph. A thin
/// `UIActivityIndicatorView` wrapper so `ABPlayerControlsView` has one place
/// to apply style and keeps `isAnimating` as its only externally meaningful
/// state — starting/stopping is what shows/hides it (`hidesWhenStopped`).
@MainActor
final class ABBufferingIndicatorView: UIActivityIndicatorView {
    convenience init() {
        self.init(style: .medium)
        hidesWhenStopped = true
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
    }

    func apply(_ style: ABPlayerControlsStyle) {
        color = style.bufferingIndicatorColor ?? style.tintColor
    }
}
