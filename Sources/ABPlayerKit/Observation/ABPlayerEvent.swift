import CoreGraphics
import Foundation
@preconcurrency import AVFoundation

/// Identifies which call `.callRejected`/`.playbackRejected` reports as
/// ignored because `grade != .current`.
public enum ABRejectedCall: Sendable, Equatable {
    case play
    case pause
    case seek
    case skip
    case beginScrubbing
    case scrub
    case endScrubbing
}

public enum ABItemStatus: Sendable, Equatable {
    case unknown
    case readyToPlay
    case failed
}

public enum ABTimeControlStatus: Sendable, Equatable {
    case paused
    case waitingToPlay
    case playing
}

public enum ABDetachReason: Sendable, Equatable {
    case demotion
    case release
    case sourceChanged
    case backgroundPolicy
}

/// A lifecycle or playback event emitted by ``ABPlayer``.
///
/// Treat this enum as non-exhaustive: minor releases may add cases. Consumer
/// switches should include a `default` branch to remain source-compatible.
public enum ABPlayerEvent: Sendable, Equatable {
    case gradeChanged(from: ABPlaybackGrade, to: ABPlaybackGrade)
    case sourceChanged(ABMediaSource?)
    case itemStatusChanged(ABItemStatus)
    /// TTFF end point. `t` is `CACurrentMediaTime()` captured on the
    /// callback thread, before hopping to the main actor.
    case firstFrameDisplayed(at: CFTimeInterval)
    case prerollCompleted(success: Bool)
    case preloadCancelled
    case playbackStalled
    case playedToEnd
    case timeControlStatusChanged(ABTimeControlStatus)
    /// Emitted after the desired playback rate actually changes.
    case rateChanged(Float)
    /// Emitted at interactive scrubbing boundaries.
    case scrubbingChanged(isScrubbing: Bool)
    /// Emitted when any seek lands, including intermediate scrubbing seeks.
    case seekCompleted(to: CMTime)
    /// Emitted when ``ABPlayer/pendingSeekTime`` changes: the requested
    /// destination while a non-scrubbing seek is outstanding, or `nil` once
    /// it settles. Not emitted during an active scrubbing session — the
    /// seek bar owns position feedback there.
    case seekTargetChanged(CMTime?)
    /// Emitted at the configured interval while current and not scrubbing.
    case periodicTime(ABPlaybackTime)
    /// Legacy channel — kept for source compatibility, still broadcast
    /// alongside `.failureReported` for every failure. New code should
    /// prefer `.failureReported`, which carries provenance.
    case failed(ABPlayerError)
    /// Broadcast immediately after `.failed`, at the same failure site,
    /// carrying the failure's classification and originating subsystem
    /// together.
    case failureReported(ABPlayerFailure)
    case tuningApplied(ABTuningRole, ABPlaybackTuning)
    case itemDetached(reason: ABDetachReason)
    /// Broadcast immediately after `target.attachItem(...)`, before the
    /// same action's `.tuningApplied` — once per attach.
    case itemAttached(source: ABMediaSource)
    /// Emitted instead of throwing when `set(source:grade:)` receives an
    /// illegal combination (`grade >= .preloaded && source == nil`).
    case invalidGradeForSource(requested: ABPlaybackGrade)
    /// Emitted when a playback control call (`play`/`pause`/`seek`) is
    /// ignored because `grade != .current`.
    case playbackRejected
    /// Broadcast immediately after `.playbackRejected`, at the same site,
    /// identifying which call and grade caused the rejection.
    case callRejected(ABRejectedCall, grade: ABPlaybackGrade)
    /// ``ABPlayer/isBuffering`` changed. Command-driven transitions
    /// (`play()`/`pause()`) broadcast synchronously; KVO-driven transitions
    /// broadcast on the next run loop turn.
    case bufferingChanged(Bool)
    /// The attached item's duration first became known (finite,
    /// `seconds > 0`), or changed to a different finite value. Not
    /// re-broadcast for the same value, and reset on detach.
    case durationAvailable(CMTime)
    /// A previously-unresolved `.playbackStalled` reached
    /// `timeControlStatus == .playing` again. Broadcast once per stall — a
    /// stall left unresolved by a detach/release never gets this event;
    /// `.itemDetached` is the boundary signal for that case.
    case stallEnded
    /// `AVPlayerItem.presentationSize` changed to a non-zero size.
    case presentationSizeChanged(CGSize)
    /// Emitted after `ABPlayerConfiguration/isMuted` is actually applied to
    /// the target.
    case mutedChanged(Bool)
    /// An `AVAudioSession` interruption (phone call, Siri, another app
    /// taking the session) began and paused this player. Only emitted when
    /// `ABPlayerConfiguration/interruptionPolicy != .ignore` (round3
    /// Phase4 WP10).
    case audioInterruptionBegan
    /// A previously-began interruption ended. `resumed` is `true` only if
    /// `ABInterruptionPolicy/pauseAndResume` was configured, the system
    /// reported `.shouldResume`, and this player was actually playing when
    /// the interruption began.
    case audioInterruptionEnded(resumed: Bool)
    /// The audio route changed because the previous output device became
    /// unavailable (e.g. headphones unplugged) and this player paused in
    /// response. Only emitted when
    /// `ABPlayerConfiguration/pausesOnRouteChangeDeviceUnavailable` is
    /// `true` (its default).
    case audioRouteChangedDeviceUnavailable
}
