import UIKit

/// The visual background behind the controls.
public enum ABControlsBackgroundStyle: Equatable {
    case none
    case color(UIColor)
    case gradient(top: UIColor, bottom: UIColor)
    case blur(UIBlurEffect.Style)
}

/// A rule for deriving a layer's corner radius.
public enum ABTrackCornerRadius: Equatable {
    case capsule
    case fixed(CGFloat)
    case square
}

/// The visual treatment for the playback-rate control.
public enum ABRateLabelStyle: Equatable {
    case text(font: UIFont, format: String)
    case icon(ABControlIcon, showsValueBadge: Bool)
}

/// Appearance values applied live by ``ABPlayerControlsView``.
public struct ABPlayerControlsStyle: Equatable {
    public var playIcon: ABControlIcon = .system("play.fill")
    public var pauseIcon: ABControlIcon = .system("pause.fill")
    public var skipBackwardIcon: ABControlIcon?
    public var skipForwardIcon: ABControlIcon?
    public var iconPointSize: CGFloat = 22
    public var iconWeight: UIImage.SymbolWeight = .semibold
    public var iconRenderingMode: UIImage.RenderingMode = .alwaysTemplate

    public var playPauseButtonSize = CGSize(width: 44, height: 44)
    public var skipButtonSize = CGSize(width: 44, height: 44)
    public var buttonSpacing: CGFloat = 32
    public var buttonHighlightedAlpha: CGFloat = 0.5

    public var tintColor: UIColor = .white
    public var disabledTintColor: UIColor = UIColor.white.withAlphaComponent(0.35)
    public var timeLabelColor: UIColor = .white
    public var timeLabelFont: UIFont = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    public var usesFixedWidthTimeLabels = true

    public var trackColor: UIColor = UIColor.white.withAlphaComponent(0.3)
    public var progressColor: UIColor = .white
    public var bufferedColor: UIColor = UIColor.white.withAlphaComponent(0.45)
    public var trackHeight: CGFloat = 3
    public var trackHeightWhileScrubbing: CGFloat = 6
    public var trackCornerRadius: ABTrackCornerRadius = .capsule
    public var seekBarHorizontalInset: CGFloat = 0

    public var thumbSize = CGSize(width: 12, height: 12)
    public var thumbSizeWhileScrubbing = CGSize(width: 18, height: 18)
    public var thumbColor: UIColor = .white
    public var thumbBorderColor: UIColor?
    public var thumbBorderWidth: CGFloat = 0
    public var thumbCornerRadius: ABTrackCornerRadius = .capsule
    public var thumbShadowOpacity: Float = 0.25
    public var thumbShadowRadius: CGFloat = 2
    public var thumbImage: UIImage?
    public var isThumbHidden = false
    public var thumbTouchInflation: CGFloat = 16

    public var rateLabelStyle: ABRateLabelStyle = .text(
        font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
        format: "%@×"
    )
    public var rateButtonSize = CGSize(width: 52, height: 44)

    public var backgroundStyle: ABControlsBackgroundStyle = .gradient(
        top: UIColor.black.withAlphaComponent(0.08),
        bottom: UIColor.black.withAlphaComponent(0.3)
    )
    public var contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    public var containerCornerRadius: CGFloat = 0
    public var seekBarBottomSpacing: CGFloat = 8

    public var visibilityAnimationDuration: TimeInterval = 0.25
    public var respectsReduceMotion = true

    public init() {}

    @MainActor public static let `default` = ABPlayerControlsStyle()

    @MainActor public static let minimal: ABPlayerControlsStyle = {
        var style = ABPlayerControlsStyle()
        style.backgroundStyle = .gradient(
            top: .clear,
            bottom: UIColor.black.withAlphaComponent(0.16)
        )
        style.bufferedColor = .clear
        style.trackColor = UIColor.white.withAlphaComponent(0.24)
        style.trackHeight = 2
        style.trackHeightWhileScrubbing = 3
        style.thumbSize = CGSize(width: 10, height: 10)
        style.thumbSizeWhileScrubbing = CGSize(width: 14, height: 14)
        style.thumbShadowOpacity = 0
        return style
    }()

    @MainActor public static let tinted: ABPlayerControlsStyle = {
        var style = ABPlayerControlsStyle()
        style.tintColor = .systemBlue
        style.progressColor = .systemBlue
        style.thumbColor = .systemBlue
        style.trackColor = UIColor.white.withAlphaComponent(0.28)
        style.bufferedColor = UIColor.systemBlue.withAlphaComponent(0.42)
        style.backgroundStyle = .gradient(
            top: UIColor.systemBlue.withAlphaComponent(0.04),
            bottom: UIColor.black.withAlphaComponent(0.24)
        )
        return style
    }()
}
