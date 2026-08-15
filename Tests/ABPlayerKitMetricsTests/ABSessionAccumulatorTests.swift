import ABPlayerKit
import ABTestSupport
import Foundation
@preconcurrency import QuartzCore
import Testing
@testable import ABPlayerKitMetrics

/// Every test that touches this constructs and reads it from a single test
/// function body, never concurrently — `nonisolated(unsafe)` on the two
/// stored properties documents that instead of reaching for a lock.
private final class ABFakeClock: ABClock {
    nonisolated(unsafe) private var storedNow: CFTimeInterval
    nonisolated(unsafe) private var storedWallClockEpoch: TimeInterval

    init(now: CFTimeInterval, wallClockEpoch: TimeInterval = 1_700_000_000) {
        self.storedNow = now
        self.storedWallClockEpoch = wallClockEpoch
    }

    var now: CFTimeInterval { storedNow }
    var wallClockEpoch: TimeInterval { storedWallClockEpoch }

    func setNow(_ value: CFTimeInterval) {
        storedNow = value
    }
}

private let playerID = ABPlayerID()

private func openedAccumulator(at now: CFTimeInterval = 0) -> ABPlaybackSessionAccumulator {
    var accumulator = ABPlaybackSessionAccumulator()
    _ = accumulator.ingest(
        .attached(sourceURL: "https://example.com/a.mp4", wallClockEpoch: 1_700_000_000, isPartial: false),
        playerID: playerID,
        at: now
    )
    return accumulator
}

private func firstSummary(in events: [ABMetricEvent]) -> ABSessionSummary? {
    events.compactMap { event -> ABSessionSummary? in
        guard case .sessionSummary(let summary) = event else { return nil }
        return summary
    }.first
}

private func firstBuffering(in events: [ABMetricEvent]) -> ABBufferingInterval? {
    events.compactMap { event -> ABBufferingInterval? in
        guard case .buffering(let interval) = event else { return nil }
        return interval
    }.first
}

enum BufferingOpenTrigger: Sendable {
    case buffering
    case stall
}

enum BufferingCloseTrigger: Sendable {
    case bufferingResumed
    case stallEnded
    case detached
    case failure
}

struct BufferingCase: Sendable, CustomStringConvertible {
    let open: BufferingOpenTrigger
    let close: BufferingCloseTrigger
    let afterFirstFrame: Bool

    var description: String {
        "open:\(open) close:\(close) afterFirstFrame:\(afterFirstFrame)"
    }
}

private let bufferingCases: [BufferingCase] = {
    var cases: [BufferingCase] = []
    for open: BufferingOpenTrigger in [.buffering, .stall] {
        for close: BufferingCloseTrigger in [.bufferingResumed, .stallEnded, .detached, .failure] {
            for afterFirstFrame in [false, true] {
                cases.append(BufferingCase(open: open, close: close, afterFirstFrame: afterFirstFrame))
            }
        }
    }
    return cases
}()

