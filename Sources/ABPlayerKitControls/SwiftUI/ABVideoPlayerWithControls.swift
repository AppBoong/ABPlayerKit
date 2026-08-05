@preconcurrency import AVFoundation
import ABPlayerKit
import SwiftUI

/// A ready-made SwiftUI composition of video content and playback controls.
@MainActor
public struct ABVideoPlayerWithControls: View {
    private let player: ABPlayer
    private let videoGravity: AVLayerVideoGravity
    /// Built eagerly, inside each initializer below, from whichever
    /// `ABPlayerControls` initializer matches — the deprecated
    /// `init(legacyPlayer:...)` bridge for the legacy `accessoryViews:`
    /// path, `init(player:...accessories:)` for the new one. `body` below
    /// only ever reads this single, already-built, type-erased value —
    /// never either `ABPlayerControls` initializer directly — so it stays
    /// warning-free while covering both paths from one non-deprecated
    /// property. A deprecated declaration calling another deprecated
    /// declaration doesn't warn, which is what lets the legacy branch build
    /// this from inside *this type's own* deprecated initializer without
    /// tripping `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (round4 review WP-B3's
    /// "CI 함정" note, mn-8).
    private let controlsView: AnyView

    @available(*, deprecated, message: "Use the @ViewBuilder `accessories:` initializer instead. Scheduled for removal in 1.0.0.")
    public init(
        player: ABPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init(),
        accessoryViews: [UIView] = []
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.controlsView = AnyView(
            ABPlayerControls(
                legacyPlayer: player,
                style: style,
                configuration: configuration,
                accessoryViews: accessoryViews,
                onEvent: nil
            )
        )
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
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init(),
        @ViewBuilder accessories: @escaping () -> Accessories
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.controlsView = AnyView(
            ABPlayerControls(player: player, style: style, configuration: configuration, accessories: accessories)
        )
    }

    public var body: some View {
        ABVideoPlayer(player: player, videoGravity: videoGravity)
            .overlay {
                controlsView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }
}
