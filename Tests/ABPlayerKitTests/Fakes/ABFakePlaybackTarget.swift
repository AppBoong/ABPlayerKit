import Foundation
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Records every call `ABPlayer` makes so tests can assert on call
/// sequences (e.g. "every release path calls detachItem exactly once")
/// without touching real `AVFoundation`.
@MainActor
final class ABFakePlaybackTarget: ABPlaybackTarget {
    enum Call: Equatable {
        case makePlayer
        case releasePlayer
        case attachItem(ABMediaSource, ABPlaybackTuning)
        case detachItem
        case applyTuning(ABPlaybackTuning)
        case play
        case pause
        case setRate(Float)
        case setMuted(Bool)
        case setLooping(Bool)
        case applyExternalPlayback(ABExternalPlaybackSettings)
        case preroll(rate: Float)
        case seekToStart
        case seek(CMTime, ABSeekTolerance)
        case setPeriodicObserver(TimeInterval?)
    }

    private(set) var calls: [Call] = []
    var onEvent: ((ABTargetEvent) -> Void)?

    var avPlayer: AVPlayer?
    var avPlayerItem: AVPlayerItem?
    var isPlaying = false
    private(set) var desiredRate: Float = 1.0
    private(set) var appliedRate: Float = 0
    var currentTime: CMTime = .zero
    var duration: CMTime?
    var bufferedUntil: CMTime?
    /// Settable directly by tests exercising `ABBufferingEvaluator`
    /// integration — `play()`/`pause()` also keep this in sync with
    /// `isPlaying` for tests that don't care about buffering specifically.
    var timeControlStatus: ABTimeControlStatus = .paused
    var isPlaybackLikelyToKeepUp = false
    var isPlaybackBufferEmpty = false
    var isWaitingWithNoItem = false
    var presentationSize: CGSize = .zero
    var isExternalPlaybackActive = false
    private(set) var appliedExternalPlaybackSettings: ABExternalPlaybackSettings?
    var seekLandingTime: CMTime?
    var waitsForSeekContinuation = false
    private var seekContinuations: [CheckedContinuation<Void, Never>] = []
    private var periodicTimeHandler: (@MainActor @Sendable (CMTime) -> Void)?

    /// Controls what `preroll(rate:timeout:)` returns.
    var prerollResult: ABPrerollResult = .success
    var waitsForPrerollCancellation = false
    private(set) var prerollWasCancelled = false
    /// Records the `timeout` argument passed to the most recent
    /// `preroll(rate:timeout:)` call, so tests can assert `ABPlayer` actually
    /// threads `configuration.prerollTimeout` through unchanged.
    private(set) var recordedPrerollTimeout: TimeInterval?
    private var hasAttachedItem = false

    func makePlayer() {
        calls.append(.makePlayer)
        avPlayer = AVPlayer()
    }

    func releasePlayer() {
        calls.append(.releasePlayer)
        hasAttachedItem = false
        avPlayerItem = nil
        avPlayer = nil
    }

    func attachItem(_ source: ABMediaSource, tuning: ABPlaybackTuning, assetFactory: any ABAssetFactory) {
        calls.append(.attachItem(source, tuning))
        hasAttachedItem = true
    }

    func detachItem() {
        calls.append(.detachItem)
        hasAttachedItem = false
        // Mirrors `ABAVPlaybackTarget.detachItem()` nulling `avPlayerItem`
        // — needed so tests can assert `player.avPlayerItem == nil` from
        // inside a `.itemDetached` observer, since the target detaches
        // before that event broadcasts.
        avPlayerItem = nil
    }

    @discardableResult
    func applyTuning(_ tuning: ABPlaybackTuning) -> Bool {
        calls.append(.applyTuning(tuning))
        return hasAttachedItem
    }

    func play() {
        calls.append(.play)
        isPlaying = true
        appliedRate = desiredRate
        timeControlStatus = .playing
    }

    func pause() {
        calls.append(.pause)
        isPlaying = false
        appliedRate = 0
        timeControlStatus = .paused
    }

    func setRate(_ rate: Float) {
        calls.append(.setRate(rate))
        desiredRate = rate
        if isPlaying {
            appliedRate = rate
        }
    }

    func setMuted(_ muted: Bool) {
        calls.append(.setMuted(muted))
    }

    func setLooping(_ isLooping: Bool) {
        calls.append(.setLooping(isLooping))
    }

    func applyExternalPlayback(_ settings: ABExternalPlaybackSettings) {
        calls.append(.applyExternalPlayback(settings))
        appliedExternalPlaybackSettings = settings
    }

    func preroll(rate: Float, timeout: TimeInterval) async -> ABPrerollResult {
        calls.append(.preroll(rate: rate))
        recordedPrerollTimeout = timeout
        if waitsForPrerollCancellation {
            while !Task.isCancelled {
                await Task.yield()
            }
            prerollWasCancelled = true
            return .cancelled
        }
        return prerollResult
    }

    func seekToStart() async {
        calls.append(.seekToStart)
    }

    func seek(to time: CMTime, tolerance: ABSeekTolerance) async -> CMTime {
        calls.append(.seek(time, tolerance))
        let landed = seekLandingTime ?? time
        if waitsForSeekContinuation {
            await withCheckedContinuation { continuation in
                seekContinuations.append(continuation)
            }
        }
        currentTime = landed
        return currentTime
    }

    var pendingSeekCount: Int { seekContinuations.count }

    func completeNextSeek() {
        guard !seekContinuations.isEmpty else { return }
        seekContinuations.removeFirst().resume()
    }

    func setPeriodicTimeObserver(
        interval: TimeInterval?,
        onTick: (@MainActor @Sendable (CMTime) -> Void)?
    ) {
        calls.append(.setPeriodicObserver(interval))
        periodicTimeHandler = onTick
    }

    func tick(_ time: CMTime) {
        currentTime = time
        periodicTimeHandler?(time)
    }

    func detachCount() -> Int {
        calls.filter { $0 == .detachItem }.count
    }

    /// Test-only helper that lets tests drive `ABPlayer.handle(_:)` directly
    /// by simulating a target-originated event, exactly as
    /// `ABAVPlaybackTarget.observeItem` would via `onEvent`.
    func emit(_ event: ABTargetEvent) {
        onEvent?(event)
    }
}
