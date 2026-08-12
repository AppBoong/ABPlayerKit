import Foundation
import ABTestSupport
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for TTFF bookkeeping resetting on detach (no false cache hits
/// after release), and `.itemDetached` broadcasting only after the
/// target has actually detached — so observers reading `avPlayerItem`
/// inside the handler see `nil`, not the about-to-be-torn-down item.
@Suite("ABPlayer resets first-frame bookkeeping and orders detach before broadcast", .timeLimit(.minutes(3)))
@MainActor
struct ABDetachOrderingTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    private func makePlayer() -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore), target: target)
        return (player, target)
    }

    @Test("hasDisplayedFirstFrame resets to false on release()")
    func firstFrameResetsOnRelease() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        target.avPlayerItem = AVPlayerItem(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-ttff-fixture.mp4"))

        player.reportFirstFrameDisplayed(at: 1)
        #expect(player.hasDisplayedFirstFrame)

        player.release()

        #expect(!player.hasDisplayedFirstFrame)
    }

    @Test("hasDisplayedFirstFrame resets on demotion below .preloaded, not just full release")
    func firstFrameResetsOnDemotion() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        target.avPlayerItem = AVPlayerItem(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-ttff-fixture-2.mp4"))
        player.reportFirstFrameDisplayed(at: 1)
        #expect(player.hasDisplayedFirstFrame)

        player.set(source: source, grade: .instanceOnly)

        #expect(!player.hasDisplayedFirstFrame)
    }

    @Test("A report for a since-released item's identity does not re-arm after a fresh attach reuses the same reported-item slot")
    func firstFrameReportGuardsAgainstDoubleReportAfterReset() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        let firstItem = AVPlayerItem(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-ttff-fixture-3.mp4"))
        target.avPlayerItem = firstItem
        player.reportFirstFrameDisplayed(at: 1)
        #expect(player.hasDisplayedFirstFrame)

        player.release()
        player.set(source: source, grade: .current)
        let secondItem = AVPlayerItem(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-ttff-fixture-4.mp4"))
        target.avPlayerItem = secondItem

        // Before the fix, `reportedFirstFrameItem` stayed pointed at
        // `firstItem`'s identity forever, so a report against the new
        // item's genuinely-first frame would still be honored (identities
        // differ) — this specifically checks the reset happened, not that
        // reporting is broken.
        #expect(!player.hasDisplayedFirstFrame)
        player.reportFirstFrameDisplayed(at: 2)
        #expect(player.hasDisplayedFirstFrame)
    }

    @Test(".itemDetached broadcasts only after the target has already detached — avPlayerItem reads nil inside the handler")
    func itemDetachedBroadcastsAfterTargetDetach() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        target.avPlayerItem = AVPlayerItem(url: URL(fileURLWithPath: "/private/tmp/abplayerkit-detach-order-fixture.mp4"))

        var observedItemDuringDetach: AVPlayerItem??
        let token = player.addObserver { event in
            if case .itemDetached = event {
                observedItemDuringDetach = player.avPlayerItem
            }
        }
        defer { token.cancel() }

        player.release()

        #expect(observedItemDuringDetach != nil)
        #expect((observedItemDuringDetach ?? nil) == nil)
    }

    @Test("waitUntilReady resolves immediately for an item already at .readyToPlay, no timeout wait")
    func waitUntilReadyResolvesImmediatelyForAlreadyReadyItem() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
        let target = ABAVPlaybackTarget()
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        try await waitUntil { item.status == .readyToPlay }

        let clock = ContinuousClock()
        let start = clock.now
        let result = await target.waitUntilReady(item: item, timeout: 10)
        let elapsed = clock.now - start

        #expect(result == .ready)
        #expect(elapsed < .seconds(1))
        _ = avPlayer
    }
}
