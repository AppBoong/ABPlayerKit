import Foundation

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
    case failed(ABPlayerError)
    case tuningApplied(ABTuningRole, ABPlaybackTuning)
    case itemDetached(reason: ABDetachReason)
    /// Emitted instead of throwing when `set(source:grade:)` receives an
    /// illegal combination (`grade >= .preloaded && source == nil`).
    case invalidGradeForSource(requested: ABPlaybackGrade)
    /// Emitted when a playback control call (`play`/`pause`/`seek`) is
    /// ignored because `grade != .current`.
    case playbackRejected
}
