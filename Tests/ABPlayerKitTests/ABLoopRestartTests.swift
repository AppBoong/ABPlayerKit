import Foundation
import ABTestSupport
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for looping actually resuming playback: `actionAtItemEnd`
/// defaults to `.pause`, so `isLooping`'s restart seek used to leave
/// `rate == 0` at the head of the item forever.
@Suite("ABAVPlaybackTarget resumes playback after a looped end-of-item", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABLoopRestartTests {
    private func makeAttachedTarget() throws -> (ABAVPlaybackTarget, AVPlayerItem) {
        let target = ABAVPlaybackTarget()
        target.makePlayer()
        let url = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
        let source = ABMediaSource(url: url)
        target.attachItem(source, tuning: .unrestricted, assetFactory: ABDefaultAssetFactory())
        let item = try #require(target.avPlayerItem)
        return (target, item)
    }

    @Test("setLooping(true) sets actionAtItemEnd to .none")
    func loopingSetsActionAtItemEndToNone() throws {
        let (target, _) = try makeAttachedTarget()

        target.setLooping(true)

        #expect(target.avPlayer?.actionAtItemEnd == AVPlayer.ActionAtItemEnd.none)
    }

    @Test("setLooping(false) sets actionAtItemEnd to .pause")
    func notLoopingSetsActionAtItemEndToPause() throws {
        let (target, _) = try makeAttachedTarget()

        target.setLooping(false)

        #expect(target.avPlayer?.actionAtItemEnd == .pause)
    }

    @Test("A looped end-of-item resumes playback")
    func loopedEndOfItemResumesPlayback() async throws {
        let (target, item) = try makeAttachedTarget()
        target.setLooping(true)
        target.play()

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)

        try await waitUntil { target.isPlaying }
    }

    @Test("A non-looped end-of-item does not resume playback")
    func nonLoopedEndOfItemDoesNotResumePlayback() async throws {
        let (target, item) = try makeAttachedTarget()
        target.setLooping(false)
        target.play()
        target.pause()

        var events: [ABTargetEvent] = []
        target.onEvent = { events.append($0) }
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)

        try await waitUntil { events.contains(.playedToEnd) }
        for _ in 0..<10 { await Task.yield() }

        #expect(!target.isPlaying)
    }

    @Test(".playedToEnd broadcasts exactly once per end-of-item, before the loop restart begins")
    func playedToEndBroadcastsOnceBeforeLoopRestart() async throws {
        let (target, item) = try makeAttachedTarget()
        target.setLooping(true)
        // Deliberately never calls `target.play()`: once the manually
        // posted notification below reaches the restart branch,
        // `didPlayToEnd` itself calls `avPlayer?.play()` — real playback
        // would then genuinely reach the end of `tiny.mp4` on its own and
        // repost this same notification for real, for as long as looping
        // stays enabled. This invariant is about `.playedToEnd` ordering
        // and count for a single end-of-item, not about resumed playback
        // (covered separately by `loopedEndOfItemResumesPlayback`), so
        // real playback never needs to start at all.

        var events: [ABTargetEvent] = []
        target.onEvent = { [weak target] event in
            events.append(event)
            // Bounds this test to exactly one end-of-item: `didPlayToEnd`
            // checks `self.isLooping` synchronously right after this
            // callback returns, with no `await` in between, so disabling
            // looping here lands before that check and short-circuits the
            // restart (including its own `play()` call) before it can run.
            if event == .playedToEnd {
                target?.setLooping(false)
            }
        }
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)

        try await waitUntil { events.contains(.playedToEnd) }
        // A bounded drain: if the restart branch ran anyway (the guard
        // above failed to short-circuit it), a stray second broadcast
        // would show up here instead of racing the assertion below.
        for _ in 0..<10 { await Task.yield() }

        #expect(events.filter { $0 == .playedToEnd }.count == 1)
    }
}

/// The target restarts a looping item itself (seek to start + `play()`),
/// without going through `ABPlayer.play()`. If `.playedToEnd` cleared the
/// play intent anyway, every loop after the first would read as "not
/// trying to play", and `ABBufferingEvaluator` would never report a stall
/// again: no spinner, no QoE buffering interval.
@Suite("A looping player keeps its play intent across the loop point", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABLoopPlayIntentTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/loop.mp4")!)

    private func playThroughEnd(looping: Bool) -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        // `ABBufferingEvaluator` reports nothing without an item.
        target.avPlayerItem = AVPlayerItem(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-loop-intent-fixture.mp4"))
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(isLooping: looping, backgroundPolicy: .ignore),
            target: target
        )
        player.load(source)
        target.emit(.playedToEnd)
        return (player, target)
    }

    @Test("After a loop, a stall is still reported as buffering")
    func loopingKeepsBufferingDetection() {
        let (player, target) = playThroughEnd(looping: true)

        target.timeControlStatus = .waitingToPlay
        target.emit(.timeControlStatusChanged(.waitingToPlay))

        #expect(player.isBuffering)
    }

    @Test("Without looping, reaching the end still clears the play intent")
    func nonLoopingClearsIntent() {
        let (player, target) = playThroughEnd(looping: false)

        target.timeControlStatus = .waitingToPlay
        target.emit(.timeControlStatusChanged(.waitingToPlay))

        #expect(!player.isBuffering)
    }
}
