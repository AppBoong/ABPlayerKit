@preconcurrency import AVFoundation
import ABPlayerKit
import Testing
@testable import ABPlayerKitControls

/// Coverage for `ABOwnedPlayerBox`, which backs `ABVideoPlayerWithControls`'s
/// `url:`/`source:` initializers' ownership.
@Suite("ABOwnedPlayerBox backs ABVideoPlayerWithControls's url:/source: initializers", .timeLimit(.minutes(3)))
@MainActor
struct ABOwnedPlayerBoxTests {
    private let url = URL(string: "https://example.com/owned-box-test.mp4")!

    private func ignoringBackground() -> ABPlayerConfiguration {
        ABPlayerConfiguration(backgroundPolicy: .ignore)
    }

    @Test("player(configuration:videoGravity:) creates exactly one player per box")
    func createsExactlyOnce() {
        let box = ABOwnedPlayerBox()
        let first = box.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        let second = box.player(configuration: ignoringBackground(), videoGravity: .resizeAspect)

        #expect(first === second)
    }

    @Test("A repeat apply(source:autoplay:) call with the same source doesn't resume a player the user paused")
    func applyIsIdempotent() async throws {
        let box = ABOwnedPlayerBox()
        let player = box.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        let source = ABMediaSource(url: url)

        box.apply(source: source, autoplay: true)
        try await waitUntil { player.isPlaying }

        player.pause()
        #expect(!player.isPlaying)

        box.apply(source: source, autoplay: true)

        #expect(!player.isPlaying)
    }

    @Test("releaseIfOwned is idempotent")
    func releaseIfOwnedIsIdempotent() {
        let box = ABOwnedPlayerBox()
        let player = box.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        box.apply(source: ABMediaSource(url: url), autoplay: false)

        box.releaseIfOwned()
        box.releaseIfOwned()

        #expect(player.grade == .released)
        #expect(player.source == nil)
    }

    @Test("releaseIfOwned is a no-op when the box never created a player")
    func releaseIfOwnedNoopWithoutPlayer() {
        let box = ABOwnedPlayerBox()
        box.releaseIfOwned()
        box.releaseIfOwned()
    }

    @Test("The box's own deinit releases the player when releaseIfOwned was never called")
    func deinitReleasesUnreleasedPlayer() async throws {
        let player: ABPlayer = {
            let box = ABOwnedPlayerBox()
            let player = box.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
            box.apply(source: ABMediaSource(url: url), autoplay: false)
            return player
        }()

        try await waitUntil { player.grade == .released }
    }
}
