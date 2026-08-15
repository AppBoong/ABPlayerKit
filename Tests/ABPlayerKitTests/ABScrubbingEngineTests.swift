@preconcurrency import AVFoundation
import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit

@Suite("Scrubbing coalesces engine seeks and commits the newest target", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABScrubbingEngineTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/scrub.mp4")!)

    private func makePlayer(
        suspendedSeeks: Bool = false,
        periodicTimeInterval: TimeInterval? = nil
    ) -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        target.waitsForSeekContinuation = suspendedSeeks
        target.duration = CMTime(seconds: 100, preferredTimescale: 600)
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(
                periodicTimeInterval: periodicTimeInterval,
                prerollRate: nil,
                backgroundPolicy: .ignore
            ),
            target: target
        )
        player.set(source: source, grade: .current)
        return (player, target)
    }

    @Test("Given no explicit session, scrub performs one coarse seek")
    func scrubWithoutBeginIsSingleCoarseSeek() async throws {
        let (player, target) = makePlayer()
        let destination = CMTime(seconds: 25, preferredTimescale: 600)

        player.scrub(to: destination)
        try await waitUntil { target.calls.contains(.seek(destination, .scrubbing)) }

        #expect(target.calls.filter { if case .seek = $0 { true } else { false } }.count == 1)
    }

    @Test("Given duplicate begin calls, the boundary event is emitted once")
    func duplicateBeginIsNoOp() {
        let (player, _) = makePlayer()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.beginScrubbing()
        player.beginScrubbing()

        #expect(player.isScrubbing)
        #expect(events.filter { $0 == .scrubbingChanged(isScrubbing: true) }.count == 1)
    }

    @Test("Given rapid scrub requests, only the first and latest precise seeks issue")
    func rapidScrubsCoalesceAndCommitLatest() async throws {
        let (player, target) = makePlayer(suspendedSeeks: true)
        let first = CMTime(seconds: 10, preferredTimescale: 600)
        let stale = CMTime(seconds: 20, preferredTimescale: 600)
        let latest = CMTime(seconds: 30, preferredTimescale: 600)
        player.beginScrubbing()

        player.scrub(to: first)
        try await waitUntil { target.pendingSeekCount > 0 }
        player.scrub(to: stale)
        player.scrub(to: latest)

        let endTask = Task { await player.endScrubbing() }
        // `Task { ... }` created from this `@MainActor` test infers
        // `@MainActor` isolation, so `endTask` cannot run its synchronous
        // prefix (through `endScrubbing()`'s first `await`) until this test
        // function itself yields the actor — a single `Task.yield()` is a
        // deterministic hand-off, not a speculative poll (round3 Phase1+2
        // review m6: distinguishing this from the busy-loop pattern WP8
        // removed elsewhere).
        await Task.yield()
        target.completeNextSeek()
        try await waitUntil { target.pendingSeekCount > 0 }
        target.completeNextSeek()
        await endTask.value

        let seeks = target.calls.compactMap { call -> (CMTime, ABSeekTolerance)? in
            guard case .seek(let time, let tolerance) = call else { return nil }
            return (time, tolerance)
        }
        #expect(seeks.count == 2)
        #expect(seeks[0].0 == first)
        #expect(seeks[1].0 == latest)
        #expect(seeks[1].1 == .precise)
        #expect(!seeks.contains { $0.0 == stale })
    }

    @Test("Given the coarse seek already completed, ending adds one precise commit")
    func completedCoarseSeekStillCommitsPrecisely() async throws {
        let (player, target) = makePlayer()
        let destination = CMTime(seconds: 35, preferredTimescale: 600)
        var completedSeeks: [CMTime] = []
        let token = player.addObserver {
            if case .seekCompleted(let time) = $0 {
                completedSeeks.append(time)
            }
        }
        defer { token.cancel() }
        player.beginScrubbing()
        player.scrub(to: destination)
        try await waitUntil { !completedSeeks.isEmpty }

        await player.endScrubbing()

        let tolerances = target.calls.compactMap { call -> ABSeekTolerance? in
            guard case .seek(let time, let tolerance) = call, time == destination else { return nil }
            return tolerance
        }
        #expect(tolerances == [.scrubbing, .precise])
    }

    @Test("Given a completed session, seek completion precedes the false boundary")
    func completionPrecedesScrubbingEnd() async {
        let (player, _) = makePlayer()
        let destination = CMTime(seconds: 40, preferredTimescale: 600)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }
        player.beginScrubbing()
        player.scrub(to: destination)

        await player.endScrubbing()

        let finalSeekIndex = events.lastIndex(of: .seekCompleted(to: destination))
        let endIndex = events.lastIndex(of: .scrubbingChanged(isScrubbing: false))
        #expect(finalSeekIndex != nil)
        #expect(endIndex != nil)
        #expect(finalSeekIndex! < endIndex!)
    }

    @Test("Given rapid skips during scrubbing, they share the seek coalescer")
    func rapidScrubbingSkipsCoalesce() async throws {
        let (player, target) = makePlayer(suspendedSeeks: true)
        player.beginScrubbing()

        await player.skip(by: 5)
        try await waitUntil { target.pendingSeekCount > 0 }
        for _ in 0..<4 {
            await player.skip(by: 5)
        }

        #expect(target.calls.filter { if case .seek = $0 { true } else { false } }.count == 1)
        target.completeNextSeek()
        try await waitUntil { target.pendingSeekCount > 0 }
        target.completeNextSeek()
        target.waitsForSeekContinuation = false
        await player.endScrubbing()
    }

    @Test("Given a demotion during scrubbing, the session ends and periodic events resume")
    func demotionEndsSessionAndRestoresPeriodicEvents() {
        let (player, target) = makePlayer(periodicTimeInterval: 0.25)
        var periodicEvents: [ABPlaybackTime] = []
        let token = player.addObserver {
            if case .periodicTime(let time) = $0 {
                periodicEvents.append(time)
            }
        }
        defer { token.cancel() }
        player.beginScrubbing()

        player.promote(to: .preloaded)
        player.promote(to: .current)
        target.tick(CMTime(seconds: 5, preferredTimescale: 600))

        #expect(!player.isScrubbing)
        #expect(periodicEvents.count == 1)
    }

    @Test("Given a source swap during scrubbing, the session ends and no stale seek issues")
    func sourceSwapEndsSessionAndDiscardsStaleSeek() async throws {
        let (player, target) = makePlayer(suspendedSeeks: true)
        let staleDestination = CMTime(seconds: 25, preferredTimescale: 600)
        let replacement = ABMediaSource(url: URL(string: "https://example.com/replacement.mp4")!)
        var seekCompletions: [CMTime] = []
        let token = player.addObserver {
            if case .seekCompleted(let time) = $0 {
                seekCompletions.append(time)
            }
        }
        defer { token.cancel() }
        player.beginScrubbing()
        player.scrub(to: staleDestination)
        try await waitUntil { target.pendingSeekCount > 0 }

        player.set(source: replacement, grade: .current)
        target.completeNextSeek()
        // Asserting an *absence* (no `.seekCompleted` broadcast) has no
        // positive predicate `waitUntil` can poll for — `set(source:grade:)`
        // already bumped `seekGeneration` synchronously above, so the
        // now-stale seek worker's `guard generation == seekGeneration`
        // silently returns instead of broadcasting once it resumes past
        // `completeNextSeek()`'s continuation. A bounded drain of pending
        // main-actor work is the deterministic-enough substitute (round3
        // Phase1+2 review m6).
        for _ in 0..<10 { await Task.yield() }

        #expect(!player.isScrubbing)
        #expect(seekCompletions.isEmpty)
        #expect(target.calls.filter { if case .seek = $0 { true } else { false } }.count == 1)
    }

    @Test("Given a session ended by demotion, a later beginScrubbing emits its boundary event")
    func beginAfterDemotionEmitsBoundaryEvent() {
        let (player, _) = makePlayer()
        var boundaries: [Bool] = []
        let token = player.addObserver {
            if case .scrubbingChanged(let isScrubbing) = $0 {
                boundaries.append(isScrubbing)
            }
        }
        defer { token.cancel() }
        player.beginScrubbing()

        player.promote(to: .preloaded)
        player.promote(to: .current)
        player.beginScrubbing()

        #expect(boundaries == [true, false, true])
    }

    @Test("Given demotion while ending, no non-current seek issues and state cleanup remains")
    func demotionWhileEndingRejectsCommitAndKeepsCleanup() async throws {
        let (player, target) = makePlayer(suspendedSeeks: true)
        let destination = CMTime(seconds: 50, preferredTimescale: 600)
        var boundaries: [Bool] = []
        var rejections = 0
        let token = player.addObserver {
            switch $0 {
            case .scrubbingChanged(let isScrubbing):
                boundaries.append(isScrubbing)
            case .playbackRejected:
                rejections += 1
            default:
                break
            }
        }
        defer { token.cancel() }
        player.beginScrubbing()
        player.scrub(to: destination)
        try await waitUntil { target.pendingSeekCount > 0 }
        let endTask = Task { await player.endScrubbing() }
        // `Task { ... }` created from this `@MainActor` test infers
        // `@MainActor` isolation, so `endTask` cannot run its synchronous
        // prefix (through `endScrubbing()`'s first `await`) until this test
        // function itself yields the actor — a single `Task.yield()` is a
        // deterministic hand-off, not a speculative poll (round3 Phase1+2
        // review m6: distinguishing this from the busy-loop pattern WP8
        // removed elsewhere).
        await Task.yield()

        player.promote(to: .preloaded)
        target.completeNextSeek()
        await endTask.value

        #expect(!player.isScrubbing)
        #expect(boundaries == [true, false])
        #expect(rejections == 1)
        #expect(target.calls.filter { if case .seek = $0 { true } else { false } }.count == 1)
    }
}