@Suite("ABPlaybackSessionAccumulator", .timeLimit(abScaledMinutes(3)))
struct ABSessionAccumulatorTests {
    @Test("Session open emits sessionStarted with the anchor")
    func opensSessionWithAnchor() {
        var accumulator = ABPlaybackSessionAccumulator()
        let events = accumulator.ingest(
            .attached(sourceURL: "https://example.com/a.mp4", wallClockEpoch: 1_700_000_000, isPartial: false),
            playerID: playerID,
            at: 10
        )
        #expect(events == [.sessionStarted(ABSessionAnchor(
            playerID: playerID,
            startedAt: 10,
            wallClockEpoch: 1_700_000_000,
            sourceURL: "https://example.com/a.mp4",
            isPartial: false
        ))])
    }

    @Test("A synthesized attach can mark the session partial")
    func partialSessionAnchor() {
        var accumulator = ABPlaybackSessionAccumulator()
        let events = accumulator.ingest(
            .attached(sourceURL: nil, wallClockEpoch: 5, isPartial: true),
            playerID: playerID,
            at: 1
        )
        #expect(events == [.sessionStarted(ABSessionAnchor(
            playerID: playerID,
            startedAt: 1,
            wallClockEpoch: 5,
            sourceURL: nil,
            isPartial: true
        ))])
    }

    @Test("Buffering interval combinations", arguments: bufferingCases)
    func bufferingIntervalCombinations(_ testCase: BufferingCase) throws {
        var accumulator = openedAccumulator(at: 0)
        if testCase.afterFirstFrame {
            _ = accumulator.ingest(.firstFrame, playerID: playerID, at: 1)
        }

        let openInput: ABSessionInput = testCase.open == .buffering ? .bufferingChanged(true) : .stalled
        let openedEvents = accumulator.ingest(openInput, playerID: playerID, at: 5)
        #expect(openedEvents.isEmpty)

        let closeEvents: [ABMetricEvent]
        let expectedEnd: ABBufferingInterval.End
        switch testCase.close {
        case .bufferingResumed:
            closeEvents = accumulator.ingest(.bufferingChanged(false), playerID: playerID, at: 8)
            expectedEnd = .resumed
        case .stallEnded:
            closeEvents = accumulator.ingest(.stallEnded, playerID: playerID, at: 8)
            expectedEnd = .resumed
        case .detached:
            closeEvents = accumulator.ingest(.detached(reason: .release, access: nil), playerID: playerID, at: 8)
            expectedEnd = .detached
        case .failure:
            closeEvents = accumulator.ingest(.failure(ABPlayerFailure(kind: .prerollFailed)), playerID: playerID, at: 8)
            expectedEnd = .failed
        }

        let interval = try #require(firstBuffering(in: closeEvents))
        #expect(interval.trigger == (testCase.open == .buffering ? .buffering : .stall))
        #expect(interval.phase == (testCase.afterFirstFrame ? .rebuffer : .startup))
        #expect(interval.end == expectedEnd)
        #expect(interval.startedAt == 5)
        #expect(interval.endedAt == 8)
        #expect(interval.milliseconds == 3_000)
    }

    @Test("A second open trigger while a span is open is ignored and keeps the original trigger")
    func doubleOpenKeepsOriginalTrigger() throws {
        var accumulator = openedAccumulator(at: 0)
        _ = accumulator.ingest(.bufferingChanged(true), playerID: playerID, at: 1)
        _ = accumulator.ingest(.stalled, playerID: playerID, at: 2)
        let closeEvents = accumulator.ingest(.bufferingChanged(false), playerID: playerID, at: 5)
        let interval = try #require(firstBuffering(in: closeEvents))
        #expect(interval.trigger == .buffering)
        #expect(interval.startedAt == 1)
    }

    @Test("A close trigger without a matching open produces no events")
    func closeWithoutOpenProducesNothing() {
        var accumulator = openedAccumulator(at: 0)
        let events = accumulator.ingest(.stallEnded, playerID: playerID, at: 1)
        #expect(events.isEmpty)
    }

    @Test("Detach closes an unresolved buffering span, then the session summary")
    func detachClosesOpenBufferingThenSummary() {
        var accumulator = openedAccumulator(at: 0)
        _ = accumulator.ingest(.bufferingChanged(true), playerID: playerID, at: 2)
        let events = accumulator.ingest(.detached(reason: .release, access: nil), playerID: playerID, at: 6)
        #expect(events.count == 2)
        guard case .buffering(let interval) = events[0] else {
            Issue.record("expected .buffering first, got \(events[0])")
            return
        }
        guard case .sessionSummary(let summary) = events[1] else {
            Issue.record("expected .sessionSummary second, got \(events[1])")
            return
        }
        #expect(interval.end == .detached)
        #expect(summary.endReason == .detached(.release))
    }

    @Test("A re-attach without a prior detach finalizes the open session before opening the next")
    func reattachWithoutDetachFinalizesPreviousSession() {
        var accumulator = ABPlaybackSessionAccumulator()
        _ = accumulator.ingest(.attached(sourceURL: "a", wallClockEpoch: 1, isPartial: false), playerID: playerID, at: 0)
        let events = accumulator.ingest(.attached(sourceURL: "b", wallClockEpoch: 2, isPartial: false), playerID: playerID, at: 5)
        #expect(events.count == 2)
        guard case .sessionSummary(let summary) = events[0] else {
            Issue.record("expected finalized summary first, got \(events[0])")
            return
        }
        guard case .sessionStarted(let anchor) = events[1] else {
            Issue.record("expected new sessionStarted second, got \(events[1])")
            return
        }
        #expect(summary.endReason == .finalized)
        #expect(summary.sourceURL == "a")
        #expect(anchor.sourceURL == "b")
        #expect(anchor.startedAt == 5)
    }

    // MARK: - Watch time / completion (F-2w)

    @Test("Watch time accumulates only while playing")
    func watchTimeAccumulatesWhilePlaying() throws {
        var accumulator = openedAccumulator(at: 0)
        _ = accumulator.ingest(.timeControl(.playing), playerID: playerID, at: 10)
        _ = accumulator.ingest(.timeControl(.paused), playerID: playerID, at: 25)
        _ = accumulator.ingest(.timeControl(.playing), playerID: playerID, at: 30)
        let events = accumulator.ingest(.detached(reason: .release, access: nil), playerID: playerID, at: 40)
        let summary = try #require(firstSummary(in: events))
        #expect(summary.watchedMilliseconds == 25_000)
    }

    @Test("Watch time is accurate with no position updates; completion ratio stays unknown")
    func watchTimeWithoutPositionUpdates() throws {
        var accumulator = openedAccumulator(at: 0)
        _ = accumulator.ingest(.timeControl(.playing), playerID: playerID, at: 0)
        let events = accumulator.ingest(.detached(reason: .release, access: nil), playerID: playerID, at: 12)
        let summary = try #require(firstSummary(in: events))
        #expect(summary.watchedMilliseconds == 12_000)
        #expect(summary.completionRatio == nil)
    }

    @Test("playedToEnd resolves completion ratio to 1")
    func playedToEndCompletesFully() throws {
        var accumulator = openedAccumulator(at: 0)
        _ = accumulator.ingest(.playedToEnd, playerID: playerID, at: 5)
        let events = accumulator.ingest(.finalize(access: nil), playerID: playerID, at: 6)
        let summary = try #require(firstSummary(in: events))
        #expect(summary.completionRatio == 1)
    }

    @Test("Time spent scrubbing is excluded from watch time")
    func scrubbingExcludedFromWatchTime() throws {
        var accumulator = openedAccumulator(at: 0)
        _ = accumulator.ingest(.timeControl(.playing), playerID: playerID, at: 0)
        _ = accumulator.ingest(.scrubbing(true), playerID: playerID, at: 5)
        _ = accumulator.ingest(.scrubbing(false), playerID: playerID, at: 9)
        let events = accumulator.ingest(.detached(reason: .release, access: nil), playerID: playerID, at: 15)
        let summary = try #require(firstSummary(in: events))
        #expect(summary.watchedMilliseconds == 11_000)
    }

    @Test("Watched and rebuffer time never exceed elapsed wall time")
    func watchedAndRebufferDoNotOverlap() throws {
        var accumulator = openedAccumulator(at: 0)
        _ = accumulator.ingest(.firstFrame, playerID: playerID, at: 0)
        _ = accumulator.ingest(.timeControl(.playing), playerID: playerID, at: 0)
        _ = accumulator.ingest(.bufferingChanged(true), playerID: playerID, at: 4)
        _ = accumulator.ingest(.timeControl(.waitingToPlay), playerID: playerID, at: 4)
        _ = accumulator.ingest(.bufferingChanged(false), playerID: playerID, at: 7)
        _ = accumulator.ingest(.timeControl(.playing), playerID: playerID, at: 7)
        let events = accumulator.ingest(.detached(reason: .release, access: nil), playerID: playerID, at: 10)
        let summary = try #require(firstSummary(in: events))
        #expect(summary.watchedMilliseconds + summary.rebufferMilliseconds == 10_000)
    }

    // MARK: - Failures (F-3w)

    @Test("Failure events preserve the origin's domain and code")
    func failurePreservesOrigin() throws {
        var accumulator = openedAccumulator(at: 0)
        let failure = ABPlayerFailure(
            kind: .itemFailed(description: "boom"),
            origin: ABErrorOrigin(domain: "NSURLErrorDomain", code: -1_009)
        )
        let events = accumulator.ingest(.failure(failure), playerID: playerID, at: 3)
        guard case .failure(let record) = try #require(events.first) else {
            Issue.record("expected .failure, got \(events)")
            return
        }
        #expect(record.failure.origin?.domain == "NSURLErrorDomain")
        #expect(record.failure.origin?.code == -1_009)
    }

    @Test("A non-terminal diagnostic increments diagnosticCount, not terminalFailureCount")
    func nonTerminalFailureIsADiagnostic() throws {
        var accumulator = openedAccumulator(at: 0)
        let diagnostic = ABPlayerFailure(kind: .itemErrorLogEntry(description: "hiccup"))
        _ = accumulator.ingest(.failure(diagnostic), playerID: playerID, at: 2)
        let events = accumulator.ingest(.finalize(access: nil), playerID: playerID, at: 3)
        let summary = try #require(firstSummary(in: events))
        #expect(summary.diagnosticCount == 1)
        #expect(summary.terminalFailureCount == 0)
    }

    @Test("A terminal failure closes an open buffering span and keeps the session open")
    func terminalFailureClosesBufferingButKeepsSessionOpen() throws {
        var accumulator = openedAccumulator(at: 0)
        _ = accumulator.ingest(.bufferingChanged(true), playerID: playerID, at: 1)
        let failureEvents = accumulator.ingest(.failure(ABPlayerFailure(kind: .prerollFailed)), playerID: playerID, at: 3)
        #expect(firstBuffering(in: failureEvents)?.end == .failed)

        let closeEvents = accumulator.ingest(.finalize(access: nil), playerID: playerID, at: 4)
        let summary = try #require(firstSummary(in: closeEvents))
        #expect(summary.terminalFailureCount == 1)
    }

    @Test("A failure outside any open session has no sessionStartedAt")
    func failureOutsideSessionHasNoSessionStartedAt() throws {
        var accumulator = ABPlaybackSessionAccumulator()
        let events = accumulator.ingest(.failure(ABPlayerFailure(kind: .prerollFailed)), playerID: playerID, at: 1)
        guard case .failure(let record) = try #require(events.first) else {
            Issue.record("expected .failure, got \(events)")
            return
        }
        #expect(record.sessionStartedAt == nil)
    }
}

