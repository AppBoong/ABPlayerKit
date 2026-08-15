@preconcurrency import AVFoundation
import ABPlayerKit
import ABTestSupport
import Testing
@testable import ABPlayerKitControls

@Suite("ABControlsPresenter maps player-driven state into view-update effects, no UIView or ABPlayer required", .timeLimit(abScaledMinutes(3)))
struct ABControlsPresenterTests {
    // MARK: - attached / detached

    @Test("Given a player attaches at grade .current, controls are enabled with promotion allowed")
    func attachedAtCurrentGradeEnablesControls() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.attached(grade: .current)) == [
            .setEnabled(true, allowsPromotionTap: true)
        ])
    }

    @Test("Given a player attaches at a non-current grade, controls are disabled (but promotion tap stays allowed, matching the pre-extraction default argument)")
    func attachedAtNonCurrentGradeDisablesControls() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.attached(grade: .preloaded)) == [
            .setEnabled(false, allowsPromotionTap: true)
        ])
    }

    @Test("Given a player detaches, the timeline resets and playback time state clears")
    func detachedResetsTimeline() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 90, preferredTimescale: 600),
            bufferedUntil: nil
        ))))

        #expect(presenter.handle(.detached) == [.resetTimeline])
        #expect(presenter.currentPlaybackTime == .zero)
    }

    // MARK: - playerEvent: pure sub-cases

    @Test("Given a periodicTime event, the timeline renders and the internal playback time updates")
    func periodicTimeRendersAndTracksState() {
        var presenter = ABControlsPresenter()
        let time = ABPlaybackTime(
            currentTime: CMTime(seconds: 12, preferredTimescale: 600),
            duration: CMTime(seconds: 60, preferredTimescale: 600),
            bufferedUntil: nil
        )

        #expect(presenter.handle(.playerEvent(.periodicTime(time))) == [.renderTimeline(time)])
        #expect(presenter.currentPlaybackTime == time)
    }

    @Test("Given timeControlStatusChanged(.playing), the icon reflects playing and isPlaying tracks it")
    func timeControlStatusPlayingSetsIcon() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.timeControlStatusChanged(.playing))) == [
            .setPlaybackIcon(isPlaying: true)
        ])
        #expect(presenter.isPlaying)
    }

    @Test("Given timeControlStatusChanged(.paused), the icon reflects paused")
    func timeControlStatusPausedSetsIcon() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(.playing)))

        #expect(presenter.handle(.playerEvent(.timeControlStatusChanged(.paused))) == [
            .setPlaybackIcon(isPlaying: false)
        ])
        #expect(!presenter.isPlaying)
    }

    @Test("Given a rateChanged event, the rate title updates and the internal rate tracks it")
    func rateChangedUpdatesTitleAndState() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.rateChanged(1.5))) == [.setRateTitle(rate: 1.5)])
        #expect(presenter.rate == 1.5)
    }

    @Test("Given gradeChanged to .current, controls enable and the timeline is left alone")
    func gradeChangedToCurrentEnablesWithoutResetting() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.gradeChanged(from: .preloaded, to: .current))) == [
            .setEnabled(true, allowsPromotionTap: true)
        ])
    }

    @Test("Given gradeChanged away from .current, controls disable and the timeline resets, in that order")
    func gradeChangedAwayFromCurrentDisablesAndResets() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.gradeChanged(from: .current, to: .preloaded))) == [
            .setEnabled(false, allowsPromotionTap: true),
            .resetTimeline
        ])
        #expect(presenter.currentPlaybackTime == .zero)
    }

    @Test("Given itemDetached or sourceChanged, the timeline resets — the presenter contributes nothing else, since disabling controls needs a live player.grade read the view supplies separately")
    func itemDetachedAndSourceChangedOnlyResetTimeline() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.itemDetached(reason: .sourceChanged))) == [.resetTimeline])

        presenter = ABControlsPresenter()
        #expect(presenter.handle(.playerEvent(.sourceChanged(nil))) == [.resetTimeline])
    }

    @Test("Given itemStatusChanged(.readyToPlay) or seekCompleted, the presenter contributes no effects — both need a live ABPlayer read the view supplies directly")
    func readyToPlayAndSeekCompletedContributeNoEffects() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.itemStatusChanged(.readyToPlay))) == [])
        #expect(presenter.handle(.playerEvent(.seekCompleted(to: CMTime(seconds: 5, preferredTimescale: 600)))) == [])
    }

    @Test("Given itemStatusChanged(.unknown), no effect is produced")
    func unknownItemStatusProducesNoEffect() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.itemStatusChanged(.unknown))) == [])
    }

    @Test("Given itemStatusChanged(.failed) or .failed, controls disable and promotion tap is refused")
    func failureDisablesControlsWithoutPromotionTap() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.itemStatusChanged(.failed))) == [
            .setEnabled(false, allowsPromotionTap: false)
        ])

        presenter = ABControlsPresenter()
        #expect(presenter.handle(.playerEvent(.failed(.itemFailed(description: "boom")))) == [
            .setEnabled(false, allowsPromotionTap: false)
        ])
    }

    @Test("Given playedToEnd, the icon reflects paused and isPlaying clears")
    func playedToEndSetsIconToPaused() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(.playing)))

        #expect(presenter.handle(.playerEvent(.playedToEnd)) == [.setPlaybackIcon(isPlaying: false)])
        #expect(!presenter.isPlaying)
    }

    @Test("Given an event this presenter doesn't recognize, no effect is produced")
    func unrecognizedEventProducesNoEffect() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playerEvent(.preloadCancelled)) == [])
    }

    // MARK: - playPauseTapped (WP-A4b: command emission)

    @Test("Given a live-paused player and promotion allowed, a tap promotes then plays, in that order, and isPlaying flips immediately")
    func playPauseTappedWhilePausedWithPromotionSendsPromoteThenPlay() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playPauseTapped(isPlaying: false, allowsPromotionTap: true)) == [
            .send(.promoteToCurrent),
            .send(.play)
        ])
        #expect(presenter.isPlaying)
    }

    @Test("Given a live-paused player and promotion not allowed, a tap only plays")
    func playPauseTappedWhilePausedWithoutPromotionOnlySendsPlay() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.playPauseTapped(isPlaying: false, allowsPromotionTap: false)) == [.send(.play)])
        #expect(presenter.isPlaying)
    }

    @Test("Given a live-playing player, a tap only pauses (promotion is irrelevant once already playing) and isPlaying flips immediately")
    func playPauseTappedWhilePlayingSendsPause() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playPauseTapped(isPlaying: false, allowsPromotionTap: false))

        #expect(presenter.handle(.playPauseTapped(isPlaying: true, allowsPromotionTap: true)) == [.send(.pause)])
        #expect(!presenter.isPlaying)
    }

    @Test("Given the live isPlaying value disagrees with this presenter's own cached copy (buffering: player.isPlaying is true at .waitingToPlayAtSpecifiedRate, but the cache only tracks .playing), the tap follows the live value, not the cache — round4 review MJ-3 regression")
    func playPauseTappedFollowsLiveValueOverItsOwnCache() {
        var presenter = ABControlsPresenter()
        // Buffering: `.timeControlStatusChanged(.waitingToPlay)` never sets
        // `self.isPlaying = true` (only `.playing` does), so the cache reads
        // `false` here even though the live player is already playing
        // (rate≠0, not paused) while it buffers.
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(.waitingToPlay)))
        #expect(!presenter.isPlaying, "the cache must still read false — this is the premise of the divergence this test exercises")

        // A tap during that buffering window must pause (cancel buffering),
        // matching the pre-extraction `togglePlayback`'s `player.isPlaying`
        // branch — not promote+play, which is what branching on the stale
        // cached `false` would have produced.
        #expect(presenter.handle(.playPauseTapped(isPlaying: true, allowsPromotionTap: true)) == [.send(.pause)])
        #expect(!presenter.isPlaying)
    }

    // MARK: - skipTapped

    @Test("Given a skip tap, the interval is sent to the player verbatim")
    func skipTappedSendsSkipCommand() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.skipTapped(15)) == [.send(.skip(by: 15))])
    }

    // MARK: - rateSelected

    @Test("Given a rate selection within the allowed range, the rate is sent and the title updates, and the internal rate tracks it")
    func rateSelectedSendsAndTitles() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.rateSelected(1.5)) == [
            .send(.setRate(1.5)),
            .setRateTitle(rate: 1.5)
        ])
        #expect(presenter.rate == 1.5)
    }

    @Test("Given a rate selection outside the allowed range, it clamps before sending or updating state")
    func rateSelectedClampsOutOfRange() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.rateSelected(10)) == [
            .send(.setRate(ABPlaybackRate.allowedRange.upperBound)),
            .setRateTitle(rate: ABPlaybackRate.allowedRange.upperBound)
        ])
        #expect(presenter.rate == ABPlaybackRate.allowedRange.upperBound)
    }

    // MARK: - accessibilityAdjusted

    @Test("Given no duration, an accessibility adjustment produces no effect")
    func accessibilityAdjustedWithoutDurationProducesNoEffect() {
        var presenter = ABControlsPresenter()

        #expect(presenter.handle(.accessibilityAdjusted(direction: 1, skipInterval: 10)) == [])
    }

    @Test("Given zero direction, an accessibility adjustment produces no effect even with a known duration")
    func accessibilityAdjustedWithZeroDirectionProducesNoEffect() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 90, preferredTimescale: 600),
            bufferedUntil: nil
        ))))

        #expect(presenter.handle(.accessibilityAdjusted(direction: 0, skipInterval: 10)) == [])
    }

    @Test("Given a forward adjustment within range, the timeline renders the new target and the same delta is sent as a skip")
    func accessibilityAdjustedForwardWithinRange() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 90, preferredTimescale: 600),
            bufferedUntil: nil
        ))))

        let effects = presenter.handle(.accessibilityAdjusted(direction: 1, skipInterval: 10))

        guard case .renderTimeline(let time) = effects.first else {
            Issue.record("expected a .renderTimeline effect first, got \(effects)")
            return
        }
        #expect(abs(CMTimeGetSeconds(time.currentTime) - 40) < 0.01)
        #expect(effects.last == .send(.skip(by: 10)))
        #expect(presenter.currentPlaybackTime == time)
    }

    @Test("Given a backward adjustment past zero, the target clamps to zero rather than going negative")
    func accessibilityAdjustedBackwardClampsToZero() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 5, preferredTimescale: 600),
            duration: CMTime(seconds: 90, preferredTimescale: 600),
            bufferedUntil: nil
        ))))

        let effects = presenter.handle(.accessibilityAdjusted(direction: -1, skipInterval: 10))

        guard case .renderTimeline(let time) = effects.first else {
            Issue.record("expected a .renderTimeline effect first, got \(effects)")
            return
        }
        #expect(abs(CMTimeGetSeconds(time.currentTime) - 0) < 0.01)
    }

    @Test("Given a forward adjustment past the end, the target clamps to duration rather than overshooting")
    func accessibilityAdjustedForwardClampsToDuration() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 85, preferredTimescale: 600),
            duration: CMTime(seconds: 90, preferredTimescale: 600),
            bufferedUntil: nil
        ))))

        let effects = presenter.handle(.accessibilityAdjusted(direction: 1, skipInterval: 10))

        guard case .renderTimeline(let time) = effects.first else {
            Issue.record("expected a .renderTimeline effect first, got \(effects)")
            return
        }
        #expect(abs(CMTimeGetSeconds(time.currentTime) - 90) < 0.01)
    }

    // MARK: - seed

    @Test("Given a freshly attached, already-playing source, seed hydrates isPlaying/rate/currentPlaybackTime directly, without going through handle(_:)")
    func seedHydratesStateDirectly() {
        var presenter = ABControlsPresenter()
        let time = ABPlaybackTime(
            currentTime: CMTime(seconds: 12, preferredTimescale: 600),
            duration: CMTime(seconds: 34, preferredTimescale: 600),
            bufferedUntil: nil
        )

        presenter.seed(isPlaying: true, rate: 1.5, currentPlaybackTime: time)

        #expect(presenter.isPlaying)
        #expect(presenter.rate == 1.5)
        #expect(presenter.currentPlaybackTime == time)
    }
}

