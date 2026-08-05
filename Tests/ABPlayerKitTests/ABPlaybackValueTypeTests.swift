@preconcurrency import AVFoundation
import Testing
@testable import ABPlayerKit

@Suite("Seek tolerance maps to AVFoundation tolerances", .timeLimit(.minutes(3)))
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

@Suite("Playback rate values stay inside the supported range", .timeLimit(.minutes(3)))
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

@Suite("ABPlaybackTime derives progress safely", .timeLimit(.minutes(3)))
struct ABPlaybackTimeTests {
    private let duration = CMTime(seconds: 100, preferredTimescale: 600)

    @Test("Given no duration, neither playback nor buffered progress is available")
    func missingDurationHasNoProgress() {
        let time = ABPlaybackTime(currentTime: .zero, duration: nil, bufferedUntil: .zero)

        #expect(time.progress == nil)
        #expect(time.bufferedProgress == nil)
    }

    @Test("Given a zero duration, progress derivation avoids division by zero")
    func zeroDurationHasNoProgress() {
        let time = ABPlaybackTime(currentTime: .zero, duration: .zero, bufferedUntil: nil)

        #expect(time.duration == nil)
        #expect(time.progress == nil)
    }

    @Test("Given current time beyond duration, playback progress clamps to one")
    func clampsPlaybackProgress() {
        let time = ABPlaybackTime(
            currentTime: CMTime(seconds: 125, preferredTimescale: 600),
            duration: duration,
            bufferedUntil: nil
        )

        #expect(time.progress == 1)
    }

    @Test("Given an earlier buffered time, its independent progress is preserved")
    func preservesIndependentBufferedProgress() {
        let time = ABPlaybackTime(
            currentTime: CMTime(seconds: 50, preferredTimescale: 600),
            duration: duration,
            bufferedUntil: CMTime(seconds: 25, preferredTimescale: 600)
        )

        #expect(time.progress == 0.5)
        #expect(time.bufferedProgress == 0.25)
    }

    @Test("Given an indefinite duration, the snapshot normalizes it to nil")
    func normalizesIndefiniteDuration() {
        let time = ABPlaybackTime(
            currentTime: .zero,
            duration: .indefinite,
            bufferedUntil: nil
        )

        #expect(time.duration == nil)
        #expect(time.progress == nil)
    }
}
