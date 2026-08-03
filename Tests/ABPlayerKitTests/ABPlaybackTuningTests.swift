import CoreGraphics
import Foundation
import Testing
@testable import ABPlayerKit

@Suite("ABPlaybackTuning promote/demote round trip is symmetric")
@MainActor
struct ABPlaybackTuningRoundTripTests {
    @Test("Promoting then demoting applies current and restores the exact preload tuning")
    func promoteThenDemoteRoundTrip() {
        let preloadTuning = ABPlaybackTuning(
            preferredPeakBitRate: 1_250_000,
            preferredForwardBufferDuration: 3,
            preferredMaximumResolution: CGSize(width: 640, height: 360),
            automaticallyWaitsToMinimizeStalling: false
        )
        let currentTuning = ABPlaybackTuning(
            preferredPeakBitRate: 4_500_000,
            preferredForwardBufferDuration: 8,
            preferredMaximumResolution: CGSize(width: 1920, height: 1080),
            automaticallyWaitsToMinimizeStalling: true
        )
        let configuration = ABPlayerConfiguration(
            preloadTuning: preloadTuning,
            currentTuning: currentTuning,
            prerollRate: nil,
            backgroundPolicy: .ignore
        )
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: configuration, target: target)
        let source = ABMediaSource(url: URL(string: "https://example.com/video.mp4")!)

        player.set(source: source, grade: .preloaded)
        player.promote(to: .current)
        player.promote(to: .preloaded)

        let appliedTunings = target.calls.compactMap { call -> ABPlaybackTuning? in
            guard case .applyTuning(let tuning) = call else { return nil }
            return tuning
        }
        #expect(appliedTunings == [preloadTuning, currentTuning, preloadTuning])
        #expect(appliedTunings.last == configuration.preloadTuning)
    }

    @Test("displaySize sentinel resolves to the supplied screen size")
    func sentinelResolution() {
        #expect(ABPlaybackTuning.displayCapped.preferredMaximumResolution == ABPlaybackTuning.displaySizeSentinel)
        let resolved = ABPlaybackTuning.displayCapped.resolved(displaySize: CGSize(width: 1080, height: 1920))
        #expect(resolved.preferredMaximumResolution == CGSize(width: 1080, height: 1920))
        #expect(resolved.preferredPeakBitRate == ABPlaybackTuning.displayCapped.preferredPeakBitRate)
    }

    @Test("Non-sentinel tunings are unaffected by resolution")
    func nonSentinelUnaffected() {
        let resolved = ABPlaybackTuning.conservativePreload.resolved(displaySize: CGSize(width: 1080, height: 1920))
        #expect(resolved == .conservativePreload)
    }
}
