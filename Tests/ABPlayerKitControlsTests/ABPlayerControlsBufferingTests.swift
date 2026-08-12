@preconcurrency import AVFoundation
import ABPlayerKit
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls show a buffering spinner and suppress the play/pause glyph without disabling it", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerControlsBufferingTests {
    @Test("Given bufferingChanged(true), the spinner animates, the glyph is suppressed, but the button stays enabled and hit-testable at its own center")
    func bufferingShowsSpinnerAndSuppressesGlyph() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.layoutIfNeeded()
        let transportFrameBefore = view.renderedTransportControlsFrame

        view.handlePlayerEvent(.bufferingChanged(true))
        view.layoutIfNeeded()

        #expect(view.isBufferingIndicatorAnimating)
        #expect(view.displayedPlayPauseImage == nil)
        #expect(view.playPauseButton.isEnabled)
        let center = view.playPauseButton.convert(
            CGPoint(x: view.playPauseButton.bounds.midX, y: view.playPauseButton.bounds.midY),
            to: view
        )
        #expect(view.hitTest(center, with: nil) === view.playPauseButton)
        #expect(view.renderedTransportControlsFrame == transportFrameBefore)
    }

    @Test("Given the spinner starts, controlsContentView fading to 0 (auto-hide) does not hide the spinner — it's the only stall signal left once controls are hidden")
    func spinnerSurvivesControlsFadingOut() {
        let view = ABPlayerControlsView()
        view.handlePlayerEvent(.bufferingChanged(true))

        view.setControlsVisible(false, animated: false)

        #expect(view.controlsContentAlpha == 0)
        #expect(view.isBufferingIndicatorAnimating)
    }

    @Test("Given buffering ends, the spinner stops and the glyph returns")
    func bufferingEndingRestoresGlyph() {
        let view = ABPlayerControlsView()
        view.handlePlayerEvent(.bufferingChanged(true))

        view.handlePlayerEvent(.bufferingChanged(false))

        #expect(!view.isBufferingIndicatorAnimating)
        #expect(view.displayedPlayPauseImage != nil)
    }

    @Test("Given buffering starts while playing, auto-hide is suppressed, and does not fire until buffering ends")
    func bufferingSuppressesAutoHideUntilItEnds() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.autoHideDelay = 0.01
        let view = ABPlayerControlsView(configuration: configuration)
        view.handleVisibility(.playbackStateChanged(isPlaying: true), animated: false)
        #expect(view.hasScheduledAutoHide)

        view.handlePlayerEvent(.bufferingChanged(true))
        #expect(!view.hasScheduledAutoHide)

        view.handlePlayerEvent(.bufferingChanged(false))
        #expect(view.hasScheduledAutoHide)
    }

    @Test("Given buffering starts while controls are hidden, it does not force them visible")
    func bufferingDoesNotForceControlsVisible() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.initialVisibility = .hidden
        let view = ABPlayerControlsView(configuration: configuration)

        view.handlePlayerEvent(.bufferingChanged(true))

        #expect(!view.isControlsVisible)
        #expect(view.isBufferingIndicatorAnimating)
    }

    @Test("Given waitingToPlay plus bufferingChanged(true), the icon still shows pause, not the reverted play icon")
    func waitingToPlayWithBufferingShowsPauseIcon() {
        let view = ABPlayerControlsView()

        view.handlePlayerEvent(.timeControlStatusChanged(.waitingToPlay))
        view.handlePlayerEvent(.bufferingChanged(true))

        #expect(view.isShowingPauseIcon)
        #expect(view.playPauseButton.accessibilityLabel == ABControlsLocalization.string("controls.pause"))
    }

    @Test("Given a genuinely playing player starts buffering, a tap still sends pause — the live isPlaying || isBuffering value, not a stale cache")
    func liveBufferingPlayerTapSendsPause() {
        let source = ABMediaSource(url: URL(string: "https://example.com/buffering-live.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        player.play()
        let view = ABPlayerControlsView()
        view.player = player
        #expect(player.isPlaying)

        view.playPauseButton.sendActions(for: .touchUpInside)

        #expect(!player.isPlaying)
    }

    @Test("Given showsBufferingIndicator is false, buffering neither shows the spinner nor suppresses the glyph")
    func disabledBufferingIndicatorSuppressesNothing() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.showsBufferingIndicator = false
        let view = ABPlayerControlsView(configuration: configuration)

        view.handlePlayerEvent(.bufferingChanged(true))

        #expect(!view.isBufferingIndicatorAnimating)
        #expect(view.displayedPlayPauseImage != nil)
    }

    @Test("Given showsBufferingIndicator flips to false mid-stall, the spinner stops and the glyph is restored immediately")
    func disablingIndicatorMidStallRestoresGlyph() {
        var configuration = ABPlayerControlsConfiguration()
        let view = ABPlayerControlsView(configuration: configuration)
        view.handlePlayerEvent(.bufferingChanged(true))
        #expect(view.isBufferingIndicatorAnimating)

        configuration.showsBufferingIndicator = false
        view.configuration = configuration

        #expect(!view.isBufferingIndicatorAnimating)
        #expect(view.displayedPlayPauseImage != nil)
    }

    @Test("Given a player is detached while buffering, the spinner stops and the glyph is restored — it cannot outlive the player")
    func detachingPlayerWhileBufferingStopsSpinner() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = player
        view.handlePlayerEvent(.bufferingChanged(true))
        #expect(view.isBufferingIndicatorAnimating)

        view.player = nil

        #expect(!view.isBufferingIndicatorAnimating)
        #expect(view.displayedPlayPauseImage != nil)
    }
}
