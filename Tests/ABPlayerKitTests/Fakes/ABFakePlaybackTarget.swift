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
        case preroll(rate: Float)
        case seekToStart
        case seek(CMTime)
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

    /// Controls what `preroll(rate:timeout:)` returns.
    var prerollResult: ABPrerollResult = .success
    var waitsForPrerollCancellation = false
    private(set) var prerollWasCancelled = false
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
    }

    func pause() {
        calls.append(.pause)
        isPlaying = false
        appliedRate = 0
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

    func preroll(rate: Float, timeout: TimeInterval) async -> ABPrerollResult {
        calls.append(.preroll(rate: rate))
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

    func seek(to time: CMTime) async {
        calls.append(.seek(time))
    }

    func detachCount() -> Int {
        calls.filter { $0 == .detachItem }.count
    }
}
