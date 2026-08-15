import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for `ABAVPlaybackTarget.setRate(_:)` mirroring into
/// `AVPlayer.defaultRate` so a system-driven resume (not routed through
/// this type's own `play()`) still honors the configured rate, and
/// `audioTimePitchAlgorithm` reaches the attached `AVPlayerItem`.
@Suite("ABAVPlaybackTarget mirrors rate and applies audioTimePitchAlgorithm", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABRateTuningTargetTests {
    private func makeAttachedTarget(tuning: ABPlaybackTuning = .unrestricted) throws -> ABAVPlaybackTarget {
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        let url = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
        target.attachItem(ABMediaSource(url: url), tuning: tuning, assetFactory: ABDefaultAssetFactory())
        return target
    }

    @Test("setRate mirrors into AVPlayer.defaultRate")
    func setRateMirrorsIntoDefaultRate() throws {
        let target = try makeAttachedTarget()

        target.setRate(1.5)

        #expect(target.avPlayer?.defaultRate == 1.5)
    }

    @Test("A non-nil audioTimePitchAlgorithm reaches the attached AVPlayerItem")
    func audioTimePitchAlgorithmReachesItem() throws {
        var tuning = ABPlaybackTuning.unrestricted
        tuning.audioTimePitchAlgorithm = .spectral

        let target = try makeAttachedTarget(tuning: tuning)

        #expect(target.avPlayerItem?.audioTimePitchAlgorithm == .spectral)
    }

    @Test("A nil audioTimePitchAlgorithm leaves AVFoundation's own default (.timeDomain) unchanged")
    func nilAudioTimePitchAlgorithmLeavesDefaultUnchanged() throws {
        let target = try makeAttachedTarget(tuning: .unrestricted)

        #expect(target.avPlayerItem?.audioTimePitchAlgorithm == .timeDomain)
    }
}
