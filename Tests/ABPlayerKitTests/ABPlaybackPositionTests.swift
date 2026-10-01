import ABTestSupport
@preconcurrency import AVFoundation
import Foundation
import Observation
import Testing
@testable import ABPlayerKit

@Suite("ABPlayer.position is an observable, opt-in playback position", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPlaybackPositionTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/position.mp4")!)

    private func makePlayer(
        _ configuration: ABPlayerConfiguration = ABPlayerConfiguration(backgroundPolicy: .ignore)
    ) -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: configuration, target: target)
        return (player, target)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: 600)
    }

    /// The interval of the most recent `setPeriodicTimeObserver` call.
    private func lastPeriodicCall(_ target: ABFakePlaybackTarget) -> ABFakePlaybackTarget.Call? {
        target.calls.last { if case .setPeriodicObserver = $0 { true } else { false } }
    }

    /// Records whether anything read inside `read` was invalidated.
    private final class InvalidationFlag: @unchecked Sendable {
        var fired = false
    }

    private func track(_ read: () -> Void) -> InvalidationFlag {
        let flag = InvalidationFlag()
        withObservationTracking(read) { flag.fired = true }
        return flag
    }

    @Test("A player whose position is never read installs no periodic observer")
    func noObserverUntilRead() {
        let (player, target) = makePlayer()

        player.load(source)

        #expect(!target.calls.contains { if case .setPeriodicObserver(.some) = $0 { true } else { false } })
    }

    @Test("Reading position installs the periodic observer at positionUpdateInterval")
    func readingInstallsObserver() {
        let (player, target) = makePlayer()
        player.load(source)

        _ = player.position

        #expect(lastPeriodicCall(target) == .setPeriodicObserver(0.25))
    }

    @Test("The observer runs at the finer of periodicTimeInterval and positionUpdateInterval")
    func finerIntervalWins() {
        var configuration = ABPlayerConfiguration(backgroundPolicy: .ignore)
        configuration.periodicTimeInterval = 1
        configuration.positionUpdateInterval = 0.1
        let (player, target) = makePlayer(configuration)
        player.load(source)
        #expect(lastPeriodicCall(target) == .setPeriodicObserver(1))

        _ = player.position

        #expect(lastPeriodicCall(target) == .setPeriodicObserver(0.1))
    }

    @Test("A tick updates position without broadcasting .periodicTime when no event interval is configured")
    func tickUpdatesPositionOnly() {
        let (player, target) = makePlayer()
        player.load(source)
        let position = player.position
        var periodicEvents = 0
        let token = player.addObserver { event in
            if case .periodicTime = event { periodicEvents += 1 }
        }
        defer { token.cancel() }

        target.tick(seconds(3))

        #expect(position.time.currentTime == seconds(3))
        #expect(periodicEvents == 0)
    }

    @Test("A tick invalidates views reading position, and not views reading the player's own state")
    func tickInvalidatesOnlyPositionReaders() {
        let (player, target) = makePlayer()
        player.load(source)
        let position = player.position

        let positionReader = track { _ = position.time }
        let playerStateReader = track {
            _ = player.isPlaying
            _ = player.grade
            _ = player.isBuffering
            _ = player.duration
        }
        target.tick(seconds(1))

        #expect(positionReader.fired)
        #expect(!playerStateReader.fired)
    }

    @Test("A tick at the same time doesn't invalidate, so a paused player never re-renders its readers")
    func repeatedTimeDoesNotInvalidate() {
        let (player, target) = makePlayer()
        player.load(source)
        let position = player.position
        target.tick(seconds(2))

        let reader = track { _ = position.time }
        target.tick(seconds(2))

        #expect(!reader.fired)
    }

    @Test("Releasing the player resets the position and stops the observer")
    func releaseResetsPosition() {
        let (player, target) = makePlayer()
        player.load(source)
        let position = player.position
        target.tick(seconds(5))

        target.currentTime = .zero
        player.release()

        #expect(position.time.currentTime == .zero)
        #expect(lastPeriodicCall(target) == .setPeriodicObserver(nil))
    }

    @Test("position is one object per player")
    func positionIsStable() {
        let (player, _) = makePlayer()

        #expect(player.position === player.position)
    }
}
