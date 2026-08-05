import Testing
@testable import ABPlayerKitControls

@Suite("Controls auto-hide follows playback and scrubbing state", .timeLimit(.minutes(3)))
struct ABControlsVisibilityMachineTests {
    @Test("Given hidden playing controls, a tap shows, notifies, and schedules hiding")
    func hiddenTapShowsControls() {
        var machine = playingMachine(visibility: .hidden)

        #expect(machine.handle(.tapped) == [
            .show,
            .notifyVisibility(true),
            .scheduleAutoHide(after: 3)
        ])
    }

    @Test("Given visible controls, a tap cancels and hides them")
    func visibleTapHidesControls() {
        var machine = playingMachine()

        #expect(machine.handle(.tapped) == [
            .cancelAutoHide,
            .hide,
            .notifyVisibility(false)
        ])
    }

    @Test("Given visible playing controls, interaction only rearms the timer")
    func interactionRearmsWithoutHiding() {
        var machine = playingMachine()

        #expect(machine.handle(.controlInteracted) == [
            .cancelAutoHide,
            .scheduleAutoHide(after: 3)
        ])
    }

    @Test("Given hidden controls, scrubbing cancels hiding and forces them visible")
    func scrubBeganShowsHiddenControls() {
        var machine = playingMachine(visibility: .hidden)

        #expect(machine.handle(.scrubBegan) == [
            .cancelAutoHide,
            .show,
            .notifyVisibility(true)
        ])
        #expect(machine.isScrubbing)
    }

    @Test("Given playing scrub state, ending scrubbing schedules hiding")
    func scrubEndedSchedulesHide() {
        var machine = playingMachine()
        _ = machine.handle(.scrubBegan)

        #expect(machine.handle(.scrubEnded) == [.scheduleAutoHide(after: 3)])
        #expect(!machine.isScrubbing)
    }

    @Test("Given active scrubbing, a racing auto-hide event is ignored")
    func autoHideDuringScrubIsIgnored() {
        var machine = playingMachine()
        _ = machine.handle(.scrubBegan)

        #expect(machine.handle(.autoHideFired) == [])
        #expect(machine.visibility == .visible)
    }

    @Test("Given paused sticky controls, auto-hide is ignored")
    func pausedStickyControlsDoNotHide() {
        var machine = ABControlsVisibilityMachine(visibility: .visible)

        #expect(machine.handle(.autoHideFired) == [])
    }

    @Test("Given eligible visible controls, auto-hide hides and notifies")
    func eligibleAutoHideFires() {
        var machine = playingMachine()

        #expect(machine.handle(.autoHideFired) == [.hide, .notifyVisibility(false)])
    }

    @Test("Given visible controls, playback start schedules hiding")
    func playbackStartSchedulesHide() {
        var machine = ABControlsVisibilityMachine(visibility: .visible)

        #expect(machine.handle(.playbackStateChanged(isPlaying: true)) == [.scheduleAutoHide(after: 3)])
    }

    @Test("Given sticky controls, playback pause cancels hiding")
    func playbackPauseCancelsHide() {
        var machine = playingMachine()

        #expect(machine.handle(.playbackStateChanged(isPlaying: false)) == [.cancelAutoHide])
    }

    @Test("Given the current visibility, setting it again emits no effects")
    func duplicateVisibilityIsNoOp() {
        var machine = ABControlsVisibilityMachine(visibility: .visible)

        #expect(machine.handle(.setVisible(true)) == [])
    }

    @Test("Given configuration changes, the existing timer is cancelled and recalculated")
    func configurationChangeRecalculatesTimer() {
        var machine = playingMachine()

        #expect(machine.handle(.configurationChanged(
            autoHideDelay: 5,
            staysVisibleWhilePaused: true
        )) == [.cancelAutoHide, .scheduleAutoHide(after: 5)])
    }

    @Test("Given any state, detaching always cancels auto-hide")
    func detachAlwaysCancels() {
        var machine = playingMachine()
        _ = machine.handle(.scrubBegan)

        #expect(machine.handle(.detached) == [.cancelAutoHide])
        #expect(!machine.isScrubbing)
    }

    @Test("Given non-sticky paused controls, pause schedules and permits hiding")
    func pausedControlsCanAutoHideWhenConfigured() {
        var machine = playingMachine()
        _ = machine.handle(.configurationChanged(
            autoHideDelay: 3,
            staysVisibleWhilePaused: false
        ))

        #expect(machine.handle(.playbackStateChanged(isPlaying: false)) == [.scheduleAutoHide(after: 3)])
        #expect(machine.handle(.autoHideFired) == [.hide, .notifyVisibility(false)])
    }

    @Test("Given no auto-hide delay, no input schedules a timer")
    func nilDelayNeverSchedules() {
        var machine = playingMachine()
        _ = machine.handle(.configurationChanged(
            autoHideDelay: nil,
            staysVisibleWhilePaused: false
        ))

        let effects = [
            machine.handle(.controlInteracted),
            machine.handle(.playbackStateChanged(isPlaying: true)),
            machine.handle(.scrubBegan),
            machine.handle(.scrubEnded)
        ].flatMap { $0 }
        #expect(!effects.contains { if case .scheduleAutoHide = $0 { true } else { false } })
    }

    private func playingMachine(
        visibility: ABControlsVisibilityMachine.Visibility = .visible
    ) -> ABControlsVisibilityMachine {
        ABControlsVisibilityMachine(
            visibility: visibility,
            isScrubbing: false,
            isPlaying: true,
            autoHideDelay: 3,
            staysVisibleWhilePaused: true
        )
    }
}
