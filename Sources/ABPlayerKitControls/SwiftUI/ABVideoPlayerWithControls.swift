@preconcurrency import AVFoundation
import ABPlayerKit
import SwiftUI

/// A ready-made SwiftUI composition of video content and playback controls.
@MainActor
public struct ABVideoPlayerWithControls: View {
    private enum Ownership {
        /// The `AnyView` is built eagerly, inside each `.explicit`-path
        /// initializer below, from whichever `ABPlayerControls` initializer
        /// matches — the deprecated `init(legacyPlayer:...)` bridge for the
        /// legacy `accessoryViews:` path, `init(player:...accessories:)` for
        /// the new one. `body` below only ever reads this single,
        /// already-built, type-erased value — never either
        /// `ABPlayerControls` initializer directly — so it stays
        /// warning-free while covering both paths from one non-deprecated
        /// property. A deprecated declaration calling another deprecated
        /// declaration doesn't warn, which is what lets the legacy branch
        /// build this from inside *this type's own* deprecated initializer
        /// without tripping `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (round4
        /// review WP-B3's "CI 함정" note, mn-8).
        case explicit(ABPlayer, controls: AnyView)
        /// The `.owned` path's player doesn't exist yet at initializer
        /// time, so it has nothing to build eagerly — its `ABPlayerControls`
        /// is built lazily in `body` instead, once `owner` has a player.
        case owned(ABMediaSource, autoplay: Bool, ABPlayerConfiguration)
    }

    private let ownership: Ownership
    private let videoGravity: AVLayerVideoGravity
    private let style: ABPlayerControlsStyle?
    private let configuration: ABPlayerControlsConfiguration?
    /// Only used by the `.owned` path — `nil` means no accessories were
    /// requested (routes to `ABPlayerControls`'s `EmptyView`-skips-hosting
    /// shortcut), a closure means accessories content, type-erased since
    /// this struct itself isn't generic over the accessories view type.
    private let accessoriesContent: (() -> AnyView)?

    /// Backs the `.owned` path only — see `ABOwnedPlayerBox`'s own doc
    /// comment. Left untouched (and its `deinit` stays a no-op) on the
    /// `.explicit` path, where `player` already comes from the caller.
    @State private var owner = ABOwnedPlayerBox()

    @available(*, deprecated, message: "Use the @ViewBuilder `accessories:` initializer instead. Scheduled for removal in 1.0.0.")
    public init(
        player: ABPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        style: ABPlayerControlsStyle? = nil,
        configuration: ABPlayerControlsConfiguration? = nil,
        accessoryViews: [UIView] = []
    ) {
        self.ownership = .explicit(
            player,
            controls: AnyView(
                ABPlayerControls(
                    legacyPlayer: player,
                    style: style,
                    configuration: configuration,
                    accessoryViews: accessoryViews,
                    onEvent: nil
                )
            )
        )
        self.videoGravity = videoGravity
        self.style = style
        self.configuration = configuration
        self.accessoriesContent = nil
    }

    /// SwiftUI accessory overlay content — see `ABPlayerControls`'s matching
    /// initializer, which this delegates to. No separate hosting box
    /// ownership is needed here: the nested `ABPlayerControls`'s own
    /// `Coordinator` owns it, and that `Coordinator` persists across
    /// `ABVideoPlayerWithControls.body` recomputation the same way any
    /// `UIViewRepresentable`'s coordinator does.
    public init<Accessories: View>(
        player: ABPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        style: ABPlayerControlsStyle? = nil,
        configuration: ABPlayerControlsConfiguration? = nil,
        @ViewBuilder accessories: @escaping () -> Accessories
    ) {
        self.ownership = .explicit(
            player,
            controls: AnyView(
                ABPlayerControls(player: player, style: style, configuration: configuration, accessories: accessories)
            )
        )
        self.videoGravity = videoGravity
        self.style = style
        self.configuration = configuration
        self.accessoriesContent = nil
    }

