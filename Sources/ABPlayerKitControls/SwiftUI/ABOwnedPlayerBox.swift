@preconcurrency import AVFoundation
import ABPlayerKit

/// Backs `ABVideoPlayerWithControls`'s `url:`/`source:` initializers'
/// ownership. Held in a `@State` property so it persists across the
/// SwiftUI value's reconstruction while tracking this view's identity —
/// released only when that `@State` storage is torn down, never on the
/// view merely scrolling off-screen (this type is never wired to
/// `onDisappear`).
///
/// The release lives in `deinit`, not in a `dismantleUIView` hook like the
/// core `ABVideoPlayer.Coordinator`'s. The difference is lifetime: a
/// representable's coordinator dies with its UIKit view, but lazy
/// containers can keep this `@State` alive across a dismantle/remake of
/// the views below it. Releasing on dismantle would hand the remade view a
/// released player that `apply` then refuses to restart.
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

    // Hops to the MainActor for the same reason `ABPlayerControls.Coordinator`'s
    // deinit does: `deinit` isn't statically MainActor-isolated under
    // tools-version 6.0, and `ABPlayer.release()` is.
    deinit {
        guard let owned else { return }
        Task { @MainActor in
            owned.release()
        }
    }
}
