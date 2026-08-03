@preconcurrency import AVFoundation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The real `AVFoundation`-backed `ABPlaybackTarget`. `ABPlayer` talks to
/// this exclusively through the protocol; `ABFakePlaybackTarget` (test-only)
/// is the other conformer.
@MainActor
final class ABAVPlaybackTarget: ABPlaybackTarget {
    private(set) var avPlayer: AVPlayer?
    private(set) var avPlayerItem: AVPlayerItem?
    var onEvent: ((ABTargetEvent) -> Void)?

    private let observations = ABObservationBag()
    private var isLooping = false

    var isPlaying: Bool {
        guard let avPlayer else { return false }
        return avPlayer.rate != 0 && avPlayer.timeControlStatus != .paused
    }

    var currentTime: CMTime {
        avPlayer?.currentTime() ?? .zero
    }

    var duration: CMTime? {
        avPlayerItem?.duration
    }

    func makePlayer() {
        avPlayer = AVPlayer()
        avPlayer?.automaticallyWaitsToMinimizeStalling = true
    }

    func releasePlayer() {
        observations.invalidateAll()
        avPlayerItem = nil
        avPlayer = nil
    }

    func attachItem(_ source: ABMediaSource, tuning: ABPlaybackTuning, assetFactory: any ABAssetFactory) {
        observations.invalidateAll()
        let asset = assetFactory.makeAsset(for: source)
        let item = AVPlayerItem(asset: asset)
        apply(tuning, to: item)
        avPlayerItem = item
        avPlayer?.replaceCurrentItem(with: item)
        observeItem(item)
    }

    func detachItem() {
        observations.invalidateAll()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayerItem = nil
    }

    func applyTuning(_ tuning: ABPlaybackTuning) {
        guard let avPlayerItem else { return }
        apply(tuning, to: avPlayerItem)
    }

    func play() {
        avPlayer?.play()
    }

    func pause() {
        avPlayer?.pause()
    }

    func setMuted(_ muted: Bool) {
        avPlayer?.isMuted = muted
    }

    func setLooping(_ isLooping: Bool) {
        self.isLooping = isLooping
    }

    func preroll(rate: Float, timeout: TimeInterval) async -> Bool {
        guard let avPlayer, let avPlayerItem else { return false }
        let ready = await waitUntilReady(item: avPlayerItem, timeout: timeout)
        guard ready else { return false }
        return await avPlayer.preroll(atRate: rate)
    }

    func seekToStart() async {
        await avPlayer?.seek(to: .zero)
    }

    func seek(to time: CMTime) async {
        await avPlayer?.seek(to: time)
    }

    private func apply(_ tuning: ABPlaybackTuning, to item: AVPlayerItem) {
        let resolved = tuning.resolved(displaySize: currentScreenNativeSize())
        item.preferredPeakBitRate = resolved.preferredPeakBitRate
        item.preferredForwardBufferDuration = resolved.preferredForwardBufferDuration
        item.preferredMaximumResolution = resolved.preferredMaximumResolution
        avPlayer?.automaticallyWaitsToMinimizeStalling = resolved.automaticallyWaitsToMinimizeStalling
    }

    private func currentScreenNativeSize() -> CGSize {
        #if canImport(UIKit)
        return UIScreen.main.nativeBounds.size
        #else
        return .zero
        #endif
    }

    /// Guards a `CheckedContinuation` so it resumes exactly once even
    /// though both the KVO callback and the timeout `Task` race to resume
    /// it. A dedicated `@unchecked Sendable` box (rather than a captured
    /// local closure) avoids capturing non-`Sendable` state in the
    /// `@Sendable` closures `Task { ... }` requires.
    private final class ContinuationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private let continuation: CheckedContinuation<Bool, Never>

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            continuation.resume(returning: value)
        }
    }

    private func waitUntilReady(item: AVPlayerItem, timeout: TimeInterval) async -> Bool {
        if item.status == .readyToPlay { return true }
        if item.status == .failed { return false }

        return await withCheckedContinuation { continuation in
            let box = ContinuationBox(continuation)

            let statusObservation = item.observe(\.status, options: [.new]) { item, _ in
                Task { @MainActor in
                    switch item.status {
                    case .readyToPlay: box.resume(true)
                    case .failed: box.resume(false)
                    case .unknown: break
                    @unknown default: break
                    }
                }
            }
            observations.add { statusObservation.invalidate() }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                box.resume(item.status == .readyToPlay)
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem) {
        let statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status: ABItemStatus
            switch item.status {
            case .unknown: status = .unknown
            case .readyToPlay: status = .readyToPlay
            case .failed: status = .failed
            @unknown default: status = .unknown
            }
            Task { @MainActor in
                self?.onEvent?(.itemStatusChanged(status))
                if case .failed = item.status, let error = item.error {
                    self?.onEvent?(.failed(.itemFailed(description: error.localizedDescription)))
                }
            }
        }
        observations.add { statusObservation.invalidate() }

        let center = NotificationCenter.default
        let endToken = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.isLooping == true {
                    Task { await self?.seekToStart() }
                }
                self?.onEvent?(.playedToEnd)
            }
        }
        observations.add { center.removeObserver(endToken) }

        let stallToken = center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onEvent?(.playbackStalled)
            }
        }
        observations.add { center.removeObserver(stallToken) }

        if let avPlayer {
            let timeControlObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let status: ABTimeControlStatus
                switch player.timeControlStatus {
                case .paused: status = .paused
                case .waitingToPlayAtSpecifiedRate: status = .waitingToPlay
                case .playing: status = .playing
                @unknown default: status = .paused
                }
                Task { @MainActor in
                    self?.onEvent?(.timeControlStatusChanged(status))
                }
            }
            observations.add { timeControlObservation.invalidate() }
        }
    }
}