@Suite("ABJSONLinesMetricsSink.kindName", .timeLimit(abScaledMinutes(3)))
struct ABKindNameTests {
    @Test("kindName maps every current ABPlayerError case to a stable string")
    func kindNameCoversEveryCase() {
        #expect(ABJSONLinesMetricsSink.kindName(.itemFailed(description: "x")) == "itemFailed")
        #expect(ABJSONLinesMetricsSink.kindName(.prerollTimedOut(after: 1)) == "prerollTimedOut")
        #expect(ABJSONLinesMetricsSink.kindName(.prerollFailed) == "prerollFailed")
        #expect(ABJSONLinesMetricsSink.kindName(.invalidGradeForSource(requested: .current)) == "invalidGradeForSource")
        #expect(ABJSONLinesMetricsSink.kindName(.cacheUnavailable(description: "x")) == "cacheUnavailable")
        #expect(ABJSONLinesMetricsSink.kindName(.audioSessionOperationFailed(description: "x")) == "audioSessionOperationFailed")
        #expect(ABJSONLinesMetricsSink.kindName(.itemErrorLogEntry(description: "x")) == "itemErrorLogEntry")
    }
}

@Suite("ABMetricsRecorder session integration", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABMetricsRecorderSessionTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/video.mp4")!)

    @Test("A real attach/release produces exactly one sessionStarted and one sessionSummary")
    func integrationOpenAndCloseSession() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 100))
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        let token = recorder.attach(to: player)

        player.set(source: source, grade: .current)
        player.release()

        let startedCount = sink.events.filter {
            if case .sessionStarted = $0 { return true }
            return false
        }.count
        let summaryCount = sink.events.filter {
            if case .sessionSummary = $0 { return true }
            return false
        }.count
        #expect(startedCount == 1)
        #expect(summaryCount == 1)
        #expect(recorder.snapshot(for: player) == nil)
        token.cancel()
    }

    @Test("sessionStarted carries the clock's wall-clock epoch")
    func anchorCarriesWallClockEpoch() {
        let sink = ABInMemoryMetricsSink()
        let clock = ABFakeClock(now: 10, wallClockEpoch: 1_700_000_555)
        let recorder = ABMetricsRecorder(sink: sink, clock: clock)
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        let token = recorder.attach(to: player)

        player.set(source: source, grade: .current)

        let anchor = sink.events.compactMap { event -> ABSessionAnchor? in
            guard case .sessionStarted(let anchor) = event else { return nil }
            return anchor
        }.first
        #expect(anchor?.wallClockEpoch == 1_700_000_555)
        token.cancel()
    }

    @Test("Recorder translation synthesizes a partial session when state precedes attach")
    func partialSessionOpensFromRecorderTranslation() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 10))
        let syntheticPlayerID = ABPlayerID()

        let events = recorder.ingest(
            .timeControlStatusChanged(.playing),
            playerID: syntheticPlayerID,
            hasItem: true,
            at: 10
        )
        guard case .sessionStarted(let anchor) = events.first else {
            Issue.record("expected .sessionStarted first, got \(events)")
            return
        }
        #expect(anchor.isPartial)
    }

    @Test("endSession is idempotent and produces no events without an open session")
    func endSessionIsIdempotent() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 1))
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))

        recorder.endSession(for: player)

        #expect(sink.events.isEmpty)
    }

    @Test("endSession closes an open session with a finalized summary")
    func endSessionClosesOpenSession() {
        let sink = ABInMemoryMetricsSink()
        let recorder = ABMetricsRecorder(sink: sink, clock: ABFakeClock(now: 1))
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        let token = recorder.attach(to: player)

        player.set(source: source, grade: .current)
        recorder.endSession(for: player)
        token.cancel()

        let summary = sink.events.compactMap { event -> ABSessionSummary? in
            guard case .sessionSummary(let summary) = event else { return nil }
            return summary
        }.first
        #expect(summary?.endReason == .finalized)
    }

    @Test("snapshot virtually closes an open playback span without sinking anything")
    func snapshotReflectsLiveStateWithoutSinking() {
        let sink = ABInMemoryMetricsSink()
        let clock = ABFakeClock(now: 0)
        let recorder = ABMetricsRecorder(sink: sink, clock: clock)
        let player = ABPlayer(configuration: .init(backgroundPolicy: .ignore))
        let token = recorder.attach(to: player)

        player.set(source: source, grade: .current)
        recorder.ingest(.timeControlStatusChanged(.playing), playerID: player.id, hasItem: true, at: 0)
        clock.setNow(5)

        let live = recorder.snapshot(for: player)
        #expect(live?.endReason == .active)
        #expect(live?.watchedMilliseconds == 5_000)
        #expect(sink.events.contains {
            if case .sessionSummary = $0 { return true }
            return false
        } == false)
        token.cancel()
    }
}
