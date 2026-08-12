@preconcurrency import AVFoundation
import ABPlayerKit
import Testing
@testable import ABPlayerKitControls

@Suite("Controls replay from the start after playback ends", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerControlsReplayTests {
    @Test("Given playback reaches the end, a play tap still goes through the usual tap side effects (bounce, broadcast) — the replay command doesn't short-circuit them")
    func playedToEndTapStillBouncesAndBroadcasts() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = player
        view.handlePlayerEvent(.playedToEnd)
        #expect(!view.isShowingPauseIcon)
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.playPauseButton.sendActions(for: .touchUpInside)

        #expect(view.lastPlayPauseBounceDuration != nil)
        #expect(events.contains { if case .playPauseTapped = $0 { true } else { false } })
    }

    @Test("Given a source change after playedToEnd, a later tap plays normally instead of replaying")
    func sourceChangedThenTapPlaysWithoutReplayFlag() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = player
        view.handlePlayerEvent(.playedToEnd)

        view.handlePlayerEvent(.sourceChanged(nil))

        #expect(!view.isShowingPauseIcon)
    }
}
