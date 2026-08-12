/// Judges whether playback is currently buffering from raw target signals.
/// Pure — no `AVFoundation` import, no state — so every combination is
/// table-testable without a simulator, the same way `ABGradePlanner` is.
struct ABBufferingEvaluator {
    static func isBuffering(
        hasItem: Bool,
        intendsToPlay: Bool,
        timeControlStatus: ABTimeControlStatus,
        isWaitingWithNoItem: Bool,
        isPlaybackLikelyToKeepUp: Bool,
        isPlaybackBufferEmpty: Bool
    ) -> Bool {
        guard hasItem, intendsToPlay, !isWaitingWithNoItem else { return false }
        switch timeControlStatus {
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
            return isPlaybackBufferEmpty || !isPlaybackLikelyToKeepUp
        }
    }
}
