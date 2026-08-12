import ABPlayerKit
import ABPlayerKitCache
import ABPlayerKitMetrics
import AVFoundation
import Foundation
import Observation

enum DemoMedia: String, CaseIterable, Identifiable {
    case hls = "Apple HLS"
    case mp4 = "Sample MP4"

    var id: Self { self }

    var source: ABMediaSource {
        switch self {
        case .hls:
            ABMediaSource(
                url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!,
                kind: .hls
            )
        case .mp4:
            ABMediaSource(
                url: URL(string: "https://media.w3.org/2010/05/sintel/trailer.mp4")!,
                kind: .progressive
            )
        }
    }
}

enum DemoTuningPreset: String, CaseIterable, Identifiable {
    case conservativePreload
    case displayCapped
    case unrestricted

    var id: Self { self }

    var title: String {
        switch self {
        case .conservativePreload: "Conservative"
        case .displayCapped: "Display capped"
        case .unrestricted: "Unrestricted"
        }
    }

    var tuning: ABPlaybackTuning {
        switch self {
        case .conservativePreload: .conservativePreload
        case .displayCapped: .displayCapped
        case .unrestricted: .unrestricted
        }
    }
}

enum HLSPrefetchState: Equatable {
    case idle
    case downloading
    case available
    case cancelled
    case failed

    var title: String {
        switch self {
        case .idle: "Not downloaded"
        case .downloading: "Downloading…"
        case .available: "Available offline"
        case .cancelled: "Cancelled"
        case .failed: "Download failed"
        }
    }
}

private final class HLSPrefetchLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: ABHLSPrefetchHandle?
    private var resultTask: Task<Void, Never>?

    func replace(handle: ABHLSPrefetchHandle, resultTask: Task<Void, Never>) {
        lock.lock()
        let previousHandle = self.handle
        let previousTask = self.resultTask
        self.handle = handle
        self.resultTask = resultTask
        lock.unlock()
        previousTask?.cancel()
        previousHandle?.cancel()
    }

    func clear(ifMatching handle: ABHLSPrefetchHandle) {
        lock.lock()
        if self.handle == handle {
            self.handle = nil
            resultTask = nil
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let handle = self.handle
        let resultTask = self.resultTask
        self.handle = nil
        self.resultTask = nil
        lock.unlock()
        resultTask?.cancel()
        handle?.cancel()
    }

    deinit {
        cancel()
    }
}

@MainActor
@Observable
final class DemoModel {
    private enum AssetFactoryMode {
        case standard
        case cached
    }

    /// `@Observable` (round3 Phase3 WP9) — views read `player.grade` and
    /// other tracked state directly (see `PlaybackScreen`'s `gradeBinding`)
    /// instead of this model mirroring it into its own `var`. `latestEvent`
    /// and other derived UI text still come from the token-based
    /// `addObserver` event stream below, since those need the *event*, not
    /// just the resulting state.
    let player: ABPlayer

    private let clock = ABMonotonicClock()
    private let metricsSink: ABInMemoryMetricsSink
    private let metricsRecorder: ABMetricsRecorder
    private let mediaCache: ABMediaCache?
    private let hlsPrefetcher: ABHLSPrefetcher
    private let defaultAssetFactory: any ABAssetFactory
    private let cacheAssetFactory: (any ABAssetFactory)?
    private let prefetchLifetime = HLSPrefetchLifetime()
    private var metricsToken: ABObservationToken?
    private var eventToken: ABObservationToken?
    private var installedFactoryMode = AssetFactoryMode.standard
    private var usesPrefetchedHLS = false

    var selectedMedia = DemoMedia.hls
    var selectedTuning = DemoTuningPreset.displayCapped
    var isMuted = false
    var isLooping = false
    var isPlaying = false
    var statistics = ABPlaybackStatistics.aggregate([])
    var latestEvent = "Waiting for playback events"
    var cacheSize: Int64 = 0
    var cacheEnabled = false
    var prefetchState = HLSPrefetchState.idle
    var cacheError: String?

    init() {
        let player = ABPlayer()
        let metricsSink = ABInMemoryMetricsSink()
        let metricsRecorder = ABMetricsRecorder(sink: metricsSink)
        let hlsPrefetcher = ABHLSPrefetcher()
        let defaultAssetFactory = ABDefaultAssetFactory()
        let mediaCache: ABMediaCache?
        let cacheError: String?

        do {
            mediaCache = try ABMediaCache()
            cacheError = nil
        } catch {
            mediaCache = nil
            cacheError = error.localizedDescription
        }

        self.player = player
        self.metricsSink = metricsSink
        self.metricsRecorder = metricsRecorder
        self.mediaCache = mediaCache
        self.hlsPrefetcher = hlsPrefetcher
        self.defaultAssetFactory = defaultAssetFactory
        self.cacheAssetFactory = mediaCache?.makeAssetFactory(hlsPrefetcher: hlsPrefetcher)
        self.cacheError = cacheError

        metricsToken = metricsRecorder.attach(to: player)
        eventToken = player.addObserver { [weak self] event in
            guard let self else { return }
            self.handle(event)
        }

        player.set(source: selectedMedia.source, grade: .preloaded)

        if hlsPrefetcher.localAsset(for: DemoMedia.hls.source) != nil {
            prefetchState = .available
        }
    }

