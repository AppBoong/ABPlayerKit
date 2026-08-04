@preconcurrency import AVFoundation
import Foundation

/// An interaction emitted by ``ABPlayerControlsView``.
public enum ABControlsEvent: Sendable, Equatable {
    case visibilityChanged(isVisible: Bool)
    case playPauseTapped(isPlayingAfterTap: Bool)
    case skipTapped(by: TimeInterval)
    case rateSelected(Float)
    case scrubbingChanged(isScrubbing: Bool)
    case seekCommitted(to: CMTime)
}
