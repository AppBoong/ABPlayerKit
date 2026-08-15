@preconcurrency import AVFoundation
import ABPlayerKit
import ABTestSupport
import Testing
@testable import ABPlayerKitControls

/// Coverage for `ABOwnedPlayerBox`, which backs `ABVideoPlayerWithControls`'s
/// `url:`/`source:` initializers' ownership.
@Suite("ABOwnedPlayerBox backs ABVideoPlayerWithControls's url:/source: initializers", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABOwnedPlayerBoxTests {
    // A nonexistent *local* file, not a remote host: `AVPlayer.play()` sets
    // `rate` synchronously regardless of the underlying item's validity
    // (so `isPlaying` still flips as these tests need), but a missing local
    // file fails fast. An unreachable remote host instead leaves a real
    // `AVPlayer` retrying DNS/connection with no timeout of its own for the
    // rest of the test run, competing for CPU with every other suite.
    private let url = URL(fileURLWithPath: "/private/tmp/abplayerkit-owned-box-test-\(UUID().uuidString).mp4")

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