    /// Creates and owns its own `ABPlayer` for the lifetime of this view's
    /// identity — this is the whole integration, one line. Media type is
    /// inferred from `url`'s extension; use the `source:` initializer to
    /// specify it explicitly or to carry HTTP headers. Controls appearance
    /// is customized with `.playerControlsStyle(_:)`/
    /// `.playerControlsConfiguration(_:)`, not an initializer argument —
    /// see those modifiers.
    public init(
        url: URL,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        playerConfiguration: ABPlayerConfiguration = ABPlayerConfiguration()
    ) {
        self.init(
            source: ABMediaSource(url: url),
            videoGravity: videoGravity,
            autoplay: autoplay,
            playerConfiguration: playerConfiguration
        )
    }

    /// Same ownership as `init(url:videoGravity:autoplay:playerConfiguration:)`,
    /// taking a pre-built `ABMediaSource` for explicit `kind`/`httpHeaders`.
    public init(
        source: ABMediaSource,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        playerConfiguration: ABPlayerConfiguration = ABPlayerConfiguration()
    ) {
        self.ownership = .owned(source, autoplay: autoplay, playerConfiguration)
        self.videoGravity = videoGravity
        self.style = nil
        self.configuration = nil
        self.accessoriesContent = nil
    }

    /// Same ownership as `init(url:videoGravity:autoplay:playerConfiguration:)`,
    /// with a SwiftUI accessory overlay — see `ABPlayerControls`'s matching
    /// initializer.
    public init<Accessories: View>(
        url: URL,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        playerConfiguration: ABPlayerConfiguration = ABPlayerConfiguration(),
        @ViewBuilder accessories: @escaping () -> Accessories
    ) {
        self.init(
            source: ABMediaSource(url: url),
            videoGravity: videoGravity,
            autoplay: autoplay,
            playerConfiguration: playerConfiguration,
            accessories: accessories
        )
    }

    /// Same ownership as `init(source:videoGravity:autoplay:playerConfiguration:)`,
    /// with a SwiftUI accessory overlay.
    public init<Accessories: View>(
        source: ABMediaSource,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        playerConfiguration: ABPlayerConfiguration = ABPlayerConfiguration(),
        @ViewBuilder accessories: @escaping () -> Accessories
    ) {
        self.ownership = .owned(source, autoplay: autoplay, playerConfiguration)
        self.videoGravity = videoGravity
        self.style = nil
        self.configuration = nil
        self.accessoriesContent = Accessories.self == EmptyView.self ? nil : { AnyView(accessories()) }
    }

    public var body: some View {
        switch ownership {
        case .explicit(let player, let controls):
            ABVideoPlayer(player: player, videoGravity: videoGravity)
                .overlay {
                    controls
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        case .owned(let source, let autoplay, let playerConfiguration):
            ownedContent(source: source, autoplay: autoplay, playerConfiguration: playerConfiguration)
        }
    }

    /// A plain (non-`@ViewBuilder`) function, unlike `body` and
    /// `ownedControls(for:)` below — its `owner.apply(...)` call returns
    /// `Void`, which a result builder would reject as a non-`View`
    /// statement. An ordinary function body has no such restriction.
    private func ownedContent(
        source: ABMediaSource,
        autoplay: Bool,
        playerConfiguration: ABPlayerConfiguration
    ) -> some View {
        let player = owner.player(configuration: playerConfiguration, videoGravity: videoGravity)
        owner.apply(source: source, autoplay: autoplay)
        return ABVideoPlayer(player: player, videoGravity: videoGravity)
            .overlay {
                ownedControls(for: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }

    @ViewBuilder
    private func ownedControls(for player: ABPlayer) -> some View {
        if let accessoriesContent {
            ABPlayerControls(player: player, style: style, configuration: configuration) {
                accessoriesContent()
            }
        } else {
            ABPlayerControls(player: player, style: style, configuration: configuration) {}
        }
    }
}