    deinit {
        prefetchLifetime.cancel()
    }

    var cacheSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    var cacheIsAvailable: Bool {
        mediaCache != nil
    }

    func selectMedia(_ media: DemoMedia) {
        let startedAt = clock.now
        guard media != selectedMedia || usesPrefetchedHLS else { return }
        abandonPendingTTFF()
        selectedMedia = media
        usesPrefetchedHLS = false
        transitionToSelectedSource(startedAt: startedAt)
    }

    func setGrade(_ newGrade: ABPlaybackGrade) {
        let startedAt = clock.now
        transitionGrade(to: newGrade, startedAt: startedAt)
    }

    func armPreroll() {
        guard player.grade == .preloaded else { return }
        latestEvent = "Preroll armed"
        player.startPreroll()
    }

    func cancelPreload() {
        guard player.grade == .preloaded else { return }
        player.cancelPreload()
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        player.setMuted(muted)
    }

    func setLooping(_ looping: Bool) {
        guard looping != isLooping else { return }
        isLooping = looping
        var configuration = player.configuration
        guard configuration.isLooping != looping else { return }
        configuration.isLooping = looping
        player.configuration = configuration
    }

    func setTuning(_ preset: DemoTuningPreset) {
        selectedTuning = preset
        var configuration = player.configuration
        let preloadTuning = ABPlaybackTuning.conservativePreload
        guard configuration.preloadTuning != preloadTuning
                || configuration.currentTuning != preset.tuning
        else { return }
        configuration.preloadTuning = preloadTuning
        configuration.currentTuning = preset.tuning
        player.configuration = configuration
    }

