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
    }

    public var body: some View {
        ABVideoPlayer(player: player, videoGravity: videoGravity)
            .overlay {
                ABPlayerControls(
                    player: player,
                    style: style,
                    configuration: configuration,
                    accessoryViews: accessoryViews
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }
}
