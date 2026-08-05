@preconcurrency import AVFoundation
import ABPlayerKit
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls expose localized and stateful accessibility", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerControlsAccessibilityTests {
    @Test("Given bundled localizations, English and Korean control labels are available")
    func localizationsAreBundled() {
        #expect(ABControlsLocalization.string("controls.play", localization: "en") == "Play")
        #expect(ABControlsLocalization.string("controls.play", localization: "ko") == "재생")
        #expect(ABControlsLocalization.string("controls.rate", localization: "en") == "Playback Rate")
        #expect(ABControlsLocalization.string("controls.rate", localization: "ko") == "재생 속도")
    }

    @Test("Given playback state changes, the play button label follows its action")
    func playPauseLabelFollowsAction() {
        let view = ABPlayerControlsView()
        #expect(view.playPauseButton.accessibilityTraits.contains(.button))
        #expect(view.playPauseButton.accessibilityLabel == ABControlsLocalization.string("controls.play"))

        view.handlePlayerEvent(.timeControlStatusChanged(.playing))

        #expect(view.playPauseButton.accessibilityLabel == ABControlsLocalization.string("controls.pause"))
    }

    @Test("Given controls, every button has a localized label and button trait")
    func everyButtonIsLabeled() {
        let view = ABPlayerControlsView()

        for button in [view.playPauseButton, view.skipBackwardButton, view.skipForwardButton, view.rateButton] {
            #expect(button.accessibilityLabel?.isEmpty == false)
            #expect(button.accessibilityTraits.contains(.button))
        }
    }

    @Test("Given finite playback, the adjustable timeline describes and changes position")
    func timelineIsAdjustable() {
        let view = ABPlayerControlsView()
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 72, preferredTimescale: 600),
            duration: CMTime(seconds: 225, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        let originalValue = view.seekBar.accessibilityValue

        view.seekBar.accessibilityIncrement()

        #expect(view.seekBar.accessibilityTraits.contains(.adjustable))
        #expect(originalValue?.isEmpty == false)
        #expect(view.displayedElapsedText == "00:01:22/00:03:45")
    }

    @Test("Given a seekCompleted event lands after a periodicTime baseline, the presenter's own copy of the playback time stays in sync with the view's — a later accessibility adjustment computes from the fresh time, not a stale one (round4 review mn-2 regression)")
    func seekCompletedKeepsPresenterPlaybackTimeInSyncForAccessibilityAdjustment() {
        let view = ABPlayerControlsView()
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 10, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))

        // No player attached, so `player?.isScrubbing != true` is trivially
        // true and the seekCompleted branch proceeds; `duration` falls back
        // to the periodicTime baseline above since there's no live
        // `player?.duration` either.
        view.handlePlayerEvent(.seekCompleted(to: CMTime(seconds: 80, preferredTimescale: 600)))

        // `adjustTimelineForAccessibility` (triggered by accessibilityIncrement)
        // reads `ABControlsPresenter.currentPlaybackTime`, a copy separate
        // from the view's own — if `seekCompleted`'s `presenter.syncPlaybackTime(_:)`
        // call were ever dropped, this would still compute from the stale
        // 10s periodicTime baseline (10 + the default 10s skipInterval =
        // "00:00:20") instead of the fresh 80s the seek landed at.
        view.seekBar.accessibilityIncrement()

        #expect(view.displayedElapsedText == "00:01:30/00:02:00")
    }

    @Test("Given a rate change, its accessibility value reflects the multiplier")
    func rateValueUpdates() {
        let view = ABPlayerControlsView()

        view.handlePlayerEvent(.rateChanged(1.5))

        #expect(view.rateButton.accessibilityValue?.contains("1.5") == true)
    }

    @Test("Given VoiceOver is running, automatic hiding is suppressed")
    func voiceOverSuppressesAutoHide() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.autoHideDelay = 0.001
        let view = ABPlayerControlsView(configuration: configuration)
        view.isVoiceOverRunningProvider = { true }

        view.handleVisibility(.playbackStateChanged(isPlaying: true), animated: false)

        // `scheduleAutoHide` checks `isVoiceOverRunningProvider()`
        // synchronously before ever creating the hide `Task` — suppression
        // is observable immediately, with no `Task.sleep` needed to prove
        // it (round3 Phase1+2 review m6: the previous version slept 5ms
        // against a 1ms `autoHideDelay`, in conflict with WP8's "no
        // sleep-based waiting" rule, for a state change that was already
        // synchronous).
        #expect(view.isControlsVisible)
        #expect(!view.hasScheduledAutoHide)
    }

    @Test("Given Reduce Motion, animated visibility changes use zero duration")
    func reduceMotionRemovesFade() {
        let view = ABPlayerControlsView()
        view.isReduceMotionEnabledProvider = { true }

        view.setControlsVisible(false, animated: true)

        #expect(view.lastVisibilityAnimationDuration == 0)
        #expect(view.controlsContentAlpha == 0)
    }

    @Test("Given time labels, they participate in Dynamic Type scaling")
    func timeLabelsScale() {
        let view = ABPlayerControlsView()

        #expect(view.elapsedLabel.adjustsFontForContentSizeCategory)
    }
}
