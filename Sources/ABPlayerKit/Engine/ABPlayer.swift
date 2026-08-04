@preconcurrency import AVFoundation
import Foundation

/// Owns a single playback grade, broadcasts its lifecycle as events, and
/// guarantees every release path passes through `replaceCurrentItem(nil)`.
/// See DESIGN-ABPlayerKit.md §5.3.
@MainActor
public final class ABPlayer {
    public let id = ABPlayerID()

    public var configuration: ABPlayerConfiguration {
        didSet { applyConfigurationChange(from: oldValue) }
    }

    public private(set) var grade: ABPlaybackGrade = .released
    public private(set) var source: ABMediaSource?
    public private(set) var lastError: ABPlayerError?
    public private(set) var hasDisplayedFirstFrame = false
    public private(set) var isScrubbing = false

    /// Escape hatch — kept public for study purposes and consumer
    /// fallback (DESIGN-ABPlayerKit.md §1). Grade-related state must still
    /// go through `set(source:grade:)`/`promote(to:)`/`release()`.
    public var avPlayer: AVPlayer? { target.avPlayer }
    public var avPlayerItem: AVPlayerItem? { target.avPlayerItem }

    public var isPlaying: Bool { target.isPlaying }
    /// The desired playback rate, retained while playback is paused.
    public var rate: Float { configuration.playbackRate }
    public var currentTime: CMTime { target.currentTime }
    public var duration: CMTime? { target.duration }
    /// A synchronous snapshot for initial rendering and state restoration.
    public var playbackTime: ABPlaybackTime {
        ABPlaybackTime(
            currentTime: target.currentTime,
            duration: target.duration,
            bufferedUntil: target.bufferedUntil
        )
    }

    private let target: any ABPlaybackTarget
    private let notificationCenter: NotificationCenter
    private let planner = ABGradePlanner()
    private let observerRegistry = ABObserverRegistry()
    private let layerAttachmentObserverRegistry = ABLayerAttachmentObserverRegistry()
    private var lastAppliedTuningRole: ABTuningRole = .preload
    /// `nonisolated(unsafe)` so `deinit` (nonisolated even on this
    /// `@MainActor` class) can cancel outstanding work when a consumer drops
    /// this instance without calling `release()`. Safe because no other
    /// owner remains to access these concurrently once `deinit` runs.
    private nonisolated(unsafe) var prerollTask: Task<Void, Never>?
    private var reportedFirstFrameItem: ObjectIdentifier?
    private(set) var isLayerAttachmentEnabled = true
    private var isNormalizingPlaybackRate = false
    private var seekCoalescer = ABSeekCoalescer()
    private nonisolated(unsafe) var seekWorkerTask: Task<Void, Never>?
    private var seekGeneration = 0
    private var lastScrubTime: CMTime?

    private var appStateObserver: ABApplicationStateObserver?
    private var gradeBeforeBackground: ABPlaybackGrade?
    private var wasPlayingBeforeBackground = false

    private let audioSessionController: any ABAudioSessionControlling
    /// The `ABAudioSessionPolicy` currently applied via `audioSessionController`,
    /// or `nil` if none is (Q4 in DESIGN-OPEN-QUESTIONS.md: opt-in, never
    /// applied unless `audioSessionPolicy != .unmanaged`).
    private var appliedAudioSessionPolicy: ABAudioSessionPolicy?
    /// The `AVAudioSession` category/mode/options captured immediately
    /// before the first apply, so restore can put them back exactly.
    private var savedAudioSessionSnapshot: ABAudioSessionCategorySnapshot?

    public init(configuration: ABPlayerConfiguration = .init()) {
        var resolvedConfiguration = configuration
        resolvedConfiguration.playbackRate = ABPlaybackRate.clamped(configuration.playbackRate)
        self.configuration = resolvedConfiguration
        self.target = ABAVPlaybackTarget()
        self.notificationCenter = .default
        self.audioSessionController = ABAudioSessionAdapter()
        wireTarget()
        reconcileBackgroundObserver()
    }