@Suite("ABControlsPresenter combines isPlaying/isBuffering into showsPauseIcon", .timeLimit(abScaledMinutes(3)))
struct ABControlsPresenterBufferingTests {
    @Test("Given isPlaying and isBuffering combinations arriving timeControlStatus-first, showsPauseIcon is their logical OR", arguments: [
        (false, false, false),
        (false, true, true),
        (true, false, true),
        (true, true, true)
    ])
    func showsPauseIconIsLogicalOr(isPlaying: Bool, isBuffering: Bool, expected: Bool) {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(isPlaying ? .playing : .paused)))
        _ = presenter.handle(.playerEvent(.bufferingChanged(isBuffering)))
        #expect(presenter.showsPauseIcon == expected)
    }

    @Test("Given the same combinations arriving bufferingChanged-first, showsPauseIcon is still their logical OR", arguments: [
        (false, false, false),
        (false, true, true),
        (true, false, true),
        (true, true, true)
    ])
    func showsPauseIconIsLogicalOrReverseOrder(isPlaying: Bool, isBuffering: Bool, expected: Bool) {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.bufferingChanged(isBuffering)))
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(isPlaying ? .playing : .paused)))
        #expect(presenter.showsPauseIcon == expected)
    }

    @Test("A bufferingChanged carrying the same value as the current state produces no effect")
    func duplicateBufferingChangedProducesNoEffect() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.bufferingChanged(true)))
        #expect(presenter.handle(.playerEvent(.bufferingChanged(true))) == [])
        _ = presenter.handle(.playerEvent(.bufferingChanged(false)))
        #expect(presenter.handle(.playerEvent(.bufferingChanged(false))) == [])
    }

    @Test("A bufferingChanged that actually changes the value emits setBuffering and setPlaybackIcon together")
    func bufferingChangeEmitsBothEffects() {
        var presenter = ABControlsPresenter()
        #expect(presenter.handle(.playerEvent(.bufferingChanged(true))) == [
            .setBuffering(true),
            .setPlaybackIcon(isPlaying: true)
        ])
    }

    @Test("Given waitingToPlay plus bufferingChanged(true), the icon still shows pause and a tap pauses (the default automaticallyWaitsToMinimizeStalling tuning)")
    func waitingToPlayWithBufferingShowsPauseIcon() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(.waitingToPlay)))
        _ = presenter.handle(.playerEvent(.bufferingChanged(true)))
        #expect(presenter.showsPauseIcon)
        #expect(presenter.handle(.playPauseTapped(isPlaying: true, allowsPromotionTap: true)) == [.send(.pause)])
    }

    @Test("automaticallyWaitsToMinimizeStalling == false variant: paused plus bufferingChanged(true) also shows the pause icon and a tap pauses")
    func pausedWithBufferingShowsPauseIcon() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(.paused)))
        _ = presenter.handle(.playerEvent(.bufferingChanged(true)))
        #expect(presenter.showsPauseIcon)
        #expect(presenter.handle(.playPauseTapped(isPlaying: true, allowsPromotionTap: true)) == [.send(.pause)])
    }

    @Test("Given a player detaches while buffering, the detach effect also clears buffering so the spinner/glyph suppression can't outlive the player")
    func detachWhileBufferingClearsBuffering() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.bufferingChanged(true)))
        #expect(presenter.handle(.detached) == [.resetTimeline, .setBuffering(false)])
        #expect(!presenter.isBuffering)
    }

    @Test("Given a player detaches while not buffering, detaching adds no extra effect beyond resetTimeline")
    func detachWhileNotBufferingAddsNoExtraEffect() {
        var presenter = ABControlsPresenter()
        #expect(presenter.handle(.detached) == [.resetTimeline])
    }
}

