import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls apply style changes live without rebuilding views")
@MainActor
struct ABPlayerControlsLiveStyleTests {
    @Test("Given color-only changes, rendering updates without invalidating layout")
    func colorsDoNotInvalidateLayout() {
        var initial = ABPlayerControlsStyle()
        initial.backgroundStyle = .gradient(top: .clear, bottom: .black)
        let view = ABPlayerControlsView(style: initial)
        let gradient = view.renderedBackgroundGradientLayer
        let rateMenu = view.rateButton.menu
        let initialInvalidations = view.styleLayoutInvalidationCount
        var changed = initial
        changed.tintColor = .systemPink
        changed.trackColor = .systemGray
        changed.progressColor = .systemGreen
        changed.backgroundStyle = .gradient(top: .clear, bottom: .systemBlue)

        view.style = changed

        #expect(view.styleLayoutInvalidationCount == initialInvalidations)
        #expect(view.renderedBackgroundGradientLayer === gradient)
        #expect(view.rateButton.menu === rateMenu)
        #expect(view.playPauseButton.tintColor == UIColor.systemPink)
    }

    @Test("Given dimension changes, constraints update and layout is invalidated once")
    func dimensionsInvalidateLayout() {
        let view = ABPlayerControlsView()
        let playButton = view.playPauseButton
        var changed = view.style
        changed.playPauseButtonSize = CGSize(width: 60, height: 58)
        changed.buttonSpacing = 12

        view.style = changed

        #expect(view.styleLayoutInvalidationCount == 1)
        #expect(view.playPauseButton === playButton)
        #expect(view.playPauseButton.constraints.contains { $0.firstAttribute == .width && $0.constant == 60 })
        #expect(view.playPauseButton.constraints.contains { $0.firstAttribute == .height && $0.constant == 58 })
    }

    @Test("Given an icon change, the existing button receives the new icon")
    func iconUpdatesExistingButton() {
        let view = ABPlayerControlsView()
        let playButton = view.playPauseButton
        var changed = view.style
        changed.playIcon = .system("stop.fill")

        view.style = changed

        #expect(view.playPauseButton === playButton)
        #expect(view.playPauseButton.resolvedIcon == .system("stop.fill"))
        #expect(view.displayedPlayPauseImage != nil)
    }

    @Test("Given a none icon, the corresponding control hides live")
    func noneIconHidesControl() {
        let view = ABPlayerControlsView()
        var changed = view.style
        changed.playIcon = .none

        view.style = changed

        #expect(view.playPauseButton.isHidden)
    }

    @Test("Given synchronized skip intervals, supported symbols and fallback are deterministic")
    func skipIconsSynchronizeWithConfiguration() {
        let view = ABPlayerControlsView()
        var configuration = view.configuration
        configuration.skipInterval = 15
        view.configuration = configuration
        #expect(view.skipBackwardButton.resolvedIcon == .system("gobackward.15"))
        #expect(view.skipForwardButton.resolvedIcon == .system("goforward.15"))

        configuration.skipInterval = 7
        view.configuration = configuration
        #expect(view.skipBackwardButton.resolvedIcon == .system("gobackward.10"))
        #expect(view.skipForwardButton.resolvedIcon == .system("goforward.10"))
    }

    @Test("Given explicit skip icons, interval synchronization never replaces them")
    func explicitSkipIconsWin() {
        var style = ABPlayerControlsStyle()
        style.skipBackwardIcon = .system("backward.fill")
        style.skipForwardIcon = .system("forward.fill")
        var configuration = ABPlayerControlsConfiguration()
        configuration.skipInterval = 15
        let view = ABPlayerControlsView(style: style, configuration: configuration)

        #expect(view.skipBackwardButton.resolvedIcon == .system("backward.fill"))
        #expect(view.skipForwardButton.resolvedIcon == .system("forward.fill"))
    }

    @Test("Given active scrubbing, scrubbing dimensions update immediately")
    func scrubbingDimensionsUpdateImmediately() {
        let view = ABPlayerControlsView()
        view.seekBar.setScrubbing(true, animated: false)
        var changed = view.style
        changed.trackHeightWhileScrubbing = 9
        changed.thumbSizeWhileScrubbing = CGSize(width: 24, height: 20)

        view.style = changed
        view.seekBar.layoutIfNeeded()

        #expect(view.seekBar.renderedTrackHeight == 9)
        #expect(view.seekBar.renderedThumbSize == CGSize(width: 24, height: 20))
    }

    @Test("Given fixed-width time labels, equal reserved widths toggle live")
    func fixedWidthTimeLabelsToggle() {
        let view = ABPlayerControlsView()
        #expect(view.hasFixedWidthTimeLabels)
        #expect(view.fixedTimeLabelMinimumWidth > 0)

        var changed = view.style
        changed.usesFixedWidthTimeLabels = false
        view.style = changed

        #expect(!view.hasFixedWidthTimeLabels)
    }
}
