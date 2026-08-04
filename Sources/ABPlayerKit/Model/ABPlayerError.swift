import Foundation

/// Errors ABPlayerKit surfaces. Never thrown from the playback control surface —
/// see DESIGN-ABPlayerKit.md §6: failures are asynchronous events, not synchronous
/// throw sites a consumer cannot reliably catch.
///
/// Treat this enum as non-exhaustive, the same convention documented on
/// ``ABPlayerEvent``: minor releases may add cases, so switches outside
/// ABPlayerKit should include a `default` branch to remain source-compatible.
public enum ABPlayerError: Error, Sendable, Equatable {
    /// `AVPlayerItem.error` stringified for `Equatable`/`Sendable` safety.
    case itemFailed(description: String)
    case prerollTimedOut(after: TimeInterval)
    case prerollFailed
    case invalidGradeForSource(requested: ABPlaybackGrade)
    /// Reserved for the Cache target (Phase 3).
    case cacheUnavailable(description: String)
    /// An opt-in `ABAudioSessionPolicy` (Model/ABPlayerConfiguration.swift)
    /// failed to apply or restore against `AVAudioSession`. `NSError`
    /// stringified for `Equatable`/`Sendable` safety, same as `itemFailed`.
    /// Added in a minor release — see the non-exhaustive convention noted
    /// on this type's own doc comment above.
    case audioSessionOperationFailed(description: String)
}
