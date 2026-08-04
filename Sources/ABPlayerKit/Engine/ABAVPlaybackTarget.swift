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
    private var desiredRate: Float = 1.0

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

    @discardableResult
    func applyTuning(_ tuning: ABPlaybackTuning) -> Bool {
        guard let avPlayerItem else { return false }
        apply(tuning, to: avPlayerItem)
        return true
    }

    func play() {
        avPlayer?.rate = desiredRate
    }

    func pause() {
        avPlayer?.pause()
    }

    func setRate(_ rate: Float) {
        let wasPlaying = isPlaying
        desiredRate = rate
        if wasPlaying {
            avPlayer?.rate = rate
        }
    }

    func setMuted(_ muted: Bool) {
        avPlayer?.isMuted = muted
    }

    func setLooping(_ isLooping: Bool) {
        self.isLooping = isLooping
    }

    func preroll(rate: Float, timeout: TimeInterval) async -> ABPrerollResult {
        guard let avPlayer, let avPlayerItem else { return .failed }
        switch await waitUntilReady(item: avPlayerItem, timeout: timeout) {
        case .ready:
            let succeeded = await avPlayer.preroll(atRate: rate)
            guard !Task.isCancelled else { return .cancelled }
            return succeeded ? .success : .failed
        case .timedOut:
            return .timedOut
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }

    func seekToStart() async {
        await avPlayer?.seek(to: .zero)
    }

    func seek(to time: CMTime, tolerance: ABSeekTolerance) async -> CMTime {
        guard let avPlayer else { return time }
        await avPlayer.seek(
            to: time,
            toleranceBefore: tolerance.before,
            toleranceAfter: tolerance.after
        )
        return avPlayer.currentTime()
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

    private enum ReadyWaitResult: Sendable {
        case ready
        case timedOut
        case failed
        case cancelled
    }

    /// Coordinates KVO, timeout, and task cancellation without letting any
    /// path resume the continuation twice. Cancellation may arrive before
    /// the continuation is installed, so the resolved result is retained
    /// until installation completes.
    private final class ReadyWaitState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ReadyWaitResult, Never>?
        private var result: ReadyWaitResult?
        private var timeoutTask: Task<Void, Never>?
        private var invalidateObservation: (() -> Void)?

        func install(_ continuation: CheckedContinuation<ReadyWaitResult, Never>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        func installTimeoutTask(_ task: Task<Void, Never>) {
            lock.lock()
            if result == nil {
                timeoutTask = task
                lock.unlock()
            } else {
                lock.unlock()
                task.cancel()
            }
        }

        func installObservationInvalidator(_ invalidate: @escaping () -> Void) {
            lock.lock()
            if result == nil {
                invalidateObservation = invalidate
                lock.unlock()
            } else {
                lock.unlock()
                invalidate()
            }
        }

        func resolve(_ result: ReadyWaitResult) {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return
            }
            self.result = result
            let continuation = continuation
            self.continuation = nil
            let timeoutTask = timeoutTask
            self.timeoutTask = nil
            let invalidateObservation = invalidateObservation
            self.invalidateObservation = nil
            lock.unlock()

            timeoutTask?.cancel()
            invalidateObservation?()
            continuation?.resume(returning: result)
        }
    }

    private func waitUntilReady(item: AVPlayerItem, timeout: TimeInterval) async -> ReadyWaitResult {
        if item.status == .readyToPlay { return .ready }
        if item.status == .failed { return .failed }

        let state = ReadyWaitState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                guard !Task.isCancelled else {
                    state.resolve(.cancelled)
                    return
                }

                let statusObservation = item.observe(\.status, options: [.new]) { item, _ in
                    switch item.status {
                    case .readyToPlay: state.resolve(.ready)
                    case .failed: state.resolve(.failed)
                    case .unknown: break
                    @unknown default: break
                    }
                }
                state.installObservationInvalidator { statusObservation.invalidate() }

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: .seconds(max(0, timeout)))
                    } catch {
                        return
                    }
                    state.resolve(.timedOut)
                }
                state.installTimeoutTask(timeoutTask)
            }
        } onCancel: {
            state.resolve(.cancelled)
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
