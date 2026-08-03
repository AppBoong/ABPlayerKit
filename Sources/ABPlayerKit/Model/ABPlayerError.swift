import Foundation

/// Errors ABPlayerKit surfaces. Never thrown from the playback control surface —
/// see DESIGN-ABPlayerKit.md §6: failures are asynchronous events, not synchronous
/// throw sites a consumer cannot reliably catch.
public enum ABPlayerError: Error, Sendable, Equatable {
    /// `AVPlayerItem.error` stringified for `Equatable`/`Sendable` safety.
    case itemFailed(description: String)
    case prerollTimedOut(after: TimeInterval)
    case prerollFailed
    case invalidGradeForSource(requested: ABPlaybackGrade)
    /// Reserved for the Cache target (Phase 3).
    case cacheUnavailable(description: String)
}
