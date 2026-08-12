@preconcurrency import AVFoundation
import ABPlayerKit

/// Backs `ABVideoPlayerWithControls`'s `url:`/`source:` initializers'
/// ownership. Held in a `@State` property so it persists across the
/// SwiftUI value's reconstruction while tracking this view's identity —
/// released only when that `@State` storage is torn down, never on the
/// view merely scrolling off-screen (this type is never wired to
/// `onDisappear`).
///
/// The core target's `ABVideoPlayer.Coordinator` holds the same fields for
/// the same reason; the two aren't shared because each is under 30 lines
/// and each is independently tested, and a shared public type would put a
/// permanent API surface behind an abstraction with exactly one consumer
/// per module.
@MainActor
final class ABOwnedPlayerBox {
    private var owned: ABPlayer?
    private var appliedSource: ABMediaSource?
    private var didRelease = false

    /// `configuration` is applied only the first time this is called for a
    /// given box — a later call (from `body` re-evaluation, carrying
    /// whatever `playerConfiguration` value this SwiftUI value happens to
    /// hold on that pass) returns the existing player untouched, so
    /// settings changed after creation (e.g. the rate the user picked from
    /// a controls menu) can't be silently reverted by a parent re-render.
    func player(configuration: ABPlayerConfiguration, videoGravity: AVLayerVideoGravity) -> ABPlayer {
        if let owned {
            return owned
        }
        var resolvedConfiguration = configuration
        resolvedConfiguration.videoGravity = videoGravity
        let player = ABPlayer(configuration: resolvedConfiguration)
        owned = player
        return player
    }

    /// A repeat call with the same source is a complete no-op — it neither
    /// reapplies the source nor calls `play()` again, so a paused player
    /// stays paused across `body` re-evaluation.
    func apply(source: ABMediaSource, autoplay: Bool) {
        guard let owned, appliedSource != source else { return }
        appliedSource = source
        owned.set(source: source, grade: .current)
        if autoplay {
            owned.play()
        }
    }

    /// No-op when this box never created a player (the explicit `player:`
    /// initializer path leaves it empty) or already released one.
    func releaseIfOwned() {
        guard !didRelease, let owned else { return }
        didRelease = true
        owned.release()
    }

    deinit {
        guard !didRelease, let owned else { return }
        Task { @MainActor in
            owned.release()
        }
    }
}
