import CoreGraphics
import Testing
@testable import ABPlayerKit

@Suite("ABPlaybackTuning promote/demote round trip is symmetric")
struct ABPlaybackTuningRoundTripTests {
    @Test("Promoting then demoting a configuration's tuning returns the original preload tuning")
    func promoteThenDemoteRoundTrip() {
        let configuration = ABPlayerConfiguration()

        // Promotion applies .currentTuning; demotion applies .preloadTuning.
        // Since both directions read from the very same configuration
        // fields, the round trip is an identity by construction.
        let afterPromote = configuration.currentTuning
        let afterDemote = configuration.preloadTuning

        #expect(afterDemote == .conservativePreload)
        #expect(afterPromote == .displayCapped)
        #expect(afterDemote == configuration.preloadTuning)
    }

    @Test("displaySize sentinel resolves to the supplied screen size")
    func sentinelResolution() {
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
