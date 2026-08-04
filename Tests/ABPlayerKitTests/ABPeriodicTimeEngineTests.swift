@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ABPlayerKit

@Suite("Periodic time observation is opt-in and pauses during scrubbing")
@MainActor
struct ABPeriodicTimeEngineTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/periodic.mp4")!)

    private func makePlayer(interval: TimeInterval? = nil) -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        target.duration = CMTime(seconds: 100, preferredTimescale: 600)
        target.bufferedUntil = CMTime(seconds: 60, preferredTimescale: 600)
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(
                periodicTimeInterval: interval,
                prerollRate: nil,
                backgroundPolicy: .ignore
            ),
            target: target
        )
        return (player, target)
    }

    @Test("Given no interval, promotion does not install an observer")
    func nilIntervalKeepsObservationDisabled() {
        let (player, target) = makePlayer()

        player.set(source: source, grade: .current)

        #expect(!target.calls.contains { $0 == .setPeriodicObserver(0.25) })
        #expect(target.calls.last(where: { if case .setPeriodicObserver = $0 { true } else { false } }) == .setPeriodicObserver(nil))
    }

    @Test("Given an interval, promotion installs its observer")
    func promotionInstallsObserver() {
        let (player, target) = makePlayer(interval: 0.25)

        player.set(source: source, grade: .current)

        #expect(target.calls.contains(.setPeriodicObserver(0.25)))
    }

    @Test("Given active scrubbing, ticks do not broadcast periodic events")
    func scrubbingGatesTicks() {
        let (player, target) = makePlayer(interval: 0.25)
        player.set(source: source, grade: .current)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }
        player.beginScrubbing()

        target.tick(CMTime(seconds: 10, preferredTimescale: 600))

        #expect(!events.contains { if case .periodicTime = $0 { true } else { false } })
    }

    @Test("Given scrubbing completion, final seek, false boundary, and immediate tick stay ordered")
    func scrubbingCompletionRestoresImmediateTickInOrder() async {
        let (player, _) = makePlayer(interval: 0.25)
        player.set(source: source, grade: .current)
        let destination = CMTime(seconds: 30, preferredTimescale: 600)
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }
        player.beginScrubbing()
        player.scrub(to: destination)

        await player.endScrubbing()

        let seekIndex = events.lastIndex(of: .seekCompleted(to: destination))
        let endIndex = events.lastIndex(of: .scrubbingChanged(isScrubbing: false))
        let tickIndex = events.lastIndex { if case .periodicTime = $0 { true } else { false } }
        #expect(seekIndex != nil && endIndex != nil && tickIndex != nil)
        #expect(seekIndex! < endIndex!)
        #expect(endIndex! < tickIndex!)
    }

    @Test("Given current playback, demotion removes the observer before lifecycle actions")
    func demotionRemovesObserver() {
        let (player, target) = makePlayer(interval: 0.25)
        player.set(source: source, grade: .current)
        let callCount = target.calls.count

        player.promote(to: .preloaded)

        let newCalls = Array(target.calls.dropFirst(callCount))
        #expect(newCalls.first == .setPeriodicObserver(nil))
    }

    @Test("Given current playback, release removes the observer before player release")
    func releaseRemovesObserverBeforePlayer() {
        let (player, target) = makePlayer(interval: 0.25)
        player.set(source: source, grade: .current)

        player.release()

        let removal = target.calls.lastIndex(of: .setPeriodicObserver(nil))
        let release = target.calls.lastIndex(of: .releasePlayer)
        #expect(removal != nil && release != nil)
        #expect(removal! < release!)
    }

    @Test("Given an installed observer, assigning nil removes it immediately")
    func nilConfigurationRemovesObserver() {
        let (player, target) = makePlayer(interval: 0.25)
        player.set(source: source, grade: .current)

        player.configuration.periodicTimeInterval = nil

        let lastObserverCall = target.calls.last { if case .setPeriodicObserver = $0 { true } else { false } }
        #expect(lastObserverCall == .setPeriodicObserver(nil))
    }

    @Test("Given source replacement, observation is reinstalled for the new item")
    func sourceReplacementReinstallsObserver() {
        let (player, target) = makePlayer(interval: 0.25)
        player.set(source: source, grade: .current)
        let callCount = target.calls.count
        let replacement = ABMediaSource(url: URL(string: "https://example.com/new.mp4")!)

        player.set(source: replacement, grade: .current)

        let newCalls = Array(target.calls.dropFirst(callCount))
        #expect(newCalls.contains(.setPeriodicObserver(nil)))
        #expect(newCalls.last == .setPeriodicObserver(0.25))
    }

    @Test("Given a tick, snapshot includes current, duration, and buffered range")
    func tickBroadcastsCompleteSnapshot() {
        let (player, target) = makePlayer(interval: 0.25)
        player.set(source: source, grade: .current)
        var snapshots: [ABPlaybackTime] = []
        let token = player.addObserver {
            if case .periodicTime(let time) = $0 { snapshots.append(time) }
        }
        defer { token.cancel() }
        let tick = CMTime(seconds: 20, preferredTimescale: 600)

        target.tick(tick)

        #expect(snapshots.last == ABPlaybackTime(
            currentTime: tick,
            duration: target.duration,
            bufferedUntil: target.bufferedUntil
        ))
    }
}
