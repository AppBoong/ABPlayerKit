@preconcurrency import AVFoundation
import ABPlayerKit
import Foundation

/// Maps player-driven state into view-update effects the view interprets —
/// same shape as `ABControlsVisibilityMachine`: a pure value type with no
/// `ABPlayer`/`UIView` dependency, holding only the state needed to decide
/// what to show next.
///
/// WP-A4a covers the read direction (player state → view effects). A
/// handful of `ABPlayerEvent` cases (`itemDetached`, `sourceChanged`,
/// `itemStatusChanged(.readyToPlay)`, `seekCompleted`) need a live `ABPlayer`
/// read (`player.grade`, `player.playbackTime`, `player.isScrubbing`,
/// `player.duration`) that this type deliberately can't have — those stay
/// inline in `ABPlayerControlsView.handlePlayerEvent`, applied in addition to
/// (and in the same order as) whatever this type contributes for the same
/// event.
///
/// WP-A4b adds most of the command-emission direction (view taps → player
/// calls): `playPauseTapped`, `skipTapped`, `rateSelected`,
/// `accessibilityAdjusted`. `togglePlayback`'s reentrancy is the one place
/// order truly matters for this direction — `player.promote(to:)` broadcasts
/// `.gradeChanged` *synchronously* (`ABObserverRegistry.broadcast` iterates
/// handlers directly, no dispatch hop) and re-enters
/// `ABPlayerControlsView.handlePlayerEvent` before `play()` runs; `play()`/
/// `pause()` themselves do not re-enter synchronously (their
/// `timeControlStatus` KVO forwards through `Task { @MainActor in ... }` in
/// `ABAVPlaybackTarget`, always landing on a later run-loop turn). Pinned by
/// `ABControlsPlayPauseReentrancyCharacterizationTests`, written and passing
/// against the pre-WP-A4b code before this direction was touched.
///
/// Scrubbing (`scrubBegan`/`scrubChanged`/`scrubEnded`) deliberately stays
/// out of this type. Scrub commands must target the specific `ABPlayer`
/// snapshotted when scrubbing began (`scrubbingPlayer` in the view) rather
/// than whatever `self.player` happens to be by the time a coalesced seek or
/// `endScrubbing()`'s completion runs — see
/// `ABPlayerControlsViewTests`' "Given a source swap during scrubbing, the
/// session ends and no stale seek issues". A player-less effect/command pair
/// has no way to express "target the pinned player, not the current one";
/// forcing it through would either lose that guarantee or reintroduce a
/// player reference into this type. The progress→`CMTime` math those methods
/// use (`ABSeekBarGeometry.time(forProgress:duration:)`) is already an
/// independently pure, separately-tested utility, so nothing is lost by
/// leaving the surrounding orchestration inline in the view.
struct ABControlsPresenter: Equatable {
    enum Input: Equatable {
        case attached(grade: ABPlaybackGrade)
        case detached
        case playerEvent(ABPlayerEvent)
        case playPauseTapped(isPlaying: Bool, allowsPromotionTap: Bool)
        case skipTapped(TimeInterval)
        case rateSelected(Float)
        case accessibilityAdjusted(direction: Int, skipInterval: TimeInterval)
    }

    enum PlayerCommand: Equatable {
        case play
        case pause
        case promoteToCurrent
        case skip(by: TimeInterval)
        case setRate(Float)
    }

    enum Effect: Equatable {
        case setPlaybackIcon(isPlaying: Bool)
        case setRateTitle(rate: Float)
        case renderTimeline(ABPlaybackTime)
        case resetTimeline
        case setEnabled(Bool, allowsPromotionTap: Bool)
        case send(PlayerCommand)
    }

    private(set) var isPlaying = false
    private(set) var currentPlaybackTime = ABPlaybackTime.zero
    private(set) var rate: Float = 1

    /// Hydrates tracked state directly from a freshly-attached player,
    /// without going through `handle(_:)` — attaching a player is not itself
    /// an `ABPlayerEvent`, and `.attached`'s `Input` case deliberately only
    /// carries `grade` (see this type's doc comment), so nothing else would
    /// seed these otherwise. Call once, right before `handle(.attached(...))`,
    /// with the same player's live values.
    mutating func seed(isPlaying: Bool, rate: Float, currentPlaybackTime: ABPlaybackTime) {
        self.isPlaying = isPlaying
        self.rate = rate
        self.currentPlaybackTime = currentPlaybackTime
    }

    /// Keeps `currentPlaybackTime` (which `.accessibilityAdjusted` reads for
    /// its duration/current-time math) in sync with renders the view performs
    /// outside `handle(_:)` — the `itemStatusChanged(.readyToPlay)` and
    /// `seekCompleted` branches of `ABPlayerControlsView.handlePlayerEvent`,
    /// both of which need a live player read this type deliberately doesn't
    /// have (see this type's doc comment) and so call `render(...)` directly
    /// rather than through an `Effect`. Without this, a VoiceOver adjustment
    /// right after either event would compute against a stale time.
    mutating func syncPlaybackTime(_ time: ABPlaybackTime) {
        currentPlaybackTime = time
    }

