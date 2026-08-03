/// Which tuning preset an `.applyTuning` action should apply.
public enum ABTuningRole: Sendable, Equatable {
    case preload
    case current
}

/// One step `ABGradePlanner` prescribes to move an `ABPlayer` from one grade
/// to another. Pure data — no AVFoundation involved; `ABAVPlaybackTarget`
/// interprets these against real `AVPlayer`/`AVPlayerItem` instances.
public enum ABGradeAction: Sendable, Equatable {
    case createPlayer
    case cancelPreload
    case pause
    /// `.preload` | `.current`.
    case applyTuning(ABTuningRole)
    /// Creates the `AVPlayerItem` and calls `replaceCurrentItem(item)`.
    case attachItem(ABMediaSource)
    /// `replaceCurrentItem(nil)`.
    case detachItem
    /// Waits for `status == .readyToPlay`, then `preroll(atRate:)`.
    case armPreroll
    case seekToStart
    case teardownObservers
    case releasePlayer
}
