@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Observation

/// Owns a single playback grade, broadcasts its lifecycle as events, and
/// guarantees every release path passes through `replaceCurrentItem(nil)`.
///
/// `@Observable` (the reason this package requires iOS 17+) so SwiftUI
/// views reading
/// `grade`/`isScrubbing`/`hasDisplayedFirstFrame`/`lastError`/`source`/
/// `configuration` directly re-render on change, with no observer bridge
/// required. The token-based `addObserver`/`ABPlayerEvent` system
/// (Observation/ABHandlerRegistry.swift) is unaffected and stays the
/// primary mechanism for anything that isn't a simple property read —
/// discrete lifecycle events, UIKit consumers, and anything needing the
/// *reason* a value changed: the two systems are deliberately parallel,
/// not a replacement for one another.
@MainActor
@Observable
public final class ABPlayer {
    public let id = ABPlayerID()

    public var configuration: ABPlayerConfiguration {
        didSet { applyConfigurationChange(from: oldValue) }
    }

    public private(set) var grade: ABPlaybackGrade = .released
    public private(set) var source: ABMediaSource?
    /// The most recent terminal failure, or `nil` once it's been reset by a
    /// new attach/source change/detach/release. Non-terminal diagnostics
    /// (`.itemErrorLogEntry`) never appear here — see ``lastDiagnostic``.
    public private(set) var lastFailure: ABPlayerFailure?
    /// The most recent non-terminal diagnostic (`.itemErrorLogEntry`) — a
    /// still-loading or still-playing stream routinely surfaces one of
    /// these on its own. Kept on a separate channel from ``lastFailure`` so
    /// a healthy diagnostic never masquerades as a terminal failure.
    public private(set) var lastDiagnostic: ABPlayerFailure?
    /// A computed projection of ``lastFailure``'s classification, kept for
    /// source compatibility. Still `@Observable`-tracked, since it reads a
    /// tracked stored property.
    public var lastError: ABPlayerError? { lastFailure?.kind }
    public private(set) var hasDisplayedFirstFrame = false
    public private(set) var isScrubbing = false
    /// The requested destination while a non-scrubbing seek (`seek(to:)`,
    /// `skip(by:)`, or an out-of-session `scrub(to:)`) is outstanding, or
    /// `nil` once it settles. Lets `skip(by:)` accumulate consecutive taps
    /// against the requested destination instead of the live (still
    /// mid-flight) `currentTime`. Not updated during an active scrubbing
    /// session.
    public private(set) var pendingSeekTime: CMTime?

    /// Escape hatch — kept public for study purposes and consumer
    /// fallback. Grade-related state must still
    /// go through `set(source:grade:)`/`promote(to:)`/`release()`.
    public var avPlayer: AVPlayer? { target.avPlayer }
    public var avPlayerItem: AVPlayerItem? { target.avPlayerItem }

    /// A recompute-from-target mirror, not an independent state machine —
    /// always reflects `target.isPlaying` re-read at whichever trigger
    /// point last fired (`refreshPlaybackMirrors()`), so its meaning can
    /// never drift from the target's own definition (`rate != 0 &&
    /// timeControlStatus != .paused`). Synchronous immediately after
    /// `play()`/`pause()` — a Controls-layer invariant this package
    /// guarantees.
    public private(set) var isPlaying = false
    /// The desired playback rate, retained while playback is paused.
    public var rate: Float { configuration.playbackRate }
    public var currentTime: CMTime { target.currentTime }
    /// Whether external playback (AirPlay) is currently active. Not
    /// `@Observable`-tracked — a target is re-read on every access, so
    /// SwiftUI does not automatically re-render on change. KVO `avPlayer`
    /// directly, or use `AVRoutePickerView`'s own state, for a reactive
    /// signal.
    public var isExternalPlaybackActive: Bool { target.isExternalPlaybackActive }
    /// A recompute-from-target mirror of `target.duration` — not
    /// normalized (a live/indefinite item still reads `kCMTimeIndefinite`
    /// here). Normalization stays ``ABPlaybackTime``'s job; only
    /// ``ABPlayerEvent/durationAvailable(_:)`` fires from a normalized,
    /// finite value.
    public private(set) var duration: CMTime?
    /// A recompute-from-target mirror judged by `ABBufferingEvaluator` from
    /// raw target signals (`isPlaybackLikelyToKeepUp`/
    /// `isPlaybackBufferEmpty`/`timeControlStatus`) — never inferred from
    /// `timeControlStatus == .waitingToPlay` alone, which conflates
    /// rate-evaluation wait with an actual rebuffer and misses the
    /// `automaticallyWaitsToMinimizeStalling == false` stall path.
    public private(set) var isBuffering = false
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
    private let backgroundPolicyMachine = ABBackgroundPolicyMachine()
    private let observerRegistry = ABHandlerRegistry<ABPlayerEvent>()
    private let layerAttachmentObserverRegistry = ABHandlerRegistry<Bool>()
    // Every `var` below is implementation-detail bookkeeping, not
    // SwiftUI-facing state — `@ObservationIgnored` so `@Observable`'s macro
    // expansion leaves them as plain stored properties. This matters beyond
    // just "avoid noise notifications": `prerollTask`/`seekWorkerTask` are
    // `nonisolated(unsafe)` specifically so `deinit` (nonisolated even on
    // this `@MainActor` class) can cancel them directly — `@Observable`
    // rewrites tracked stored properties into computed ones backed by a
    // private accessor that calls into `ObservationRegistrar`, which would
    // silently defeat that nonisolated-access guarantee.
    @ObservationIgnored
    private var lastAppliedTuningRole: ABTuningRole = .preload
    /// Reported by `ABPlayerView.layoutSubviews()`; `.zero` while no view
    /// is attached (or before its first layout pass) — resolves
    /// `displaySizeSentinel` to "no cap" rather than a device screen size.
    @ObservationIgnored
    private var displaySize: CGSize = .zero
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
    /// Set by a bound `ABPictureInPictureSession` when Picture in Picture
    /// starts/stops. While `true`, `ABBackgroundPolicyMachine` suppresses
    /// every background policy's automatic side effects — PiP renders from
    /// the same layer a policy would otherwise pause or detach.
    @ObservationIgnored
    private(set) var isPictureInPictureActive = false
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

