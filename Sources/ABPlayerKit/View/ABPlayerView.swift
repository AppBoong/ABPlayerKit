@preconcurrency import AVFoundation
import UIKit

/// A `UIView` whose backing layer is an `AVPlayerLayer`. Owns first-frame
/// detection for whichever `ABPlayer` is currently attached
/// (DESIGN-ABPlayerKit.md §5.5).
@MainActor
public final class ABPlayerView: UIView {
    public override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer {
        // Safe force-unwrap: `layerClass` guarantees this view's backing
        // layer is always an `AVPlayerLayer`.
        layer as! AVPlayerLayer // swiftlint:disable:this force_cast
    }

    /// Attaching a new player first tears down the previous player's
    /// first-frame observation, then wires the new one — order is fixed to
    /// avoid a stale report racing a fresh attachment.
    public var player: ABPlayer? {
        didSet { attach(player) }
    }

    /// Setting this applies the change inside a `CATransaction` with
    /// implicit animations disabled, so a gravity change never animates.
    public var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.videoGravity = newValue
            CATransaction.commit()
        }
    }

    public var isReadyForDisplay: Bool { playerLayer.isReadyForDisplay }

    /// When `true`, gravity is chosen from the attached item's
    /// `presentationSize` once known, instead of always using the
    /// configured default. Default `false` — the reels convention is
    /// always `resizeAspectFill` (DESIGN-ABPlayerKit.md §10, weakness #15:
    /// replaces a dead, never-called `applyVideoGravity` with a single
    /// opt-in setting).
    public var adaptsGravityToAspectRatio = false {
        didSet { applyAdaptiveGravityIfNeeded() }
    }

    private lazy var detector = ABFirstFrameDetector { [weak self] time in
        self?.player?.reportFirstFrameDisplayed(at: time)
        self?.applyAdaptiveGravityIfNeeded()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        applyAdaptiveGravityIfNeeded()
    }

    private func attach(_ newPlayer: ABPlayer?) {
        detector.invalidate()
        playerLayer.player = newPlayer?.avPlayer
        videoGravity = newPlayer?.configuration.videoGravity ?? .resizeAspectFill
        detector.observe(layer: playerLayer, item: newPlayer?.avPlayerItem)
        applyAdaptiveGravityIfNeeded()
    }

    private func applyAdaptiveGravityIfNeeded() {
        guard adaptsGravityToAspectRatio,
              bounds.height > 0,
              let presentationSize = player?.avPlayerItem?.presentationSize,
              presentationSize.width > 0, presentationSize.height > 0
        else { return }

        let contentAspect = presentationSize.width / presentationSize.height
        let viewAspect = bounds.width / bounds.height
        videoGravity = abs(contentAspect - viewAspect) < 0.05 ? .resizeAspectFill : .resizeAspect
    }
}
