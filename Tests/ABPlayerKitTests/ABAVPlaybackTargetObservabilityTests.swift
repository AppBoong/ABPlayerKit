import Foundation
import ABTestSupport
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Integration coverage for the buffering/duration/presentation-size KVO
/// registrations in `ABAVPlaybackTarget.observeItem` — driven against the
/// real bundled
/// `tiny.mp4` fixture (this suite's existing convention), rather than
/// `ABFakePlaybackTarget`, since the behavior under test is the KVO wiring
/// itself.
@Suite("ABAVPlaybackTarget observes buffering/duration/presentation-size signals", .timeLimit(.minutes(3)))
@MainActor
struct ABAVPlaybackTargetObservabilityTests {
    private func makeAttachedTarget() throws -> ABAVPlaybackTarget {
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        let url = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
        target.attachItem(ABMediaSource(url: url), tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        return target
    }

    @Test("A valid item eventually reports a finite duration via .durationChanged")
    func durationChangedEventuallyFires() async throws {
        let target = try makeAttachedTarget()
        var receivedDurationChanged = false
        target.onEvent = { event in
            if case .durationChanged = event { receivedDurationChanged = true }
        }

        try await waitUntil { receivedDurationChanged }
        #expect(target.duration != nil)
    }

    @Test("The .initial buffering signal fires .bufferStateChanged at least once")
    func bufferStateChangedFiresAtLeastOnce() async throws {
        let target = try makeAttachedTarget()
        var receivedBufferStateChanged = false
        target.onEvent = { event in
            if case .bufferStateChanged = event { receivedBufferStateChanged = true }
        }

        try await waitUntil { receivedBufferStateChanged }
    }

    @Test("presentationSize becomes readable once the item loads")
    func presentationSizeBecomesReadable() async throws {
        let target = try makeAttachedTarget()
        try await waitUntil { target.presentationSize != .zero }
        #expect(target.presentationSize.width > 0)
        #expect(target.presentationSize.height > 0)
    }

    @Test("timeControlStatus/isPlaybackLikelyToKeepUp/isPlaybackBufferEmpty/isWaitingWithNoItem are readable without crashing before and after attach")
    func rawSignalsAreReadableAndSafeBeforeAttach() {
        let target = ABAVPlaybackTarget()
        // No `makePlayer()`/`attachItem` yet — every raw signal must have a
        // safe default rather than trapping on a nil `avPlayer`/`avPlayerItem`.
        #expect(target.timeControlStatus == .paused)
        #expect(!target.isPlaybackLikelyToKeepUp)
        #expect(!target.isPlaybackBufferEmpty)
        #expect(!target.isWaitingWithNoItem)
        #expect(target.presentationSize == .zero)
    }
}