@Suite("ABControlsPresenter replays from the start after playedToEnd", .timeLimit(abScaledMinutes(3)))
struct ABControlsPresenterReplayTests {
    @Test("Given playedToEnd then a play tap with no promotion needed, the command is restartFromStart alone")
    func playedToEndThenTapRestartsWithoutPromotion() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))

        #expect(presenter.handle(.playPauseTapped(isPlaying: false, allowsPromotionTap: false)) == [.send(.restartFromStart)])
    }

    @Test("Given playedToEnd on a non-current source with promotion allowed, the tap promotes then restarts")
    func playedToEndThenTapPromotesAndRestarts() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))

        #expect(presenter.handle(.playPauseTapped(isPlaying: false, allowsPromotionTap: true)) == [
            .send(.promoteToCurrent),
            .send(.restartFromStart)
        ])
    }

    @Test("playedToEnd's own returned effect is still exactly one element — the replay flag is state, not an effect")
    func playedToEndReturnsExactlyOneEffect() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(.playing)))

        #expect(presenter.handle(.playerEvent(.playedToEnd)) == [.setPlaybackIcon(isPlaying: false)])
        #expect(presenter.hasPlayedToEnd)
    }

    @Test("A seekCompleted event after playedToEnd clears the replay flag — the next tap plays normally, and seekCompleted's own effect array stays empty")
    func seekCompletedClearsReplayFlag() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))

        #expect(presenter.handle(.playerEvent(.seekCompleted(to: .zero))) == [])
        #expect(!presenter.hasPlayedToEnd)
        #expect(presenter.handle(.playPauseTapped(isPlaying: false, allowsPromotionTap: false)) == [.send(.play)])
    }

    @Test("A sourceChanged event after playedToEnd clears the replay flag")
    func sourceChangedClearsReplayFlag() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))
        _ = presenter.handle(.playerEvent(.sourceChanged(nil)))

        #expect(!presenter.hasPlayedToEnd)
        #expect(presenter.handle(.playPauseTapped(isPlaying: false, allowsPromotionTap: false)) == [.send(.play)])
    }

    @Test("An itemDetached event after playedToEnd clears the replay flag")
    func itemDetachedClearsReplayFlag() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))
        _ = presenter.handle(.playerEvent(.itemDetached(reason: .sourceChanged)))

        #expect(!presenter.hasPlayedToEnd)
    }

    @Test("A timeControlStatusChanged(.playing) event after playedToEnd clears the replay flag")
    func resumedPlaybackClearsReplayFlag() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(.playing)))

        #expect(!presenter.hasPlayedToEnd)
    }

    @Test("timeControlStatusChanged(.paused)/.waitingToPlay after playedToEnd do NOT clear the replay flag — only .playing does")
    func nonPlayingStatusDoesNotClearReplayFlag() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))
        _ = presenter.handle(.playerEvent(.timeControlStatusChanged(.paused)))

        #expect(presenter.hasPlayedToEnd)
    }

    @Test("A .detached input after playedToEnd clears the replay flag")
    func detachedClearsReplayFlag() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))
        _ = presenter.handle(.detached)

        #expect(!presenter.hasPlayedToEnd)
    }

    @Test("A gradeChanged away from .current after playedToEnd clears the replay flag")
    func gradeChangedAwayFromCurrentClearsReplayFlag() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))
        _ = presenter.handle(.playerEvent(.gradeChanged(from: .current, to: .preloaded)))

        #expect(!presenter.hasPlayedToEnd)
    }

    @Test("A gradeChanged that lands on .current does not clear the replay flag — only leaving .current does")
    func gradeChangedToCurrentDoesNotClearReplayFlag() {
        var presenter = ABControlsPresenter()
        _ = presenter.handle(.playerEvent(.playedToEnd))
        _ = presenter.handle(.playerEvent(.gradeChanged(from: .preloaded, to: .current)))

        #expect(presenter.hasPlayedToEnd)
    }
}
