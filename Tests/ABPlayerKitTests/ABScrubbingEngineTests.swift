@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKit

@Suite("Scrubbing coalesces engine seeks and commits the newest target")
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
    func scrubWithoutBeginIsSingleCoarseSeek() async {
        let (player, target) = makePlayer()
        let destination = CMTime(seconds: 25, preferredTimescale: 600)

        player.scrub(to: destination)
        while !target.calls.contains(.seek(destination, .scrubbing)) {
            await Task.yield()
        }

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

    @Test("Given rapid scrub requests, only first, latest, and final precise seeks issue")
    func rapidScrubsCoalesceAndCommitLatest() async {
        let (player, target) = makePlayer(suspendedSeeks: true)
        let first = CMTime(seconds: 10, preferredTimescale: 600)
        let stale = CMTime(seconds: 20, preferredTimescale: 600)
        let latest = CMTime(seconds: 30, preferredTimescale: 600)
        player.beginScrubbing()

        player.scrub(to: first)
        while target.pendingSeekCount == 0 { await Task.yield() }
        player.scrub(to: stale)
        player.scrub(to: latest)

        let endTask = Task { await player.endScrubbing() }
        target.completeNextSeek()
        while target.pendingSeekCount == 0 { await Task.yield() }
        target.completeNextSeek()
        while target.pendingSeekCount == 0 { await Task.yield() }
        target.completeNextSeek()
        await endTask.value

        let seeks = target.calls.compactMap { call -> (CMTime, ABSeekTolerance)? in
            guard case .seek(let time, let tolerance) = call else { return nil }
            return (time, tolerance)
        }
        #expect(seeks.count == 3)
        #expect(seeks[0].0 == first)
        #expect(seeks[1].0 == latest)
        #expect(seeks[2].0 == latest)
        #expect(seeks[2].1 == .precise)
        #expect(!seeks.contains { $0.0 == stale })
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
    func rapidScrubbingSkipsCoalesce() async {
        let (player, target) = makePlayer(suspendedSeeks: true)
        player.beginScrubbing()

        await player.skip(by: 5)
        while target.pendingSeekCount == 0 { await Task.yield() }
        for _ in 0..<4 {
            await player.skip(by: 5)
        }

        #expect(target.calls.filter { if case .seek = $0 { true } else { false } }.count == 1)
        target.completeNextSeek()
        while target.pendingSeekCount == 0 { await Task.yield() }
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
    func sourceSwapEndsSessionAndDiscardsStaleSeek() async {
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
        while target.pendingSeekCount == 0 { await Task.yield() }

        player.set(source: replacement, grade: .current)
        target.completeNextSeek()
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
}
