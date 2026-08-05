import Foundation
import Testing
@testable import ABPlayerKit

@Suite("Playback rate survives pause, resume, and grade round-trips", .timeLimit(.minutes(3)))
@MainActor
struct ABPlaybackRateEngineTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/rate.mp4")!)

    private func makePlayer() -> (ABPlayer, ABFakePlaybackTarget) {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(
            configuration: ABPlayerConfiguration(prerollRate: nil, backgroundPolicy: .ignore),
            target: target
        )
        return (player, target)
    }

    @Test("Given paused playback, setting rate stores it without issuing play")
    func settingRateWhilePausedDoesNotPlay() {
        let (player, target) = makePlayer()
        player.setRate(1.5)

        #expect(player.rate == 1.5)
        #expect(target.calls.contains(.setRate(1.5)))
        #expect(!target.calls.contains(.play))
    }

    @Test("Given active playback, setting rate applies it immediately")
    func settingRateWhilePlayingAppliesImmediately() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.play()

        player.setRate(2.0)

        #expect(target.appliedRate == 2.0)
    }

    @Test("Given configured rate, play starts at that rate")
    func playUsesConfiguredRate() {
        let target = ABFakePlaybackTarget()
        let configuration = ABPlayerConfiguration(
            playbackRate: 1.5,
            prerollRate: nil,
            backgroundPolicy: .ignore
        )
        let player = ABPlayer(configuration: configuration, target: target)
        player.set(source: source, grade: .current)

        player.play()

        #expect(target.appliedRate == 1.5)
    }

    @Test("Given custom rate, pause and resume preserve it")
    func pauseResumePreservesRate() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.setRate(1.5)
        player.play()

        player.pause()
        player.play()

        #expect(player.rate == 1.5)
        #expect(target.appliedRate == 1.5)
    }

    @Test("Given custom rate, grade demotion and promotion preserve it")
    func gradeRoundTripPreservesRate() {
        let (player, target) = makePlayer()
        player.set(source: source, grade: .current)
        player.setRate(1.5)
        player.play()

        player.promote(to: .preloaded)
        player.promote(to: .current)
        player.play()

        #expect(player.rate == 1.5)
        #expect(target.appliedRate == 1.5)
    }

    @Test("Given out-of-range rates, events carry their clamped values")
    func outOfRangeRatesClampAndBroadcast() {
        let (player, _) = makePlayer()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.setRate(0)
        player.setRate(99)

        #expect(events.contains(.rateChanged(ABPlaybackRate.allowedRange.lowerBound)))
        #expect(events.contains(.rateChanged(ABPlaybackRate.allowedRange.upperBound)))
    }

    @Test("Given the same effective rate, resetting it emits no event")
    func duplicateRateEmitsNothing() {
        let (player, _) = makePlayer()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.setRate(1.0)

        #expect(!events.contains { if case .rateChanged = $0 { true } else { false } })
    }

    @Test("Given a non-current grade, setting rate is not rejected")
    func nonCurrentRateIsAccepted() {
        let (player, _) = makePlayer()
        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.setRate(1.25)

        #expect(events.contains(.rateChanged(1.25)))
        #expect(!events.contains(.playbackRejected))
    }

    @Test("Given direct configuration assignment, rate follows the same clamped path")
    func configurationAssignmentUsesRatePath() {
        let (player, target) = makePlayer()

        player.configuration.playbackRate = -1

        #expect(player.rate == ABPlaybackRate.allowedRange.lowerBound)
        #expect(target.calls.contains(.setRate(ABPlaybackRate.allowedRange.lowerBound)))
    }
}