    /// Test-only entry point — lets `ABPlayerKitTests` substitute
    /// `ABFakePlaybackTarget` without exposing `ABPlaybackTarget` publicly.
    init(
        configuration: ABPlayerConfiguration = .init(),
        target: any ABPlaybackTarget,
        notificationCenter: NotificationCenter = .default,
        audioSessionController: any ABAudioSessionControlling = ABAudioSessionAdapter()
    ) {
        var resolvedConfiguration = configuration
        resolvedConfiguration.playbackRate = ABPlaybackRate.clamped(configuration.playbackRate)
        self.configuration = resolvedConfiguration
        self.target = target
        self.notificationCenter = notificationCenter
        self.audioSessionController = audioSessionController
        wireTarget()
        reconcileBackgroundObserver()
    }

    /// Guards against a consumer dropping this instance without calling
    /// `release()`: an outstanding preroll/seek `Task` can otherwise keep
    /// `target` alive (strongly captured) indefinitely, delaying
    /// `ABAVPlaybackTarget`'s own `deinit` and the periodic time observer
    /// cleanup it performs. `Task.cancel()` is itself nonisolated, so this
    /// is safe to call from `deinit`. Idempotent — cancelling an already
    /// finished or nil `Task` is a no-op.
    deinit {
        prerollTask?.cancel()
        seekWorkerTask?.cancel()
    }

    // MARK: - Grade

    /// The single entry point that mutates `(source, grade)`. Illegal
    /// combinations (`grade >= .preloaded && source == nil`) are clamped to
    /// `.instanceOnly` and reported via `.invalidGradeForSource` — never a
    /// throw or a crash.
    public func set(source newSource: ABMediaSource?, grade requestedGrade: ABPlaybackGrade) {
        set(source: newSource, grade: requestedGrade, detachReason: nil)
    }

    private func set(
        source newSource: ABMediaSource?,
        grade requestedGrade: ABPlaybackGrade,
        detachReason explicitDetachReason: ABDetachReason?
    ) {
        var resolvedGrade = requestedGrade
        if requestedGrade.holdsItem && newSource == nil {
            resolvedGrade = .instanceOnly
            broadcast(.invalidGradeForSource(requested: requestedGrade))
        }

        let sourceChanged = newSource != source
        let previousGrade = grade

        guard previousGrade != resolvedGrade || sourceChanged else { return }

        let actions = planner.actions(
            from: previousGrade,
            to: resolvedGrade,
            source: newSource,
            sourceChanged: sourceChanged,
            rewindOnDemotion: configuration.rewindOnDemotion
        )

        let detachReason = explicitDetachReason ?? (resolvedGrade == .released
            ? .release
            : (resolvedGrade < previousGrade ? .demotion : .sourceChanged))

        source = newSource
        grade = resolvedGrade

        if resolvedGrade != .current || sourceChanged {
            target.setPeriodicTimeObserver(interval: nil, onTick: nil)
            resetSeeking()
        }

        interpret(actions, source: newSource, detachReason: detachReason)
        if resolvedGrade == .current {
            reconcilePeriodicTimeObserver()
            applyAudioSessionPolicyIfNeeded()
        }
        if resolvedGrade == .released {
            // `release()` is one of the two explicit restore triggers
            // (Q4 in DESIGN-OPEN-QUESTIONS.md) — the other is the policy
            // itself switching back to `.unmanaged`, handled in
            // `applyConfigurationChange`.
            restoreAudioSessionPolicyIfNeeded()
        }

        if previousGrade != resolvedGrade {
            broadcast(.gradeChanged(from: previousGrade, to: resolvedGrade))
        }
        if sourceChanged {
            broadcast(.sourceChanged(newSource))
        }
    }

    public func promote(to grade: ABPlaybackGrade) {
        set(source: source, grade: grade)
    }

    /// Releases every resource. Safe to call from any grade — always routes
    /// through `.detachItem` when an item is held.
    public func release() {
        set(source: nil, grade: .released)
    }

    // MARK: - Playback control (valid only at `.current`)

    public func play() {
        guard grade == .current else {
            broadcast(.playbackRejected)
            return
        }
        // Also covers "playback start" from Q4's apply trigger — e.g. the
        // policy was switched to a managed one after promotion but before
        // the first `play()`.
        applyAudioSessionPolicyIfNeeded()
        target.play()
    }

    public func pause() {
        guard grade == .current else {
            broadcast(.playbackRejected)
            return
        }
        target.pause()
    }