    /// "Does the user want playback running" — independent of `rate`,
    /// which a stall can force to `0` while intent is still to play (see
    /// `ABBufferingEvaluator`'s `.paused` branch). `true` from `play()`,
    /// `false` from `pause()`/`.playedToEnd`/leaving `.current`/a
    /// background-policy or interruption pause.
    @ObservationIgnored
    private var desiresPlayback = false
    /// Tracks an unresolved `.playbackStalled` so `.stallEnded` broadcasts
    /// at most once per stall, and only when one is actually outstanding.
    @ObservationIgnored
    private var isStallOutstanding = false
    /// The last finite duration `.durationAvailable` broadcast for the
    /// currently-attached item — reset on detach so a same-valued duration
    /// on the next item broadcasts again.
    @ObservationIgnored
    private var lastBroadcastFiniteDuration: CMTime?
    /// The last non-zero `presentationSize` `.presentationSizeChanged`
    /// broadcast — reset on detach for the same reason as above.
    @ObservationIgnored
    private var lastBroadcastPresentationSize: CGSize?

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
    /// state. Overridable only from the test-only initializer below.
    private let audioSessionCoordinator: ABAudioSessionCoordinator
    /// This instance's stable identity for `audioSessionCoordinator`
    /// bookkeeping. `nonisolated` (and computed fresh, not cached) so it
    /// can be read from `deinit`, which is nonisolated even on this
    /// `@MainActor` class.
    private nonisolated var audioSessionToken: ObjectIdentifier { ObjectIdentifier(self) }
    /// Whether `play()` still needs to (re)activate the audio session.
    /// `applyAudioSessionPolicyIfNeeded()` always reactivates rather than
    /// memoizing, so every `play()` call issues a synchronous
    /// `setCategory`/`setActive` IPC to mediaserverd, even
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
    /// nonisolated `deinit`: without this call, a consumer dropping this
    /// instance without calling `release()` would leave the audio session
    /// permanently in this player's category.
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

        // A source change (even one that doesn't touch a currently-held
        // item, e.g. `.instanceOnly -> .instanceOnly`) and every release
        // invalidate whatever failure/diagnostic belonged to the previous
        // source — `.attachItem`/`.detachItem` below cover the two cases
        // this condition can't see (a fresh attach or detach with the
        // source unchanged).
        if sourceChanged || resolvedGrade == .released {
            lastFailure = nil
            lastDiagnostic = nil
        }

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

