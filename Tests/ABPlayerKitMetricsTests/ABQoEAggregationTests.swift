import ABPlayerKit
import ABPlayerKitMetrics
import Foundation
import Testing
@testable import ABPlayerKitMetrics

@Suite("ABAccessLogFolder", .timeLimit(.minutes(3)))
struct ABAccessLogFolderTests {
    @Test("Folds totals, switches, and a duration-weighted average across entries")
    func foldsAcrossEntries() {
        let entries = [
            ABAccessLogEntry(
                numberOfBytesTransferred: 1_000,
                indicatedBitrate: 1_000_000,
                observedBitrate: 900_000,
                startupTime: 2.0,
                numberOfStalls: 1,
                numberOfDroppedVideoFrames: 5,
                durationWatched: 10,
                segmentsDownloadedCount: -1,
                numberOfMediaRequests: 3
            ),
            ABAccessLogEntry(
                numberOfBytesTransferred: 2_000,
                indicatedBitrate: 1_000_000,
                observedBitrate: 950_000,
                startupTime: -1,
                numberOfStalls: 0,
                numberOfDroppedVideoFrames: -1,
                durationWatched: 20,
                segmentsDownloadedCount: 2,
                numberOfMediaRequests: 4
            ),
            ABAccessLogEntry(
                numberOfBytesTransferred: 1_500,
                indicatedBitrate: 2_000_000,
                observedBitrate: 1_000_000,
                startupTime: -1,
                numberOfStalls: 2,
                numberOfDroppedVideoFrames: 3,
                durationWatched: 20,
                segmentsDownloadedCount: 1,
                numberOfMediaRequests: 2
            )
        ]

        let snapshot = ABAccessLogFolder.fold(entries)

        // Last-entry fields, unchanged from v1.
        #expect(snapshot.numberOfBytesTransferred == 1_500)
        #expect(snapshot.indicatedBitrate == 2_000_000)
        #expect(snapshot.observedBitrate == 1_000_000)
        #expect(snapshot.startupTime == -1)
        #expect(snapshot.stallCount == 2)

        // New folded totals.
        #expect(snapshot.totalBytesTransferred == 4_500)
        #expect(snapshot.totalStallCount == 3)
        #expect(snapshot.droppedVideoFrameCount == 8) // 5 + (-1 excluded) + 3
        #expect(snapshot.bitrateSwitchCount == 1) // A -> A -> B
        #expect(snapshot.segmentsDownloadedCount == 3) // (-1 excluded) + 2 + 1
        #expect(snapshot.mediaRequestCount == 9)
        #expect(snapshot.durationWatchedSeconds == 50)
        #expect(snapshot.observedBitrateAverage == 960_000) // (900k*10 + 950k*20 + 1000k*20) / 50
        #expect(snapshot.initialStartupTimeSeconds == 2.0) // first non-negative
        #expect(snapshot.entryCount == 3)
    }

    @Test("An empty log folds to all-zero, nil-startup, nil-access-worthy defaults")
    func foldsEmptyLog() {
        let snapshot = ABAccessLogFolder.fold([])
        #expect(snapshot == ABAccessSnapshot(
            numberOfBytesTransferred: 0,
            indicatedBitrate: 0,
            observedBitrate: 0,
            startupTime: 0,
            stallCount: 0
        ))
        #expect(snapshot.initialStartupTimeSeconds == nil)
        #expect(snapshot.entryCount == 0)
    }

    @Test("A negative byte count is excluded from the total but kept verbatim in the last-entry field")
    func excludesUnknownFieldsFromTotals() {
        let entries = [
            ABAccessLogEntry(
                numberOfBytesTransferred: 500,
                indicatedBitrate: 1_000_000,
                observedBitrate: 900_000,
                startupTime: 1,
                numberOfStalls: 0,
                numberOfDroppedVideoFrames: 0,
                durationWatched: 5,
                segmentsDownloadedCount: 0,
                numberOfMediaRequests: 1
            ),
            ABAccessLogEntry(
                numberOfBytesTransferred: -1,
                indicatedBitrate: -1,
                observedBitrate: -1,
                startupTime: -1,
                numberOfStalls: -1,
                numberOfDroppedVideoFrames: -1,
                durationWatched: -1,
                segmentsDownloadedCount: -1,
                numberOfMediaRequests: -1
            )
        ]

        let snapshot = ABAccessLogFolder.fold(entries)
        #expect(snapshot.numberOfBytesTransferred == -1) // last entry, verbatim
        #expect(snapshot.totalBytesTransferred == 500) // unknown excluded from the sum
        #expect(snapshot.bitrateSwitchCount == 0) // second entry's bitrate isn't > 0
    }
}

