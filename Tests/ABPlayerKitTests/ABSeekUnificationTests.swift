@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKit

/// Coverage for all seek entry points funneling through the same coalescer
/// + generation guard, `skip(by:)` accumulating against `pendingSeekTime`
/// instead of live `currentTime`, and `seek(to:)` clamping to the playable
/// range.
@Suite("ABPlayer unifies its seek entry points and accumulates skips", .timeLimit(.minutes(3)))
@MainActor
struct ABSeekUnificationTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/seek.mp4")!)

    private func makePlayer(
        current: TimeInterval = 0,
        duration: TimeInterval? = 100,
        suspendedSeeks: Bool = false
    ) -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        target.currentTime = CMTime(seconds: current, preferredTimescale: 600)
        target.duration = duration.map { CMTime(seconds: $0, preferredTimescale: 600) }
        target.waitsForSeekContinuation = suspendedSeeks
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(prerollRate: nil, backgroundPolicy: .ignore),
            target: target
        )
        player.set(source: source, grade: .current)
        return (player, target)
    }

    @Test("Two skips issued before the first settles accumulate against pendingSeekTime, not live currentTime")
    func consecutiveSkipsAccumulateAgainstPendingSeekTime() async throws {
        let (player, target) = makePlayer(current: 0, suspendedSeeks: true)

        let first = Task { await player.skip(by: 20) }
        try await waitUntil { target.pendingSeekCount > 0 }
        #expect(player.pendingSeekTime == CMTime(seconds: 20, preferredTimescale: 600))

        let second = Task { await player.skip(by: 20) }
        try await waitUntil { player.pendingSeekTime == CMTime(seconds: 40, preferredTimescale: 600) }

        target.completeNextSeek()
        try await waitUntil { target.pendingSeekCount > 0 }
        target.completeNextSeek()
        await first.value
        await second.value

        #expect(target.calls.contains(.seek(CMTime(seconds: 40, preferredTimescale: 600), .precise)))
    }

    @Test("pendingSeekTime is set on request and cleared to nil once fully settled, broadcasting seekTargetChanged at exactly those two moments")
    func pendingSeekTimeLifecycleBroadcastsAtBothEdges() async throws {
        let (player, target) = makePlayer(current: 0, suspendedSeeks: true)
        var targets: [CMTime?] = []
        let token = player.addObserver { event in
            if case .seekTargetChanged(let time) = event { targets.append(time) }
        }
        defer { token.cancel() }

        let task = Task { await player.skip(by: 15) }
        try await waitUntil { target.pendingSeekCount > 0 }
        #expect(player.pendingSeekTime != nil)

        target.completeNextSeek()
        await task.value

        #expect(player.pendingSeekTime == nil)
        #expect(targets == [CMTime(seconds: 15, preferredTimescale: 600), nil])
    }

    @Test("seek(to:) clamps a destination beyond duration")
    func seekClampsBeyondDuration() async {
        let (player, target) = makePlayer(current: 0, duration: 100)

        await player.seek(to: CMTime(seconds: 500, preferredTimescale: 600))

        #expect(target.calls.contains(.seek(CMTime(seconds: 100, preferredTimescale: 600), .precise)))
    }

    @Test("seek(to:) clamps a negative destination to zero")
    func seekClampsNegativeToZero() async {
        let (player, target) = makePlayer(current: 50, duration: 100)

        await player.seek(to: CMTime(seconds: -10, preferredTimescale: 600))

        #expect(target.calls.contains(.seek(.zero, .precise)))
    }

    @Test("A stale out-of-session scrub seek does not broadcast .seekCompleted after a source replacement")
    func staleOutOfSessionScrubIsDiscardedAfterSourceReplacement() async throws {
        let (player, target) = makePlayer(suspendedSeeks: true)
        let staleDestination = CMTime(seconds: 25, preferredTimescale: 600)
        let replacement = ABMediaSource(url: URL(string: "https://example.com/replacement.mp4")!)
        var seekCompletions: [CMTime] = []
        let token = player.addObserver {
            if case .seekCompleted(let time) = $0 { seekCompletions.append(time) }
        }
        defer { token.cancel() }

        player.scrub(to: staleDestination)
        try await waitUntil { target.pendingSeekCount > 0 }

        player.set(source: replacement, grade: .current)
        target.completeNextSeek()
        for _ in 0..<10 { await Task.yield() }

        #expect(seekCompletions.isEmpty)
    }

    @Test("Five rapid out-of-session scrub taps coalesce to fewer than five target seeks")
    func outOfSessionScrubTapsCoalesce() async throws {
        let (player, target) = makePlayer(suspendedSeeks: true)

        player.scrub(to: CMTime(seconds: 10, preferredTimescale: 600))
        try await waitUntil { target.pendingSeekCount > 0 }
        for second in [20.0, 30.0, 40.0, 50.0] {
            player.scrub(to: CMTime(seconds: second, preferredTimescale: 600))
        }

        target.completeNextSeek()
        try await waitUntil { target.pendingSeekCount > 0 }
        target.completeNextSeek()
        for _ in 0..<10 { await Task.yield() }

        let seekCount = target.calls.filter { if case .seek = $0 { true } else { false } }.count
        #expect(seekCount < 5)
        #expect(target.calls.contains(.seek(CMTime(seconds: 50, preferredTimescale: 600), .scrubbing)))
    }

    @Test("skip(by:) during an active scrubbing session does not await settlement (shares the coalescer, never blocks on it)")
    func skipDuringScrubbingDoesNotAwaitSettlement() async throws {
        let (player, target) = makePlayer(suspendedSeeks: true)
        player.beginScrubbing()

        await player.skip(by: 5)

        // Must return without hanging even though the fake target never
        // completes the seek continuation — proves skip(by:) routed to the
        // fire-and-forget `scrub(to:)` path rather than `awaitSeekSettled`.
        try await waitUntil { target.pendingSeekCount > 0 }
        target.completeNextSeek()
        target.waitsForSeekContinuation = false
        await player.endScrubbing()
    }
}
