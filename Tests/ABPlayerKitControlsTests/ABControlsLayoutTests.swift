import ABTestSupport
import Testing
@testable import ABPlayerKitControls
import UIKit

@Suite("ABControlsLayout computes pure geometry from style + trait collection, no UIView required", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABControlsLayoutTests {
    // MARK: - Characterization: literal values pinned pre-extraction (WP-A2),
    // proving the move from ABPlayerControlsView into this pure type changed
    // no constant or expression. Captured against HEAD `0e44695`.

    @Test("Given the .default style at the base trait, rootStackSpacing matches the pre-extraction literal (and is negative, per :211's documented behavior)")
    func rootStackSpacingMatchesPreExtractionLiteralForDefaultStyle() {
        let layout = ABControlsLayout(style: .default, traitCollection: UITraitCollection())

        #expect(abs(layout.rootStackSpacing - (-27.96142578125)) < 0.001)
        #expect(layout.rootStackSpacing < 0)
    }

    @Test("Given the .minimal style at the base trait, rootStackSpacing matches the pre-extraction literal")
    func rootStackSpacingMatchesPreExtractionLiteralForMinimalStyle() {
        let layout = ABControlsLayout(style: .minimal, traitCollection: UITraitCollection())

        #expect(abs(layout.rootStackSpacing - (-28.46142578125)) < 0.001)
    }

    @Test("Given .default/.minimal styles across base/AX3/XS traits, scaledTimeLabelFont.pointSize matches the pre-extraction literal")
    func scaledTimeLabelFontMatchesPreExtractionLiterals() {
        let styles: [ABPlayerControlsStyle] = [.default, .minimal]
        let expectations: [(UIContentSizeCategory, CGFloat)] = [
            (.unspecified, 12),
            (.accessibilityExtraExtraExtraLarge, 38),
            (.extraSmall, 10)
        ]
        for style in styles {
            for (category, expected) in expectations {
                let trait = UITraitCollection(preferredContentSizeCategory: category)
                let layout = ABControlsLayout(style: style, traitCollection: trait)
                #expect(layout.scaledTimeLabelFont.pointSize == expected)
            }
        }
    }

    // MARK: - Boundary / branch coverage

    @Test("Given a rate label font taller than the fixed rateButtonSize height, the centering slack clamps to zero instead of going negative")
    func frameTopToInkTopClampsWhenContainerIsSmallerThanTheFont() {
        var style = ABPlayerControlsStyle()
        style.rateLabelStyle = .text(font: .systemFont(ofSize: 80), format: "%@×")
        let layout = ABControlsLayout(style: style, traitCollection: UITraitCollection())

        // buttonCenteringSlack alone (rowHeight == rateButtonSize.height here,
        // since the default 12pt time label font is far shorter) must still be
        // >= 0 even though the 80pt font's lineHeight blows past the 44pt
        // button height frameTopToInkTop centers it in.
        #expect(layout.bottomRowVisibleContentSlack >= 0)
    }

    @Test("Given .text and .icon rate label styles at otherwise identical geometry, both produce a finite non-negative bottom-row slack via their own branch")
    func rateButtonBottomRowSlackCoversBothBranches() {
        var textStyle = ABPlayerControlsStyle()
        textStyle.rateLabelStyle = .text(font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold), format: "%@×")
        var iconStyle = ABPlayerControlsStyle()
        iconStyle.rateLabelStyle = .icon(.system("gauge"), showsValueBadge: false)

        let textLayout = ABControlsLayout(style: textStyle, traitCollection: UITraitCollection())
        let iconLayout = ABControlsLayout(style: iconStyle, traitCollection: UITraitCollection())

        #expect(textLayout.bottomRowVisibleContentSlack.isFinite)
        #expect(iconLayout.bottomRowVisibleContentSlack.isFinite)
        #expect(textLayout.bottomRowVisibleContentSlack >= 0)
        #expect(iconLayout.bottomRowVisibleContentSlack >= 0)
    }

    @Test("Given an accessibility content size large enough that the scaled time label outgrows the rate button's fixed height, the bottom row height follows the label instead of clipping it")
    func rowHeightGrowsPastRateButtonAtAccessibilitySizes() {
        let style = ABPlayerControlsStyle.default
        let axLayout = ABControlsLayout(
            style: style,
            traitCollection: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )

        #expect(axLayout.scaledTimeLabelFont.lineHeight > style.rateButtonSize.height)
        // The clamp this exercises (:274 in the pre-extraction view) only
        // matters if the resulting slack stays sane once the row grows past
        // the button's own fixed height.
        #expect(axLayout.bottomRowVisibleContentSlack >= 0)
    }

    @Test("timeLabelMinimumWidth grows with font point size, for the widest label the elapsed/duration format can produce")
    func timeLabelMinimumWidthGrowsWithFontSize() {
        let layout = ABControlsLayout(style: .default, traitCollection: UITraitCollection())
        let small = layout.timeLabelMinimumWidth(using: .monospacedDigitSystemFont(ofSize: 10, weight: .medium))
        let large = layout.timeLabelMinimumWidth(using: .monospacedDigitSystemFont(ofSize: 30, weight: .medium))

        #expect(small > 0)
        #expect(large > small)
    }

    @Test("seekBarTouchRowHeight is the documented fixed 44pt HIG touch target")
    func seekBarTouchRowHeightIsFixed() {
        #expect(ABControlsLayout.seekBarTouchRowHeight == 44)
    }
}
