import ABPlayerKit
import QuartzCore
import UIKit

@MainActor
final class ABSeekBar: UIControl {
    enum InteractionPhase {
        case began
        case changed
        case ended
        case cancelled
    }

    var style = ABPlayerControlsStyle() {
        didSet {
            applyStyle()
            setNeedsLayout()
        }
    }
    var progress: Double = 0 {
        didSet {
            progress = Self.clamp(progress)
            setNeedsLayout()
        }
    }
    var bufferedProgress: Double = 0 {
        didSet {
            bufferedProgress = Self.clamp(bufferedProgress)
            setNeedsLayout()
        }
    }
    var showsBufferedProgress = true {
        didSet { bufferedLayer.isHidden = !showsBufferedProgress }
    }
    var allowsTrackTapToSeek = true
    var isSeekEnabled = true {
        didSet { isUserInteractionEnabled = isSeekEnabled }
    }

    var onScrubBegan: (() -> Void)?
    var onScrubChanged: ((Double) -> Void)?
    var onScrubEnded: ((Double) -> Void)?

    private let trackLayer = CALayer()
    private let bufferedLayer = CALayer()
    private let progressLayer = CALayer()
    private let thumbLayer = CALayer()
    private(set) var isScrubbing = false

    var renderedTrackHeight: CGFloat {
        isScrubbing ? style.trackHeightWhileScrubbing : style.trackHeight
    }

    var renderedThumbSize: CGSize {
        isScrubbing ? style.thumbSizeWhileScrubbing : style.thumbSize
    }

    var renderedTrackFrame: CGRect { trackLayer.frame }
    var renderedBufferedFrame: CGRect { bufferedLayer.frame }
    var renderedProgressFrame: CGRect { progressLayer.frame }
    var renderedThumbFrame: CGRect { thumbLayer.frame }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        layer.addSublayer(trackLayer)
        layer.addSublayer(bufferedLayer)
        layer.addSublayer(progressLayer)
        layer.addSublayer(thumbLayer)
        applyStyle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isAccessibilityElement = true
        layer.addSublayer(trackLayer)
        layer.addSublayer(bufferedLayer)
        layer.addSublayer(progressLayer)
        layer.addSublayer(thumbLayer)
        applyStyle()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let geometry = currentGeometry
        let height = max(0, renderedTrackHeight)
        let trackFrame = CGRect(
            x: min(style.seekBarHorizontalInset, bounds.width / 2),
            y: (bounds.height - height) / 2,
            width: max(0, bounds.width - (2 * style.seekBarHorizontalInset)),
            height: height
        )
        trackLayer.frame = trackFrame
        bufferedLayer.frame = CGRect(
            x: trackFrame.minX,
            y: trackFrame.minY,
            width: min(trackFrame.width, geometry.progressWidth(forProgress: bufferedProgress)),
            height: trackFrame.height
        )
        progressLayer.frame = CGRect(
            x: trackFrame.minX,
            y: trackFrame.minY,
            width: min(trackFrame.width, geometry.progressWidth(forProgress: progress)),
            height: trackFrame.height
        )
        let thumbSize = renderedThumbSize
        thumbLayer.frame = CGRect(
            x: geometry.thumbCenterX(forProgress: progress) - (thumbSize.width / 2),
            y: (bounds.height - thumbSize.height) / 2,
            width: thumbSize.width,
            height: thumbSize.height
        )
        applyCornerRadii()
        CATransaction.commit()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        beginInteraction(at: touch.location(in: self).x)
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        continueInteraction(at: touch.location(in: self).x)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        endInteraction(at: touch?.location(in: self).x)
    }

    override func cancelTracking(with event: UIEvent?) {
        handleInteraction(.cancelled, x: nil)
    }

    @discardableResult
    func beginInteraction(at x: CGFloat) -> Bool {
        guard isSeekEnabled else { return false }
        let expandedThumb = thumbLayer.frame.insetBy(
            dx: -style.thumbTouchInflation,
            dy: -style.thumbTouchInflation
        )
        guard allowsTrackTapToSeek || expandedThumb.contains(CGPoint(x: x, y: bounds.midY)) else {
            return false
        }
        handleInteraction(.began, x: x)
        return true
    }

    @discardableResult
    func continueInteraction(at x: CGFloat) -> Bool {
        guard isScrubbing else { return false }
        handleInteraction(.changed, x: x)
        return true
    }

    func endInteraction(at x: CGFloat?) {
        guard isScrubbing else { return }
        handleInteraction(.ended, x: x)
    }

    func setScrubbing(_ scrubbing: Bool, animated: Bool) {
        guard isScrubbing != scrubbing else { return }
        isScrubbing = scrubbing
        let duration = animated ? style.visibilityAnimationDuration : 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        setNeedsLayout()
        layoutIfNeeded()
        CATransaction.commit()
    }

    private var currentGeometry: ABSeekBarGeometry {
        ABSeekBarGeometry(
            trackWidth: bounds.width,
            thumbWidth: style.isThumbHidden ? 0 : renderedThumbSize.width,
            horizontalInset: style.seekBarHorizontalInset
        )
    }

    private func handleInteraction(_ phase: InteractionPhase, x: CGFloat?) {
        if let x {
            progress = currentGeometry.progress(forTouchX: x)
        }
        switch phase {
        case .began:
            setScrubbing(true, animated: true)
            onScrubBegan?()
            onScrubChanged?(progress)
        case .changed:
            onScrubChanged?(progress)
        case .ended:
            onScrubChanged?(progress)
            onScrubEnded?(progress)
            setScrubbing(false, animated: true)
        case .cancelled:
            onScrubEnded?(progress)
            setScrubbing(false, animated: true)
        }
        sendActions(for: .valueChanged)
    }

    private func applyStyle() {
        trackLayer.backgroundColor = style.trackColor.cgColor
        bufferedLayer.backgroundColor = style.bufferedColor.cgColor
        progressLayer.backgroundColor = style.progressColor.cgColor
        thumbLayer.backgroundColor = style.thumbImage == nil ? style.thumbColor.cgColor : UIColor.clear.cgColor
        thumbLayer.borderColor = style.thumbBorderColor?.cgColor
        thumbLayer.borderWidth = style.thumbBorderWidth
        thumbLayer.shadowColor = UIColor.black.cgColor
        thumbLayer.shadowOpacity = style.thumbShadowOpacity
        thumbLayer.shadowRadius = style.thumbShadowRadius
        thumbLayer.contents = style.thumbImage?.cgImage
        thumbLayer.contentsGravity = .resizeAspect
        thumbLayer.isHidden = style.isThumbHidden
        bufferedLayer.isHidden = !showsBufferedProgress
    }

    private func applyCornerRadii() {
        trackLayer.cornerRadius = cornerRadius(style.trackCornerRadius, size: trackLayer.bounds.size)
        bufferedLayer.cornerRadius = cornerRadius(style.trackCornerRadius, size: bufferedLayer.bounds.size)
        progressLayer.cornerRadius = cornerRadius(style.trackCornerRadius, size: progressLayer.bounds.size)
        thumbLayer.cornerRadius = cornerRadius(style.thumbCornerRadius, size: thumbLayer.bounds.size)
        thumbLayer.masksToBounds = style.thumbShadowOpacity == 0
    }

    private func cornerRadius(_ rule: ABTrackCornerRadius, size: CGSize) -> CGFloat {
        switch rule {
        case .capsule:
            min(size.width, size.height) / 2
        case .fixed(let radius):
            max(0, radius)
        case .square:
            0
        }
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
