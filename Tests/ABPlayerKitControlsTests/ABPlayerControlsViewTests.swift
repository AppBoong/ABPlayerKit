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

@Suite("Controls promote a non-current player to current on a play tap")
@MainActor
struct ABPlayerControlsPromotionTests {
    @Test("Given the default configuration, promotesToCurrentOnPlay is enabled")
    func defaultsToPromoting() {
        #expect(ABPlayerControlsConfiguration().promotesToCurrentOnPlay)
    }

    @Test("Given a source at a lower grade, play/pause stays tappable and promotes on tap")
    func playTapPromotesToCurrentByDefault() {
        let source = ABMediaSource(url: URL(string: "https://example.com/promote.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .preloaded)
        let view = ABPlayerControlsView()
        view.player = player

        #expect(view.controlsAreEnabled)

        view.playPauseButton.sendActions(for: .touchUpInside)

        #expect(player.grade == .current)
        #expect(player.isPlaying)
    }

    @Test("Given a source at a lower grade, seek/skip/rate stay disabled — only play/pause is promotion-eligible")
    func onlyPlayPauseIsPromotionEligible() {
        let source = ABMediaSource(url: URL(string: "https://example.com/only-play.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .preloaded)
        let view = ABPlayerControlsView()
        view.player = player

        #expect(view.controlsAreEnabled)
        #expect(!view.skipBackwardButton.isEnabled)
        #expect(!view.skipForwardButton.isEnabled)
        #expect(!view.rateButton.isEnabled)
        #expect(!view.seekBar.isEnabled)
    }

    @Test("Given promotesToCurrentOnPlay disabled, play/pause stays disabled below current, matching prior behavior")
    func playTapStaysDisabledWhenPromotionOptedOut() {
        let source = ABMediaSource(url: URL(string: "https://example.com/no-promote.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .preloaded)
        var configuration = ABPlayerControlsConfiguration()
        configuration.promotesToCurrentOnPlay = false
        let view = ABPlayerControlsView(configuration: configuration)
        view.player = player

        #expect(!view.controlsAreEnabled)
    }

    @Test("Given no source at all, play/pause stays disabled even with promotion enabled — nothing to promote to")
    func playTapStaysDisabledWithoutSource() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = player

        #expect(!view.controlsAreEnabled)
    }

    @Test("Given an item failure, play/pause is genuinely disabled, not promotion-eligible")
    func failureDisablesPlayPauseEvenWithASource() {
        let source = ABMediaSource(url: URL(string: "https://example.com/failed.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .preloaded)
        let view = ABPlayerControlsView()
        view.player = player
        #expect(view.controlsAreEnabled)

        view.handlePlayerEvent(.itemStatusChanged(.failed))

        #expect(!view.controlsAreEnabled)
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
    }

    @Test("Given .fixedHours, labels stay always-padded HH:MM:SS even under a minute — independent of ABTimeFormatter.string(from:)'s own (minimal M:SS) default")
    func fixedHoursStaysAlwaysPaddedEvenUnderAMinute() {
        let view = ABPlayerControlsView()

        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 5, preferredTimescale: 600),
            duration: CMTime(seconds: 30, preferredTimescale: 600),
            bufferedUntil: nil
        )))

        #expect(view.displayedElapsedText == "00:00:05/00:00:30")
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
        #expect(view.displayedElapsedText?.hasSuffix(ABTimeFormatter.liveMarker) == true)
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
    @Test("Given a video-sized overlay, the seek bar spans the full width and its visible track sits exactly 10pt above the bottom row")
    func releaseLayoutGeometry() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let transport = view.renderedTransportControlsFrame
        let seekBar = view.renderedSeekBarFrame
        let visibleTrack = view.renderedSeekBarVisibleTrackFrame
        let bottomRow = view.renderedBottomRowFrame
        let timeLabel = view.renderedTimeLabelFrame
        let rateButton = view.renderedRateButtonFrame
        let rateContent = view.renderedRateButtonVisibleContentFrame
        #expect(abs(transport.midX - view.bounds.midX) < 0.5)
        #expect(abs(transport.midY - view.bounds.midY) < 0.5)
        // The seek bar's touch-target row stays a full 44pt tall (HIG/a11y) and
        // spans the full overlay width with equal padding on both sides, even
        // though (below) its *visible track* sits much closer to the row below.
        #expect(abs(seekBar.height - 44) < 0.5)
        #expect(abs(seekBar.minX - view.style.contentInsets.leading) < 0.5)
        #expect(abs(seekBar.maxX - (view.bounds.maxX - view.style.contentInsets.trailing)) < 0.5)
        #expect(seekBar.midY > view.bounds.midY)
        #expect(visibleTrack.minY > seekBar.minY, "the visible track must be inset within the taller touch row, not flush with its top")
        #expect(view.style.seekBarBottomSpacing == 10)
        // The touch-row-to-touch-row gap is derived, not the literal 10pt:
        // seekBarBottomSpacing targets the gap between *visible ink*, not
        // between either side's touch frame, so the frames themselves sit
        // closer together than 10pt by the row's font-metric slack — see
        // `bottomRowVisibleContentSlack(for:)`. This asserts the touch-row
        // math is wired correctly; the true visible-ink-to-ink distance can
        // only be confirmed empirically (on-device pixel measurement — see
        // IMPL-v0.2-RESULT.md's VISUAL-GAP-FIXED/REVIEW2-FIXES-DONE entries),
        // since UILabel/UIButton report line-height-sized frames, not the
        // glyph ink's own bounds.
        //
        // The row's cross-axis height is whichever child is tallest: normally
        // `rateButtonSize.height`, but the (scaled) time-label font's own line
        // height once it exceeds that. The label's font is the *scaled* one
        // (`UIFontMetrics`, matching what `elapsedLabel` actually renders),
        // since at larger Dynamic Type sizes the unscaled style font
        // understates the real label height substantially. Slack per side is
        // derived from real font metrics (line height for centering, then
        // `ascender - capHeight` for the ink offset within the now-positioned
        // frame) rather than an empirical constant, so it never over-corrects
        // into a collision at an arbitrary font size — re-declared here (not
        // referenced) since the production helpers are private.
        func frameTopToInkTop(font: UIFont, centeredIn containerHeight: CGFloat) -> CGFloat {
            let centeringSlack = max(0, (containerHeight - font.lineHeight) / 2)
            let inkOffsetWithinFrame = max(0, font.ascender - font.capHeight)
            return centeringSlack + inkOffsetWithinFrame
        }
        let scaledElapsedFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: view.style.timeLabelFont,
            compatibleWith: view.traitCollection
        )
        let rowHeight = max(view.style.rateButtonSize.height, scaledElapsedFont.lineHeight)
        let elapsedContentSlack = frameTopToInkTop(font: scaledElapsedFont, centeredIn: rowHeight)
        let buttonHeight = view.style.rateButtonSize.height
        let buttonCenteringSlack = max(0, (rowHeight - buttonHeight) / 2)
        let rateContentSlack: CGFloat
        switch view.style.rateLabelStyle {
        case .text(let font, _):
            rateContentSlack = buttonCenteringSlack + frameTopToInkTop(font: font, centeredIn: buttonHeight)
        case .icon:
            rateContentSlack = buttonCenteringSlack + max(0, (buttonHeight - view.style.iconPointSize) / 2)
        }
        let expectedBottomRowSlack = min(elapsedContentSlack, rateContentSlack)
        #expect(abs((bottomRow.minY - visibleTrack.maxY) - (10 - expectedBottomRowSlack)) < 0.5)
        // Both visible glyphs sit somewhere inside the row's touch frame, below
        // the visible track — the exact ink-to-track distance is a rendering
        // detail unit tests can't observe, but this bounds them sanely.
        #expect(timeLabel.minY >= visibleTrack.maxY)
        #expect(rateContent.minY >= visibleTrack.maxY)
        #expect(bottomRow.minY < visibleTrack.maxY, "the bottom row's 44pt touch frame must extend upward past the visible gap to reach its centered content")
        // The row's touch frame sits at the very bottom of the overlay, inset
        // only by contentInsets.bottom — nothing floats below it.
        #expect(abs(view.bounds.maxY - view.style.contentInsets.bottom - bottomRow.maxY) < 0.5)
        // Time label sits below the visible track, flush with the seek bar's leading edge.
        #expect(abs(timeLabel.minX - seekBar.minX) < 0.5)
        // Rate button sits below the visible track, flush with the seek bar's trailing edge.
        #expect(abs(rateButton.maxX - seekBar.maxX) < 0.5)
    }

    @Test("Given an accessibility Dynamic Type trait collection, UIFontMetrics actually scales the time-label font")
    func dynamicTypeScalingIsReal() {
        // Sanity-checks the premise the next test relies on: at an
        // accessibility content size category, UIFontMetrics(.caption1) scales
        // the default 12pt timeLabelFont dramatically (on-device measurement
        // from the review this fixes: 12pt -> 38pt at AX3). If this ever stops
        // being true, the next test's simulated large font stops representing
        // a real scenario.
        let view = ABPlayerControlsView()
        let axTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)

        let scaledFont = view.scaledTimeLabelFont(for: view.style, compatibleWith: axTraits)

        #expect(scaledFont.pointSize > view.style.timeLabelFont.pointSize * 2)
    }

    @Test("Given a time-label font at accessibility Dynamic Type size, the rendered label does not collide with the seek bar track")
    func accessibilityDynamicTypeKeepsTimeLabelClearOfTrack() {
        // Simulates the rendered state UIFontMetrics produces at AX3 (see
        // dynamicTypeScalingIsReal) by assigning that scaled size directly,
        // sidestepping live UITraitCollection propagation to a detached test
        // view — unreliable in this test target without a real window/scene.
        // Live trait-change propagation on an actual device/simulator is
        // verified separately (see IMPL-v0.2-RESULT.md's REVIEW2-FIXES-DONE
        // entry for this fix).
        var style = ABPlayerControlsStyle()
        style.timeLabelFont = .monospacedDigitSystemFont(ofSize: 38, weight: .medium)
        let view = ABPlayerControlsView(style: style)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.layoutIfNeeded()

        #expect(view.elapsedLabel.font.pointSize >= 38)
        // The label growing taller than the rate button's fixed 44pt height
        // must grow the whole row to match (UIStackView never clips a
        // `.center`-aligned child) — otherwise this test isn't exercising the
        // row-growth case `bottomRowVisibleContentSlack(for:)` accounts for.
        #expect(view.renderedBottomRowFrame.height > view.style.rateButtonSize.height)

        let visibleTrack = view.renderedSeekBarVisibleTrackFrame
        let timeLabel = view.renderedTimeLabelFrame
        #expect(timeLabel.minY >= visibleTrack.maxY, "an accessibility-sized label must not grow up into the track above it")
    }

    @Test("Given a short overlay where the bottom cluster's touch row vertically overlaps the centered transport row, buttons still win hit testing over the seek bar")
    func bottomClusterOverlapFavorsButtonsOverSeekBar() {
        let view = ABPlayerControlsView()
        // 180pt, not the standard ~220pt (16:9-at-390pt-wide) demo overlay: the
        // extra negative spacing from compensating for the bottom row's visible-
        // glyph slack (on top of the seek-bar-track compensation) pushes the seek
        // bar down enough that it no longer overlaps the transport row at ~220pt.
        // A shorter overlay (a plausible aspect ratio for some embeds) still
        // produces real overlap, so this keeps the hit-test priority fix under
        // an active regression test rather than a permanently-vacuous one.
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 180)
        view.layoutIfNeeded()

        // Confirm the overlap this test guards against is real, not hypothetical:
        // the seek bar's 44pt touch row and the centered transport row's 44pt
        // touch row actually intersect at this overlay size.
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

    @Test("Given an enabled seek bar overlapping the bottom row, accessory views still win hit testing")
    func accessoryViewsWinHitTestingOverAnEnabledSeekBar() {
        // Deliberately does NOT use a player-less view: with no player, resetTimeline()
        // sets seekBar.isSeekEnabled = false, which turns off isUserInteractionEnabled
        // and pulls the seek bar out of hit testing entirely — a probe against that
        // setup would pass for the wrong reason (the seek bar never competes at all),
        // exactly the false-positive this suite's own review caught once already.
        let source = ABMediaSource(url: URL(string: "https://example.com/accessory-hit-test.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.player = player
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))

        let accessoryButton = UIButton(type: .custom)
        accessoryButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accessoryButton.widthAnchor.constraint(equalToConstant: 44),
            accessoryButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        view.accessoryViews = [accessoryButton]
        view.layoutIfNeeded()

        // Confirm the overlap this test guards against is real, not hypothetical
        // (this is the exact geometry the review reproduced its failure with).
        #expect(view.seekBar.isSeekEnabled)
        #expect(view.renderedSeekBarFrame.intersects(
            accessoryButton.convert(accessoryButton.bounds, to: view)
        ))

        let center = accessoryButton.convert(
            CGPoint(x: accessoryButton.bounds.midX, y: accessoryButton.bounds.midY),
            to: view
        )
        #expect(view.hitTest(center, with: nil) === accessoryButton)
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
