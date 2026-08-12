import Foundation
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// A minimal `ABPlaybackTarget` fake, scoped to this test target only —
/// `Tests/ABPlayerKitTests/Fakes/ABFakePlaybackTarget.swift` belongs to a
/// separate test target and isn't importable from here. Only implements
/// what a real `ABPlayer` needs to reach `.current` and simulate playback
/// state changes; no seek/preroll bookkeeping beyond what compiles.
@MainActor
final class ABFakePlaybackTarget: ABPlaybackTarget {
    var onEvent: ((ABTargetEvent) -> Void)?

    var avPlayer: AVPlayer?
    var avPlayerItem: AVPlayerItem?
    var isPlaying = false
    var currentTime: CMTime = .zero
    var duration: CMTime?
    var bufferedUntil: CMTime?
    var timeControlStatus: ABTimeControlStatus = .paused
    var isPlaybackLikelyToKeepUp = false
    var isPlaybackBufferEmpty = false
    var isWaitingWithNoItem = false
    var presentationSize: CGSize = .zero
    var isExternalPlaybackActive = false
    private var periodicTimeHandler: (@MainActor @Sendable (CMTime) -> Void)?

    func makePlayer() {
        avPlayer = AVPlayer()
    }

    func releasePlayer() {
        avPlayerItem = nil
        avPlayer = nil
    }

    func attachItem(_ source: ABMediaSource, tuning: ABPlaybackTuning, assetFactory: any ABAssetFactory) {}

    func detachItem() {
        avPlayerItem = nil
    }

    @discardableResult
    func applyTuning(_ tuning: ABPlaybackTuning) -> Bool { true }

    func play() {
        isPlaying = true
        timeControlStatus = .playing
    }

    func pause() {
        isPlaying = false
        timeControlStatus = .paused
    }

    func setRate(_ rate: Float) {}
    func setMuted(_ muted: Bool) {}
    func setLooping(_ isLooping: Bool) {}
    func applyExternalPlayback(_ settings: ABExternalPlaybackSettings) {}

    func preroll(rate: Float, timeout: TimeInterval) async -> ABPrerollResult { .success }
    func seekToStart() async {}

    func seek(to time: CMTime, tolerance: ABSeekTolerance) async -> CMTime {
        currentTime = time
        return time
    }

    func setPeriodicTimeObserver(
        interval: TimeInterval?,
        onTick: (@MainActor @Sendable (CMTime) -> Void)?
    ) {
        periodicTimeHandler = onTick
    }

    /// Simulates a periodic-time tick without a real timer.
    func tick(_ time: CMTime) {
        currentTime = time
        periodicTimeHandler?(time)
    }

    /// Simulates a target-originated event, as `ABAVPlaybackTarget` would
    /// via `onEvent`.
    func emit(_ event: ABTargetEvent) {
        onEvent?(event)
    }
}
