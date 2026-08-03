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

    var title: String {
        switch self {
        case .idle: "Not downloaded"
        case .downloading: "Downloading…"
        case .available: "Available offline"
        case .cancelled: "Cancelled"
        }
    }
}

@MainActor
@Observable
final class DemoModel {
    let player: ABPlayer

    private let metricsSink: ABInMemoryMetricsSink
    private let metricsRecorder: ABMetricsRecorder
    private let mediaCache: ABMediaCache?
    private let hlsPrefetcher: ABHLSPrefetcher
    private var metricsToken: ABObservationToken?
    private var eventToken: ABObservationToken?
    private var prefetchHandle: ABHLSPrefetchHandle?
    private var prefetchMonitorTask: Task<Void, Never>?
    private var usesPrefetchedHLS = false

    var selectedMedia = DemoMedia.hls
    var grade = ABPlaybackGrade.preloaded
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

        self.player = player
        self.metricsSink = metricsSink
        self.metricsRecorder = metricsRecorder
        self.hlsPrefetcher = hlsPrefetcher

        do {
            self.mediaCache = try ABMediaCache()
        } catch {
            self.mediaCache = nil
            self.cacheError = error.localizedDescription
        }

        metricsToken = metricsRecorder.attach(to: player)
        eventToken = player.addObserver { [weak self] event in
            guard let self else { return }
            self.handle(event)
        }

        var configuration = player.configuration
        configuration.backgroundPolicy = .pause
        player.configuration = configuration
        player.set(source: selectedMedia.source, grade: grade)

        if hlsPrefetcher.localAsset(for: DemoMedia.hls.source) != nil {
            prefetchState = .available
        }
    }

    var cacheSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    var cacheIsAvailable: Bool {
        mediaCache != nil
    }

    func selectMedia(_ media: DemoMedia) {
        guard media != selectedMedia || usesPrefetchedHLS else { return }
        abandonPendingTTFF()
        selectedMedia = media
        usesPrefetchedHLS = false
        applyAssetFactory()
        player.set(source: media.source, grade: grade)
        resumeCurrentPlaybackIfNeeded()
    }

    func setGrade(_ newGrade: ABPlaybackGrade) {
        guard newGrade != grade else { return }
        if grade == .current {
            abandonPendingTTFF()
        }
        if newGrade == .current {
            metricsRecorder.beginTTFF(
                for: player,
                resumedFromTime: validCurrentTime
            )
        }
        grade = newGrade
        player.promote(to: newGrade)
        if newGrade == .current {
            player.play()
        }
        refreshStatistics()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player.setMuted(muted)
    }

    func setLooping(_ looping: Bool) {
        isLooping = looping
        var configuration = player.configuration
        configuration.isLooping = looping
        player.configuration = configuration
    }

    func setTuning(_ preset: DemoTuningPreset) {
        selectedTuning = preset
        var configuration = player.configuration
        configuration.preloadTuning = preset.tuning
        configuration.currentTuning = preset.tuning
        player.configuration = configuration
    }

    func togglePlayback() {
        guard grade == .current else {
            setGrade(.current)
            return
        }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func setCacheEnabled(_ enabled: Bool) {
        guard mediaCache != nil else { return }
        cacheEnabled = enabled
        guard selectedMedia == .mp4 else { return }
        reloadCurrentSource()
    }

    func replayMP4() {
        guard mediaCache != nil else { return }
        cacheEnabled = true
        selectedMedia = .mp4
        usesPrefetchedHLS = false
        reloadCurrentSource(forceCurrent: true)
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
        prefetchHandle?.cancel()
        prefetchMonitorTask?.cancel()
        prefetchState = .downloading
        prefetchHandle = hlsPrefetcher.prefetch(DemoMedia.hls.source)
        prefetchMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.hlsPrefetcher.localAsset(for: DemoMedia.hls.source) != nil {
                    self.prefetchState = .available
                    self.prefetchHandle = nil
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func cancelHLSPrefetch() {
        prefetchHandle?.cancel()
        prefetchHandle = nil
        prefetchMonitorTask?.cancel()
        prefetchMonitorTask = nil
        prefetchState = .cancelled
    }

    func playPrefetchedHLS() {
        guard hlsPrefetcher.localAsset(for: DemoMedia.hls.source) != nil else { return }
        selectedMedia = .hls
        usesPrefetchedHLS = true
        reloadCurrentSource(forceCurrent: true)
    }

    private var validCurrentTime: CFTimeInterval? {
        let seconds = player.currentTime.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private func reloadCurrentSource(forceCurrent: Bool = false) {
        abandonPendingTTFF()
        player.release()
        applyAssetFactory()
        if forceCurrent {
            grade = .current
        }
        player.set(source: selectedMedia.source, grade: grade)
        resumeCurrentPlaybackIfNeeded()
    }

    private func applyAssetFactory() {
        var configuration = player.configuration
        if let mediaCache, cacheEnabled || usesPrefetchedHLS {
            configuration.assetFactory = mediaCache.makeAssetFactory(
                hlsPrefetcher: usesPrefetchedHLS ? hlsPrefetcher : nil
            )
        } else {
            configuration.assetFactory = ABDefaultAssetFactory()
        }
        player.configuration = configuration
    }

    private func resumeCurrentPlaybackIfNeeded() {
        guard grade == .current else { return }
        metricsRecorder.beginTTFF(for: player, resumedFromTime: validCurrentTime)
        player.play()
    }

    private func abandonPendingTTFF() {
        metricsRecorder.abandonTTFF(for: player)
        refreshStatistics()
    }

    private func refreshCacheSize() async {
        cacheSize = await mediaCache?.totalSize() ?? 0
    }

    private func handle(_ event: ABPlayerEvent) {
        latestEvent = event.title
        switch event {
        case .timeControlStatusChanged(let status):
            isPlaying = status == .playing
        case .gradeChanged(_, let newGrade):
            grade = newGrade
        default:
            break
        }
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
        case .failed(let error): "Error: \(String(describing: error))"
        case .tuningApplied(let role, _): "Applied \(String(describing: role)) tuning"
        case .itemDetached(let reason): "Detached: \(String(describing: reason))"
        case .invalidGradeForSource: "Grade rejected for empty source"
        case .playbackRejected: "Playback command rejected"
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
}
