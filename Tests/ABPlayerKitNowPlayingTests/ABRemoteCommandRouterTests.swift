import Testing
@testable import ABPlayerKitNowPlaying

/// Exhaustive coverage for `ABRemoteCommandRouter` — the only way to verify
/// remote-command routing, since `MPRemoteCommandEvent` has no public
/// initializer.
@Suite("ABRemoteCommandRouter routes intents against ownership/seekability/handler availability")
struct ABRemoteCommandRouterTests {
    private let router = ABRemoteCommandRouter()

    @Test("No owner rejects every intent, regardless of seekability or handlers")
    func noOwnerRejectsEveryIntent() {
        let intents: [ABRemoteCommandIntent] = [
            .play, .pause, .togglePlayPause, .skip(15), .seek(seconds: 10), .setRate(1.5), .nextTrack, .previousTrack
        ]
        for intent in intents {
            let outcome = router.outcome(
                for: intent,
                ownerExists: false,
                isSeekable: true,
                hasTrackHandlers: (next: true, previous: true)
            )
            #expect(outcome == .rejectNoOwner, "\(intent)")
        }
    }

    @Test("play/pause/togglePlayPause/skip/setRate always perform once an owner exists", arguments: [
        ABRemoteCommandIntent.play, .pause, .togglePlayPause, .skip(15), .setRate(1.5)
    ])
    func unconditionalIntentsAlwaysPerform(intent: ABRemoteCommandIntent) {
        let outcome = router.outcome(
            for: intent,
            ownerExists: true,
            isSeekable: false,
            hasTrackHandlers: (next: false, previous: false)
        )
        #expect(outcome == .perform(intent))
    }

    @Test("seek performs only when seekable, otherwise rejects as not seekable")
    func seekGatedBySeekability() {
        let seekable = router.outcome(
            for: .seek(seconds: 30),
            ownerExists: true,
            isSeekable: true,
            hasTrackHandlers: (next: false, previous: false)
        )
        let notSeekable = router.outcome(
            for: .seek(seconds: 30),
            ownerExists: true,
            isSeekable: false,
            hasTrackHandlers: (next: false, previous: false)
        )
        #expect(seekable == .perform(.seek(seconds: 30)))
        #expect(notSeekable == .rejectNotSeekable)
    }

    @Test("nextTrack/previousTrack perform only when their handler is present")
    func trackNavigationGatedByHandlerPresence() {
        let nextWithHandler = router.outcome(
            for: .nextTrack, ownerExists: true, isSeekable: true, hasTrackHandlers: (next: true, previous: false)
        )
        let nextWithoutHandler = router.outcome(
            for: .nextTrack, ownerExists: true, isSeekable: true, hasTrackHandlers: (next: false, previous: false)
        )
        let previousWithHandler = router.outcome(
            for: .previousTrack, ownerExists: true, isSeekable: true, hasTrackHandlers: (next: false, previous: true)
        )
        let previousWithoutHandler = router.outcome(
            for: .previousTrack, ownerExists: true, isSeekable: true, hasTrackHandlers: (next: false, previous: false)
        )

        #expect(nextWithHandler == .perform(.nextTrack))
        #expect(nextWithoutHandler == .rejectNoHandler)
        #expect(previousWithHandler == .perform(.previousTrack))
        #expect(previousWithoutHandler == .rejectNoHandler)
    }
}
