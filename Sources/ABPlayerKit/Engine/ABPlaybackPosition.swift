import Observation

/// The playback position of one ``ABPlayer``, as an `@Observable` object
/// SwiftUI can read directly.
///
/// ```swift
/// Text(player.position.time.currentTime.seconds, format: .number)
/// ProgressView(value: player.position.time.progress ?? 0)
/// ```
///
/// It is a separate object from ``ABPlayer`` on purpose. Observation tracks
/// per property, per object: a view re-renders only for the properties it
/// read. Keeping the fast-changing position here means a tick invalidates
/// the views that show the position and nothing else — a view reading
/// `player.isPlaying` or `player.grade` is never re-evaluated by playback
/// merely advancing.
///
/// Get one from ``ABPlayer/position``; there is exactly one per player. It
/// refreshes every ``ABPlayerConfiguration/positionUpdateInterval`` while
/// the player is `.current` and playing, after a seek, and on every grade or
/// source change. It is not updated during an interactive scrubbing
/// session, the same as ``ABPlayerEvent/periodicTime(_:)``.
@MainActor
@Observable
public final class ABPlaybackPosition {
    /// The latest snapshot. Reassigned only when a value actually changes,
    /// so a paused player never invalidates the views reading it.
    public private(set) var time: ABPlaybackTime

    init(time: ABPlaybackTime) {
        self.time = time
    }

    func update(_ newTime: ABPlaybackTime) {
        if newTime != time {
            time = newTime
        }
    }
}
