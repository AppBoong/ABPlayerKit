@preconcurrency import AVFoundation
import Foundation

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
    /// Lock-protected rather than `nonisolated(unsafe)` stored properties:
    /// a raw `nonisolated(unsafe)` would remove isolation checking from
    /// every access site, not just `deinit`, and wouldn't stop
    /// `removeTimeObserver` itself from running off the main thread — a
    /// documented race with the observer block, which this type always
    /// registers on the main queue (`queue: nil` below). All access —
    /// normal `@MainActor` call sites and `deinit` alike — goes through
    /// this single box.
    private let periodicObserver = PeriodicObserverBox()

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

    var bufferedUntil: CMTime? {
        guard let item = avPlayerItem else { return nil }
        let current = currentTime
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            if CMTimeRangeContainsTime(range, time: current) {
                return CMTimeRangeGetEnd(range)
            }
        }
        return nil
    }

    var isPlaybackLikelyToKeepUp: Bool {
        avPlayerItem?.isPlaybackLikelyToKeepUp ?? false
    }

    var isPlaybackBufferEmpty: Bool {
        avPlayerItem?.isPlaybackBufferEmpty ?? false
    }

    var timeControlStatus: ABTimeControlStatus {
        guard let avPlayer else { return .paused }
        return Self.mapTimeControlStatus(avPlayer.timeControlStatus)
    }

    var isWaitingWithNoItem: Bool {
        avPlayer?.reasonForWaitingToPlay == .noItemToPlay
    }

    var presentationSize: CGSize {
        avPlayerItem?.presentationSize ?? .zero
    }

    var isExternalPlaybackActive: Bool {
        avPlayer?.isExternalPlaybackActive ?? false
    }

    func makePlayer() {
        avPlayer = AVPlayer()
        avPlayer?.automaticallyWaitsToMinimizeStalling = true
    }

    func releasePlayer() {
        removePeriodicTimeObserver()
        observations.invalidateAll()
        avPlayerItem = nil
        avPlayer = nil
    }

    /// Guards against a consumer dropping `ABPlayer` (and therefore this
    /// target) without calling `release()`: an `AVPlayer` deallocating with
    /// a still-registered periodic time observer raises
    /// `NSInternalInconsistencyException`. Delegates to `periodicObserver`
    /// (nonisolated, lock-protected) because `deinit` is nonisolated and
    /// cannot call an actor-isolated method. Idempotent — running after
    /// `releasePlayer()` already cleared the box is a no-op.
    deinit {
        periodicObserver.removeIfNeeded()
    }

    func attachItem(_ source: ABMediaSource, tuning: ABPlaybackTuning, assetFactory: any ABAssetFactory) {
        removePeriodicTimeObserver()
        observations.invalidateAll()
        let asset = assetFactory.makeAsset(for: source)
        let item = AVPlayerItem(asset: asset)
        apply(tuning, to: item)
        avPlayerItem = item
        avPlayer?.replaceCurrentItem(with: item)
        observeItem(item)
    }

    func detachItem() {
        removePeriodicTimeObserver()
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

    /// Uses `AVPlayer.play()` rather than setting `rate` directly — a
    /// system-driven resume (e.g. after an interruption ends) then also
    /// honors whatever rate was last configured, since `setRate(_:)`
    /// mirrors `desiredRate` into `avPlayer.defaultRate`.
    func play() {
        avPlayer?.play()
    }

    func pause() {
        avPlayer?.pause()
    }

    func setRate(_ rate: Float) {
        let wasPlaying = isPlaying
        desiredRate = rate
        // Mirrored so a system-driven `play()` (not routed through this
        // type's own `play()`, e.g. an OS-level resume) still honors the
        // configured rate instead of resetting to 1.0.
        avPlayer?.defaultRate = rate
        if wasPlaying {
            avPlayer?.rate = rate
        }
    }

    func setMuted(_ muted: Bool) {
        avPlayer?.isMuted = muted
    }

    func applyExternalPlayback(_ settings: ABExternalPlaybackSettings) {
        avPlayer?.allowsExternalPlayback = settings.allowsExternalPlayback
        avPlayer?.usesExternalPlaybackWhileExternalScreenIsActive = settings.usesExternalPlaybackWhileExternalScreenIsActive
        avPlayer?.externalPlaybackVideoGravity = settings.externalPlaybackVideoGravity
    }

    /// `actionAtItemEnd` defaults to `.pause`, so looping needs `.none` or
    /// playback stays stopped at zero after `didPlayToEnd`'s restart seek —
    /// applies unconditionally to whatever `avPlayer` currently holds, and
    /// `interpret(_:source:detachReason:)` re-calls this on every attach so
    /// the flag survives item swaps.
    func setLooping(_ isLooping: Bool) {
        self.isLooping = isLooping
        avPlayer?.actionAtItemEnd = isLooping ? .none : .pause
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

    func setPeriodicTimeObserver(
        interval: TimeInterval?,
        onTick: (@MainActor @Sendable (CMTime) -> Void)?
    ) {
        removePeriodicTimeObserver()
        guard let interval,
              interval.isFinite,
              interval > 0,
              let onTick,
              let avPlayer,
              let capturedItem = avPlayerItem else { return }
        let observerInterval = CMTime(seconds: interval, preferredTimescale: 600)
        let token = avPlayer.addPeriodicTimeObserver(
            forInterval: observerInterval,
            queue: nil
        ) { [weak self, weak capturedItem] time in
            Task { @MainActor in
                guard let self,
                      let capturedItem,
                      self.avPlayerItem === capturedItem else { return }
                onTick(time)
            }
        }
        periodicObserver.set(token: token, player: avPlayer)
    }

    private func removePeriodicTimeObserver() {
        periodicObserver.removeIfNeeded()
    }

    /// `tuning` arrives already resolved — `ABPlayer.resolvedTuning(for:)`
    /// replaces `ABPlaybackTuning.displaySizeSentinel` with the size
    /// `ABPlayerView` reports (or `.zero`/no cap, with no view attached)
    /// before this is ever called. This target has no display/screen
    /// concept of its own to resolve against — a feed cell's correct cap
    /// is the cell's own size, not the device screen's.
    private func apply(_ tuning: ABPlaybackTuning, to item: AVPlayerItem) {
        item.preferredPeakBitRate = tuning.preferredPeakBitRate
        item.preferredForwardBufferDuration = tuning.preferredForwardBufferDuration
        item.preferredMaximumResolution = tuning.preferredMaximumResolution
        avPlayer?.automaticallyWaitsToMinimizeStalling = tuning.automaticallyWaitsToMinimizeStalling
        if let audioTimePitchAlgorithm = tuning.audioTimePitchAlgorithm {
            item.audioTimePitchAlgorithm = audioTimePitchAlgorithm
        }
    }

    // `nonisolated`: called synchronously from the non-isolated
    // notification callback below — see the Sendability note there.
    nonisolated private static func describe(
        errorLogEvent event: AVPlayerItemErrorLogEvent
    ) -> (description: String, origin: ABErrorOrigin) {
        var description = "\(event.errorDomain) (\(event.errorStatusCode))"
        if let comment = event.errorComment, !comment.isEmpty {
            description += ": \(comment)"
        }
        return (description, ABErrorOrigin(domain: event.errorDomain, code: event.errorStatusCode))
    }

    nonisolated private static func mapTimeControlStatus(_ status: AVPlayer.TimeControlStatus) -> ABTimeControlStatus {
        switch status {
        case .paused: return .paused
        case .waitingToPlayAtSpecifiedRate: return .waitingToPlay
        case .playing: return .playing
        @unknown default: return .paused
        }
    }

    /// Internal (not `private`) so `@testable import ABPlayerKit` can drive
    /// `ReadyWaitState` directly in concurrency tests. Production behavior is
    /// unchanged — this is purely an access-level promotion.
    enum ReadyWaitResult: Sendable, Equatable {
        case ready
        case timedOut
        case failed
        case cancelled
    }

    /// Coordinates KVO, timeout, and task cancellation without letting any
    /// path resume the continuation twice. Cancellation may arrive before
    /// the continuation is installed, so the resolved result is retained
    /// until installation completes. Internal (not `private`) for the same
    /// testability reason as `ReadyWaitResult` above.
    final class ReadyWaitState: @unchecked Sendable {
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

        /// Returns whether *this* call was the one that actually resolved
        /// the state — `true` for the single winner of a concurrent race,
        /// `false` for every other caller whose result was discarded.
        /// Mirrors `ABCacheStore`'s `ABCacheProgressWaiter.resolve()
        /// -> Bool` so concurrency tests have a real oracle to assert
        /// against instead of a vacuous "the result is one of the possible
        /// cases" check.
        @discardableResult
        func resolve(_ result: ReadyWaitResult) -> Bool {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return false
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
            return true
        }
    }

    /// Internal (not `private`) so integration tests can drive this directly
    /// against a real `AVPlayerItem` on the simulator.
    func waitUntilReady(item: AVPlayerItem, timeout: TimeInterval) async -> ReadyWaitResult {
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

                // `[.initial, .new]`, not just `[.new]`: `.new` alone can
                // miss a status transition that lands between the early
                // `.readyToPlay`/`.failed` checks above and this
                // registration (a TOCTOU window) — the item would then sit
                // at its already-resolved status forever with no further
                // KVO callback to observe. `.initial` delivers the
                // then-current status synchronously on registration, after
                // `state.install(continuation)` above has already run, so
                // an immediate resolve here is safe.
                let statusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
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
                    let nsError = error as NSError
                    self?.onEvent?(.failed(ABPlayerFailure(
                        kind: .itemFailed(description: nsError.localizedDescription),
                        origin: ABErrorOrigin(domain: nsError.domain, code: nsError.code)
                    )))
                }
            }
        }
        observations.add { statusObservation.invalidate() }

        let center = NotificationCenter.default
        let endToken = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor in
                self?.onEvent?(.playedToEnd)
                // Restarting is target-internal — no `.seekCompleted` here,
                // since this isn't a seek `ABPlayer` itself issued. Guarded
                // by the same stale-item check every other hop in this
                // method uses, since the restart seek's `await` can outlive
                // a detach/re-attach that happens in between.
                guard let self, let item, self.isLooping, self.avPlayerItem === item else { return }
                await self.seekToStart()
                guard self.avPlayerItem === item else { return }
                self.avPlayer?.play()
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

        // A stall (above) only means playback paused to rebuffer, not that
        // anything is actually wrong — it resolves on its own most of the
        // time. These two notifications are what let a consumer tell a
        // stuck-but-healthy stall apart from a real problem: FailedToPlayToEndTime
        // is the terminal case (mid-playback failure that KVO on `.status`
        // does not reliably surface — the `.failed` branch in the status
        // observation above only catches failures during initial load), and
        // NewErrorLogEntry is a non-terminal diagnostic signal that
        // something has already gone wrong underneath even if the item
        // hasn't failed outright yet. Both route through the same
        // `.failed(ABPlayerError)` target event / `lastError` path as the
        // existing status-based failure above (stale-item guarded, like
        // `setPeriodicTimeObserver`'s `onTick`, since the `Task` hop after
        // this main-queue callback can run after a newer item replaces
        // `self.avPlayerItem`).
        // The description is resolved synchronously here, in the
        // non-isolated notification callback, rather than inside the `Task`
        // below — `Notification`/`AVPlayerItemErrorLogEvent` aren't
        // `Sendable` (unlike `Foundation`, this file's `AVFoundation`
        // import is `@preconcurrency`, but plain `Foundation` isn't), so
        // only the resulting `String` may cross the hop to `@MainActor`.
        let failedToEndToken = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] notification in
            let underlyingError = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            let resolvedError = underlyingError ?? item?.error.map { $0 as NSError }
            let description = resolvedError?.localizedDescription
                ?? "Playback failed before reaching the end of the item"
            let origin = resolvedError.map { ABErrorOrigin(domain: $0.domain, code: $0.code) }
            Task { @MainActor in
                guard let self, let item, self.avPlayerItem === item else { return }
                self.onEvent?(.failed(ABPlayerFailure(kind: .itemFailed(description: description), origin: origin)))
            }
        }
        observations.add { center.removeObserver(failedToEndToken) }

        let newErrorLogEntryToken = center.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            guard let event = item?.errorLog()?.events.last else { return }
            let (description, origin) = Self.describe(errorLogEvent: event)
            Task { @MainActor in
                guard let self, let item, self.avPlayerItem === item else { return }
                self.onEvent?(.failed(ABPlayerFailure(kind: .itemErrorLogEntry(description: description), origin: origin)))
            }
        }
        observations.add { center.removeObserver(newErrorLogEntryToken) }

        if let avPlayer {
            let timeControlObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let status = Self.mapTimeControlStatus(player.timeControlStatus)
                Task { @MainActor in
                    self?.onEvent?(.timeControlStatusChanged(status))
                }
            }
            observations.add { timeControlObservation.invalidate() }

            // Buffering-suppression signal only — never the sole basis for
            // a buffering verdict. Feeds `isWaitingWithNoItem`, re-evaluated
            // via `.bufferStateChanged` like the other raw buffering
            // signals below.
            let reasonForWaitingObservation = avPlayer.observe(\.reasonForWaitingToPlay, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.onEvent?(.bufferStateChanged)
                }
            }
            observations.add { reasonForWaitingObservation.invalidate() }
        }

        let keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.onEvent?(.bufferStateChanged)
            }
        }
        observations.add { keepUpObservation.invalidate() }

        let bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.onEvent?(.bufferStateChanged)
            }
        }
        observations.add { bufferEmptyObservation.invalidate() }

        let durationObservation = item.observe(\.duration, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.onEvent?(.durationChanged)
            }
        }
        observations.add { durationObservation.invalidate() }

        let presentationSizeObservation = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self, weak item] _, _ in
            let size = item?.presentationSize ?? .zero
            Task { @MainActor in
                guard let self, let item, self.avPlayerItem === item else { return }
                self.onEvent?(.presentationSizeChanged(size))
            }
        }
        observations.add { presentationSizeObservation.invalidate() }
    }
}