@Suite("ABPlaybackStatistics.waited", .timeLimit(.minutes(3)))
struct ABPlaybackStatisticsWaitedTests {
    @Test("waited excludes .hit samples that the legacy distribution folds in as 0 ms")
    func waitedExcludesHits() {
        let playerID = ABPlayerID()
        let samples = [
            ABMetricSample(playerID: playerID, startedAt: 1, outcome: .hit),
            ABMetricSample(playerID: playerID, startedAt: 2, outcome: .waited(ms: 100)),
            ABMetricSample(playerID: playerID, startedAt: 3, outcome: .waited(ms: 300)),
            ABMetricSample(playerID: playerID, startedAt: 4, outcome: .waited(ms: 900))
        ]

        let statistics = ABPlaybackStatistics.aggregate(samples)

        #expect(statistics.p50 == 100) // legacy: .hit folded in as 0 ms, unchanged
        #expect(statistics.waited.p50 == 300) // waited-only: the hit doesn't drag the median down
        #expect(statistics.waited.count == 3)
    }
}

@Suite("ABQoESummary.aggregate", .timeLimit(.minutes(3)))
struct ABQoESummaryTests {
    @Test("Ignores every event that isn't .sessionSummary")
    func ignoresNonSessionSummaryEvents() {
        let playerID = ABPlayerID()
        let events: [ABMetricEvent] = [
            .stall(playerID: playerID, at: 1),
            .preloadStarted(playerID: playerID, at: 2)
        ]
        let summary = ABQoESummary.aggregate(events)
        #expect(summary.sessionCount == 0)
    }

    @Test("Ratios are nil with zero sessions")
    func ratiosAreNilWithZeroSessions() {
        let summary = ABQoESummary.aggregate([])
        #expect(summary.rebufferRatio == nil)
        #expect(summary.completionRate == nil)
        #expect(summary.terminalFailureRate == nil)
        #expect(summary.rebuffersPerHourWatched == nil)
    }

    @Test("Folds session summaries into totals and rates")
    func foldsSessionSummaries() {
        let playerID = ABPlayerID()
        let completed = ABSessionSummary(
            playerID: playerID,
            startedAt: 0,
            wallClockEpoch: 0,
            endedAt: 10,
            endReason: .finalized,
            hasDisplayedFirstFrame: true,
            watchedMilliseconds: 9_000,
            rebufferMilliseconds: 1_000,
            rebufferCount: 1,
            playedToEnd: true
        )
        let failed = ABSessionSummary(
            playerID: playerID,
            startedAt: 20,
            wallClockEpoch: 0,
            endedAt: 21,
            endReason: .finalized,
            hasDisplayedFirstFrame: true,
            terminalFailureCount: 1
        )
        let events: [ABMetricEvent] = [.sessionSummary(completed), .sessionSummary(failed)]

        let summary = ABQoESummary.aggregate(events)
        #expect(summary.sessionCount == 2)
        #expect(summary.firstFrameSessionCount == 2)
        #expect(summary.completedSessionCount == 1)
        #expect(summary.failedSessionCount == 1)
        #expect(summary.completionRate == 0.5)
        #expect(summary.terminalFailureRate == 0.5)
    }
}

@Suite("Item-holding hazard (R-1)", .timeLimit(.minutes(3)))
@MainActor
struct ABItemHoldingHazardTests {
    @Test("player.avPlayerItem is already nil by the time .itemDetached reaches an observer")
    func avPlayerItemIsNilAtDetachTime() {
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        var wasNilAtDetach = false
        let token = player.addObserver { event in
            if case .itemDetached = event {
                wasNilAtDetach = (player.avPlayerItem == nil)
            }
        }
        let source = ABMediaSource(url: URL(string: "https://example.com/video.mp4")!)
        player.set(source: source, grade: .current)
        player.release()
        #expect(wasNilAtDetach)
        token.cancel()
    }
}
