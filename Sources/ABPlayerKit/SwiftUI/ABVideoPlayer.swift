@preconcurrency import AVFoundation
import SwiftUI

/// Thin `UIViewRepresentable` wrapper over `ABPlayerView`. Lives in the same
/// target as the rest of the core — the wrapper is under 40 lines and
/// `SwiftUI` has effectively zero link cost on iOS 17+, so splitting it into
/// its own target would only cost consumers a second `import`
/// (DESIGN-ABPlayerKit.md §2).
public struct ABVideoPlayer: UIViewRepresentable {
    private enum Ownership {
        case explicit(ABPlayer)
        case owned(ABMediaSource, autoplay: Bool, ABPlayerConfiguration)
    }

    private let ownership: Ownership
    private let videoGravity: AVLayerVideoGravity

    public init(player: ABPlayer, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.ownership = .explicit(player)
        self.videoGravity = videoGravity
    }

    /// Creates and owns its own `ABPlayer` for the lifetime of this view's
    /// identity — released when the identity's storage (this
    /// representable's `Coordinator`) is torn down, never on
    /// `dismantleUIView` alone (see `Coordinator`). Media type is inferred
    /// from `url`'s extension; use the `source:` initializer to specify it
    /// explicitly or to carry HTTP headers.
    public init(
        url: URL,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        configuration: ABPlayerConfiguration = ABPlayerConfiguration()
    ) {
        self.init(
            source: ABMediaSource(url: url),
            videoGravity: videoGravity,
            autoplay: autoplay,
            configuration: configuration
        )
    }

    /// Same ownership as `init(url:videoGravity:autoplay:configuration:)`,
    /// taking a pre-built `ABMediaSource` for explicit `kind`/`httpHeaders`.
    public init(
        source: ABMediaSource,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        configuration: ABPlayerConfiguration = ABPlayerConfiguration()
    ) {
        self.ownership = .owned(source, autoplay: autoplay, configuration)
        self.videoGravity = videoGravity
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> ABPlayerView {
        let view = ABPlayerView()
        switch ownership {
        case .explicit(let player):
            view.player = player
        case .owned(let source, let autoplay, let configuration):
            let player = context.coordinator.player(configuration: configuration, videoGravity: videoGravity)
            context.coordinator.apply(source: source, autoplay: autoplay)
            view.player = player
        }
        view.videoGravity = videoGravity
        return view
    }

    public func updateUIView(_ uiView: ABPlayerView, context: Context) {
        switch ownership {
        case .explicit(let player):
            if uiView.player !== player {
                uiView.player = player
            }
        case .owned(let source, let autoplay, _):
            context.coordinator.apply(source: source, autoplay: autoplay)
        }
        uiView.videoGravity = videoGravity
    }

    public static func dismantleUIView(_ uiView: ABPlayerView, coordinator: Coordinator) {
        coordinator.releaseIfOwned()
    }

    /// Implementation detail. No public members — `UIViewRepresentable`
    /// requires an associated `Coordinator` type, which is what makes this
    /// `public` in the first place.
    ///
    /// Backs the `url:`/`source:` initializers' ownership: created once in
    /// `makeUIView`, torn down synchronously in `dismantleUIView` when
    /// SwiftUI discards this view's identity — never on the player merely
    /// scrolling off-screen, since this type never observes `onDisappear`.
    /// For the `player:` initializer this coordinator is still created (one
    /// per identity, same as any `UIViewRepresentable`) but stays empty:
    /// `releaseIfOwned()` is a no-op because nothing was ever handed to it.
    @MainActor
    public final class Coordinator {
        private var owned: ABPlayer?
        private var appliedSource: ABMediaSource?
        private var didRelease = false

        /// `configuration` is applied only the first time this is called for
        /// a given coordinator — a later call (from `updateUIView`, carrying
        /// whatever `configuration` value this SwiftUI value happens to hold
        /// on that pass) returns the existing player untouched, so settings
        /// changed after creation (e.g. the rate the user picked from a
        /// controls menu) can't be silently reverted by a parent re-render.
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

        /// A repeat call with the same source is a complete no-op — it
        /// neither reapplies the source nor calls `play()` again, so a
        /// paused player stays paused across body/`updateUIView`
        /// re-evaluation.
        func apply(source: ABMediaSource, autoplay: Bool) {
            guard let owned, appliedSource != source else { return }
            appliedSource = source
            owned.set(source: source, grade: .current)
            if autoplay {
                owned.play()
            }
        }

        /// No-op when this coordinator never owned a player (the `player:`
        /// initializer's path) or already released one.
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
}
