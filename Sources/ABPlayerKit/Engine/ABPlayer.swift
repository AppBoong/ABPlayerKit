@preconcurrency import AVFoundation
import Foundation
import Observation

/// Owns a single playback grade, broadcasts its lifecycle as events, and
/// guarantees every release path passes through `replaceCurrentItem(nil)`.
/// See DESIGN-ABPlayerKit.md §5.3.
///
/// `@Observable` (round3 Phase3 WP9 — the reason this package requires
/// iOS 17+, Q7 in DESIGN-OPEN-QUESTIONS.md) so SwiftUI views reading
/// `grade`/`isScrubbing`/`hasDisplayedFirstFrame`/`lastError`/`source`/
/// `configuration` directly re-render on change, with no observer bridge
/// required. The token-based `addObserver`/`ABPlayerEvent` system
/// (Observation/ABObserverRegistry.swift) is unaffected and stays the
/// primary mechanism for anything that isn't a simple property read —
/// discrete lifecycle events, UIKit consumers, and anything needing the
/// *reason* a value changed (Q3 in DESIGN-OPEN-QUESTIONS.md: the two
/// systems are deliberately parallel, not a replacement for one another).
@MainActor
@Observable
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
    // Every `var` below is implementation-detail bookkeeping, not
    // SwiftUI-facing state — `@ObservationIgnored` so `@Observable`'s macro
    // expansion leaves them as plain stored properties. This matters beyond
    // just "avoid noise notifications": `prerollTask`/`seekWorkerTask` are
    // `nonisolated(unsafe)` specifically so `deinit` (nonisolated even on
    // this `@MainActor` class) can cancel them directly — `@Observable`
    // rewrites tracked stored properties into computed ones backed by a
    // private accessor that calls into `ObservationRegistrar`, which would
    // silently defeat that nonisolated-access guarantee (round3 Phase3
    // WP9.2).
    @ObservationIgnored
    private var lastAppliedTuningRole: ABTuningRole = .preload
    /// `nonisolated(unsafe)` so `deinit` (nonisolated even on this
    /// `@MainActor` class) can cancel outstanding work when a consumer drops
    /// this instance without calling `release()`. Safe because no other
    /// owner remains to access these concurrently once `deinit` runs.
    @ObservationIgnored
    private nonisolated(unsafe) var prerollTask: Task<Void, Never>?
    @ObservationIgnored
    private var reportedFirstFrameItem: ObjectIdentifier?
    @ObservationIgnored
    private(set) var isLayerAttachmentEnabled = true
    @ObservationIgnored
    private var isNormalizingPlaybackRate = false
    @ObservationIgnored
    private var seekCoalescer = ABSeekCoalescer()
    @ObservationIgnored
    private nonisolated(unsafe) var seekWorkerTask: Task<Void, Never>?
    @ObservationIgnored
    private var seekGeneration = 0
    @ObservationIgnored
    private var lastScrubTime: CMTime?

    @ObservationIgnored
    private var appStateObserver: ABApplicationStateObserver?
    @ObservationIgnored
    private var gradeBeforeBackground: ABPlaybackGrade?
    @ObservationIgnored
    private var wasPlayingBeforeBackground = false

    @ObservationIgnored
    private var interruptionObserver: ABAudioInterruptionObserver?
    @ObservationIgnored
    private var wasPlayingBeforeInterruption = false

    /// The process-wide owner of audio session apply/restore
    /// (`Policy/ABAudioSessionCoordinator.swift`) — shared across every
    /// `ABPlayer` instance so concurrent players (the feed scenario)
    /// coordinate one snapshot/refcount instead of stomping each other's
    /// state (round3 Phase1+2 review C1). Overridable only from the
    /// test-only initializer below.
    private let audioSessionCoordinator: ABAudioSessionCoordinator
    /// This instance's stable identity for `audioSessionCoordinator`
    /// bookkeeping. `nonisolated` (and computed fresh, not cached) so it
    /// can be read from `deinit`, which is nonisolated even on this
    /// `@MainActor` class.
    private nonisolated var audioSessionToken: ObjectIdentifier { ObjectIdentifier(self) }
    /// Whether `play()` still needs to (re)activate the audio session
    /// (round4 review N1). `applyAudioSessionPolicyIfNeeded()`'s M1 fix
    /// ("never memoize, always reactivate") made every `play()` call issue
    /// a synchronous `setCategory`/`setActive` IPC to mediaserverd, even
    /// though most `play()` calls follow a grade promotion (or another
    /// `play()`) that already just activated the exact same policy — a
    /// real cost for feed autoplay, where every cell's promotion is
    /// immediately followed by `play()`. This flag scopes the "always
    /// reactivate" guarantee to only the moments the session might
    /// actually have gone inactive without this instance's knowledge:
    /// starts `true` (nothing has been activated yet), set back to `true`
    /// on an observed interruption `.began` and on returning to the
    /// foreground, and cleared on every successful apply. Grade promotion
    /// to `.current` and an explicit `audioSessionPolicy` switch still
    /// apply unconditionally (`applyAudioSessionPolicyIfNeeded()`'s
    /// `force` parameter) — only the `play()` call site is gated, since
    /// those two are inherently infrequent state transitions, not a
    /// per-tap cost.
    @ObservationIgnored
    private var audioSessionActivationDirty = true

    public init(configuration: ABPlayerConfiguration = .init()) {
        var resolvedConfiguration = configuration
        resolvedConfiguration.playbackRate = ABPlaybackRate.clamped(configuration.playbackRate)
        self.configuration = resolvedConfiguration
        self.target = ABAVPlaybackTarget()
        self.notificationCenter = .default
        self.audioSessionCoordinator = .shared
        wireTarget()
        reconcileBackgroundObserver()
        reconcileInterruptionObserver()
    }

    /// Test-only entry point — lets `ABPlayerKitTests` substitute
    /// `ABFakePlaybackTarget` without exposing `ABPlaybackTarget` publicly,
    /// and substitute an isolated `ABAudioSessionCoordinator` so tests can
    /// exercise multi-player scenarios without polluting `.shared` across
    /// parallel test runs.
    init(
        configuration: ABPlayerConfiguration = .init(),
        target: any ABPlaybackTarget,
        notificationCenter: NotificationCenter = .default,
        audioSessionCoordinator: ABAudioSessionCoordinator = .shared
    ) {
        var resolvedConfiguration = configuration
        resolvedConfiguration.playbackRate = ABPlaybackRate.clamped(configuration.playbackRate)
        self.configuration = resolvedConfiguration
        self.target = target
        self.notificationCenter = notificationCenter
        self.audioSessionCoordinator = audioSessionCoordinator
        wireTarget()
        reconcileBackgroundObserver()
        reconcileInterruptionObserver()
    }

    /// Guards against a consumer dropping this instance without calling
    /// `release()`: an outstanding preroll/seek `Task` can otherwise keep
    /// `target` alive (strongly captured) indefinitely, delaying
    /// `ABAVPlaybackTarget`'s own `deinit` and the periodic time observer
    /// cleanup it performs. `Task.cancel()` is itself nonisolated, so this
    /// is safe to call from `deinit`. Idempotent — cancelling an already
    /// finished or nil `Task` is a no-op.
    /// `audioSessionCoordinator.leave` is a no-op for a token that never
    /// applied a policy, and its own internals are lock-protected rather
    /// than actor-isolated, so it's safe to call unconditionally from this
    /// nonisolated `deinit` — the fix for M4 ("WP1 and WP2 don't compose":
    /// a consumer dropping this instance without calling `release()` used
    /// to leave the audio session permanently in this player's category).
    /// Any restore failure is dropped rather than surfaced — by the time
    /// `deinit` runs there is no observer left to receive a `.failed`
    /// event.
    deinit {
        prerollTask?.cancel()
        seekWorkerTask?.cancel()
        audioSessionCoordinator.leave(audioSessionToken)
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
        // the first `play()`. Not forced (round4 N1) — only reactivates if
        // `audioSessionActivationDirty`, since a grade promotion or an
        // earlier `play()` typically already activated this exact policy.
        applyAudioSessionPolicyIfNeeded(force: false)
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
        if previousConfiguration.interruptionPolicy != configuration.interruptionPolicy
            || previousConfiguration.pausesOnRouteChangeDeviceUnavailable != configuration.pausesOnRouteChangeDeviceUnavailable {
            reconcileInterruptionObserver()
        }

        guard grade.holdsItem else { return }
        // Only re-apply/broadcast when a tuning value actually changed —
        // otherwise unrelated configuration changes (e.g.
        // `periodicTimeInterval` above) would re-issue an identical
        // `AVPlayerItem` tuning call and a spurious `.tuningApplied` on
        // every settings tweak. The grade-transition reapply path
        // (`interpret(_:source:detachReason:)`'s `.applyTuning` action,
        // driven by `set(source:grade:)`) is untouched by this guard.
        //
        // Compares only the tuning that actually applies to the resolved
        // role — not an OR of both (round3 Phase1+2 review m1). With the
        // OR, changing `preloadTuning` alone while `.current` passed the
        // guard despite `currentTuning` being unchanged, re-applying the
        // identical tuning and broadcasting a spurious
        // `.tuningApplied(.current, sameValue)`.
        let role: ABTuningRole = grade == .current ? .current : .preload
        let previousRoleTuning = role == .preload
            ? previousConfiguration.preloadTuning
            : previousConfiguration.currentTuning
        guard previousRoleTuning != tuning(for: role) else { return }
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
        // The system may have deactivated the audio session while
        // backgrounded regardless of `backgroundPolicy` — re-dirty
        // unconditionally so the next `play()` reactivates instead of
        // being skipped by N1's dirty-flag optimization above.
        audioSessionActivationDirty = true
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

    // MARK: - Audio interruption / route change (round3 Phase4 WP10)

    private func reconcileInterruptionObserver() {
        guard configuration.interruptionPolicy != .ignore
            || configuration.pausesOnRouteChangeDeviceUnavailable else {
            interruptionObserver?.invalidate()
            interruptionObserver = nil
            return
        }
        guard interruptionObserver == nil else { return }
        interruptionObserver = ABAudioInterruptionObserver(
            center: notificationCenter,
            onInterruptionBegan: { [weak self] in self?.handleInterruptionBegan() },
            onInterruptionEnded: { [weak self] shouldResume in self?.handleInterruptionEnded(shouldResume: shouldResume) },
            onRouteChangeDeviceUnavailable: { [weak self] in self?.handleRouteChangeDeviceUnavailable() }
        )
    }

    private func handleInterruptionBegan() {
        guard configuration.interruptionPolicy != .ignore else { return }
        // iOS deactivates the audio session for the duration of the
        // interruption — the next `play()` (from `handleInterruptionEnded`'s
        // resume, or a manual one) must reactivate it rather than being
        // skipped by N1's dirty-flag optimization above.
        audioSessionActivationDirty = true
        wasPlayingBeforeInterruption = isPlaying
        if grade == .current {
            target.pause()
        }
        broadcast(.audioInterruptionBegan)
    }

    private func handleInterruptionEnded(shouldResume: Bool) {
        guard configuration.interruptionPolicy != .ignore else { return }
        let resumes = configuration.interruptionPolicy == .pauseAndResume
            && shouldResume
            && wasPlayingBeforeInterruption
            && grade == .current
        wasPlayingBeforeInterruption = false
        if resumes {
            // `play()` reactivates the audio session through
            // `applyAudioSessionPolicyIfNeeded()` → `audioSessionCoordinator`
            // (round3 Phase3 WP2 M1's "always reactivate" fix), so an
            // interruption that deactivated the session ends with it
            // correctly reactivated rather than silently staying inactive.
            play()
        }
        broadcast(.audioInterruptionEnded(resumed: resumes))
    }

    private func handleRouteChangeDeviceUnavailable() {
        guard configuration.pausesOnRouteChangeDeviceUnavailable, grade == .current else { return }
        target.pause()
        broadcast(.audioRouteChangedDeviceUnavailable)
    }

    // MARK: - Audio session (Q4 in DESIGN-OPEN-QUESTIONS.md)

    /// Applies `configuration.audioSessionPolicy` through
    /// `audioSessionCoordinator` if it isn't `.unmanaged`. No-op while not
    /// `.current` — callers gate this at grade `.current` promotion and
    /// `play()` (playback start), per the confirmed Q4 design.
    ///
    /// `force: true` (the default — used by grade promotion and by an
    /// explicit `audioSessionPolicy` switch) always (re)activates, never
    /// memoized on "already applied", so a promotion after an interruption
    /// reactivates the session instead of silently staying inactive
    /// (round3 Phase1+2 review M1). `force: false` (used only by `play()`)
    /// additionally requires `audioSessionActivationDirty`, so a `play()`
    /// that immediately follows an already-successful apply is a no-op
    /// instead of a redundant IPC (round4 N1) — reactivation is still
    /// guaranteed for the case M1 exists to fix, because
    /// `handleInterruptionBegan`/`handleWillEnterForeground` re-dirty the
    /// flag at the two points the session might actually have gone
    /// inactive out from under this instance.
    ///
    /// The coordinator itself snapshots the host's prior category/mode/
    /// options exactly once, before its *first* participant's apply, and
    /// keeps that snapshot across a failed activate (M2) or additional
    /// participants (C1).
    private func applyAudioSessionPolicyIfNeeded(force: Bool = true) {
        guard grade == .current else { return }
        let policy = configuration.audioSessionPolicy
        guard policy != .unmanaged else { return }
        guard force || audioSessionActivationDirty else { return }
        switch audioSessionCoordinator.apply(policy, for: audioSessionToken) {
        case .success:
            audioSessionActivationDirty = false
        case .failure(let error):
            surfaceAudioSessionFailure(error)
        }
    }

    /// Leaves `audioSessionCoordinator`. Callers gate this at the policy
    /// switching back to `.unmanaged` and at `release()`, per Q4. A no-op
    /// if this instance never participated, and only actually restores the
    /// host's snapshot once every other participating player has also left
    /// (C1) — so this is safe to call unconditionally from either trigger.
    private func restoreAudioSessionPolicyIfNeeded() {
        if case .failure(let error)? = audioSessionCoordinator.leave(audioSessionToken) {
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
