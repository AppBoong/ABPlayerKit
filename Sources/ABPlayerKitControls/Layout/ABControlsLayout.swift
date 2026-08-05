import UIKit

/// Pure geometry calculations for `ABPlayerControlsView`. Values here depend
/// only on `style` and `traitCollection` — the same reason
/// `ABControlsVisibilityMachine` is a value type with no `UIView` dependency —
/// so the whole surface can be unit tested without a `UIView` instance.
struct ABControlsLayout {
    let style: ABPlayerControlsStyle
    let traitCollection: UITraitCollection

    /// The seek bar's fixed touch-target row height. The visible track is
    /// vertically centered inside it (see `ABSeekBar.layoutSubviews`), so the
    /// row is taller than the drawn track by design (44pt hit area, HIG/a11y).
    static let seekBarTouchRowHeight: CGFloat = 44

    /// `style.seekBarBottomSpacing` is a gap between the seek bar's *visible*
    /// track and the row below it's *visible glyphs* — not between either
    /// side's full 44pt touch-target frame and the other. Both sides center
    /// their visible content inside a taller accessible touch area (the seek
    /// bar's track inside its 44pt row; the rate button's title/icon inside
    /// its own 44pt `rateButtonSize.height`), so half of each side's slack
    /// must be subtracted from the stack spacing to land the two visible
    /// surfaces at the requested distance. This routinely goes negative,
    /// deliberately overlapping the touch rows with each other and with the
    /// row below (hit-test priority in `hitTest(_:with:)` already resolves any
    /// resulting ambiguity in favor of the more specific control).
    var rootStackSpacing: CGFloat {
        let touchRowSlackBelowTrack = (Self.seekBarTouchRowHeight - style.trackHeight) / 2
        return style.seekBarBottomSpacing - touchRowSlackBelowTrack - bottomRowVisibleContentSlack
    }

    /// How much of the bottom row's cross-axis height sits above its visible
    /// *ink*, on the *tightest* side:
    /// - Whichever side sits closest to the seek bar's own ink dictates the
    ///   distance; using the *smaller* of the two sides keeps that one at
    ///   exactly `seekBarBottomSpacing`, while the looser side lands within a
    ///   point or two of it (two different fonts can't both hit one target
    ///   from a single shared stack-spacing value).
    /// - `elapsedLabel` is a *direct* arranged child of the bottom row, so its
    ///   own frame is centered directly in the row's cross-axis height.
    /// - The rate button's title is nested one level deeper: `rateButton`
    ///   itself (fixed at `rateButtonSize.height`) is the arranged child, so
    ///   its title is centered inside *that* fixed height first, and the
    ///   button itself is then centered inside the row.
    ///
    /// Uses `scaledTimeLabelFont` for the label side — the font
    /// `elapsedLabel` actually renders with, including `UIFontMetrics`
    /// Dynamic Type scaling — not `style.timeLabelFont` directly (confirmed
    /// on-device: unscaled 8.5pt vs. AX3-scaled 26.8pt capHeight; using the
    /// unscaled value under-subtracts the slack and lets the real, larger
    /// label collide with the track above it). The rate button's title font
    /// is *not* Dynamic Type-scaled (no `UIFontMetrics`/
    /// `adjustsFontForContentSizeCategory` wiring for it currently), so
    /// `style.rateLabelStyle`'s raw font remains accurate for that side.
    var bottomRowVisibleContentSlack: CGFloat {
        // The row's real cross-axis height is whichever child is tallest — normally
        // the rate button's fixed rateButtonSize.height, but a `UIStackView` with
        // `alignment = .center` never clips: at a large enough Dynamic Type size,
        // elapsedLabel's own (scaled) line height can exceed the rate button's and
        // become the row's actual height instead, growing the whole row (and, with
        // it, the rate button's own centering slack) rather than just the label's.
        let rowHeight = max(style.rateButtonSize.height, scaledTimeLabelFont.lineHeight)
        return min(
            Self.frameTopToInkTop(font: scaledTimeLabelFont, centeredIn: rowHeight),
            rateButtonBottomRowSlack(rowHeight: rowHeight)
        )
    }

    private func rateButtonBottomRowSlack(rowHeight: CGFloat) -> CGFloat {
        let buttonHeight = style.rateButtonSize.height
        let buttonCenteringSlack = max(0, (rowHeight - buttonHeight) / 2)
        switch style.rateLabelStyle {
        case .text(let font, _):
            return buttonCenteringSlack + Self.frameTopToInkTop(font: font, centeredIn: buttonHeight)
        case .icon:
            // An icon's height is its rendered size, not font metrics — no
            // ascender/capHeight gap applies; centering slack alone does.
            return buttonCenteringSlack + max(0, (buttonHeight - style.iconPointSize) / 2)
        }
    }

    /// Distance from the top of a `containerHeight`-tall box to `font`'s ink
    /// top, when a label/title using `font` is vertically centered in it:
    /// half the box's slack around the font's line height, plus the further
    /// offset from that (now-positioned) frame's own top down to where the
    /// font's cap-height glyphs actually start drawing.
    ///
    /// Deliberately *not* a fixed-point or point-size-ratio calibration
    /// (both were tried and rejected — see IMPL-v0.2-RESULT.md's
    /// REVIEW2-FIXES-DONE entry for the numbers): a value tuned to land
    /// exactly on `seekBarBottomSpacing` at the 12pt default font
    /// systematically over- or under-corrected at a much larger accessibility
    /// font, in one case badly enough to collide the label into the track —
    /// exactly the bug this function exists to prevent. This real-metrics
    /// version is deliberately not pixel-perfect at the default size (it
    /// lands within roughly a point and a half of `seekBarBottomSpacing`
    /// rather than exactly on it — confirmed on-device), but it never
    /// collides at any tested font size, which matters far more than being
    /// exact at exactly one of them.
    private static func frameTopToInkTop(font: UIFont, centeredIn containerHeight: CGFloat) -> CGFloat {
        let centeringSlack = max(0, (containerHeight - font.lineHeight) / 2)
        let inkOffsetWithinFrame = max(0, font.ascender - font.capHeight)
        return centeringSlack + inkOffsetWithinFrame
    }

    /// The font `elapsedLabel` actually renders with — `style.timeLabelFont`
    /// run through `UIFontMetrics(.caption1)` for the current trait
    /// collection, matching the assignment in `applyStyle`. Computed fresh
    /// rather than read from `elapsedLabel.font` so `rootStackSpacing`
    /// can be read before the label's font is first assigned.
    var scaledTimeLabelFont: UIFont {
        UIFontMetrics(forTextStyle: .caption1).scaledFont(for: style.timeLabelFont, compatibleWith: traitCollection)
    }

    /// The minimum width to reserve for the elapsed/duration label so it
    /// doesn't reflow the layout as its digits change, sized to the widest
    /// value the label's format can produce (`"00:00:00/-00:00:00"`) at
    /// `font`.
    func timeLabelMinimumWidth(using font: UIFont) -> CGFloat {
        let reference = "00:00:00/-00:00:00" as NSString
        return ceil(reference.size(withAttributes: [.font: font]).width)
    }
}
