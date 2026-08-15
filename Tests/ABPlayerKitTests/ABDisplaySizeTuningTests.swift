import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for `preferredMaximumResolution`'s sentinel resolving against
/// the size `ABPlayerView` reports, not the device screen — a feed cell's
/// correct cap is the cell's own size.
@Suite("ABPlayer resolves displaySizeSentinel from reported display size", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABDisplaySizeTuningTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    @Test("With no view ever attached, the sentinel resolves to .zero (no cap)")
    func noReportedSizeResolvesToNoCap() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)

        player.set(source: source, grade: .current)

        let expected = ABPlaybackTuning.displayCapped.resolved(displaySize: .zero)
        #expect(target.calls.contains(.attachItem(source, expected)))
    }

    @Test("reportDisplaySize resolves the sentinel to the reported cell size and re-applies tuning")
    func reportDisplaySizeResolvesSentinelAndReapplies() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        player.set(source: source, grade: .current)
        let applyTuningCallCountBefore = target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count

        let cellSize = CGSize(width: 375, height: 667)
        player.reportDisplaySize(cellSize)

        let expected = ABPlaybackTuning.displayCapped.resolved(displaySize: cellSize)
        #expect(target.calls.contains(.applyTuning(expected)))
        let applyTuningCallCountAfter = target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count
        #expect(applyTuningCallCountAfter == applyTuningCallCountBefore + 1)
    }

    @Test("Reporting the same display size twice does not re-apply tuning (loop guard)")
    func repeatedIdenticalDisplaySizeDoesNotReapply() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        player.set(source: source, grade: .current)
        let cellSize = CGSize(width: 375, height: 667)
        player.reportDisplaySize(cellSize)
        let applyTuningCallCountAfterFirst = target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count

        player.reportDisplaySize(cellSize)

        let applyTuningCallCountAfterSecond = target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count
        #expect(applyTuningCallCountAfterSecond == applyTuningCallCountAfterFirst)
    }

    /// Reproduced on device: a host whose layout alternates between two
    /// sizes one pixel apart (legal, and nothing this library can prevent)
    /// used to re-resolve the cap, re-apply it, and broadcast
    /// `.tuningApplied` on every single layout pass. A consumer that
    /// re-renders on that event fed the broadcast straight back into the
    /// next layout pass, so the two ran each other at display refresh rate
    /// indefinitely.
    @Test("A display size oscillating by one pixel neither re-applies tuning nor broadcasts")
    func onePixelOscillationDoesNotReapplyOrBroadcast() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        player.set(source: source, grade: .current)
        player.reportDisplaySize(CGSize(width: 1165, height: 655))
        let applyTuningCallCountBefore = applyTuningCallCount(target)
        var broadcastCount = 0
        let token = player.addObserver { event in
            if case .tuningApplied = event { broadcastCount += 1 }
        }
        defer { token.cancel() }

        for _ in 0..<200 {
            player.reportDisplaySize(CGSize(width: 1164, height: 655))
            player.reportDisplaySize(CGSize(width: 1165, height: 655))
        }

        #expect(applyTuningCallCount(target) == applyTuningCallCountBefore)
        #expect(broadcastCount == 0)
    }

    @Test("A genuine resize (rotation) still re-caps to the new size and broadcasts")
    func genuineResizeStillReapplies() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        player.set(source: source, grade: .current)
        player.reportDisplaySize(CGSize(width: 1165, height: 655))
        let applyTuningCallCountBefore = applyTuningCallCount(target)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        let rotated = CGSize(width: 655, height: 1165)
        player.reportDisplaySize(rotated)

        #expect(applyTuningCallCount(target) == applyTuningCallCountBefore + 1)
        #expect(target.calls.contains(.applyTuning(ABPlaybackTuning.displayCapped.resolved(displaySize: rotated))))
        #expect(events.contains(.tuningApplied(.current, .displayCapped)))
    }

    /// The tolerance is a window around the last *stored* size, not around
    /// the last reported one, so jitter can't accumulate into a drift —
    /// but a view that genuinely keeps growing still crosses it, exactly
    /// once per crossing.
    @Test("A view growing a pixel at a time still re-caps, once, when it clears the tolerance")
    func cumulativeGrowthEventuallyReapplies() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        player.set(source: source, grade: .current)
        player.reportDisplaySize(CGSize(width: 1000, height: 655))
        let applyTuningCallCountBefore = applyTuningCallCount(target)

        for step in 1...20 {
            player.reportDisplaySize(CGSize(width: 1000 + CGFloat(step), height: 655))
        }

        #expect(applyTuningCallCount(target) == applyTuningCallCountBefore + 1)
        let crossing = CGSize(width: 1016, height: 655)
        #expect(target.calls.contains(.applyTuning(ABPlaybackTuning.displayCapped.resolved(displaySize: crossing))))
    }

    @Test(".zero is the no-cap sentinel, so entering and leaving it always re-caps")
    func zeroDisplaySizeTransitionsAlwaysReapply() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        player.set(source: source, grade: .current)
        let applyTuningCallCountBefore = applyTuningCallCount(target)

        let tiny = CGSize(width: 8, height: 8)
        player.reportDisplaySize(tiny)
        player.reportDisplaySize(.zero)

        #expect(applyTuningCallCount(target) == applyTuningCallCountBefore + 2)
        #expect(target.calls.contains(.applyTuning(ABPlaybackTuning.displayCapped.resolved(displaySize: tiny))))
        #expect(target.calls.contains(.applyTuning(ABPlaybackTuning.displayCapped.resolved(displaySize: .zero))))
    }

    @Test("A tuning carrying no display-size sentinel is never re-applied on a resize")
    func nonSentinelTuningIsNotReappliedOnResize() {
        let target = ABFakePlaybackTarget()
        var configuration = ABPlayerConfiguration(backgroundPolicy: .ignore)
        configuration.currentTuning = .resolutionCapped
        let player = ABPlayer(configuration: configuration, target: target)
        player.set(source: source, grade: .current)
        let applyTuningCallCountBefore = applyTuningCallCount(target)

        player.reportDisplaySize(CGSize(width: 1165, height: 655))
        player.reportDisplaySize(CGSize(width: 655, height: 1165))

        #expect(applyTuningCallCount(target) == applyTuningCallCountBefore)
    }

    private func applyTuningCallCount(_ target: ABFakePlaybackTarget) -> Int {
        target.calls.filter { if case .applyTuning = $0 { true } else { false } }.count
    }

    @Test(".tuningApplied still broadcasts the unresolved preset value, not the resolved pixel cap")
    func tuningAppliedBroadcastsUnresolvedValue() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .current)

        #expect(events.contains(.tuningApplied(.current, .displayCapped)))
    }
}