    func togglePlayback() {
        let startedAt = clock.now
        guard player.grade == .current else {
            transitionGrade(to: .current, startedAt: startedAt)
            return
        }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func setCacheEnabled(_ enabled: Bool) {
        let startedAt = clock.now
        guard mediaCache != nil, enabled != cacheEnabled else { return }
        cacheEnabled = enabled
        guard selectedMedia == .mp4 else { return }
        reloadCurrentSource(startedAt: startedAt)
    }

    func replayMP4() {
        let startedAt = clock.now
        guard mediaCache != nil else { return }
        cacheEnabled = true
        selectedMedia = .mp4
        usesPrefetchedHLS = false
        reloadCurrentSource(startedAt: startedAt, forceCurrent: true)
    }

    func removeAllCachedMedia() async {
        guard let mediaCache else { return }
        await mediaCache.removeAll()
        await refreshCacheSize()
    }

    func monitorCacheSize() async {
        while !Task.isCancelled {
            await refreshCacheSize()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func startHLSPrefetch() {
        prefetchState = .downloading
        let handle = hlsPrefetcher.prefetch(DemoMedia.hls.source)
        let resultTask = Task { [weak self] in
            await Task.yield()
            let result = await handle.result
            guard !Task.isCancelled, let self else { return }
            self.prefetchLifetime.clear(ifMatching: handle)
            switch result {
            case .completed:
                self.prefetchState = self.hlsPrefetcher.localAsset(for: DemoMedia.hls.source) == nil
                    ? .failed
                    : .available
            case .cancelled:
                self.prefetchState = .cancelled
            case .failed:
                self.prefetchState = .failed
            }
        }
        prefetchLifetime.replace(handle: handle, resultTask: resultTask)
    }

    func cancelHLSPrefetch() {
        prefetchLifetime.cancel()
        prefetchState = .cancelled
    }

    func playPrefetchedHLS() {
        let startedAt = clock.now
        guard cacheAssetFactory != nil,
              hlsPrefetcher.localAsset(for: DemoMedia.hls.source) != nil
        else { return }
        selectedMedia = .hls
        usesPrefetchedHLS = true
        reloadCurrentSource(startedAt: startedAt, forceCurrent: true)
    }

    private func transitionGrade(to newGrade: ABPlaybackGrade, startedAt: CFTimeInterval) {
        guard newGrade != player.grade else { return }
        if player.grade == .current {
            abandonPendingTTFF()
        }
        let source = newGrade == .released ? nil : selectedMedia.source
        player.set(source: source, grade: newGrade)
        resumeCurrentPlaybackIfNeeded(startedAt: startedAt)
    }

    private func transitionToSelectedSource(startedAt: CFTimeInterval) {
        // Captured before the possible `player.release()` below, which
        // would otherwise clobber `player.grade` to `.released` before this
        // function gets a chance to read the actual target grade.
        let targetGrade = player.grade
        let desiredFactoryMode = desiredFactoryModeForSelection
        if desiredFactoryMode != installedFactoryMode {
            player.release()
            installAssetFactory(desiredFactoryMode)
        }
        guard targetGrade != .released else { return }
        player.set(source: selectedMedia.source, grade: targetGrade)
        resumeCurrentPlaybackIfNeeded(startedAt: startedAt)
    }

    private func reloadCurrentSource(
        startedAt: CFTimeInterval,
        forceCurrent: Bool = false
    ) {
        // Same ordering note as `transitionToSelectedSource` above.
        let targetGrade = forceCurrent ? ABPlaybackGrade.current : player.grade
        abandonPendingTTFF()
        player.release()
        installAssetFactory(desiredFactoryModeForSelection)
        guard targetGrade != .released else { return }
        player.set(source: selectedMedia.source, grade: targetGrade)
        resumeCurrentPlaybackIfNeeded(startedAt: startedAt)
    }

    private var desiredFactoryModeForSelection: AssetFactoryMode {
        guard cacheAssetFactory != nil else { return .standard }
        if usesPrefetchedHLS || (selectedMedia == .mp4 && cacheEnabled) {
            return .cached
        }
        return .standard
    }

    private func installAssetFactory(_ mode: AssetFactoryMode) {
        guard mode != installedFactoryMode else { return }
        precondition(!player.grade.holdsItem)
        var configuration = player.configuration
        switch mode {
        case .standard:
            configuration.assetFactory = defaultAssetFactory
        case .cached:
            guard let cacheAssetFactory else { return }
            configuration.assetFactory = cacheAssetFactory
        }
        player.configuration = configuration
        installedFactoryMode = mode
    }

    private func resumeCurrentPlaybackIfNeeded(startedAt: CFTimeInterval) {
        guard player.grade == .current else { return }
        metricsRecorder.beginTTFF(
            for: player,
            at: startedAt,
            resumedFromTime: nil
        )
        player.play()
    }

    private func abandonPendingTTFF() {
        metricsRecorder.abandonTTFF(for: player)
    }

    private func refreshCacheSize() async {
        cacheSize = await mediaCache?.totalSize() ?? 0
    }

    private func handle(_ event: ABPlayerEvent) {
        latestEvent = event.title
        switch event {
        case .timeControlStatusChanged(let status):
            isPlaying = status == .playing
        case .firstFrameDisplayed, .itemDetached:
            scheduleStatisticsRefresh()
        default:
            break
        }
    }

    private func scheduleStatisticsRefresh() {
        // Observer invocation order is unspecified, so let ABMetricsRecorder write first.
        Task { [weak self] in
            await Task.yield()
            self?.refreshStatistics()
        }
    }

    private func refreshStatistics() {
        let samples = metricsSink.events.compactMap { event -> ABMetricSample? in
            guard case .ttff(let sample) = event else { return nil }
            return sample
        }
        statistics = ABPlaybackStatistics.aggregate(samples)
    }
}

private extension ABPlayerEvent {
    var title: String {
        switch self {
        case .gradeChanged(let from, let to): "Grade: \(from.label) → \(to.label)"
        case .sourceChanged: "Source changed"
        case .itemStatusChanged(let status): "Item: \(String(describing: status))"
        case .firstFrameDisplayed: "First frame displayed"
        case .prerollCompleted(let success): "Preroll \(success ? "completed" : "failed")"
        case .preloadCancelled: "Preload cancelled"
        case .playbackStalled: "Playback stalled"
        case .playedToEnd: "Playback reached the end"
        case .timeControlStatusChanged(let status): "Playback: \(String(describing: status))"
        case .rateChanged(let rate): "Rate: \(String(format: "%g", rate))×"
        case .scrubbingChanged(let isScrubbing): isScrubbing ? "Scrubbing began" : "Scrubbing ended"
        case .seekCompleted(let time): "Seek: \(ABTimeFormatter.string(from: time))"
        case .periodicTime(let time): "Time: \(ABTimeFormatter.string(from: time.currentTime))"
        case .failed(let error): "Error: \(String(describing: error))"
        case .tuningApplied(let role, _): "Applied \(String(describing: role)) tuning"
        case .itemDetached(let reason): "Detached: \(String(describing: reason))"
        case .invalidGradeForSource: "Grade rejected for empty source"
        case .playbackRejected: "Playback command rejected"
        case .audioInterruptionBegan: "Audio interruption began"
        case .audioInterruptionEnded(let resumed): "Audio interruption ended (resumed: \(resumed))"
        case .audioRouteChangedDeviceUnavailable: "Audio route changed: device unavailable"
        // `default`, not `@unknown default`: this app is built from source
        // against this exact package version, so the compiler always knows
        // every case — `@unknown default` only suppresses the missing-case
        // warning for cases added in a *future* library version the app
        // wasn't rebuilt against. Newer event cases fall through here with
        // a generic label rather than being spelled out individually; a
        // richer demo of any one of them is out of scope for this fix.
        default: "Playback event"
        }
    }
}

extension ABPlaybackGrade {
    var label: String {
        switch self {
        case .released: "Released"
        case .instanceOnly: "Instance only"
        case .preloaded: "Preloaded"
        case .current: "Current"
        }
    }

    var shortLabel: String {
        switch self {
        case .released: "Released"
        case .instanceOnly: "Instance"
        case .preloaded: "Preload"
        case .current: "Current"
        }
    }
}
