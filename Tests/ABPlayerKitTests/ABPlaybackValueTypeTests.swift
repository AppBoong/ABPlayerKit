@preconcurrency import AVFoundation
import Testing
@testable import ABPlayerKit

@Suite("Seek tolerance maps to AVFoundation tolerances")
struct ABSeekToleranceTests {
    @Test("Given precise tolerance, both target tolerances are zero")
    func preciseMapsToZero() {
        #expect(ABSeekTolerance.precise.before == .zero)
        #expect(ABSeekTolerance.precise.after == .zero)
    }

    @Test("Given coarse values, both target tolerances are preserved")
    func coarsePreservesValues() {
        let before = CMTime(seconds: 0.25, preferredTimescale: 600)
        let after = CMTime(seconds: 0.75, preferredTimescale: 600)
        let tolerance = ABSeekTolerance.coarse(before: before, after: after)

        #expect(tolerance.before == before)
        #expect(tolerance.after == after)
    }

    @Test("Given nearest tolerance, both target tolerances are positive infinity")
    func nearestMapsToInfinity() {
        #expect(ABSeekTolerance.nearest.before == .positiveInfinity)
        #expect(ABSeekTolerance.nearest.after == .positiveInfinity)
    }
}

@Suite("Playback rate values stay inside the supported range")
struct ABPlaybackRateTests {
    @Test("Given an in-range rate, clamping preserves it")
    func preservesAllowedRate() {
        #expect(ABPlaybackRate.clamped(1.5) == 1.5)
    }

    @Test("Given rates outside either boundary, clamping selects that boundary")
    func clampsBothBoundaries() {
        #expect(ABPlaybackRate.clamped(-1) == ABPlaybackRate.allowedRange.lowerBound)
        #expect(ABPlaybackRate.clamped(99) == ABPlaybackRate.allowedRange.upperBound)
    }

    @Test("Given a non-number rate, clamping returns the normal playback rate")
    func normalizesNaN() {
        #expect(ABPlaybackRate.clamped(.nan) == 1.0)
    }
}
