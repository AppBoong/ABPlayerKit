import Testing
@testable import ABPlayerKitControls

@Suite("Controls view integrates auto-hide and scrubbing visibility")
@MainActor
struct ABPlayerControlsAutoHideTests {
    @Test("Given playing controls, playback state arms and fires auto-hide")
    func playingAutoHideFires() async throws {
        var configuration = ABPlayerControlsConfiguration()
        configuration.autoHideDelay = 0.01
        let view = ABPlayerControlsView(configuration: configuration)

        view.handleVisibility(.playbackStateChanged(isPlaying: true), animated: false)
        #expect(view.hasScheduledAutoHide)
        try await Task.sleep(for: .milliseconds(30))

        #expect(!view.isControlsVisible)
        #expect(view.controlsContentAlpha == 0)
        #expect(!view.controlsContentIsInteractive)
    }

    @Test("Given hidden controls, a background tap shows and rearms them")
    func backgroundTapShowsControls() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.initialVisibility = .hidden
        let view = ABPlayerControlsView(configuration: configuration)

        view.simulateBackgroundTap()

        #expect(view.isControlsVisible)
        #expect(view.controlsContentIsInteractive)
    }

    @Test("Given scrubbing, scheduled auto-hide is cancelled until scrubbing ends")
    func scrubbingSuppressesAutoHide() async throws {
        var configuration = ABPlayerControlsConfiguration()
        configuration.autoHideDelay = 0.01
        let view = ABPlayerControlsView(configuration: configuration)
        view.handleVisibility(.playbackStateChanged(isPlaying: true), animated: false)

        view.handleVisibility(.scrubBegan, animated: false)
        #expect(!view.hasScheduledAutoHide)
        try await Task.sleep(for: .milliseconds(30))
        #expect(view.isControlsVisible)

        view.handleVisibility(.scrubEnded, animated: false)
        #expect(view.hasScheduledAutoHide)
    }

    @Test("Given programmatic visibility, notifications emit only on actual changes")
    func programmaticVisibilityAvoidsDuplicateNotification() {
        let view = ABPlayerControlsView()
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.setControlsVisible(true, animated: false)
        view.setControlsVisible(false, animated: false)
        view.setControlsVisible(false, animated: false)

        #expect(events == [.visibilityChanged(isVisible: false)])
    }

    @Test("Given background tapping disabled, simulated taps do not change visibility")
    func disabledBackgroundTapDoesNothing() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.initialVisibility = .hidden
        configuration.handlesBackgroundTap = false
        let view = ABPlayerControlsView(configuration: configuration)

        view.simulateBackgroundTap()

        #expect(!view.isControlsVisible)
    }
}
