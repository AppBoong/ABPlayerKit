import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for looping actually resuming playback: `actionAtItemEnd`
/// defaults to `.pause`, so `isLooping`'s restart seek used to leave
/// `rate == 0` at the head of the item forever.
@Suite("ABAVPlaybackTarget resumes playback after a looped end-of-item", .timeLimit(.minutes(3)))
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

    @Test(".playedToEnd broadcasts even for a looped item, exactly once")
    func playedToEndBroadcastsOnceForLoopedItem() async throws {
        let (target, item) = try makeAttachedTarget()
        target.setLooping(true)
        target.play()

        var events: [ABTargetEvent] = []
        target.onEvent = { events.append($0) }
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)

        try await waitUntil { events.contains(.playedToEnd) }
        try await waitUntil { target.isPlaying }
        #expect(events.filter { $0 == .playedToEnd }.count == 1)
    }
}
