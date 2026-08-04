import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls apply style changes live without rebuilding views", .timeLimit(.minutes(1)))
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
        #expect(view.skipBackwardButton.resolvedSkipBadgeNumber == nil)

        // 20 is a valid clamped interval (a multiple of 5 in 5...60) but has no
        // native SF Symbol variant — the number badges over the generic arrow.
        configuration.skipInterval = 20
        view.configuration = configuration
        #expect(configuration.skipInterval == 20)
        #expect(view.skipBackwardButton.resolvedIcon == .system("gobackward"))
        #expect(view.skipForwardButton.resolvedIcon == .system("goforward"))
        #expect(view.skipBackwardButton.resolvedSkipBadgeNumber == 20)
        #expect(view.skipForwardButton.resolvedSkipBadgeNumber == 20)
    }

    @Test("Given an out-of-step or out-of-range skip interval, assignment clamps it")
    func skipIntervalClampsToSupportedSteps() {
        var configuration = ABPlayerControlsConfiguration()

        configuration.skipInterval = 7
        #expect(configuration.skipInterval == 5)

        configuration.skipInterval = 63
        #expect(configuration.skipInterval == 60)

        configuration.skipInterval = 3
        #expect(configuration.skipInterval == 5)

        configuration.skipInterval = 32
        #expect(configuration.skipInterval == 30)
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

    @Test("Given a fixed-width timeline label, its reserved width toggles live")
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