    mutating func handle(_ input: Input) -> [Effect] {
        switch input {
        case .attached(let grade):
            return [.setEnabled(grade == .current, allowsPromotionTap: true)]

        case .detached:
            currentPlaybackTime = .zero
            return [.resetTimeline]

        case .playerEvent(let event):
            return handlePlayerEvent(event)

        case .playPauseTapped(let isPlaying, let allowsPromotionTap):
            // `isPlaying` here is the *live* `player.isPlaying` the caller
            // resolved just before calling `handle(_:)` — this decision
            // deliberately does NOT read `self.isPlaying` (this type's own
            // cached copy, last updated by `.timeControlStatusChanged`).
            // Round4 review MJ-3: an earlier version branched on
            // `self.isPlaying`, which diverges from the live value while
            // buffering (`timeControlStatus == .waitingToPlayAtSpecifiedRate`
            // has `player.isPlaying == true` — rate≠0, not paused — but
            // never set `self.isPlaying = true`, since only `.playing`
            // does). The pre-extraction `togglePlayback` always branched on
            // `player.isPlaying`; this restores that exact source, per the
            // "pure move" principle this whole decomposition is supposed to
            // hold to. `self.isPlaying` is still updated optimistically
            // afterward (matching the pre-extraction code's own
            // `isPlayingState = true/false` assignment, right after the
            // branch, independent of whether a reentrant
            // `.timeControlStatusChanged` ever confirms it).
            self.isPlaying = !isPlaying
            if isPlaying {
                return [.send(.pause)]
            }
            var effects: [Effect] = []
            if allowsPromotionTap {
                effects.append(.send(.promoteToCurrent))
            }
            effects.append(.send(.play))
            return effects

        case .skipTapped(let interval):
            return [.send(.skip(by: interval))]

        case .rateSelected(let requestedRate):
            let resolvedRate = ABPlaybackRate.clamped(requestedRate)
            rate = resolvedRate
            return [.send(.setRate(resolvedRate)), .setRateTitle(rate: resolvedRate)]

        case .accessibilityAdjusted(let direction, let skipInterval):
            guard direction != 0, let duration = currentPlaybackTime.duration else { return [] }
            let durationSeconds = CMTimeGetSeconds(duration)
            let currentSeconds = CMTimeGetSeconds(currentPlaybackTime.currentTime)
            guard durationSeconds.isFinite, durationSeconds > 0, currentSeconds.isFinite else { return [] }
            let delta = Double(direction) * skipInterval
            let targetSeconds = min(max(currentSeconds + delta, 0), durationSeconds)
            let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
            let newTime = ABPlaybackTime(
                currentTime: target,
                duration: duration,
                bufferedUntil: currentPlaybackTime.bufferedUntil
            )
            currentPlaybackTime = newTime
            return [.renderTimeline(newTime), .send(.skip(by: delta))]
        }
    }

    private mutating func handlePlayerEvent(_ event: ABPlayerEvent) -> [Effect] {
        switch event {
        case .periodicTime(let time):
            currentPlaybackTime = time
            return [.renderTimeline(time)]

        case .timeControlStatusChanged(let status):
            isPlaying = status == .playing
            return [.setPlaybackIcon(isPlaying: isPlaying)]

        case .rateChanged(let newRate):
            rate = newRate
            return [.setRateTitle(rate: newRate)]

        case .gradeChanged(_, let grade):
            var effects: [Effect] = [.setEnabled(grade == .current, allowsPromotionTap: true)]
            if grade != .current {
                currentPlaybackTime = .zero
                effects.append(.resetTimeline)
            }
            return effects

        case .itemDetached, .sourceChanged:
            // The rest of this transition (disabling controls based on
            // `player?.grade`) needs a live player read — the view applies
            // it directly, right after this effect. See this type's doc comment.
            currentPlaybackTime = .zero
            return [.resetTimeline]

        case .itemStatusChanged(.readyToPlay):
            // Needs `player.playbackTime`/`player.grade` — fully handled by
            // the view. See this type's doc comment.
            return []

        case .itemStatusChanged(.unknown):
            return []

        case .itemStatusChanged(.failed), .failed:
            return [.setEnabled(false, allowsPromotionTap: false)]

        case .playedToEnd:
            isPlaying = false
            return [.setPlaybackIcon(isPlaying: false)]

        case .seekCompleted:
            // Needs `player?.isScrubbing`/`player?.duration` — fully handled
            // by the view. See this type's doc comment.
            return []

        default:
            return []
        }
    }
}