    /// Changes the desired rate without starting paused playback.
    public func setRate(_ rate: Float) {
        configuration.playbackRate = ABPlaybackRate.clamped(rate)
    }

    /// Performs the precise seek behavior provided in v0.1.
    public func seek(to time: CMTime) async {
        await seek(to: time, tolerance: .precise)
    }

    /// Seeks with explicit tolerances when this player is current.
    public func seek(to time: CMTime, tolerance: ABSeekTolerance) async {
        guard grade == .current else {
            broadcast(.playbackRejected)
            return
        }
        let landed = await target.seek(to: time, tolerance: tolerance)
        broadcast(.seekCompleted(to: landed))
    }

    /// Moves relative to the current time, clamped to the playable range.
    public func skip(by interval: TimeInterval) async {
        guard grade == .current else {
            broadcast(.playbackRejected)
            return
        }
        let currentSeconds = currentTime.isNumeric ? CMTimeGetSeconds(currentTime) : 0
        let proposedSeconds = max(0, currentSeconds + (interval.isFinite ? interval : 0))
        let upperBound: TimeInterval?
        if let duration, duration.isNumeric {
            let seconds = CMTimeGetSeconds(duration)
            upperBound = seconds.isFinite && seconds >= 0 ? seconds : nil
        } else {
            upperBound = nil
        }
        let destinationSeconds = upperBound.map { min(proposedSeconds, $0) } ?? proposedSeconds
        let destination = CMTime(
            seconds: destinationSeconds,
            preferredTimescale: currentTime.timescale > 0 ? currentTime.timescale : 600
        )
        if isScrubbing {
            scrub(to: destination)
        } else {
            let landed = await target.seek(to: destination, tolerance: .precise)
            broadcast(.seekCompleted(to: landed))
        }
    }

    // MARK: - Scrubbing

    /// Starts a coalesced interactive seek session.
    public func beginScrubbing() {
        guard grade == .current else {
            broadcast(.playbackRejected)
            return
        }
        guard !isScrubbing else { return }
        isScrubbing = true
        lastScrubTime = nil
        broadcast(.scrubbingChanged(isScrubbing: true))
    }

    /// Requests the newest interactive destination without making callers await AVFoundation.
    public func scrub(to time: CMTime) {
        guard grade == .current else {
            broadcast(.playbackRejected)
            return
        }
        guard isScrubbing else {
            Task { [weak self, target] in
                guard let self else { return }
                let landed = await target.seek(to: time, tolerance: self.configuration.scrubTolerance)
                self.broadcast(.seekCompleted(to: landed))
            }
            return
        }

        lastScrubTime = time
        let decision = seekCoalescer.request(time, tolerance: configuration.scrubTolerance)
        startSeekWorker(for: decision)
    }

    /// Commits the newest scrub destination precisely before resuming normal updates.
    public func endScrubbing() async {
        guard isScrubbing else { return }
        var requiresStandaloneCommit = false
        if grade == .current {
            let flushDecision = seekCoalescer.flush(finalTolerance: .precise)
            requiresStandaloneCommit = flushDecision == .hold && seekCoalescer.inFlight == nil
            startSeekWorker(for: flushDecision)
        }
        if let seekWorkerTask {
            await seekWorkerTask.value
            self.seekWorkerTask = nil
        }
        if grade == .current, requiresStandaloneCommit, let lastScrubTime {
            let landed = await target.seek(to: lastScrubTime, tolerance: .precise)
            broadcast(.seekCompleted(to: landed))
        } else if grade != .current {
            broadcast(.playbackRejected)
        }
        let shouldBroadcastBoundary = isScrubbing
        seekCoalescer.reset()
        lastScrubTime = nil
        isScrubbing = false
        if shouldBroadcastBoundary {
            broadcast(.scrubbingChanged(isScrubbing: false))
        }
        broadcastPeriodicTime(at: target.currentTime)
    }

    public func setMuted(_ muted: Bool) {
        configuration.isMuted = muted
    }

    // MARK: - Preload control

    public func startPreroll() {
        guard grade == .preloaded, let rate = configuration.prerollRate else { return }
        armPreroll(rate: rate)
    }

    public func cancelPreload() {
        guard let prerollTask else { return }
        prerollTask.cancel()
        self.prerollTask = nil
        broadcast(.preloadCancelled)
    }

