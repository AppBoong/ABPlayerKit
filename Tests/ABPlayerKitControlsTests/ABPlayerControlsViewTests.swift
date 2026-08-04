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

    @Test("Given a fresh controls view over a fresh player, the rate label always starts at 1×")
    func freshAttachmentShowsDefaultRate() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()

        view.player = player

        #expect(player.rate == 1)
        #expect(view.displayedRateText == "1×")
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

    @Test("Given automatic time format, labels use MM:SS under an hour and add hours once the duration reaches one")
    func automaticTimeFormatAdaptsToDuration() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.timeFormat = .automatic
        let view = ABPlayerControlsView(configuration: configuration)

        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 83, preferredTimescale: 600),
            duration: CMTime(seconds: 300, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        #expect(view.displayedElapsedText == "01:23/05:00")

        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 83, preferredTimescale: 600),
            duration: CMTime(seconds: 4_000, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        #expect(view.displayedElapsedText == "00:01:23/01:06:40")
    }

    @Test("Given a custom time format, its formatter receives elapsed seconds and duration seconds")
    func customTimeFormatReceivesSecondsAndDuration() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.timeFormat = .custom { seconds, duration in
            "\(Int(seconds))s/\(duration.map { "\(Int($0))s" } ?? "?")"
        }
        let view = ABPlayerControlsView(configuration: configuration)

        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 12, preferredTimescale: 600),
            duration: CMTime(seconds: 90, preferredTimescale: 600),
            bufferedUntil: nil
        )))

        #expect(view.displayedElapsedText == "12s/90s/90s/90s")
    }

    @Test("Given playing status, controls display the pause icon")
    func playingDisplaysPause() {
        let view = ABPlayerControlsView()

        view.handlePlayerEvent(.timeControlStatusChanged(.playing))

        #expect(view.displayedPlayPauseImage != nil)
        #expect(view.isShowingPauseIcon)
    }

    @Test("Given a play/pause tap, the button bounces quickly")
    func playPauseTapBounces() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = player

        view.playPauseButton.sendActions(for: .touchUpInside)

        #expect(view.lastPlayPauseBounceDuration != nil)
        #expect((view.lastPlayPauseBounceDuration ?? 1) < 0.35)
        #expect(view.playPauseButton.layer.animation(forKey: "abplayerkit.playPauseBounce") != nil)
    }

    @Test("Given Reduce Motion enabled, the play/pause bounce is skipped")
    func playPauseBounceSkippedForReduceMotion() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.isReduceMotionEnabledProvider = { true }
        view.player = player

        view.playPauseButton.sendActions(for: .touchUpInside)

        #expect(view.lastPlayPauseBounceDuration == nil)
        #expect(view.playPauseButton.layer.animation(forKey: "abplayerkit.playPauseBounce") == nil)
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
    @Test("Given a video-sized overlay, the seek bar spans the full width and the bottom cluster hugs the overlay's bottom edge")
    func releaseLayoutGeometry() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let transport = view.renderedTransportControlsFrame
        let seekBar = view.renderedSeekBarFrame
        let bottomRow = view.renderedBottomRowFrame
        let timeLabel = view.renderedTimeLabelFrame
        let rateButton = view.renderedRateButtonFrame
        #expect(abs(transport.midX - view.bounds.midX) < 0.5)
        #expect(abs(transport.midY - view.bounds.midY) < 0.5)
        #expect(abs(seekBar.height - 44) < 0.5)
        // Seek bar spans the full overlay width with equal padding on both sides.
        #expect(abs(seekBar.minX - view.style.contentInsets.leading) < 0.5)
        #expect(abs(seekBar.maxX - (view.bounds.maxX - view.style.contentInsets.trailing)) < 0.5)
        #expect(seekBar.midY > view.bounds.midY)
        // The default spacing between the seek bar and the row below it is pinned
        // to exactly 10pt — a regression test for the default value itself, not
        // just for whatever `style.seekBarBottomSpacing` happens to be set to.
        #expect(view.style.seekBarBottomSpacing == 10)
        #expect(abs(bottomRow.minY - seekBar.maxY - 10) < 0.5)
        // The row (time label + rate button) sits at the very bottom of the
        // overlay, inset only by contentInsets.bottom — nothing floats below it.
        #expect(abs(view.bounds.maxY - view.style.contentInsets.bottom - bottomRow.maxY) < 0.5)
        // The whole cluster (seek bar + 10pt gap + row) hugs the bottom edge: its
        // total height accounts for every point between the seek bar's top and
        // the overlay's bottom margin — no extra slack anywhere in the cluster.
        let clusterHeight = view.bounds.maxY - view.style.contentInsets.bottom - seekBar.minY
        #expect(abs(clusterHeight - (seekBar.height + 10 + bottomRow.height)) < 0.5)
        // Time label sits below the bar, flush with its leading edge.
        #expect(abs(timeLabel.minX - seekBar.minX) < 0.5)
        #expect(timeLabel.minY >= seekBar.maxY)
        // Rate button sits below the bar, flush with its trailing edge.
        #expect(abs(rateButton.maxX - seekBar.maxX) < 0.5)
        #expect(rateButton.minY >= seekBar.maxY)
    }

    @Test("Given a short overlay where the bottom cluster's touch row vertically overlaps the centered transport row, buttons still win hit testing over the seek bar")
    func bottomClusterOverlapFavorsButtonsOverSeekBar() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.layoutIfNeeded()

        // Confirm the overlap this test guards against is real, not hypothetical:
        // the seek bar's 44pt touch row and the centered transport row's 44pt
        // touch row actually intersect at this (realistic, 16:9-at-390pt-wide)
        // overlay size.
        let seekBar = view.renderedSeekBarFrame
        let transport = view.renderedTransportControlsFrame
        #expect(seekBar.intersects(transport))

        for control in [view.playPauseButton, view.skipForwardButton, view.skipBackwardButton] {
            let center = control.convert(
                CGPoint(x: control.bounds.midX, y: control.bounds.midY),
                to: view
            )
            #expect(view.hitTest(center, with: nil) === control)
        }
    }

    @Test("Given a hidden rate control, the seek bar still spans the full width and the row below collapses")
    func hiddenRateKeepsFullWidthSeekBar() {
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
        #expect(abs(
            view.renderedSeekBarFrame.minX
                - view.style.contentInsets.leading
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

    @Test("Given a touch that resolves to a control (or a descendant of one), the background-tap recognizer must refuse it")
    func backgroundTapRecognizerRefusesControlTouches() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.layoutIfNeeded()

        for control in [
            view.playPauseButton,
            view.skipBackwardButton,
            view.skipForwardButton,
            view.rateButton,
            view.seekBar
        ] {
            #expect(!ABPlayerControlsView.backgroundTapShouldReceiveTouch(on: control, upTo: view))
        }

        // A real touch's `touch.view` can resolve to a control's internal subview
        // (e.g. a UIButton's title/image view) rather than the control itself —
        // the walk up to `root` must still find the ancestor UIControl and refuse.
        let imageView = view.playPauseButton.imageView
        #expect(imageView != nil)
        if let imageView {
            #expect(!ABPlayerControlsView.backgroundTapShouldReceiveTouch(on: imageView, upTo: view))
        }

        // Plain layout containers and the view itself are not controls — the
        // background tap must still fire for taps on genuinely empty space.
        #expect(ABPlayerControlsView.backgroundTapShouldReceiveTouch(on: view.seekBar.superview, upTo: view))
        #expect(ABPlayerControlsView.backgroundTapShouldReceiveTouch(on: view, upTo: view))
        #expect(ABPlayerControlsView.backgroundTapShouldReceiveTouch(on: nil, upTo: view))
    }
}
