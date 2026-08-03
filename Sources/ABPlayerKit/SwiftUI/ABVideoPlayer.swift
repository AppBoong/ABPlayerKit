@preconcurrency import AVFoundation
import SwiftUI

/// Thin `UIViewRepresentable` wrapper over `ABPlayerView`. Lives in the same
/// target as the rest of the core — the wrapper is under 40 lines and
/// `SwiftUI` has effectively zero link cost on iOS 17+, so splitting it into
/// its own target would only cost consumers a second `import`
/// (DESIGN-ABPlayerKit.md §2).
public struct ABVideoPlayer: UIViewRepresentable {
    private let player: ABPlayer
    private let videoGravity: AVLayerVideoGravity

    public init(player: ABPlayer, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.player = player
        self.videoGravity = videoGravity
    }

    public func makeUIView(context: Context) -> ABPlayerView {
        let view = ABPlayerView()
        view.player = player
        view.videoGravity = videoGravity
        return view
    }

    public func updateUIView(_ uiView: ABPlayerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
        uiView.videoGravity = videoGravity
    }
}
