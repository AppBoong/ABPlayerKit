@preconcurrency import AVFoundation
import ABPlayerKit
import Foundation
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls attach and detach without leaking observation")
@MainActor
struct ABPlayerControlsAttachmentTests {
    @Test("Given attachment, controls install their configured periodic interval")
    func attachmentInstallsInterval() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()

        view.player = player

        #expect(player.configuration.periodicTimeInterval == 0.25)
    }

    @Test("Given detachment, controls restore the player's prior interval")
    func detachmentRestoresInterval() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(
            periodicTimeInterval: 1,
            backgroundPolicy: .ignore
        ))
        let view = ABPlayerControlsView()
        view.player = player

        view.player = nil

        #expect(player.configuration.periodicTimeInterval == 1)
    }

    @Test("Given player replacement, old-player events no longer update the view")
    func replacementStopsOldEvents() {
        let first = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let second = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = first
        view.player = second

        first.setRate(1.5)

        #expect(view.displayedRateText == "1×")
    }

    @Test("Given view deallocation, later player events do not retain or crash it")
    func deallocationCancelsObservation() async {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        weak var weakView: ABPlayerControlsView?
        autoreleasepool {
            let view = ABPlayerControlsView()
            view.player = player
            weakView = view
        }

        player.setRate(1.5)
        while player.configuration.periodicTimeInterval != nil {
            await Task.yield()
        }

        #expect(weakView == nil)
        #expect(player.configuration.periodicTimeInterval == nil)
    }

    @Test("Given accessory replacement, only the new arranged views remain")
    func accessoryReplacementCleansOldViews() {
        let view = ABPlayerControlsView()
        let old = UIView()
        let first = UIView()
        let second = UIView()
        view.accessoryViews = [old]

        view.accessoryViews = [first, second]

        #expect(view.accessoryViews == [first, second])
        #expect(old.superview == nil)
    }
}

