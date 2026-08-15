@preconcurrency import AVFoundation
import Foundation

/// An interaction emitted by ``ABPlayerControlsView``.
public enum ABControlsEvent: Sendable, Equatable {
    case visibilityChanged(isVisible: Bool)
    /// A play/pause tap, carrying the resulting *intent* to play.
    ///
    /// `isPlayingAfterTap` folds in buffering, so it can read `true` at a
    /// moment `ABPlayer.isPlaying` still reads `false` — a stall drops
    /// `timeControlStatus` to `.paused` without the user's intent changing.
    /// Treat it as "the pause glyph is showing," not as a mirror of the
    /// player's rate.
    case playPauseTapped(isPlayingAfterTap: Bool)
    case skipTapped(by: TimeInterval)
    case rateSelected(Float)
    case scrubbingChanged(isScrubbing: Bool)
    /// A seek the user committed by finishing a scrub, or by a VoiceOver
    /// adjustment.
    ///
    /// Not emitted for skip buttons or double-tap seeks — those emit only
    /// ``skipTapped(by:)``. An observer that needs every seek must handle
    /// both cases.
    case seekCommitted(to: CMTime)
}
