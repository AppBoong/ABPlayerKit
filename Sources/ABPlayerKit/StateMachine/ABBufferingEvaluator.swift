/// Raw buffering-relevant signals fed to `ABBufferingEvaluator.isBuffering(_:)`,
/// grouped into one value so the evaluator itself stays a single-parameter
/// pure function — the same "bundle related inputs into one value" shape
/// `ABGradePlanner`'s `(from, to, source, sourceChanged, rewindOnDemotion)`
/// list would take if it needed to grow further.
struct ABBufferingSignals: Equatable {
    var hasItem: Bool
    var intendsToPlay: Bool
    var timeControlStatus: ABTimeControlStatus
    var isWaitingWithNoItem: Bool
    var isPlaybackLikelyToKeepUp: Bool
    var isPlaybackBufferEmpty: Bool
}

/// Judges whether playback is currently buffering from raw target signals.
/// Pure — no `AVFoundation` import, no state — so every combination is
/// table-testable without a simulator, the same way `ABGradePlanner` is.
struct ABBufferingEvaluator {
    static func isBuffering(_ signals: ABBufferingSignals) -> Bool {
        guard signals.hasItem, signals.intendsToPlay, !signals.isWaitingWithNoItem else { return false }
        switch signals.timeControlStatus {
        case .playing:
            // A frame is actively advancing — not buffering, regardless of
            // the buffer-empty/keep-up signals below.
            return false
        case .waitingToPlay:
            return true
        case .paused:
            // Only reachable while `intendsToPlay` when
            // `automaticallyWaitsToMinimizeStalling == false` lets `rate`
            // drop to 0 on a stall instead of moving to `.waitingToPlay`.
            return signals.isPlaybackBufferEmpty || !signals.isPlaybackLikelyToKeepUp
        }
    }
}
