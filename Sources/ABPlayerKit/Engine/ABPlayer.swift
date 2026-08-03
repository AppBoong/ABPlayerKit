@preconcurrency import AVFoundation
import Foundation

/// Owns a single playback grade, broadcasts its lifecycle as events, and
/// guarantees every release path passes through `replaceCurrentItem(nil)`.
/// See DESIGN-ABPlayerKit.md §5.3.
@MainActor
public final class ABPlayer {
    public let id = ABPlayerID()

    public var configuration: ABPlayerConfiguration {
        didSet { applyConfigurationChange() }
    }

    public private(set) var grade: ABPlaybackGrade = .released
    public private(set) var source: ABMediaSource?
    public private(set) var lastError: ABPlayerError?
    public private(set) var hasDisplayedFirstFrame = false

    /// Escape hatch — kept public for study purposes and consumer
    /// fallback (DESIGN-ABPlayerKit.md §1). Grade-related state must still
    /// go through `set(source:grade:)`/`promote(to:)`/`release()`.
    public var avPlayer: AVPlayer? { target.avPlayer }
    public var avPlayerItem: AVPlayerItem? { target.avPlayerItem }

    public var isPlaying: Bool { target.isPlaying }
    public var currentTime: CMTime { target.currentTime }
    public var duration: CMTime? { target.duration }

    private let target: any ABPlaybackTarget
    private let planner = ABGradePlanner()
    private let observerRegistry = ABObserverRegistry()
    private var lastAppliedTuningRole: ABTuningRole = .preload
    private var prerollTask: Task<Void, Never>?
    private var reportedFirstFrameItem: ObjectIdentifier?

    private var appStateObserver: ABApplicationStateObserver?
    private var gradeBeforeBackground: ABPlaybackGrade?
    private var wasPlayingBeforeBackground = false

    public init(configuration: ABPlayerConfiguration = .init()) {
        self.configuration = configuration
        self.target = ABAVPlaybackTarget()
        wireTarget()
        installBackgroundObserverIfNeeded()
    }

    /// Test-only entry point — lets `ABPlayerKitTests` substitute
    /// `ABFakePlaybackTarget` without exposing `ABPlaybackTarget` publicly.
    init(configuration: ABPlayerConfiguration = .init(), target: any ABPlaybackTarget) {
        self.configuration = configuration
        self.target = target
        wireTarget()
        installBackgroundObserverIfNeeded()
    }

    // MARK: - Grade

    /// The single entry point that mutates `(source, grade)`. Illegal
    /// combinations (`grade >= .preloaded && source == nil`) are clamped to
    /// `.instanceOnly` and reported via `.invalidGradeForSource` — never a
    /// throw or a crash.
    public func set(source newSource: ABMediaSource?, grade requestedGrade: ABPlaybackGrade) {
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

        let detachReason: ABDetachReason = resolvedGrade == .released
            ? .release
            : (resolvedGrade < previousGrade ? .demotion : .sourceChanged)

        source = newSource
        grade = resolvedGrade

        interpret(actions, source: newSource, detachReason: detachReason)

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
        target.play()
    }

    public func pause() {
        guard grade == .current else {
            broadcast(.playbackRejected)
            return
        }
        target.pause()
    }

    public func seek(to time: CMTime) async {
        guard grade == .current else {
            broadcast(.playbackRejected)
            return
        }
        await target.seek(to: time)
    }

    public func setMuted(_ muted: Bool) {
        target.setMuted(muted)
    }

    // MARK: - Preload control

    public func startPreroll() {
        guard grade == .preloaded, let rate = configuration.prerollRate else { return }
        armPreroll(rate: rate)
    }

    public func cancelPreload() {
        prerollTask?.cancel()
        prerollTask = nil
        broadcast(.preloadCancelled)
    }

    // MARK: - Observation

    public func addObserver(_ observer: some ABPlayerObserver) -> ABObservationToken {
        observerRegistry.add { [weak observer] player, event in
            observer?.player(player, didEmit: event)
        }
    }

    public func addObserver(_ handler: @escaping @MainActor (ABPlayerEvent) -> Void) -> ABObservationToken {
        observerRegistry.add { _, event in handler(event) }
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
                target.applyTuning(tuning)
                broadcast(.tuningApplied(role, tuning))

            case .attachItem(let attachedSource):
                reportedFirstFrameItem = nil
                hasDisplayedFirstFrame = false
                target.attachItem(
                    attachedSource,
                    tuning: tuning(for: lastAppliedTuningRole),
                    assetFactory: configuration.assetFactory
                )
                target.setMuted(configuration.isMuted)
                target.setLooping(configuration.isLooping)

            case .detachItem:
                target.detachItem()
                broadcast(.itemDetached(reason: detachReason))

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
            let success = await target.preroll(rate: rate, timeout: timeout)
            guard !Task.isCancelled else { return }
            self?.prerollTask = nil
            self?.broadcast(.prerollCompleted(success: success))
        }
    }

    private func applyConfigurationChange() {
        guard grade.holdsItem else { return }
        let role: ABTuningRole = grade == .current ? .current : .preload
        lastAppliedTuningRole = role
        let resolvedTuning = tuning(for: role)
        target.applyTuning(resolvedTuning)
        broadcast(.tuningApplied(role, resolvedTuning))
    }

    private func installBackgroundObserverIfNeeded() {
        guard configuration.backgroundPolicy != .ignore else { return }
        appStateObserver = ABApplicationStateObserver(
            onBackground: { [weak self] in self?.handleDidEnterBackground() },
            onForeground: { [weak self] in self?.handleWillEnterForeground() }
        )
    }

    /// `.pauseAndDetachLayer` is handled identically to `.pause` at the
    /// engine level (YAGNI for this phase): actually detaching
    /// `AVPlayerLayer.player` requires coordination with whichever
    /// `ABPlayerView` currently displays this player, which `ABPlayer`
    /// does not reference. A future phase can have `ABPlayerView` observe
    /// this policy directly if the decoder-release behavior proves
    /// necessary in practice.
    private func handleDidEnterBackground() {
        switch configuration.backgroundPolicy {
        case .ignore:
            return
        case .pause, .pauseAndDetachLayer:
            wasPlayingBeforeBackground = isPlaying
            if grade == .current {
                target.pause()
            }
        case .demoteToInstance:
            gradeBeforeBackground = grade
            if grade.holdsItem {
                promote(to: .instanceOnly)
            }
        }
    }

    private func handleWillEnterForeground() {
        switch configuration.backgroundPolicy {
        case .ignore:
            return
        case .pause, .pauseAndDetachLayer:
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
}
