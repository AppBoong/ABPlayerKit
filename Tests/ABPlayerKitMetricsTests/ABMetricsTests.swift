import ABPlayerKit
import ABPlayerKitMetrics
@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKit

private final class ABFakeClock: ABClock, @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: CFTimeInterval

    init(now: CFTimeInterval) {
        self.storedNow = now
    }

    var now: CFTimeInterval {
        lock.lock()
        let value = storedNow
        lock.unlock()
        return value
    }

    func setNow(_ value: CFTimeInterval) {
        lock.lock()
        storedNow = value
        lock.unlock()
    }
}

@Suite("ABPlaybackStatistics aggregation", .timeLimit(.minutes(1)))
struct ABPlaybackStatisticsTests {
    @Test("Aggregates fixed samples with abandoned samples in rate denominators")
    func aggregatesFixedSamples() {
        let playerID = ABPlayerID()
        let samples = [
            ABMetricSample(playerID: playerID, startedAt: 1, outcome: .hit),
            ABMetricSample(playerID: playerID, startedAt: 2, outcome: .waited(ms: 100)),
            ABMetricSample(playerID: playerID, startedAt: 3, outcome: .waited(ms: 300)),
            ABMetricSample(playerID: playerID, startedAt: 4, outcome: .waited(ms: 900)),
            ABMetricSample(playerID: playerID, startedAt: 5, outcome: .abandoned)
        ]

        let statistics = ABPlaybackStatistics.aggregate(samples)

        #expect(statistics.sampleCount == 5)
        #expect(statistics.hitCount == 1)
        #expect(statistics.abandonedCount == 1)
        #expect(statistics.p50 == 100)
        #expect(statistics.p95 == 900)
        #expect(statistics.max == 900)
        #expect(statistics.hitRate == 0.2)
        #expect(statistics.abandonRate == 0.2)
    }

    @Test("Empty aggregation returns zero values")
    func emptyAggregation() {
        #expect(ABPlaybackStatistics.aggregate([]) == ABPlaybackStatistics(
            sampleCount: 0,
            hitCount: 0,
            abandonedCount: 0,
            p50: 0,
            p95: 0,
            max: 0
        ))
    }
}

@Suite("ABMetricsRecorder scenarios", .timeLimit(.minutes(1)))
@MainActor
struct ABMetricsRecorderTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/video.mp4")!)

    @Test("Observation token cancellation detaches the recorder")
    func tokenCancellationDetachesRecorder() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 10))
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        let token = recorder.attach(to: player)
        player.set(source: source, grade: .current)
        let countBeforeCancellation = sink.events.count

        token.cancel()
        player.release()

        #expect(sink.events.count == countBeforeCancellation)
    }

    @Test("Begin and first frame record waited TTFF with resume time")
    func recordsWaitedTTFFWithResumeTime() {
        let sink = ABInMemoryMetricsSink()
        let clock = ABFakeClock(now: 20)
        let recorder = ABMetricsRecorder(sink: sink, clock: clock)
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        let token = recorder.attach(to: player)
        player.set(source: source, grade: .current)

        recorder.beginTTFF(for: player, resumedFromTime: 12.5)
        player.reportFirstFrameDisplayed(at: 20.25)

        #expect(sink.events.contains(.ttff(ABMetricSample(
            playerID: player.id,
            startedAt: 20,
            outcome: .waited(ms: 250),
            resumedFromTime: 12.5
        ))))
        token.cancel()
    }

    @Test("Beginning after a displayed frame records a hit")
    func recordsHitForDisplayedFrame() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 30))
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        player.reportFirstFrameDisplayed(at: 29)

        recorder.beginTTFF(for: player, resumedFromTime: 4)

        #expect(sink.events == [.ttff(ABMetricSample(
            playerID: player.id,
            startedAt: 30,
            outcome: .hit,
            resumedFromTime: 4
        ))])
    }

    @Test("Abandoning an active measurement records abandoned once")
    func recordsAbandonedTTFFOnce() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 40))
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))

        recorder.beginTTFF(for: player, resumedFromTime: 7)
        recorder.abandonTTFF(for: player)
        recorder.abandonTTFF(for: player)

        #expect(sink.events == [.ttff(ABMetricSample(
            playerID: player.id,
            startedAt: 40,
            outcome: .abandoned,
            resumedFromTime: 7
        ))])
    }

    @Test("Item detachment abandons and clears a pending TTFF measurement")
    func itemDetachmentAbandonsPendingTTFF() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 50))
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        let token = recorder.attach(to: player)
        player.set(source: source, grade: .current)

        recorder.beginTTFF(for: player, resumedFromTime: 11)
        player.release()
        recorder.abandonTTFF(for: player)

        let samples = sink.events.compactMap { event -> ABMetricSample? in
            guard case .ttff(let sample) = event else { return nil }
            return sample
        }
        #expect(samples == [ABMetricSample(
            playerID: player.id,
            startedAt: 50,
            outcome: .abandoned,
            resumedFromTime: 11
        )])
        token.cancel()
    }

    @Test("Preload starts are recorded only on upward transitions")
    func recordsPreloadOnlyOnUpwardTransition() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 60))
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        let token = recorder.attach(to: player)

        player.set(source: source, grade: .preloaded)
        player.set(source: source, grade: .current)
        player.set(source: source, grade: .preloaded)

        let preloadEvents = sink.events.filter {
            if case .preloadStarted = $0 { return true }
            return false
        }
        #expect(preloadEvents.count == 1)
        token.cancel()
    }
}
