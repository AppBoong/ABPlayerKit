import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit
@testable import ABPlayerKitNowPlaying
@preconcurrency import AVFoundation

/// Coverage for `ABNowPlayingCenter`'s wiring — ownership acquisition
/// against a real `ABPlayer` (backed by a fake target, never real
/// `AVFoundation`/`MediaPlayer`): no surface contact before the first
/// attach, no touch while unowned, and no republish from periodic ticks —
/// all held end to end through a fake `ABNowPlayingSurface`.
@Suite("ABNowPlayingCenter bridges ABPlayer lifecycle to a Now Playing surface", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABNowPlayingCenterTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    private func makePlayer(duration: CMTime? = nil) -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        target.duration = duration
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(periodicTimeInterval: 1, backgroundPolicy: .ignore),
            target: target
        )
        return (player, target)
    }

    @Test("Before any attach, the surface is never touched (R6)")
    func noSurfaceContactBeforeAttach() {
        let surface = ABFakeNowPlayingSurface()
        _ = ABNowPlayingCenter(surface: surface)

        #expect(surface.calls.isEmpty)
    }

    @Test("Promoting a fresh attachment to .current publishes and installs commands, without touching a surface it isn't the owner of yet")
    func promotingToCurrentAcquiresAndPublishes() {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        let (player, _) = makePlayer(duration: CMTime(seconds: 120, preferredTimescale: 600))

        let token = center.attach(player, metadata: ABNowPlayingMetadata(title: "Title"))
        #expect(surface.calls.isEmpty, "attaching a .released player must not touch the surface")

        player.set(source: source, grade: .current)

        #expect(center.owner == player.id)
        // Two legitimate triggers land in this one promotion — ownership
        // acquisition itself, then `durationAvailable` once
        // `ABPlayer.duration` catches up — so `>= 1` is the correct bound
        // here, not an exact count (see the periodic-tick test below for
        // the invariant this test doesn't cover: that nothing *extra*
        // fires from ticks alone).
        #expect(surface.setInfoCallCount >= 1)
        _ = token
    }

    @Test("nextTrack requested without a handler is disabled and never installs a handler")
    func nextTrackWithoutHandlerIsDisabledWithNoHandler() {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        let (player, _) = makePlayer()

        let token = center.attach(
            player,
            metadata: ABNowPlayingMetadata(title: "Title"),
            configuration: ABNowPlayingConfiguration(commands: [.nextTrack])
        )
        player.set(source: source, grade: .current)

        guard case .setCommand(.nextTrack, let enabled, let hasHandler)? = surface.calls.last(where: {
            if case .setCommand(.nextTrack, _, _) = $0 { return true }
            return false
        }) else {
            Issue.record("Expected a .setCommand(.nextTrack, ...) call")
            return
        }
        #expect(!enabled)
        #expect(!hasHandler)
        #expect(surface.trigger(.nextTrack, intent: .nextTrack) == nil)
        _ = token
    }

    @Test("Providing a next handler afterward re-installs nextTrack as enabled")
    func settingNextHandlerAfterAttachEnablesNextTrack() {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        let (player, _) = makePlayer()

        let token = center.attach(
            player,
            metadata: ABNowPlayingMetadata(title: "Title"),
            configuration: ABNowPlayingConfiguration(commands: [.nextTrack])
        )
        player.set(source: source, grade: .current)

        center.setTrackNavigationHandlers(next: {}, previous: nil, for: player)

        let enabled = surface.enablement[.nextTrack]
        #expect(enabled == true)
        #expect(surface.trigger(.nextTrack, intent: .nextTrack) == .perform(.nextTrack))
        _ = token
    }

    @Test("An infinite/unknown duration disables changePlaybackPosition")
    func unknownDurationDisablesChangePlaybackPosition() {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        let (player, _) = makePlayer(duration: nil)

        let token = center.attach(player, metadata: ABNowPlayingMetadata(title: "Title"))
        player.set(source: source, grade: .current)

        #expect(surface.enablement[.changePlaybackPosition] == false)
        _ = token
    }

    @Test("A finite duration enables changePlaybackPosition")
    func finiteDurationEnablesChangePlaybackPosition() {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        let (player, _) = makePlayer(duration: CMTime(seconds: 120, preferredTimescale: 600))

        let token = center.attach(player, metadata: ABNowPlayingMetadata(title: "Title"))
        player.set(source: source, grade: .current)

        #expect(surface.enablement[.changePlaybackPosition] == true)
        _ = token
    }

    @Test("R5: the last token cancelling restores the pre-seeded snapshot")
    func lastTokenCancellingRestoresSnapshot() {
        let surface = ABFakeNowPlayingSurface()
        surface.preSeededInfo = ["preexisting": "value"]
        surface.preSeededCommandEnablement = [.play: true, .pause: false]
        let center = ABNowPlayingCenter(surface: surface)
        let (player, _) = makePlayer()

        let token = center.attach(player, metadata: ABNowPlayingMetadata(title: "Title"))
        player.set(source: source, grade: .current)
        #expect(center.owner == player.id)

        token.cancel()

        #expect(center.owner == nil)
        guard case .setInfo(let restored)? = surface.calls.last(where: {
            if case .setInfo = $0 { return true }
            return false
        }) else {
            Issue.record("Expected a final .setInfo restoring the snapshot")
            return
        }
        #expect(restored["preexisting"] == "value")
        #expect(surface.enablement[.play] == true)
        #expect(surface.enablement[.pause] == false)
    }

    @Test("Discarding the returned token detaches immediately")
    func discardingTheTokenDetachesImmediately() {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        let (player, _) = makePlayer()
        player.set(source: source, grade: .current)

        // No local binding retains the token returned here — it deinits at
        // the end of this statement, which cancels it before the next line
        // ever runs.
        _ = center.attach(player, metadata: ABNowPlayingMetadata(title: "Title"))

        #expect(center.owner == nil)
    }

    @Test("Periodic time ticks never trigger an extra publish")
    func periodicTimeNeverTriggersExtraPublish() {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        let (player, target) = makePlayer(duration: CMTime(seconds: 120, preferredTimescale: 600))

        let token = center.attach(player, metadata: ABNowPlayingMetadata(title: "Title"))
        // Attaching the item at `.preloaded` first (rather than jumping
        // straight from `.released` to `.current`) settles duration
        // availability before ownership is ever acquired, so promoting
        // afterward fires exactly one legitimate publish trigger
        // (`.gradeChanged`) instead of two.
        player.set(source: source, grade: .preloaded)
        player.promote(to: .current)
        let countAfterAcquisition = surface.setInfoCallCount
        #expect(countAfterAcquisition == 1)

        for tick in 0..<100 {
            target.tick(CMTime(seconds: Double(tick), preferredTimescale: 600))
        }

        #expect(surface.setInfoCallCount == countAfterAcquisition)
        _ = token
    }

    @Test("A deallocated participant is reconciled the next time owner is read")
    func deallocatedParticipantIsReconciled() async throws {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        var player: ABPlayer? = makePlayer().0
        let token = center.attach(player!, metadata: ABNowPlayingMetadata(title: "Title"))
        player!.set(source: source, grade: .current)
        #expect(center.owner == player!.id)

        player = nil

        try await waitUntil { center.owner == nil }
        _ = token
    }

    @Test("Two-player LIFO acquires B over A and A auto-returns once B detaches")
    func twoPlayerLIFOAutoReturns() {
        let surface = ABFakeNowPlayingSurface()
        let center = ABNowPlayingCenter(surface: surface)
        let (playerA, _) = makePlayer()
        let (playerB, _) = makePlayer()

        let tokenA = center.attach(playerA, metadata: ABNowPlayingMetadata(title: "A"))
        playerA.set(source: source, grade: .current)
        #expect(center.owner == playerA.id)

        let tokenB = center.attach(playerB, metadata: ABNowPlayingMetadata(title: "B"))
        playerB.set(source: source, grade: .current)
        #expect(center.owner == playerB.id)

        tokenB.cancel()

        #expect(center.owner == playerA.id)
        _ = tokenA
    }
}
