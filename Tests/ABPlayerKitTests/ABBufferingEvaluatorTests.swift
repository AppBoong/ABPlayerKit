import Testing
@testable import ABPlayerKit

/// Full-combination table coverage for `ABBufferingEvaluator` — pure logic,
/// no `AVFoundation`, exactly like `ABGradePlannerTests`.
@Suite("ABBufferingEvaluator judges buffering from raw target signals")
struct ABBufferingEvaluatorTests {
    @Test("No item, no intent, or waiting-with-no-item all short-circuit to not buffering", arguments: [
        (hasItem: false, intendsToPlay: true, isWaitingWithNoItem: false),
        (hasItem: true, intendsToPlay: false, isWaitingWithNoItem: false),
        (hasItem: true, intendsToPlay: true, isWaitingWithNoItem: true)
    ])
    func guardConditionsShortCircuit(hasItem: Bool, intendsToPlay: Bool, isWaitingWithNoItem: Bool) {
        let result = ABBufferingEvaluator.isBuffering(ABBufferingSignals(
            hasItem: hasItem,
            intendsToPlay: intendsToPlay,
            timeControlStatus: .waitingToPlay,
            isWaitingWithNoItem: isWaitingWithNoItem,
            isPlaybackLikelyToKeepUp: false,
            isPlaybackBufferEmpty: true
        ))
        #expect(!result)
    }

    @Test(".playing is never buffering, regardless of the raw buffer signals", arguments: [
        (keepUp: true, empty: false), (keepUp: false, empty: false), (keepUp: false, empty: true), (keepUp: true, empty: true)
    ])
    func playingIsNeverBuffering(keepUp: Bool, empty: Bool) {
        let result = ABBufferingEvaluator.isBuffering(ABBufferingSignals(
            hasItem: true,
            intendsToPlay: true,
            timeControlStatus: .playing,
            isWaitingWithNoItem: false,
            isPlaybackLikelyToKeepUp: keepUp,
            isPlaybackBufferEmpty: empty
        ))
        #expect(!result)
    }

    @Test(".waitingToPlay is always buffering when an item is held and intent is to play")
    func waitingToPlayIsAlwaysBuffering() {
        let result = ABBufferingEvaluator.isBuffering(ABBufferingSignals(
            hasItem: true,
            intendsToPlay: true,
            timeControlStatus: .waitingToPlay,
            isWaitingWithNoItem: false,
            isPlaybackLikelyToKeepUp: true,
            isPlaybackBufferEmpty: false
        ))
        #expect(result)
    }

    @Test(".paused buffers only when the buffer is empty or not likely to keep up — the automaticallyWaitsToMinimizeStalling == false path", arguments: [
        (keepUp: true, empty: false, expected: false),
        (keepUp: false, empty: false, expected: true),
        (keepUp: true, empty: true, expected: true),
        (keepUp: false, empty: true, expected: true)
    ])
    func pausedBuffersOnStallSignalsOnly(keepUp: Bool, empty: Bool, expected: Bool) {
        let result = ABBufferingEvaluator.isBuffering(ABBufferingSignals(
            hasItem: true,
            intendsToPlay: true,
            timeControlStatus: .paused,
            isWaitingWithNoItem: false,
            isPlaybackLikelyToKeepUp: keepUp,
            isPlaybackBufferEmpty: empty
        ))
        #expect(result == expected)
    }
}
