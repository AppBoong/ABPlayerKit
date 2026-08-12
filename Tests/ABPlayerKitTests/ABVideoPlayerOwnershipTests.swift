@preconcurrency import AVFoundation
import ABTestSupport
import Testing
@testable import ABPlayerKit

/// Coverage for `ABVideoPlayer`'s `url:`/`source:` convenience
/// initializers — the owned player is created and released through
/// `Coordinator`, so these tests drive that type directly (via
/// `makeCoordinator()`) rather than through `makeUIView`/`updateUIView`,
/// which need a `UIViewRepresentableContext` SwiftUI alone can construct.
/// `dismantleUIView(_:coordinator:)` takes no such context and is called
/// directly, exactly as SwiftUI itself would.
@Suite("ABVideoPlayer's url:/source: initializers own their player for the view's SwiftUI identity", .timeLimit(.minutes(3)))
@MainActor
struct ABVideoPlayerOwnershipTests {
    private func tinyURL() throws -> URL {
        try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
    }

    private func ignoringBackground() -> ABPlayerConfiguration {
        ABPlayerConfiguration(backgroundPolicy: .ignore)
    }

    @Test("Mounting the url: initializer attaches a player carrying the requested source at .current")
    func mountsWithSourceAtCurrent() throws {
        let url = try tinyURL()
        let coordinator = ABVideoPlayer(url: url, autoplay: false).makeCoordinator()

        let player = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        coordinator.apply(source: ABMediaSource(url: url), autoplay: false)
        let view = ABPlayerView()
        view.player = player

        #expect(view.player?.source?.url == url)
        #expect(view.player?.grade == .current)
    }

    @Test("autoplay: true starts playback; autoplay: false reaches .current without playing")
    func autoplayControlsPlaybackStart() async throws {
        let url = try tinyURL()

        let autoplayCoordinator = ABVideoPlayer(url: url).makeCoordinator()
        let autoplayPlayer = autoplayCoordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        autoplayCoordinator.apply(source: ABMediaSource(url: url), autoplay: true)
        try await waitUntil { autoplayPlayer.isPlaying }

        let pausedCoordinator = ABVideoPlayer(url: url).makeCoordinator()
        let pausedPlayer = pausedCoordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        pausedCoordinator.apply(source: ABMediaSource(url: url), autoplay: false)

        #expect(pausedPlayer.grade == .current)
        #expect(!pausedPlayer.isPlaying)
    }

    @Test("Repeated calls (mirroring updateUIView on unrelated SwiftUI passes) reuse the same player instance")
    func repeatedUpdatesReuseInstance() throws {
        let url = try tinyURL()
        let coordinator = ABVideoPlayer(url: url).makeCoordinator()

        let first = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        coordinator.apply(source: ABMediaSource(url: url), autoplay: false)
        let second = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        coordinator.apply(source: ABMediaSource(url: url), autoplay: false)

        #expect(first === second)
    }

    @Test("Pausing the owned player and reapplying the same source afterward doesn't resume it")
    func pauseSurvivesRepeatedApply() async throws {
        let url = try tinyURL()
        let coordinator = ABVideoPlayer(url: url).makeCoordinator()
        let player = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        coordinator.apply(source: ABMediaSource(url: url), autoplay: true)
        try await waitUntil { player.isPlaying }

        player.pause()
        #expect(!player.isPlaying)

        coordinator.apply(source: ABMediaSource(url: url), autoplay: true)

        #expect(!player.isPlaying)
    }

    @Test("Changing url reuses the same player instance, updates the applied source, and re-applies autoplay")
    func urlChangeReusesInstanceAndReapplies() async throws {
        let firstURL = try tinyURL()
        let coordinator = ABVideoPlayer(url: firstURL).makeCoordinator()
        let player = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        coordinator.apply(source: ABMediaSource(url: firstURL), autoplay: false)

        let secondSource = ABMediaSource(url: URL(string: "https://example.com/second.mp4")!)
        coordinator.apply(source: secondSource, autoplay: true)

        #expect(player.source == secondSource)
        try await waitUntil { player.isPlaying }
    }

    @Test("dismantleUIView releases an owned player synchronously")
    func dismantleReleasesOwnedPlayer() throws {
        let url = try tinyURL()
        let coordinator = ABVideoPlayer(url: url, autoplay: false).makeCoordinator()
        let player = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        coordinator.apply(source: ABMediaSource(url: url), autoplay: false)
        let view = ABPlayerView()
        view.player = player

        ABVideoPlayer.dismantleUIView(view, coordinator: coordinator)

        #expect(player.grade == .released)
        #expect(player.source == nil)
    }

    @Test("dismantleUIView on the explicit player: initializer never releases the caller's player")
    func explicitOwnershipNeverReleases() throws {
        let url = try tinyURL()
        let player = ABPlayer(configuration: ignoringBackground())
        player.set(source: ABMediaSource(url: url), grade: .current)
        let coordinator = ABVideoPlayer(player: player).makeCoordinator()
        let view = ABPlayerView()
        view.player = player

        ABVideoPlayer.dismantleUIView(view, coordinator: coordinator)

        #expect(player.grade == .current)
    }

    @Test("Calling dismantleUIView twice is harmless — the second call is a no-op")
    func doubleDismantleIsHarmless() throws {
        let url = try tinyURL()
        let coordinator = ABVideoPlayer(url: url, autoplay: false).makeCoordinator()
        let player = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        coordinator.apply(source: ABMediaSource(url: url), autoplay: false)
        let view = ABPlayerView()
        view.player = player

        ABVideoPlayer.dismantleUIView(view, coordinator: coordinator)
        ABVideoPlayer.dismantleUIView(view, coordinator: coordinator)

        #expect(player.grade == .released)
        #expect(player.source == nil)
    }

    @Test("When dismantleUIView never runs, the coordinator's own deinit still releases the player")
    func deinitReleasesWhenDismantleNeverRuns() async throws {
        let url = try tinyURL()
        let player: ABPlayer = {
            let coordinator = ABVideoPlayer(url: url, autoplay: false).makeCoordinator()
            let player = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
            coordinator.apply(source: ABMediaSource(url: url), autoplay: false)
            return player
        }()

        try await waitUntil { player.grade == .released }
    }

    @Test("The source: initializer preserves an explicit kind and httpHeaders through to the owned player")
    func sourceInitializerPreservesKindAndHeaders() throws {
        let source = ABMediaSource(
            url: URL(string: "https://example.com/no-extension-asset")!,
            kind: .hls,
            httpHeaders: ["Authorization": "Bearer test"]
        )
        let coordinator = ABVideoPlayer(source: source, autoplay: false).makeCoordinator()
        let player = coordinator.player(configuration: ignoringBackground(), videoGravity: .resizeAspectFill)
        coordinator.apply(source: source, autoplay: false)

        #expect(player.source?.kind == .hls)
        #expect(player.source?.httpHeaders == ["Authorization": "Bearer test"])
    }
}
