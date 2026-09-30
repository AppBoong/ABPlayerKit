import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit

@Suite("load(_:autoplay:) is an idempotent attach-and-play", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPlayerLoadTests {
    private let first = ABMediaSource(url: URL(string: "https://example.com/first.mp4")!)
    private let second = ABMediaSource(url: URL(string: "https://example.com/second.mp4")!)

    private func makePlayer() -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(backgroundPolicy: .ignore),
            target: target
        )
        return (player, target)
    }

    private func attachCount(_ target: ABFakePlaybackTarget) -> Int {
        target.calls.filter { if case .attachItem = $0 { true } else { false } }.count
    }

    @Test("Loading attaches the source at .current and starts playback")
    func loadAttachesAndPlays() {
        let (player, target) = makePlayer()

        player.load(first)

        #expect(player.source == first)
        #expect(player.grade == .current)
        #expect(attachCount(target) == 1)
        #expect(target.calls.last == .play)
    }

    @Test("autoplay: false attaches without playing")
    func loadWithoutAutoplay() {
        let (player, target) = makePlayer()

        player.load(first, autoplay: false)

        #expect(player.grade == .current)
        #expect(!target.calls.contains(.play))
    }

    @Test("Loading the same source again neither re-attaches nor resumes a paused player")
    func repeatLoadIsNoOp() {
        let (player, target) = makePlayer()
        player.load(first)
        player.pause()
        let callsBeforeRepeat = target.calls.count

        player.load(first)

        #expect(target.calls.count == callsBeforeRepeat)
        #expect(attachCount(target) == 1)
    }

    @Test("A different source replaces the current one")
    func differentSourceReplaces() {
        let (player, target) = makePlayer()
        player.load(first)

        player.load(second)

        #expect(player.source == second)
        #expect(attachCount(target) == 2)
    }

    @Test("A released player loads the same source again")
    func reloadAfterRelease() {
        let (player, target) = makePlayer()
        player.load(first)
        player.release()

        player.load(first)

        #expect(player.grade == .current)
        #expect(attachCount(target) == 2)
    }

    @Test("A player demoted below .current is promoted back by load")
    func reloadAfterDemotion() {
        let (player, _) = makePlayer()
        player.load(first)
        player.promote(to: .preloaded)

        player.load(first, autoplay: false)

        #expect(player.grade == .current)
    }
}