@Suite("Controls reflect engine events")
@MainActor
struct ABPlayerControlsEventReflectionTests {
    @Test("Given finite playback, the timeline uses a combined fixed-hour label")
    func finitePlaybackUsesCombinedClockLabel() {
        let view = ABPlayerControlsView()

        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 83, preferredTimescale: 600),
            duration: CMTime(seconds: 600, preferredTimescale: 600),
            bufferedUntil: nil
        )))

        #expect(view.displayedElapsedText == "00:01:23/00:10:00")
        #expect(view.displayedDurationText == "00:10:00")
    }

    @Test("Given playing status, controls display the pause icon")
    func playingDisplaysPause() {
        let view = ABPlayerControlsView()

        view.handlePlayerEvent(.timeControlStatusChanged(.playing))

        #expect(view.displayedPlayPauseImage != nil)
        #expect(view.isShowingPauseIcon)
    }

    @Test("Given demotion, controls disable and reset the timeline")
    func demotionDisablesAndResets() {
        let view = ABPlayerControlsView()
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 50, preferredTimescale: 600),
            duration: CMTime(seconds: 100, preferredTimescale: 600),
            bufferedUntil: nil
        )))

        view.handlePlayerEvent(.gradeChanged(from: .current, to: .preloaded))

        #expect(!view.controlsAreEnabled)
        #expect(view.seekBar.progress == 0)
    }

    @Test("Given a rate event, controls display its multiplier")
    func rateEventUpdatesLabel() {
        let view = ABPlayerControlsView()

        view.handlePlayerEvent(.rateChanged(1.5))

        #expect(view.displayedRateText == "1.5×")
    }

    @Test("Given playback end, controls return to play and become visible")
    func playbackEndShowsPlayAndControls() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.initialVisibility = .hidden
        let view = ABPlayerControlsView(configuration: configuration)
        view.handlePlayerEvent(.timeControlStatusChanged(.playing))

        view.handlePlayerEvent(.playedToEnd)

        #expect(view.isControlsVisible)
        #expect(view.isUserInteractionEnabled)
    }

    @Test("Given indefinite duration, timeline is disabled and marked live")
    func indefiniteDurationShowsLive() {
        let view = ABPlayerControlsView()

        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: .zero,
            duration: .indefinite,
            bufferedUntil: nil
        )))

        #expect(!view.seekBar.isSeekEnabled)
        #expect(view.displayedDurationText == ABTimeFormatter.liveMarker)
    }

    @Test("Given duration disappears during scrubbing, controls always end the session")
    func missingDurationStillEndsScrubbing() async {
        let source = ABMediaSource(url: URL(string: "https://example.com/controls-scrub.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        var configuration = ABPlayerControlsConfiguration()
        configuration.staysVisibleWhilePaused = false
        let view = ABPlayerControlsView(configuration: configuration)
        view.player = player
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 20, preferredTimescale: 600),
            duration: CMTime(seconds: 100, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        view.handlePlayerEvent(.timeControlStatusChanged(.playing))
        var controlsEvents: [ABControlsEvent] = []
        let token = view.addObserver { controlsEvents.append($0) }
        defer { token.cancel() }
        view.seekBar.onScrubBegan?()
        #expect(player.isScrubbing)

        view.handlePlayerEvent(.sourceChanged(nil))
        view.seekBar.onScrubEnded?(0.5)
        while player.isScrubbing { await Task.yield() }

        #expect(controlsEvents.contains(.scrubbingChanged(isScrubbing: false)))
        #expect(!controlsEvents.contains { if case .seekCommitted = $0 { true } else { false } })
        #expect(view.hasScheduledAutoHide)
    }
}

@Suite("Controls follow the release overlay geometry")
@MainActor
struct ABPlayerControlsLayoutTests {
    @Test("Given a video-sized overlay, transport is centered and timeline controls hug the bottom")
    func releaseLayoutGeometry() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let transport = view.renderedTransportControlsFrame
        let seekBar = view.renderedSeekBarFrame
        let timeLabel = view.renderedTimeLabelFrame
        let rateButton = view.renderedRateButtonFrame
        #expect(abs(transport.midX - view.bounds.midX) < 0.5)
        #expect(abs(transport.midY - view.bounds.midY) < 0.5)
        #expect(abs(seekBar.height - 44) < 0.5)
        #expect(abs(seekBar.maxY - (view.bounds.maxY - view.style.contentInsets.bottom)) < 0.5)
        #expect(seekBar.midY > view.bounds.midY)
        #expect(abs(timeLabel.minX - seekBar.minX) < 0.5)
        #expect(timeLabel.maxY <= seekBar.minY)
        #expect(abs(rateButton.maxX - (view.bounds.maxX - view.style.contentInsets.trailing)) < 0.5)
        #expect(abs(rateButton.midY - seekBar.midY) < 0.5)
    }

    @Test("Given a hidden rate control, the timeline expands to the trailing margin")
    func hiddenRateExpandsTimeline() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateInteraction = .hidden
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)

        view.layoutIfNeeded()

        #expect(view.rateButton.isHidden)
        #expect(abs(
            view.renderedSeekBarFrame.maxX
                - (view.bounds.maxX - view.style.contentInsets.trailing)
        ) < 0.5)
    }

    @Test("Given visible controls, hit testing reaches every interactive control")
    func interactiveControlHitTesting() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))

        view.layoutIfNeeded()

        // Layout-only containers must never gate their visibly positioned controls.
        view.playPauseButton.superview?.isUserInteractionEnabled = false
        view.seekBar.superview?.isUserInteractionEnabled = false

        for control in [
            view.skipBackwardButton,
            view.playPauseButton,
            view.skipForwardButton,
            view.rateButton,
            view.seekBar
        ] {
            let center = control.convert(
                CGPoint(x: control.bounds.midX, y: control.bounds.midY),
                to: view
            )
            #expect(view.hitTest(center, with: nil) === control)
        }

        view.setControlsVisible(false, animated: false)
        #expect(view.hitTest(
            CGPoint(x: view.bounds.midX, y: view.bounds.midY),
            with: nil
        ) === view)
    }
}
