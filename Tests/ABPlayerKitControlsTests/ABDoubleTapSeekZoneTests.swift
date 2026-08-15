import ABTestSupport
import CoreGraphics
import Testing
@testable import ABPlayerKitControls

@Suite("ABDoubleTapSeekZone computes pure horizontal bands, no gesture recognizer required", .timeLimit(abScaledMinutes(3)))
struct ABDoubleTapSeekZoneTests {
    @Test("Given a 0.3 edge fraction, the left/right 30% bands are backward/forward and the middle 40% is neutral")
    func standardEdgeFraction() {
        let width: CGFloat = 300
        #expect(ABDoubleTapSeekZone.zone(forX: 0, width: width, edgeFraction: 0.3) == .backward)
        #expect(ABDoubleTapSeekZone.zone(forX: 89, width: width, edgeFraction: 0.3) == .backward)
        #expect(ABDoubleTapSeekZone.zone(forX: 90, width: width, edgeFraction: 0.3) == .neutral)
        #expect(ABDoubleTapSeekZone.zone(forX: 150, width: width, edgeFraction: 0.3) == .neutral)
        #expect(ABDoubleTapSeekZone.zone(forX: 210, width: width, edgeFraction: 0.3) == .neutral)
        #expect(ABDoubleTapSeekZone.zone(forX: 211, width: width, edgeFraction: 0.3) == .forward)
        #expect(ABDoubleTapSeekZone.zone(forX: 300, width: width, edgeFraction: 0.3) == .forward)
    }

    @Test("Given a 0.1 edge fraction, the bands narrow to 10% each side")
    func narrowEdgeFraction() {
        let width: CGFloat = 200
        #expect(ABDoubleTapSeekZone.zone(forX: 19, width: width, edgeFraction: 0.1) == .backward)
        #expect(ABDoubleTapSeekZone.zone(forX: 20, width: width, edgeFraction: 0.1) == .neutral)
        #expect(ABDoubleTapSeekZone.zone(forX: 180, width: width, edgeFraction: 0.1) == .neutral)
        #expect(ABDoubleTapSeekZone.zone(forX: 181, width: width, edgeFraction: 0.1) == .forward)
    }

    @Test("Given a 0.5 edge fraction, the bands meet at the midpoint and there is no neutral zone")
    func maximalEdgeFraction() {
        let width: CGFloat = 100
        #expect(ABDoubleTapSeekZone.zone(forX: 0, width: width, edgeFraction: 0.5) == .backward)
        #expect(ABDoubleTapSeekZone.zone(forX: 49, width: width, edgeFraction: 0.5) == .backward)
        #expect(ABDoubleTapSeekZone.zone(forX: 50, width: width, edgeFraction: 0.5) == .neutral)
        #expect(ABDoubleTapSeekZone.zone(forX: 51, width: width, edgeFraction: 0.5) == .forward)
    }

    @Test("Given edgeFraction values outside 0.1...0.5, they clamp instead of producing out-of-range bands")
    func edgeFractionClamps() {
        let width: CGFloat = 100
        // Below 0.1 clamps up to 0.1 — a 0.01 fraction would put the boundary
        // at x=1, but it must behave identically to edgeFraction: 0.1 (x=10).
        #expect(ABDoubleTapSeekZone.zone(forX: 5, width: width, edgeFraction: 0.01) == .backward)
        #expect(ABDoubleTapSeekZone.zone(forX: 15, width: width, edgeFraction: 0.01) == .neutral)
        // Above 0.5 clamps down to 0.5.
        #expect(ABDoubleTapSeekZone.zone(forX: 40, width: width, edgeFraction: 0.9) == .backward)
        #expect(ABDoubleTapSeekZone.zone(forX: 60, width: width, edgeFraction: 0.9) == .forward)
    }

    @Test("Given a non-positive width, the result is always neutral regardless of x or edgeFraction")
    func nonPositiveWidthIsAlwaysNeutral() {
        #expect(ABDoubleTapSeekZone.zone(forX: 0, width: 0, edgeFraction: 0.3) == .neutral)
        #expect(ABDoubleTapSeekZone.zone(forX: 10, width: -50, edgeFraction: 0.3) == .neutral)
    }

    @Test("flippedHorizontally swaps backward/forward and leaves neutral alone — the RTL correction ABPlayerControlsView applies")
    func flippedHorizontallySwapsDirectionalCases() {
        #expect(ABDoubleTapSeekZone.backward.flippedHorizontally == .forward)
        #expect(ABDoubleTapSeekZone.forward.flippedHorizontally == .backward)
        #expect(ABDoubleTapSeekZone.neutral.flippedHorizontally == .neutral)
    }
}
