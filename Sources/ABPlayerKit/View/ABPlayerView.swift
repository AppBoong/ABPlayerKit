@preconcurrency import AVFoundation
import UIKit

/// A `UIView` whose backing layer is an `AVPlayerLayer`. Owns first-frame
/// detection for whichever `ABPlayer` is currently attached.
@MainActor
public final class ABPlayerView: UIView {
    public override static var layerClass: AnyClass { AVPlayerLayer.self }

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

    private var playerObservationToken: ABObservationToken?
    private var layerAttachmentToken: ABObservationToken?

    /// Binding a session creates an `AVPictureInPictureController` for this
    /// view's backing layer once. `nil` unbinds — deferred until the
    /// session's `isActive` returns to `false` if it's currently active
    /// (the session itself keeps this view alive in the meantime).
    public var pictureInPictureSession: ABPictureInPictureSession? {
        didSet {
            guard pictureInPictureSession !== oldValue else { return }
            oldValue?.unbind(from: self)
            pictureInPictureSession?.bind(to: self, layer: playerLayer)
        }
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
    /// always `resizeAspectFill`. Replaces a dead, never-called
    /// `applyVideoGravity` with a single opt-in setting.
    public var adaptsGravityToAspectRatio = false {
        didSet { applyAdaptiveGravityIfNeeded() }
    }

    private lazy var detector = ABFirstFrameDetector { [weak self] time in
        self?.player?.reportFirstFrameDisplayed(at: time)
        self?.applyAdaptiveGravityIfNeeded()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        player?.reportDisplaySize(CGSize(width: bounds.width * scale, height: bounds.height * scale))
        applyAdaptiveGravityIfNeeded()
    }

    private func attach(_ newPlayer: ABPlayer?) {
        playerObservationToken?.cancel()
        playerObservationToken = nil
        layerAttachmentToken?.cancel()
        layerAttachmentToken = nil
        detector.invalidate()
        playerLayer.player = nil

        guard let newPlayer else {
            videoGravity = .resizeAspectFill
            return
        }

        playerObservationToken = newPlayer.addObserver { [weak self, weak newPlayer] event in
            guard let self, self.player === newPlayer else { return }
            switch event {
            case .gradeChanged, .sourceChanged, .itemDetached:
                self.rebindPlayerLayer()
            case .presentationSizeChanged:
                // Event-driven re-evaluation alongside the `layoutSubviews`
                // trigger below — lets an aspect-ratio-driven gravity
                // change react to the item's size becoming known without
                // waiting for the next layout pass.
                self.applyAdaptiveGravityIfNeeded()
            default:
                break
            }
        }
        videoGravity = newPlayer.configuration.videoGravity
        layerAttachmentToken = newPlayer.addLayerAttachmentObserver { [weak self, weak newPlayer] _ in
            guard let self, self.player === newPlayer else { return }
            self.rebindPlayerLayer()
        }
        rebindPlayerLayer()
    }

    private func rebindPlayerLayer() {
        detector.invalidate()
        let attachedPlayer = player?.isLayerAttachmentEnabled == true ? player : nil
        playerLayer.player = attachedPlayer?.avPlayer
        detector.observe(layer: playerLayer, item: attachedPlayer?.avPlayerItem)
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
