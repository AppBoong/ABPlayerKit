import UIKit

/// An icon rendered by a playback control button.
public enum ABControlIcon: Sendable, Equatable {
    /// An SF Symbol name. Missing symbols are omitted safely.
    case system(String)
    /// A consumer-provided image.
    case image(UIImage)
    /// Hides the associated button.
    case none
}
