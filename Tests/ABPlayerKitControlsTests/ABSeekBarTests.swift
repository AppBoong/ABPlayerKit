import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Seek bar renders buffered progress and tracks dragging")
@MainActor
struct ABSeekBarTests {
    @Test("Given progress values, layers use shared geometry")
    func progressLayersUseGeometry() {
        let seekBar = ABSeekBar(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        seekBar.progress = 0.25
        seekBar.bufferedProgress = 0.75

        seekBar.layoutIfNeeded()

        #expect(seekBar.renderedProgressFrame.width < seekBar.renderedBufferedFrame.width)
        #expect(seekBar.renderedThumbFrame.midX == 53)
    }

    @Test("Given a track drag, callbacks receive optimistic clamped progress")
    func dragCallbacksFollowTouch() {
        let seekBar = ABSeekBar(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        seekBar.layoutIfNeeded()
        var began = 0
        var changes: [Double] = []
        var ended: [Double] = []
        seekBar.onScrubBegan = { began += 1 }
        seekBar.onScrubChanged = { changes.append($0) }
        seekBar.onScrubEnded = { ended.append($0) }

        #expect(seekBar.beginInteraction(at: 50))
        #expect(seekBar.continueInteraction(at: 150))
        seekBar.endInteraction(at: 300)

        #expect(began == 1)
        #expect(changes.contains { $0 > 0.7 })
        #expect(ended == [1])
        #expect(seekBar.progress == 1)
        #expect(!seekBar.isScrubbing)
    }

    @Test("Given disabled seeking, interaction does not begin")
    func disabledSeekRejectsInteraction() {
        let seekBar = ABSeekBar(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        seekBar.isSeekEnabled = false

        #expect(!seekBar.beginInteraction(at: 100))
        #expect(!seekBar.isScrubbing)
    }

    @Test("Given thumb-only interaction, a distant track touch is rejected")
    func trackTapCanBeDisabled() {
        let seekBar = ABSeekBar(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        seekBar.progress = 0
        seekBar.allowsTrackTapToSeek = false
        seekBar.layoutIfNeeded()

        #expect(!seekBar.beginInteraction(at: 150))
        #expect(seekBar.beginInteraction(at: seekBar.renderedThumbFrame.midX))
    }

    @Test("Given scrubbing state, track and thumb use their enlarged dimensions")
    func scrubbingUsesExpandedStyle() {
        let seekBar = ABSeekBar(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        seekBar.setScrubbing(true, animated: false)

        seekBar.layoutIfNeeded()

        #expect(seekBar.renderedTrackFrame.height == 6)
        #expect(seekBar.renderedThumbFrame.size == CGSize(width: 18, height: 18))
    }

    @Test("Given hidden thumb style, the track still reaches physical endpoints")
    func hiddenThumbUsesFullTrack() {
        var style = ABPlayerControlsStyle()
        style.isThumbHidden = true
        let seekBar = ABSeekBar(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        seekBar.style = style
        seekBar.layoutIfNeeded()

        _ = seekBar.beginInteraction(at: 200)

        #expect(seekBar.progress == 1)
        #expect(seekBar.renderedThumbFrame.isEmpty == false)
    }
}
