import ABPlayerKit
import Testing
@testable import ABPlayerKitControls

@Suite("Controls configuration starts with documented behavior", .timeLimit(.minutes(1)))
struct ABPlayerControlsConfigurationTests {
    @Test("Given a fresh configuration, playback interactions use v0.2 defaults")
    func defaultSnapshot() {
        let configuration = ABPlayerControlsConfiguration()

        #expect(configuration.skipInterval == 10)
        #expect(configuration.synchronizesSkipIconWithInterval)
        #expect(configuration.rateOptions == ABPlaybackRate.common)
        #expect(configuration.rateInteraction == .menu)
        #expect(configuration.autoHideDelay == 3)
        #expect(configuration.staysVisibleWhilePaused)
        #expect(configuration.periodicTimeInterval == 0.25)
    }

    @Test("Given a fresh configuration, timeline and interaction flags are enabled")
    func defaultTimelineSnapshot() {
        let configuration = ABPlayerControlsConfiguration()

        #expect(configuration.showsBufferedProgress)
        #expect(configuration.showsTimeLabels)
        #expect(configuration.timeLabelLayout == .elapsedAndTotal)
        #expect(configuration.timeFormat == .fixedHours)
        #expect(configuration.showsSkipButtons)
        #expect(configuration.handlesBackgroundTap)
        #expect(configuration.allowsTrackTapToSeek)
        #expect(configuration.initialVisibility == .visible)
        #expect(configuration.promotesToCurrentOnPlay)
    }
}
