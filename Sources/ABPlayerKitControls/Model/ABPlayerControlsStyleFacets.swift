import UIKit

/// The single source of truth for what a style-property change costs to
/// redraw — replaces three independent diff lists (`iconsDiffer`,
/// `requiresControlsLayout`, `ABSeekBar.requiresSeekBarLayout`) that used to
/// require remembering to update all three whenever a property was added.
/// Miss this registry and the exhaustiveness test (comparing its names
/// against `Mirror(reflecting:)`'s stored-property labels) fails instead of
/// silently under-invalidating.
extension ABPlayerControlsStyle {
    struct ChangeImpact: OptionSet, Sendable {
        let rawValue: Int
        /// Requires `invalidateIntrinsicContentSize()` on the icon buttons.
        static let iconRebuild = ChangeImpact(rawValue: 1 << 0)
        /// Requires `setNeedsLayout()` on the controls overlay.
        static let controlsLayout = ChangeImpact(rawValue: 1 << 1)
        /// Requires `setNeedsLayout()` on the seek bar specifically.
        static let seekBarLayout = ChangeImpact(rawValue: 1 << 2)
        /// Redraw only — color/opacity-shaped values that never move a frame.
        static let paintOnly: ChangeImpact = []
    }

    struct Facet: Sendable {
        /// Must match the stored property's name exactly — the
        /// exhaustiveness test compares this set against
        /// `Mirror(reflecting:)`'s labels.
        let name: String
        let impact: ChangeImpact
        let isEqual: @Sendable (ABPlayerControlsStyle, ABPlayerControlsStyle) -> Bool
    }

