@preconcurrency import AVFoundation
import ABPlayerKit
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls show a cumulative seek badge driven only by seekTargetChanged, never accumulating deltas themselves", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerControlsSeekFeedbackTests {
    private func baselinedView(currentSeconds: Double = 30, durationSeconds: Double = 120) -> ABPlayerControlsView {
        let view = ABPlayerControlsView()
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: currentSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        return view
    }

    @Test("Given a first seekTargetChanged, the badge shows the delta from the pre-streak baseline")
    func firstSeekTargetShowsDeltaFromBaseline() {
        let view = baselinedView(currentSeconds: 30)

        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 40, preferredTimescale: 600)))

        #expect(view.isSeekFeedbackVisible)
        #expect(view.seekFeedbackText == "+10s")
    }

    @Test("Given a second seekTargetChanged before settling, the badge accumulates from the same anchor — not from the intermediate target")
    func secondSeekTargetBeforeSettlingAccumulatesFromTheSameAnchor() {
        let view = baselinedView(currentSeconds: 30)
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 40, preferredTimescale: 600)))

        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 50, preferredTimescale: 600)))

        #expect(view.seekFeedbackText == "+20s")
    }

    @Test("Given seekTargetChanged(nil), the badge dismisses and the anchor is discarded")
    func nilSeekTargetDismissesAndDiscardsAnchor() {
        let view = baselinedView(currentSeconds: 30)
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 40, preferredTimescale: 600)))

        view.handlePlayerEvent(.seekTargetChanged(nil))

        #expect(!view.isSeekFeedbackVisible)
    }

    @Test("Given a fresh streak starts after the anchor was discarded, the delta is computed from a freshly re-snapshotted anchor, not the old one")
    func freshStreakAfterDismissalReSnapshotsTheAnchor() {
        let view = baselinedView(currentSeconds: 30)
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 40, preferredTimescale: 600)))
        view.handlePlayerEvent(.seekTargetChanged(nil))
        // The settle also rendered the timeline to the last target (40s, via
        // the shared render(_:) path) — the next streak's anchor must be
        // re-snapshotted from *that*, not the original 30s baseline.
        #expect(view.displayedElapsedText?.hasPrefix("00:00:40") == true)

        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 50, preferredTimescale: 600)))

        #expect(view.seekFeedbackText == "+10s")
    }

    @Test("Given an active scrubbing session, seekTargetChanged is ignored entirely — the seek bar owns position feedback while scrubbing")
    func seekTargetChangedIgnoredWhileScrubbing() {
        let source = ABMediaSource(url: URL(string: "https://example.com/seek-feedback-scrub.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        let view = baselinedView(currentSeconds: 30)
        view.player = player
        view.seekBar.onScrubBegan?()
        #expect(player.isScrubbing)
        let elapsedTextBefore = view.displayedElapsedText

        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 999, preferredTimescale: 600)))

        #expect(!view.isSeekFeedbackVisible)
        #expect(view.displayedElapsedText == elapsedTextBefore)
    }

    @Test("A skip tap's resulting seekTargetChanged moves the seek bar's progress optimistically, before the seek settles")
    func skipTappedSeekTargetMovesProgressOptimistically() {
        let view = baselinedView(currentSeconds: 30, durationSeconds: 120)
        let progressBefore = view.seekBar.progress

        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 40, preferredTimescale: 600)))

        #expect(view.seekBar.progress > progressBefore)
        #expect(abs(view.seekBar.progress - (40.0 / 120.0)) < 0.01)
    }

    @Test("Given a lone durationAvailable event, the seek bar enables without waiting for the next periodic tick")
    func durationAvailableAloneEnablesSeekBar() {
        let source = ABMediaSource(url: URL(string: "https://example.com/duration-available.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        let view = ABPlayerControlsView()
        view.player = player
        #expect(!view.seekBar.isSeekEnabled)

        view.handlePlayerEvent(.durationAvailable(CMTime(seconds: 90, preferredTimescale: 600)))

        #expect(view.seekBar.isSeekEnabled)
    }

    @Test("Given two VoiceOver adjustments, the displayed time always agrees with the presenter's own tracked playback time — the label/command convergence claim for the accessibility path")
    func voiceOverAdjustmentsKeepLabelAndPresenterTimeInAgreement() {
        let view = baselinedView(currentSeconds: 30, durationSeconds: 120)

        view.seekBar.accessibilityIncrement()

        #expect(view.displayedElapsedText?.hasPrefix("00:00:40") == true)

        view.seekBar.accessibilityIncrement()

        #expect(view.displayedElapsedText?.hasPrefix("00:00:50") == true)
    }

    @Test("Given a VoiceOver adjustment's own optimistic render already moved the tracked time forward, a subsequent seekTargetChanged confirming that same landing renders the identical value — the two paths never disagree once settled")
    func seekTargetConfirmationAfterAccessibilityAdjustmentAgreesOnTheFinalValue() {
        let view = baselinedView(currentSeconds: 30, durationSeconds: 120)
        view.seekBar.accessibilityIncrement()
        #expect(view.displayedElapsedText?.hasPrefix("00:00:40") == true)

        // Simulates the core's asynchronous confirmation of that same skip
        // landing in `pendingSeekTime` — the convergence claim is that both
        // paths compute the same destination from the same base, so this
        // doesn't move the label at all (it was already there).
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 40, preferredTimescale: 600)))

        #expect(view.displayedElapsedText?.hasPrefix("00:00:40") == true)
        #expect(view.seekFeedbackText == "+10s")
    }

    @Test("Given a VoiceOver adjustment streak of two forward taps, the badge delta reflects the real cumulative move, not the post-optimistic-render remainder — the anchor is snapshotted before the adjustment moves the tracked time, not after")
    func voiceOverStreakBadgeDeltaMatchesRealCumulativeMove() {
        let view = baselinedView(currentSeconds: 100, durationSeconds: 300)

        // Tap 1: the presenter's own optimistic render advances the tracked
        // time to 110s *before* any seekTargetChanged exists. If the anchor
        // were captured after that render (the bug this test guards
        // against), it would snapshot 110s instead of the pre-streak 100s,
        // and every subsequent badge delta would read one skipInterval low.
        view.seekBar.accessibilityIncrement()
        #expect(view.displayedElapsedText?.hasPrefix("00:01:50") == true) // 110s

        // The core's asynchronous confirmation for tap 1 arrives.
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 110, preferredTimescale: 600)))
        #expect(view.seekFeedbackText == "+10s")

        // Tap 2, still within the same streak (pendingSeekTime hasn't
        // settled back to nil).
        view.seekBar.accessibilityIncrement()
        #expect(view.displayedElapsedText?.hasPrefix("00:02:00") == true) // 120s

        // The core's confirmation for tap 2 arrives, carrying its own
        // accumulated base (pendingSeekTime ?? currentTime = 110 + 10).
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 120, preferredTimescale: 600)))
        #expect(view.seekFeedbackText == "+20s", "two 10s forward taps must show +20s, not +10s")
    }

    @Test("Given a VoiceOver adjustment streak, the badge never shows +0s for a real, non-zero move — the specific regression this fix closes")
    func voiceOverStreakBadgeNeverShowsZeroForARealMove() {
        let view = baselinedView(currentSeconds: 100, durationSeconds: 300)

        view.seekBar.accessibilityIncrement()
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 110, preferredTimescale: 600)))

        #expect(view.seekFeedbackText != "+0s")
        #expect(view.seekFeedbackText == "+10s")
    }

    @Test("Given a VoiceOver adjustment streak already in progress, a skip-button-style seekTargetChanged (no optimistic render of its own) still reuses the same anchor established by the first VoiceOver tap — the three consumers share one mechanism")
    func mixedStreakSharesTheSameAnchorAcrossConsumers() {
        let view = baselinedView(currentSeconds: 100, durationSeconds: 300)
        view.seekBar.accessibilityIncrement()
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 110, preferredTimescale: 600)))
        #expect(view.seekFeedbackText == "+10s")

        // A skip button (or double-tap) tap within the same still-open
        // streak — its own presenter case has no optimistic render, so this
        // exercises the "already-anchored" branch from the other direction.
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 120, preferredTimescale: 600)))

        #expect(view.seekFeedbackText == "+20s")
    }
}
