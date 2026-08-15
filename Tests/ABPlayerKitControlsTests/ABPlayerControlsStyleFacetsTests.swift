import ABTestSupport
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("ABPlayerControlsStyle's facet registry is the single, exhaustive source of change-impact classification", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPlayerControlsStyleFacetsTests {
    @Test("Every stored property of ABPlayerControlsStyle is registered as exactly one facet — adding a property without registering it fails this test")
    func facetRegistryIsExhaustive() {
        let mirror = Mirror(reflecting: ABPlayerControlsStyle())
        let mirrorLabels = Set(mirror.children.compactMap(\.label))
        let facetNames = Set(ABPlayerControlsStyle.facets.map(\.name))

        #expect(mirrorLabels == facetNames)
        #expect(ABPlayerControlsStyle.facets.count == mirror.children.count, "a duplicate or missing facet name would pass the Set comparison above but fail this count")
    }

    @Test("A playIcon change reports exactly .iconRebuild")
    func iconRebuildClassification() {
        var changed = ABPlayerControlsStyle()
        changed.playIcon = .system("stop.fill")
        #expect(changed.changeImpact(comparedTo: ABPlayerControlsStyle()) == .iconRebuild)
    }

    @Test("A buttonSpacing change reports exactly .controlsLayout")
    func controlsLayoutOnlyClassification() {
        var changed = ABPlayerControlsStyle()
        changed.buttonSpacing = 40
        #expect(changed.changeImpact(comparedTo: ABPlayerControlsStyle()) == .controlsLayout)
    }

    @Test("A trackHeight change reports both .controlsLayout and .seekBarLayout")
    func controlsAndSeekBarLayoutClassification() {
        var changed = ABPlayerControlsStyle()
        changed.trackHeight = 8
        #expect(changed.changeImpact(comparedTo: ABPlayerControlsStyle()) == [.controlsLayout, .seekBarLayout])
    }

    @Test("A tintColor change reports .paintOnly (the empty set)")
    func paintOnlyClassification() {
        var changed = ABPlayerControlsStyle()
        changed.tintColor = .systemPink
        #expect(changed.changeImpact(comparedTo: ABPlayerControlsStyle()) == .paintOnly)
        #expect(changed.changeImpact(comparedTo: ABPlayerControlsStyle()).isEmpty)
    }

    @Test("The four new style properties this round adds are all .paintOnly")
    func newPropertiesArePaintOnly() {
        var bufferingColor = ABPlayerControlsStyle()
        bufferingColor.bufferingIndicatorColor = .systemRed
        #expect(bufferingColor.changeImpact(comparedTo: ABPlayerControlsStyle()) == .paintOnly)

        var seekFeedbackText = ABPlayerControlsStyle()
        seekFeedbackText.seekFeedbackTextColor = .systemRed
        #expect(seekFeedbackText.changeImpact(comparedTo: ABPlayerControlsStyle()) == .paintOnly)

        var seekFeedbackBackground = ABPlayerControlsStyle()
        seekFeedbackBackground.seekFeedbackBackgroundColor = .systemRed
        #expect(seekFeedbackBackground.changeImpact(comparedTo: ABPlayerControlsStyle()) == .paintOnly)

        var seekFeedbackFont = ABPlayerControlsStyle()
        seekFeedbackFont.seekFeedbackFont = .boldSystemFont(ofSize: 20)
        #expect(seekFeedbackFont.changeImpact(comparedTo: ABPlayerControlsStyle()) == .paintOnly)
    }

    @Test("No change reports no impact")
    func unchangedStyleReportsNoImpact() {
        #expect(ABPlayerControlsStyle().changeImpact(comparedTo: ABPlayerControlsStyle()).isEmpty)
    }

    @Test("Changing two facets from different groups unions both impacts")
    func multipleFacetChangesUnionImpacts() {
        var changed = ABPlayerControlsStyle()
        changed.playIcon = .system("stop.fill")
        changed.buttonSpacing = 40
        #expect(changed.changeImpact(comparedTo: ABPlayerControlsStyle()) == [.iconRebuild, .controlsLayout])
    }

    @Test("ABPlayerControlsLiveStyleTests' two invalidation-count assertions still hold with the unified registry — color-only changes invalidate zero times, a dimension change invalidates exactly once")
    func liveStyleInvalidationCountsAreUnaffected() {
        let colorOnly = { () -> ABPlayerControlsStyle in
            var style = ABPlayerControlsStyle()
            style.tintColor = .systemPink
            style.trackColor = .systemGray
            style.progressColor = .systemGreen
            return style
        }()
        #expect(colorOnly.changeImpact(comparedTo: ABPlayerControlsStyle()).contains(.controlsLayout) == false)

        var dimensionOnly = ABPlayerControlsStyle()
        dimensionOnly.playPauseButtonSize = CGSize(width: 60, height: 58)
        #expect(dimensionOnly.changeImpact(comparedTo: ABPlayerControlsStyle()).contains(.controlsLayout))
    }
}