        if resolvedGrade != .current {
            // Leaving `.current` — whatever the user's play intent was, it
            // can no longer be honored (no `AVPlayer` command surface at
            // this grade).
            desiresPlayback = false
        }
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
            // `release()` is one of the two explicit restore triggers —
            // the other is the policy itself switching back to
            // `.unmanaged`, handled in `applyConfigurationChange`.
            restoreAudioSessionPolicyIfNeeded()
        }

        if previousGrade != resolvedGrade {
            broadcast(.gradeChanged(from: previousGrade, to: resolvedGrade))
        }
        if sourceChanged {
            broadcast(.sourceChanged(newSource))
        }
        // End of the transition — re-evaluate the mirrors once against
        // whatever attach/detach/tuning just happened, on top of whichever
        // KVO-driven refreshes land asynchronously afterward.
        refreshPlaybackMirrors()
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
            rejectCall(.play)
            return
        }
        // Also covers "playback start" as an audio session apply trigger —
        // e.g. the policy was switched to a managed one after promotion but
        // before the first `play()`. Not forced — only reactivates if
        // `audioSessionActivationDirty`, since a grade promotion or an
        // earlier `play()` typically already activated this exact policy.
        applyAudioSessionPolicyIfNeeded(force: false)
        desiresPlayback = true
        target.play()
        // Synchronous — Controls relies on `isPlaying` reading `true`
        // immediately after this call returns, not after a KVO round trip.
        refreshPlaybackMirrors()
    }

    public func pause() {
        guard grade == .current else {
            rejectCall(.pause)
            return
        }
        desiresPlayback = false
        // Retires a `capturePlaying` from `willResignActive`, if one is
        // outstanding. Only `.continueAudioOnly` can reach this while
        // backgrounded — it's the only policy that leaves playback running
        // there, so it's the only one where an explicit `pause()` (lock
        // screen, Now Playing, Controls) can contradict the capture.
        // Without this, `willEnterForeground`'s `.resumePlay` — gated only
        // on that stale flag — would override the user's pause on return.
        // The machine's own `.pause` action and interruption/route-change
        // handling call `target.pause()` directly rather than through this
        // method, so they don't touch the capture and stay unaffected.
        wasPlayingBeforeBackground = false
        target.pause()
        refreshPlaybackMirrors()
    }

    /// Changes the desired rate without starting paused playback.
    public func setRate(_ rate: Float) {
        configuration.playbackRate = ABPlaybackRate.clamped(rate)
    }

    /// Performs the precise seek behavior provided in v0.1.
    public func seek(to time: CMTime) async {
        await seek(to: time, tolerance: .precise)
    }

    /// Seeks with explicit tolerances when this player is current. The
    /// destination is clamped to `0...duration` (when duration is known and
    /// finite) — a change from v0.1, which forwarded whatever time was
    /// given as-is.
    public func seek(to time: CMTime, tolerance: ABSeekTolerance) async {
        guard grade == .current else {
            rejectCall(.seek)
            return
        }
        let generation = seekGeneration
        enqueueSeek(to: time, tolerance: tolerance)
        await awaitSeekSettled(generation: generation)
    }

    /// Moves relative to the current time, clamped to the playable range.
    /// Accumulates against ``pendingSeekTime`` rather than the live
    /// `currentTime` when a prior skip hasn't settled yet, so consecutive
    /// taps add up instead of each landing relative to a `currentTime` that
    /// hasn't moved yet.
    public func skip(by interval: TimeInterval) async {
        guard grade == .current else {
            rejectCall(.skip)
            return
        }
        let base = pendingSeekTime ?? currentTime
        let baseSeconds = base.isNumeric ? CMTimeGetSeconds(base) : 0
        let proposedSeconds = max(0, baseSeconds + (interval.isFinite ? interval : 0))
        let destination = CMTime(
            seconds: proposedSeconds,
            preferredTimescale: base.timescale > 0 ? base.timescale : 600
        )
        if isScrubbing {
            // Fire-and-forget, deliberately not awaited — a skip tapped
            // while scrubbing shares the seek coalescer with `scrub(to:)`
            // and must not block on settlement (a scrubbing session's own
            // rapid `scrub(to:)` calls never await either).
            scrub(to: destination)
            return
        }
        let generation = seekGeneration
        enqueueSeek(to: destination, tolerance: .precise)
        await awaitSeekSettled(generation: generation)
    }

    // MARK: - Scrubbing

    /// Starts a coalesced interactive seek session.
    public func beginScrubbing() {
        guard grade == .current else {
            rejectCall(.beginScrubbing)
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
            rejectCall(.scrub)
            return
        }
        guard isScrubbing else {
            // Routed through the shared seek coalescer/generation guard
            // (like every other non-scrubbing-session entry point) rather
            // than a per-call `Task` — rapid out-of-session taps now
            // coalesce instead of each issuing its own unbounded seek.
            enqueueSeek(to: time, tolerance: configuration.scrubTolerance)
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
            let generation = seekGeneration
            let landed = await target.seek(to: lastScrubTime, tolerance: .precise)
            if generation == seekGeneration {
                broadcast(.seekCompleted(to: landed))
            }
        } else if grade != .current {
            rejectCall(.endScrubbing)
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
        observerRegistry.add { [weak self, weak observer] event in
            guard let self else { return }
            observer?.player(self, didEmit: event)
        }
    }

    public func addObserver(
        _ handler: @escaping @MainActor @Sendable (ABPlayerEvent) -> Void
    ) -> ABObservationToken {
        observerRegistry.add(handler)
    }

    func addLayerAttachmentObserver(
        _ handler: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> ABObservationToken {
        layerAttachmentObserverRegistry.add(handler)
    }

    // MARK: - Internal (used by ABPictureInPictureSession)

    /// Notified by a bound `ABPictureInPictureSession` when Picture in
    /// Picture starts or stops. Starting repairs a layer left detached or
    /// playback left paused by a background policy that ran before PiP's
    /// own activation KVO landed — the platform does not guarantee which of
    /// the two lands first. No repair is attempted below `.current`:
    /// without an item there's nothing PiP could have started against.
    func setPictureInPictureActive(_ active: Bool) {
        guard isPictureInPictureActive != active else { return }
        isPictureInPictureActive = active
        guard active, grade == .current else { return }
        if !isLayerAttachmentEnabled {
            setLayerAttachmentEnabled(true)
        }
        if wasPlayingBeforeBackground, !isPlaying {
            play()
        }
        wasPlayingBeforeBackground = false
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
            refreshPlaybackMirrors()
        case .playbackStalled:
            isStallOutstanding = true
            broadcast(.playbackStalled)
            refreshPlaybackMirrors()
        case .playedToEnd:
            desiresPlayback = false
            broadcast(.playedToEnd)
            refreshPlaybackMirrors()
        case .timeControlStatusChanged(let status):
            broadcast(.timeControlStatusChanged(status))
            refreshPlaybackMirrors()
            if isStallOutstanding, status == .playing {
                isStallOutstanding = false
                broadcast(.stallEnded)
            }
        case .failed(let failure):
            routeFailure(failure)
        case .bufferStateChanged:
            refreshPlaybackMirrors()
        case .durationChanged:
            refreshPlaybackMirrors()
        case .presentationSizeChanged(let size):
            guard size != .zero, size != lastBroadcastPresentationSize else { return }
            lastBroadcastPresentationSize = size
            broadcast(.presentationSizeChanged(size))
        }
    }

    /// Re-reads the target's raw signals and updates the three
    /// recompute-from-target mirrors, broadcasting only what actually
    /// changed — `@Observable` re-fires `withMutation` even for an
    /// identical-value re-assignment, which would otherwise invalidate
    /// SwiftUI on every trigger regardless of whether anything moved.
    /// Assignment always precedes its broadcast, so a re-entrant handler
    /// reading the mirror mid-broadcast sees the already-settled value.
    private func refreshPlaybackMirrors() {
        let newIsPlaying = target.isPlaying
        if newIsPlaying != isPlaying {
            isPlaying = newIsPlaying
        }

        let newDuration = target.duration
        if newDuration != duration {
            duration = newDuration
        }
        if let newDuration, newDuration.isNumeric {
            let seconds = CMTimeGetSeconds(newDuration)
            if seconds.isFinite, seconds > 0, newDuration != lastBroadcastFiniteDuration {
                lastBroadcastFiniteDuration = newDuration
                broadcast(.durationAvailable(newDuration))
            }
        }

        let newIsBuffering = ABBufferingEvaluator.isBuffering(ABBufferingSignals(
            hasItem: avPlayerItem != nil,
            intendsToPlay: desiresPlayback,
            timeControlStatus: target.timeControlStatus,
            isWaitingWithNoItem: target.isWaitingWithNoItem,
            isPlaybackLikelyToKeepUp: target.isPlaybackLikelyToKeepUp,
            isPlaybackBufferEmpty: target.isPlaybackBufferEmpty
        ))
        if newIsBuffering != isBuffering {
            isBuffering = newIsBuffering
            broadcast(.bufferingChanged(newIsBuffering))
        }
    }

    /// Routes a failure to ``lastFailure`` or ``lastDiagnostic`` by
    /// `isTerminal`, then broadcasts both the legacy `.failed` channel and
    /// `.failureReported` from the same site — additive-only means neither
    /// channel can be dropped in favor of the other this round.
    private func routeFailure(_ failure: ABPlayerFailure) {
        if failure.isTerminal {
            lastFailure = failure
        } else {
            lastDiagnostic = failure
        }
        broadcast(.failed(failure.kind))
        broadcast(.failureReported(failure))
    }

    private func interpret(_ actions: [ABGradeAction], source: ABMediaSource?, detachReason: ABDetachReason) {
        for action in actions {
            switch action {
            case .createPlayer:
                target.makePlayer()
                target.applyExternalPlayback(externalPlaybackSettings)

            case .cancelPreload:
                cancelPreload()

            case .pause:
                desiresPlayback = false
                target.pause()
                refreshPlaybackMirrors()

            case .applyTuning(let role):
                lastAppliedTuningRole = role
                if target.applyTuning(resolvedTuning(for: role)) {
                    broadcast(.tuningApplied(role, tuning(for: role)))
                }

            case .attachItem(let attachedSource):
                reportedFirstFrameItem = nil
                hasDisplayedFirstFrame = false
                lastFailure = nil
                lastDiagnostic = nil
                target.attachItem(
                    attachedSource,
                    tuning: resolvedTuning(for: lastAppliedTuningRole),
                    assetFactory: configuration.assetFactory
                )
                // Before `.tuningApplied`, same action — consumers can rely
                // on an attached item always being announced before its
                // tuning.
                broadcast(.itemAttached(source: attachedSource))
                broadcast(.tuningApplied(lastAppliedTuningRole, tuning(for: lastAppliedTuningRole)))
                target.setMuted(configuration.isMuted)
                target.setLooping(configuration.isLooping)
                target.setRate(configuration.playbackRate)

            case .detachItem:
                lastFailure = nil
                lastDiagnostic = nil
                reportedFirstFrameItem = nil
                hasDisplayedFirstFrame = false
                isStallOutstanding = false
                lastBroadcastFiniteDuration = nil
                lastBroadcastPresentationSize = nil
                // Detach before broadcasting: `.itemDetached` observers
                // (e.g. `ABPlayerView`) read `player.avPlayerItem` to decide
                // whether to rebind — it must already be `nil` by the time
                // they see the event, not still pointing at the item that's
                // about to be torn down.
                target.detachItem()
                broadcast(.itemDetached(reason: detachReason))
                refreshPlaybackMirrors()

            case .armPreroll:
                if let rate = configuration.prerollRate {
                    armPreroll(rate: rate)
                }

            case .seekToStart:
                // Routed through the same seek gate every other seek uses
                // (rather than a bare `target.seekToStart()` `Task`), so a
                // `rewindOnDemotion` rewind now broadcasts `.seekCompleted`
                // like any other seek instead of silently landing.
                enqueueSeek(to: .zero, tolerance: .precise)

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

    private var externalPlaybackSettings: ABExternalPlaybackSettings {
        ABExternalPlaybackSettings(
            allowsExternalPlayback: configuration.allowsExternalPlayback,
            usesExternalPlaybackWhileExternalScreenIsActive: configuration.usesExternalPlaybackWhileExternalScreenIsActive,
            externalPlaybackVideoGravity: configuration.externalPlaybackVideoGravity
        )
    }

    /// The tuning actually handed to `target` — `displaySizeSentinel`
    /// resolved against `displaySize` (`ABPlayerView`'s reported pixel
    /// size, or `.zero`/no cap while no view is attached). `.tuningApplied`
    /// keeps broadcasting the unresolved `tuning(for:)` value, matching its
    /// existing meaning as "which preset was requested" rather than the
    /// resolved pixel cap.
    private func resolvedTuning(for role: ABTuningRole) -> ABPlaybackTuning {
        tuning(for: role).resolved(displaySize: displaySize)
    }

    /// Called by `ABPlayerView.layoutSubviews()` with its pixel size
    /// (`bounds.size × traitCollection.displayScale`). Re-applies tuning
    /// only when the size actually changed, so repeated identical layout
    /// passes don't loop. `.zero` (no view attached) resolves
    /// `displaySizeSentinel` to "no cap" — a feed cell's correct cap is the
    /// cell's own size, never the device screen's.
    func reportDisplaySize(_ size: CGSize) {
        guard displaySize != size else { return }
        displaySize = size
        guard grade.holdsItem else { return }
        let role: ABTuningRole = grade == .current ? .current : .preload
        lastAppliedTuningRole = role
        if target.applyTuning(resolvedTuning(for: role)) {
            broadcast(.tuningApplied(role, tuning(for: role)))
        }
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
                self?.routeFailure(ABPlayerFailure(kind: error))
                self?.broadcast(.prerollCompleted(success: false))
            case .failed:
                let error = ABPlayerError.prerollFailed
                self?.routeFailure(ABPlayerFailure(kind: error))
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
            if previousConfiguration.backgroundPolicy.detachesLayerInBackground,
               !configuration.backgroundPolicy.detachesLayerInBackground {
                setLayerAttachmentEnabled(true)
            }
            reconcileBackgroundObserver()
        }
        if previousConfiguration.isMuted != configuration.isMuted {
            target.setMuted(configuration.isMuted)
            broadcast(.mutedChanged(configuration.isMuted))
        }
        if previousConfiguration.isLooping != configuration.isLooping {
            target.setLooping(configuration.isLooping)
        }
        if previousConfiguration.allowsExternalPlayback != configuration.allowsExternalPlayback
            || previousConfiguration.usesExternalPlaybackWhileExternalScreenIsActive != configuration.usesExternalPlaybackWhileExternalScreenIsActive
            || previousConfiguration.externalPlaybackVideoGravity != configuration.externalPlaybackVideoGravity {
            target.applyExternalPlayback(externalPlaybackSettings)
        }
        if ABPlaybackRate.clamped(previousConfiguration.playbackRate) != configuration.playbackRate {
            target.setRate(configuration.playbackRate)
            broadcast(.rateChanged(configuration.playbackRate))
            refreshPlaybackMirrors()
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
            || previousConfiguration.pausesOnRouteChangeDeviceUnavailable != configuration.pausesOnRouteChangeDeviceUnavailable
            || previousConfiguration.audioSessionPolicy != configuration.audioSessionPolicy {
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
        // role, not an OR of both: with an OR, changing `preloadTuning`
        // alone while `.current` would pass the guard despite
        // `currentTuning` being unchanged, re-applying the identical
        // tuning and broadcasting a spurious
        // `.tuningApplied(.current, sameValue)`.
        let role: ABTuningRole = grade == .current ? .current : .preload
        let previousRoleTuning = role == .preload
            ? previousConfiguration.preloadTuning
            : previousConfiguration.currentTuning
        guard previousRoleTuning != tuning(for: role) else { return }
        lastAppliedTuningRole = role
        if target.applyTuning(resolvedTuning(for: role)) {
            broadcast(.tuningApplied(role, tuning(for: role)))
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
            onWillResignActive: { [weak self] in self?.handleWillResignActive() },
            onBackground: { [weak self] in self?.handleDidEnterBackground() },
            onForeground: { [weak self] in self?.handleWillEnterForeground() }
        )
    }

    /// `willResignActive` always precedes `didEnterBackground` — capturing
    /// `isPlaying` here (rather than in `handleDidEnterBackground`) is what
    /// makes the capture reliable: by the time `didEnterBackground` fires,
    /// iOS may already have stopped decode, so `isPlaying` would often read
    /// `false` there even for playback that was genuinely still active a
    /// moment earlier. The actual pause/detach/demote side effects stay in
    /// `handleDidEnterBackground` — a resign that gets cancelled (e.g. a
    /// system alert dismissed without truly backgrounding) must not stop
    /// playback, only overwrite the capture for whenever backgrounding does
    /// happen.
    private func handleWillResignActive() {
        interpretBackgroundActions(backgroundPolicyMachine.actions(
            for: .willResignActive,
            policy: configuration.backgroundPolicy,
            grade: grade,
            wasPlayingBeforeBackground: wasPlayingBeforeBackground,
            hasCapturedGrade: gradeBeforeBackground != nil,
            isPictureInPictureActive: isPictureInPictureActive
        ))
    }

    private func handleDidEnterBackground() {
        interpretBackgroundActions(backgroundPolicyMachine.actions(
            for: .didEnterBackground,
            policy: configuration.backgroundPolicy,
            grade: grade,
            wasPlayingBeforeBackground: wasPlayingBeforeBackground,
            hasCapturedGrade: gradeBeforeBackground != nil,
            isPictureInPictureActive: isPictureInPictureActive
        ))
    }

    private func handleWillEnterForeground() {
        interpretBackgroundActions(backgroundPolicyMachine.actions(
            for: .willEnterForeground,
            policy: configuration.backgroundPolicy,
            grade: grade,
            wasPlayingBeforeBackground: wasPlayingBeforeBackground,
            hasCapturedGrade: gradeBeforeBackground != nil,
            isPictureInPictureActive: isPictureInPictureActive
        ))
    }

    private func interpretBackgroundActions(_ actions: [ABBackgroundAction]) {
        for action in actions {
            switch action {
            case .capturePlaying:
                // Reads the target directly, not the `isPlaying` mirror —
                // this must be the live, authoritative value at the exact
                // capture instant, not whatever the mirror last settled to.
                wasPlayingBeforeBackground = target.isPlaying
            case .pause:
                desiresPlayback = false
                target.pause()
                refreshPlaybackMirrors()
            case .setLayerAttachment(let enabled):
                setLayerAttachmentEnabled(enabled)
            case .demoteToInstance:
                gradeBeforeBackground = grade
                if grade.holdsItem {
                    set(source: source, grade: .instanceOnly, detachReason: .backgroundPolicy)
                }
            case .restoreCapturedGrade:
                if let restoredGrade = gradeBeforeBackground {
                    promote(to: restoredGrade)
                }
                gradeBeforeBackground = nil
            case .resumePlay:
                // Routed through `self.play()` (not a direct `target.play()`
                // call) so a foreground resume also reactivates the audio
                // session via `applyAudioSessionPolicyIfNeeded` — the fix
                // for the bypass a direct target call used to cause.
                play()
            case .markAudioSessionDirty:
                audioSessionActivationDirty = true
            case .clearCapture:
                wasPlayingBeforeBackground = false
            }
        }
    }

    private func broadcast(_ event: ABPlayerEvent) {
        observerRegistry.broadcast(event)
    }

    /// Broadcasts the legacy `.playbackRejected` signal together with
    /// `.callRejected`, which identifies which call and grade caused the
    /// rejection — the "why did nothing happen" gap `.playbackRejected`
    /// alone left a first-time consumer to guess at.
    private func rejectCall(_ call: ABRejectedCall) {
        broadcast(.playbackRejected)
        broadcast(.callRejected(call, grade: grade))
    }

    // MARK: - Audio interruption / route change

    private func reconcileInterruptionObserver() {
        // Also installed whenever this instance actively manages the audio
        // session (`audioSessionPolicy != .unmanaged`), independent of
        // `interruptionPolicy`/`pausesOnRouteChangeDeviceUnavailable` — even
        // with both of those at their do-nothing settings, this instance
        // still needs `handleInterruptionBegan` to fire so it can re-dirty
        // `audioSessionActivationDirty` when iOS deactivates the session out
        // from under it (the callbacks this observer drives besides that
        // re-dirtying — pause-on-interruption, pause-on-route-change — stay
        // correctly gated by their own policy checks inside
        // `handleInterruptionEnded`/`handleRouteChangeDeviceUnavailable`).
        guard configuration.interruptionPolicy != .ignore
            || configuration.pausesOnRouteChangeDeviceUnavailable
            || configuration.audioSessionPolicy != .unmanaged else {
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
        // iOS deactivates the audio session for the duration of the
        // interruption regardless of `interruptionPolicy` — the next
        // `play()` (from `handleInterruptionEnded`'s resume, or a manual
        // one) must reactivate it rather than being skipped by the
        // dirty-flag optimization above. This is a fact about *session
        // state*, not about whether to pause/resume playback, so it must
        // not be gated by the policy guard below. If the dirty flag were set
        // after that guard, the default `.ignore` policy would break: the
        // observer still fires and deactivation still happens, but nothing
        // would record it, so a later `play()`'s `force: false` optimization
        // would skip reactivation and leave playback silently muted.
        audioSessionActivationDirty = true
        guard configuration.interruptionPolicy != .ignore else { return }
        // Reads the target directly (not the `isPlaying` mirror) for the
        // same reason `ABBackgroundPolicyMachine`'s `.capturePlaying`
        // capture does — this needs the live value at this exact instant.
        wasPlayingBeforeInterruption = target.isPlaying
        if grade == .current {
            desiresPlayback = false
            target.pause()
            refreshPlaybackMirrors()
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
            // `applyAudioSessionPolicyIfNeeded()` → `audioSessionCoordinator`,
            // which always reactivates rather than memoizing, so an
            // interruption that deactivated the session ends with it
            // correctly reactivated rather than silently staying inactive.
            play()
        }
        broadcast(.audioInterruptionEnded(resumed: resumes))
    }

    private func handleRouteChangeDeviceUnavailable() {
        guard configuration.pausesOnRouteChangeDeviceUnavailable, grade == .current else { return }
        desiresPlayback = false
        target.pause()
        refreshPlaybackMirrors()
        broadcast(.audioRouteChangedDeviceUnavailable)
    }

    // MARK: - Audio session

    /// Applies `configuration.audioSessionPolicy` through
    /// `audioSessionCoordinator` if it isn't `.unmanaged`. No-op while not
    /// `.current` — callers gate this at grade `.current` promotion and
    /// `play()` (playback start).
    ///
    /// `force: true` (the default — used by grade promotion and by an
    /// explicit `audioSessionPolicy` switch) always (re)activates, never
    /// memoized on "already applied", so a promotion after an interruption
    /// reactivates the session instead of silently staying inactive.
    /// `force: false` (used only by `play()`) additionally requires
    /// `audioSessionActivationDirty`, so a `play()` that immediately
    /// follows an already-successful apply is a no-op instead of a
    /// redundant IPC — reactivation is still guaranteed for the case this
    /// dirty-flag gating exists to protect, because
    /// `handleInterruptionBegan`/`handleWillEnterForeground` re-dirty the
    /// flag at the two points the session might actually have gone
    /// inactive out from under this instance.
    ///
    /// The coordinator itself snapshots the host's prior category/mode/
    /// options exactly once, before its *first* participant's apply, and
    /// keeps that snapshot across a failed activate or additional
    /// participants.
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
    /// switching back to `.unmanaged` and at `release()`. A no-op
    /// if this instance never participated, and only actually restores the
    /// host's snapshot once every other participating player has also left
    /// — so this is safe to call unconditionally from either trigger.
    private func restoreAudioSessionPolicyIfNeeded() {
        if case .failure(let error)? = audioSessionCoordinator.leave(audioSessionToken) {
            surfaceAudioSessionFailure(error)
        }
    }

    /// Apply/restore failures are never swallowed — surface
    /// them the same way every other asynchronous failure in this type is
    /// surfaced.
    private func surfaceAudioSessionFailure(_ error: Error) {
        let nsError = error as NSError
        let policyError = ABPlayerError.audioSessionOperationFailed(
            description: nsError.localizedDescription
        )
        let origin = ABErrorOrigin(domain: nsError.domain, code: nsError.code)
        routeFailure(ABPlayerFailure(kind: policyError, origin: origin))
    }

    /// The single gate every seek entry point (`seek(to:)`, non-scrubbing
    /// `skip(by:)`, out-of-session `scrub(to:)`, the planner's
    /// `.seekToStart`) funnels through. Does not check `grade` — callers
    /// already broadcast their own rejection and return before reaching
    /// this, and a planner-originated seek (`.seekToStart`) is called
    /// mid-grade-transition, before `grade` has necessarily settled.
    /// Because the existing seek worker (`runSeekWorker`) already carries
    /// the generation guard, every entry point that funnels through here
    /// automatically gets stale-seek protection for free.
    @discardableResult
    private func enqueueSeek(to time: CMTime, tolerance: ABSeekTolerance) -> Bool {
        let destination = clampToPlayableRange(time)
        if !isScrubbing, pendingSeekTime != destination {
            pendingSeekTime = destination
            broadcast(.seekTargetChanged(destination))
        }
        let decision = seekCoalescer.request(destination, tolerance: tolerance)
        startSeekWorker(for: decision)
        if case .issue = decision { return true }
        return false
    }

    /// Clamps to `0...duration` when duration is known and finite —
    /// otherwise only the lower bound applies (matches `skip(by:)`'s
    /// pre-existing "no upper clamp while live" behavior).
    private func clampToPlayableRange(_ time: CMTime) -> CMTime {
        var result = time.isNumeric ? time : .zero
        if result.seconds < 0 {
            result = .zero
        }
        if let duration, duration.isNumeric {
            let durationSeconds = CMTimeGetSeconds(duration)
            if durationSeconds.isFinite, durationSeconds >= 0, result.seconds > durationSeconds {
                result = duration
            }
        }
        return result
    }

    /// Waits for the seek worker outstanding at `generation` (captured by
    /// the caller *before* calling `enqueueSeek`) to fully settle —
    /// including any further requests it coalesces in along the way.
    /// Returns immediately if `generation` is already stale (a grade
    /// transition reset seeking while this call was suspended elsewhere).
    private func awaitSeekSettled(generation: Int) async {
        guard generation == seekGeneration, let seekWorkerTask else { return }
        await seekWorkerTask.value
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
        guard generation == seekGeneration,
              !isScrubbing,
              pendingSeekTime != nil,
              seekCoalescer.inFlight == nil,
              seekCoalescer.pending == nil else { return }
        pendingSeekTime = nil
        broadcast(.seekTargetChanged(nil))
    }

    private func resetSeeking() {
        seekGeneration += 1
        seekWorkerTask?.cancel()
        seekWorkerTask = nil
        seekCoalescer.reset()
        lastScrubTime = nil
        if pendingSeekTime != nil {
            pendingSeekTime = nil
            broadcast(.seekTargetChanged(nil))
        }
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
