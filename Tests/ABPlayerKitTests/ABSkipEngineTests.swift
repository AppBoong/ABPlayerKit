@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKit

@Suite("Skip clamps to the playable range")
@MainActor
struct ABSkipEngineTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/skip.mp4")!)

    private func makePlayer(
        current: TimeInterval,
        duration: TimeInterval?
    ) -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        target.currentTime = CMTime(seconds: current, preferredTimescale: 600)
        target.duration = duration.map { CMTime(seconds: $0, preferredTimescale: 600) }
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(prerollRate: nil, backgroundPolicy: .ignore),
            target: target
        )
        player.set(source: source, grade: .current)
        return (player, target)
    }

    @Test("Given room ahead, forward skip adds its interval")
    func forwardSkipAddsInterval() async {
        let (player, target) = makePlayer(current: 20, duration: 100)

        await player.skip(by: 10)

        #expect(target.calls.contains(.seek(CMTime(seconds: 30, preferredTimescale: 600), .precise)))
    }

    @Test("Given playback near the end, forward skip clamps to duration")
    func forwardSkipClampsAtEnd() async {
        let (player, target) = makePlayer(current: 95, duration: 100)

        await player.skip(by: 10)

        #expect(target.calls.contains(.seek(CMTime(seconds: 100, preferredTimescale: 600), .precise)))
    }

    @Test("Given playback near the start, backward skip clamps to zero")
    func backwardSkipClampsAtStart() async {
        let (player, target) = makePlayer(current: 5, duration: 100)

        await player.skip(by: -10)

        #expect(target.calls.contains(.seek(.zero, .precise)))
    }

    @Test("Given live playback, forward skip has no upper clamp")
    func liveForwardSkipHasNoUpperClamp() async {
        let (player, target) = makePlayer(current: 95, duration: nil)

        await player.skip(by: 10)

        #expect(target.calls.contains(.seek(CMTime(seconds: 105, preferredTimescale: 600), .precise)))
    }

    @Test("Given live playback, backward skip still clamps to zero")
    func liveBackwardSkipClampsAtStart() async {
        let (player, target) = makePlayer(current: 5, duration: nil)

        await player.skip(by: -10)

        #expect(target.calls.contains(.seek(.zero, .precise)))
    }

    @Test("Given a non-current grade, skip emits rejection and does not seek")
    func nonCurrentSkipIsRejected() async {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .ignore),
            target: target
        )
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        await player.skip(by: 10)

        #expect(events.contains(.playbackRejected))
        #expect(!target.calls.contains { if case .seek = $0 { true } else { false } })
    }

    @Test("Given the v0.1 seek API, it remains a precise seek")
    func legacySeekRemainsPrecise() async {
        let (player, target) = makePlayer(current: 0, duration: 100)
        let destination = CMTime(seconds: 42, preferredTimescale: 600)

        await player.seek(to: destination)

        #expect(target.calls.contains(.seek(destination, .precise)))
    }
}