    /// One entry per stored property, no more and no fewer — see this file's
    /// doc comment.
    static let facets: [Facet] = [
        Facet(name: "playIcon", impact: .iconRebuild) { $0.playIcon == $1.playIcon },
        Facet(name: "pauseIcon", impact: .iconRebuild) { $0.pauseIcon == $1.pauseIcon },
        Facet(name: "skipBackwardIcon", impact: .iconRebuild) { $0.skipBackwardIcon == $1.skipBackwardIcon },
        Facet(name: "skipForwardIcon", impact: .iconRebuild) { $0.skipForwardIcon == $1.skipForwardIcon },
        Facet(name: "iconPointSize", impact: .iconRebuild) { $0.iconPointSize == $1.iconPointSize },
        Facet(name: "iconWeight", impact: .iconRebuild) { $0.iconWeight == $1.iconWeight },
        Facet(name: "iconRenderingMode", impact: .iconRebuild) { $0.iconRenderingMode == $1.iconRenderingMode },
        Facet(name: "rateLabelStyle", impact: .iconRebuild) { $0.rateLabelStyle == $1.rateLabelStyle },

        Facet(name: "playPauseButtonSize", impact: .controlsLayout) { $0.playPauseButtonSize == $1.playPauseButtonSize },
        Facet(name: "skipButtonSize", impact: .controlsLayout) { $0.skipButtonSize == $1.skipButtonSize },
        Facet(name: "buttonSpacing", impact: .controlsLayout) { $0.buttonSpacing == $1.buttonSpacing },
        Facet(name: "timeLabelFont", impact: .controlsLayout) { $0.timeLabelFont == $1.timeLabelFont },
        Facet(name: "usesFixedWidthTimeLabels", impact: .controlsLayout) { $0.usesFixedWidthTimeLabels == $1.usesFixedWidthTimeLabels },
        Facet(name: "rateButtonSize", impact: .controlsLayout) { $0.rateButtonSize == $1.rateButtonSize },
        Facet(name: "contentInsets", impact: .controlsLayout) { $0.contentInsets == $1.contentInsets },
        Facet(name: "containerCornerRadius", impact: .controlsLayout) { $0.containerCornerRadius == $1.containerCornerRadius },
        Facet(name: "seekBarBottomSpacing", impact: .controlsLayout) { $0.seekBarBottomSpacing == $1.seekBarBottomSpacing },

        Facet(name: "trackHeight", impact: [.controlsLayout, .seekBarLayout]) { $0.trackHeight == $1.trackHeight },
        Facet(name: "trackHeightWhileScrubbing", impact: [.controlsLayout, .seekBarLayout]) { $0.trackHeightWhileScrubbing == $1.trackHeightWhileScrubbing },
        Facet(name: "trackCornerRadius", impact: [.controlsLayout, .seekBarLayout]) { $0.trackCornerRadius == $1.trackCornerRadius },
        Facet(name: "seekBarHorizontalInset", impact: [.controlsLayout, .seekBarLayout]) { $0.seekBarHorizontalInset == $1.seekBarHorizontalInset },
        Facet(name: "thumbSize", impact: [.controlsLayout, .seekBarLayout]) { $0.thumbSize == $1.thumbSize },
        Facet(name: "thumbSizeWhileScrubbing", impact: [.controlsLayout, .seekBarLayout]) { $0.thumbSizeWhileScrubbing == $1.thumbSizeWhileScrubbing },
        Facet(name: "thumbBorderWidth", impact: [.controlsLayout, .seekBarLayout]) { $0.thumbBorderWidth == $1.thumbBorderWidth },
        Facet(name: "thumbCornerRadius", impact: [.controlsLayout, .seekBarLayout]) { $0.thumbCornerRadius == $1.thumbCornerRadius },
        Facet(name: "thumbShadowRadius", impact: [.controlsLayout, .seekBarLayout]) { $0.thumbShadowRadius == $1.thumbShadowRadius },
        Facet(name: "thumbImage", impact: [.controlsLayout, .seekBarLayout]) { $0.thumbImage == $1.thumbImage },
        Facet(name: "isThumbHidden", impact: [.controlsLayout, .seekBarLayout]) { $0.isThumbHidden == $1.isThumbHidden },

        Facet(name: "buttonHighlightedAlpha", impact: .paintOnly) { $0.buttonHighlightedAlpha == $1.buttonHighlightedAlpha },
        Facet(name: "tintColor", impact: .paintOnly) { $0.tintColor == $1.tintColor },
        Facet(name: "disabledTintColor", impact: .paintOnly) { $0.disabledTintColor == $1.disabledTintColor },
        Facet(name: "timeLabelColor", impact: .paintOnly) { $0.timeLabelColor == $1.timeLabelColor },
        Facet(name: "trackColor", impact: .paintOnly) { $0.trackColor == $1.trackColor },
        Facet(name: "progressColor", impact: .paintOnly) { $0.progressColor == $1.progressColor },
        Facet(name: "bufferedColor", impact: .paintOnly) { $0.bufferedColor == $1.bufferedColor },
        Facet(name: "thumbColor", impact: .paintOnly) { $0.thumbColor == $1.thumbColor },
        Facet(name: "thumbBorderColor", impact: .paintOnly) { $0.thumbBorderColor == $1.thumbBorderColor },
        Facet(name: "thumbShadowOpacity", impact: .paintOnly) { $0.thumbShadowOpacity == $1.thumbShadowOpacity },
        Facet(name: "thumbTouchInflation", impact: .paintOnly) { $0.thumbTouchInflation == $1.thumbTouchInflation },
        Facet(name: "backgroundStyle", impact: .paintOnly) { $0.backgroundStyle == $1.backgroundStyle },
        Facet(name: "visibilityAnimationDuration", impact: .paintOnly) { $0.visibilityAnimationDuration == $1.visibilityAnimationDuration },
        Facet(name: "respectsReduceMotion", impact: .paintOnly) { $0.respectsReduceMotion == $1.respectsReduceMotion },
        Facet(name: "bufferingIndicatorColor", impact: .paintOnly) { $0.bufferingIndicatorColor == $1.bufferingIndicatorColor },
        Facet(name: "seekFeedbackTextColor", impact: .paintOnly) { $0.seekFeedbackTextColor == $1.seekFeedbackTextColor },
        Facet(name: "seekFeedbackBackgroundColor", impact: .paintOnly) { $0.seekFeedbackBackgroundColor == $1.seekFeedbackBackgroundColor },
        Facet(name: "seekFeedbackFont", impact: .paintOnly) { $0.seekFeedbackFont == $1.seekFeedbackFont }
    ]

    /// The union of every facet's impact where `self` and `previous` disagree.
    func changeImpact(comparedTo previous: Self) -> ChangeImpact {
        var impact: ChangeImpact = []
        for facet in Self.facets where !facet.isEqual(self, previous) {
            impact.formUnion(facet.impact)
        }
        return impact
    }
}