/// Lock-protected holder for the single periodic time observer
/// `ABAVPlaybackTarget` may have registered, so both normal `@MainActor`
/// call sites and `ABAVPlaybackTarget.deinit` (nonisolated) can clear it
/// through the same, safe path. `removeIfNeeded`
/// always performs the actual `removeTimeObserver` call on the main
/// thread — the observer itself was registered with `queue: nil` (main
/// queue), and `AVPlayer.removeTimeObserver` racing that queue's callback
/// from a background thread is a documented crash risk, not just a data
/// race on this box's own bookkeeping.
private final class PeriodicObserverBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: Any?
    private var player: AVPlayer?

    func set(token: Any, player: AVPlayer) {
        lock.lock()
        self.token = token
        self.player = player
        lock.unlock()
    }

    /// Idempotent — a second call after the box is already empty (e.g.
    /// `deinit` running after `releasePlayer()` already cleared it) is a
    /// no-op.
    func removeIfNeeded() {
        lock.lock()
        guard let token, let player else {
            lock.unlock()
            return
        }
        self.token = nil
        self.player = nil
        lock.unlock()

        if Thread.isMainThread {
            player.removeTimeObserver(token)
        } else {
            DispatchQueue.main.async {
                player.removeTimeObserver(token)
            }
        }
    }
}
