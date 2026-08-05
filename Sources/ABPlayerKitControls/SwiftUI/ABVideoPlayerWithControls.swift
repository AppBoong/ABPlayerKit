@preconcurrency import AVFoundation
import ABPlayerKit
import SwiftUI

/// A ready-made SwiftUI composition of video content and playback controls.
@MainActor
public struct ABVideoPlayerWithControls: View {
    private let player: ABPlayer
    private let videoGravity: AVLayerVideoGravity
    private let style: ABPlayerControlsStyle
    private let configuration: ABPlayerControlsConfiguration
    private let accessoryViews: [UIView]
    private let accessoriesContent: (() -> AnyView)?

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
        self.style = style
        self.configuration = configuration
        self.accessoryViews = accessoryViews
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
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init(),
        @ViewBuilder accessories: @escaping () -> Accessories
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.style = style
        self.configuration = configuration
        self.accessoryViews = []
        self.accessoriesContent = Accessories.self == EmptyView.self ? nil : { AnyView(accessories()) }
    }

    public var body: some View {
        ABVideoPlayer(player: player, videoGravity: videoGravity)
            .overlay {
                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }

    @ViewBuilder
    private var controls: some View {
        if let accessoriesContent {
            ABPlayerControls(player: player, style: style, configuration: configuration) {
                accessoriesContent()
            }
        } else {
            // Routes through `ABPlayerControls`'s non-deprecated
            // `legacyPlayer:` initializer, not its deprecated public
            // `accessoryViews:` one — see that initializer's doc comment for
            // why (ROADMAP-round4.md WP-B3's "CI 함정" note).
            ABPlayerControls(
                legacyPlayer: player,
                style: style,
                configuration: configuration,
                accessoryViews: accessoryViews,
                onEvent: nil
            )
        }
    }
}