    // MARK: - Observation

    public func addObserver(_ observer: some ABPlayerObserver) -> ABObservationToken {
        observerRegistry.add { [weak observer] player, event in
            observer?.player(player, didEmit: event)
        }
    }

    public func addObserver(
        _ handler: @escaping @MainActor @Sendable (ABPlayerEvent) -> Void
    ) -> ABObservationToken {
        observerRegistry.add { _, event in handler(event) }
    }

    func addLayerAttachmentObserver(
        _ handler: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> ABObservationToken {
        layerAttachmentObserverRegistry.add(handler)
    }

    // MARK: - Internal (used by ABPlayerView for first-frame reporting)

    /// Called by `ABPlayerView` once `ABFirstFrameDetector.shouldReport`
    /// confirms both `AVPlayerLayer.isReadyForDisplay` and
    /// `AVPlayerItem.status == .readyToPlay` for the current item.
    func reportFirstFrameDisplayed(at time: CFTimeInterval) {
        guard let avPlayerItem else { return }
        let identity = ObjectIdentifier(avPlayerItem)
        guard reportedFirstFrameItem != identity else { return }
        reportedFirstFrameItem = identity
        hasDisplayedFirstFrame = true
        broadcast(.firstFrameDisplayed(at: time))
    }

    // MARK: - Private

    private func wireTarget() {
        target.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: ABTargetEvent) {
        switch event {
        case .itemStatusChanged(let status):
            broadcast(.itemStatusChanged(status))
        case .playbackStalled:
            broadcast(.playbackStalled)
        case .playedToEnd:
            broadcast(.playedToEnd)
        case .timeControlStatusChanged(let status):
            broadcast(.timeControlStatusChanged(status))
        case .failed(let error):
            lastError = error
            broadcast(.failed(error))
        }
    }

    private func interpret(_ actions: [ABGradeAction], source: ABMediaSource?, detachReason: ABDetachReason) {
        for action in actions {
            switch action {
            case .createPlayer:
                target.makePlayer()

            case .cancelPreload:
                cancelPreload()

            case .pause:
                target.pause()

            case .applyTuning(let role):
                lastAppliedTuningRole = role
                let tuning = tuning(for: role)
                if target.applyTuning(tuning) {
                    broadcast(.tuningApplied(role, tuning))
                }

            case .attachItem(let attachedSource):
                reportedFirstFrameItem = nil
                hasDisplayedFirstFrame = false
                target.attachItem(
                    attachedSource,
                    tuning: tuning(for: lastAppliedTuningRole),
                    assetFactory: configuration.assetFactory
                )
                broadcast(.tuningApplied(lastAppliedTuningRole, tuning(for: lastAppliedTuningRole)))
                target.setMuted(configuration.isMuted)
                target.setLooping(configuration.isLooping)
                target.setRate(configuration.playbackRate)

            case .detachItem:
                broadcast(.itemDetached(reason: detachReason))
                target.detachItem()

            case .armPreroll:
                if let rate = configuration.prerollRate {
                    armPreroll(rate: rate)
                }

            case .seekToStart:
                Task { [target] in await target.seekToStart() }

            case .teardownObservers:
                // ABAVPlaybackTarget invalidates its own observation bag as
                // part of .detachItem/.releasePlayer; nothing extra to do
                // here for either conformer.
                break

            case .releasePlayer:
                target.releasePlayer()
            }
        }
    }

    private func tuning(for role: ABTuningRole) -> ABPlaybackTuning {
        role == .preload ? configuration.preloadTuning : configuration.currentTuning
    }

    private func armPreroll(rate: Float) {
        prerollTask?.cancel()
        let timeout = configuration.prerollTimeout
        prerollTask = Task { [weak self, target] in
            let result = await target.preroll(rate: rate, timeout: timeout)
            guard !Task.isCancelled else { return }
            self?.prerollTask = nil
            switch result {
            case .success:
                self?.broadcast(.prerollCompleted(success: true))
            case .timedOut:
                let error = ABPlayerError.prerollTimedOut(after: timeout)
                self?.lastError = error
                self?.broadcast(.failed(error))
                self?.broadcast(.prerollCompleted(success: false))
            case .failed:
                let error = ABPlayerError.prerollFailed
                self?.lastError = error
                self?.broadcast(.failed(error))
                self?.broadcast(.prerollCompleted(success: false))
            case .cancelled:
                break
            }
        }
    }

    private func applyConfigurationChange(from previousConfiguration: ABPlayerConfiguration) {
        guard !isNormalizingPlaybackRate else { return }
        let clampedRate = ABPlaybackRate.clamped(configuration.playbackRate)
        if configuration.playbackRate != clampedRate {
            isNormalizingPlaybackRate = true
            configuration.playbackRate = clampedRate
            isNormalizingPlaybackRate = false
        }
        if previousConfiguration.backgroundPolicy != configuration.backgroundPolicy {
            if previousConfiguration.backgroundPolicy == .pauseAndDetachLayer,
               configuration.backgroundPolicy != .pauseAndDetachLayer {
                setLayerAttachmentEnabled(true)
            }
            reconcileBackgroundObserver()
        }
        if previousConfiguration.isMuted != configuration.isMuted {
            target.setMuted(configuration.isMuted)
        }
        if previousConfiguration.isLooping != configuration.isLooping {
            target.setLooping(configuration.isLooping)
        }
        if ABPlaybackRate.clamped(previousConfiguration.playbackRate) != configuration.playbackRate {
            target.setRate(configuration.playbackRate)
            broadcast(.rateChanged(configuration.playbackRate))
        }
        if previousConfiguration.periodicTimeInterval != configuration.periodicTimeInterval {
            reconcilePeriodicTimeObserver()
        }
        if previousConfiguration.audioSessionPolicy != configuration.audioSessionPolicy {
            if configuration.audioSessionPolicy == .unmanaged {
                restoreAudioSessionPolicyIfNeeded()
            } else {
                applyAudioSessionPolicyIfNeeded()
            }
        }

        guard grade.holdsItem else { return }
        let role: ABTuningRole = grade == .current ? .current : .preload
        lastAppliedTuningRole = role
        let resolvedTuning = tuning(for: role)
        if target.applyTuning(resolvedTuning) {
            broadcast(.tuningApplied(role, resolvedTuning))
        }
    }

    private func reconcileBackgroundObserver() {
        guard configuration.backgroundPolicy != .ignore else {
            appStateObserver?.invalidate()
            appStateObserver = nil
            return
        }
        guard appStateObserver == nil else { return }
        appStateObserver = ABApplicationStateObserver(
            center: notificationCenter,
            onBackground: { [weak self] in self?.handleDidEnterBackground() },
            onForeground: { [weak self] in self?.handleWillEnterForeground() }
        )
    }

    private func handleDidEnterBackground() {
        switch configuration.backgroundPolicy {
        case .ignore:
            return
        case .pause:
            wasPlayingBeforeBackground = isPlaying
            if grade == .current {
                target.pause()
            }
        case .pauseAndDetachLayer:
            wasPlayingBeforeBackground = isPlaying
            if grade == .current {
                target.pause()
            }
            setLayerAttachmentEnabled(false)
        case .demoteToInstance:
            gradeBeforeBackground = grade
            if grade.holdsItem {
                set(source: source, grade: .instanceOnly, detachReason: .backgroundPolicy)
            }
        }
    }

    private func handleWillEnterForeground() {
        switch configuration.backgroundPolicy {
        case .ignore:
            return
        case .pause:
            if grade == .current && wasPlayingBeforeBackground {
                target.play()
            }
            wasPlayingBeforeBackground = false
        case .pauseAndDetachLayer:
            setLayerAttachmentEnabled(true)
            if grade == .current && wasPlayingBeforeBackground {
                target.play()
            }
            wasPlayingBeforeBackground = false
        case .demoteToInstance:
            if let restoredGrade = gradeBeforeBackground {
                promote(to: restoredGrade)
            }
            gradeBeforeBackground = nil
        }
    }

    private func broadcast(_ event: ABPlayerEvent) {
        observerRegistry.broadcast(event, from: self)
    }

    // MARK: - Audio session (Q4 in DESIGN-OPEN-QUESTIONS.md)

    /// Applies `configuration.audioSessionPolicy` if it isn't `.unmanaged`
    /// and isn't already the currently-applied policy. No-op while not
    /// `.current` — callers gate this at grade `.current` promotion and
    /// `play()` (playback start), per the confirmed Q4 design. Snapshots the
    /// prior category/mode/options exactly once, before the *first* apply,
    /// so restoring later always reflects the host app's original state
    /// even if the policy is switched between two managed values in between.
    private func applyAudioSessionPolicyIfNeeded() {
        guard grade == .current else { return }
        let policy = configuration.audioSessionPolicy
        guard policy != .unmanaged, appliedAudioSessionPolicy != policy else { return }
        if appliedAudioSessionPolicy == nil {
            savedAudioSessionSnapshot = audioSessionController.snapshotCurrentCategory()
        }
        do {
            try audioSessionController.activate(policy)
            appliedAudioSessionPolicy = policy
        } catch {
            if appliedAudioSessionPolicy == nil {
                savedAudioSessionSnapshot = nil
            }
            surfaceAudioSessionFailure(error)
        }
    }

    /// Restores the snapshot captured by `applyAudioSessionPolicyIfNeeded()`
    /// and deactivates the session. Callers gate this at the policy
    /// switching back to `.unmanaged` and at `release()`, per Q4. A no-op if
    /// nothing is currently applied — restoring is therefore safe to call
    /// unconditionally from either trigger.
    private func restoreAudioSessionPolicyIfNeeded() {
        guard appliedAudioSessionPolicy != nil else { return }
        appliedAudioSessionPolicy = nil
        guard let snapshot = savedAudioSessionSnapshot else { return }
        savedAudioSessionSnapshot = nil
        do {
            try audioSessionController.restore(snapshot)
        } catch {
            surfaceAudioSessionFailure(error)
        }
    }

    /// Q4 explicitly rules out swallowing apply/restore failures — surface
    /// them the same way every other asynchronous failure in this type is
    /// surfaced (DESIGN-ABPlayerKit.md §6).
    private func surfaceAudioSessionFailure(_ error: Error) {
        let policyError = ABPlayerError.audioSessionOperationFailed(
            description: (error as NSError).localizedDescription
        )
        lastError = policyError
        broadcast(.failed(policyError))
    }

    private func startSeekWorker(for decision: ABSeekCoalescer.Decision) {
        guard case .issue = decision else { return }
        let generation = seekGeneration
        seekWorkerTask = Task { [weak self] in
            await self?.runSeekWorker(startingWith: decision, generation: generation)
        }
    }

    private func runSeekWorker(
        startingWith decision: ABSeekCoalescer.Decision,
        generation: Int
    ) async {
        var nextDecision = decision
        while case .issue(let time, let tolerance) = nextDecision {
            let landed = await target.seek(to: time, tolerance: tolerance)
            guard generation == seekGeneration else { return }
            broadcast(.seekCompleted(to: landed))
            nextDecision = seekCoalescer.completed()
        }
    }

    private func resetSeeking() {
        seekGeneration += 1
        seekWorkerTask?.cancel()
        seekWorkerTask = nil
        seekCoalescer.reset()
        lastScrubTime = nil
        guard isScrubbing else { return }
        isScrubbing = false
        broadcast(.scrubbingChanged(isScrubbing: false))
    }

    private func reconcilePeriodicTimeObserver() {
        guard grade == .current,
              let interval = configuration.periodicTimeInterval,
              interval.isFinite,
              interval > 0 else {
            target.setPeriodicTimeObserver(interval: nil, onTick: nil)
            return
        }
        target.setPeriodicTimeObserver(interval: interval) { [weak self] time in
            self?.broadcastPeriodicTime(at: time)
        }
    }

    private func broadcastPeriodicTime(at time: CMTime) {
        guard grade == .current,
              !isScrubbing,
              configuration.periodicTimeInterval != nil else { return }
        broadcast(.periodicTime(ABPlaybackTime(
            currentTime: time,
            duration: target.duration,
            bufferedUntil: target.bufferedUntil
        )))
    }

    private func setLayerAttachmentEnabled(_ enabled: Bool) {
        guard isLayerAttachmentEnabled != enabled else { return }
        isLayerAttachmentEnabled = enabled
        layerAttachmentObserverRegistry.broadcast(enabled)
    }
}
