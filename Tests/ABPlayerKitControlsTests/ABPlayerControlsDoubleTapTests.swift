@preconcurrency import AVFoundation
import ABPlayerKit
import ABTestSupport
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls install a double-tap seek gesture only when opted in, and route it through the skip path", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPlayerControlsDoubleTapTests {
    private func attachedView(configuration: ABPlayerControlsConfiguration = .init()) -> (view: ABPlayerControlsView, player: ABPlayer) {
        let source = ABMediaSource(url: URL(string: "https://example.com/double-tap.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        view.player = player
        return (view, player)
    }

    @Test("Given the default configuration, doubleTapSeek is .disabled and no double-tap recognizer is installed")
    func defaultsToDisabledWithNoRecognizerInstalled() {
        #expect(ABPlayerControlsConfiguration().doubleTapSeek == .disabled)
        let view = ABPlayerControlsView()

        #expect(!view.hasDoubleTapRecognizerInstalled)
    }

    @Test("Given doubleTapSeek is enabled, the recognizer is installed on the view")
    func enablingInstallsTheRecognizer() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        let view = ABPlayerControlsView(configuration: configuration)

        #expect(view.hasDoubleTapRecognizerInstalled)
    }

    @Test("Given doubleTapSeek toggles back to .disabled after being enabled, the recognizer is removed")
    func disablingAfterEnablingRemovesTheRecognizer() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        let view = ABPlayerControlsView(configuration: configuration)
        #expect(view.hasDoubleTapRecognizerInstalled)

        configuration.doubleTapSeek = .disabled
        view.configuration = configuration

        #expect(!view.hasDoubleTapRecognizerInstalled)
    }

    @Test("Given a tap in the leading band, the player skips backward and broadcasts skipTapped with the negated interval")
    func leadingBandSkipsBackward() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        configuration.skipInterval = 15
        let (view, _) = attachedView(configuration: configuration)
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.handleDoubleTap(at: CGPoint(x: 10, y: 100))

        #expect(events.contains(.skipTapped(by: -15)))
    }

    @Test("Given a tap in the trailing band, the player skips forward and broadcasts skipTapped with the plain interval")
    func trailingBandSkipsForward() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        configuration.skipInterval = 15
        let (view, _) = attachedView(configuration: configuration)
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.handleDoubleTap(at: CGPoint(x: 290, y: 100))

        #expect(events.contains(.skipTapped(by: 15)))
    }

    @Test("Given a real double-tap followed by the core's confirming seekTargetChanged, the seek feedback badge shows the plain delta — this path reuses the skip buttons' presenter case, which has no optimistic pre-render either")
    func doubleTapFeedsTheSharedBadgeMechanismCorrectly() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        configuration.skipInterval = 10
        let (view, _) = attachedView(configuration: configuration)
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 100, preferredTimescale: 600),
            duration: CMTime(seconds: 300, preferredTimescale: 600),
            bufferedUntil: nil
        )))

        view.handleDoubleTap(at: CGPoint(x: 290, y: 100))
        view.handlePlayerEvent(.seekTargetChanged(CMTime(seconds: 110, preferredTimescale: 600)))

        #expect(view.seekFeedbackText == "+10s")
    }

    @Test("Given a tap in the neutral middle band, nothing happens — no skip, no broadcast")
    func neutralBandDoesNothing() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        let (view, _) = attachedView(configuration: configuration)
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.handleDoubleTap(at: CGPoint(x: 150, y: 100))

        #expect(events.isEmpty)
    }

    @Test("Given a right-to-left layout, the leading/trailing bands flip — a tap at the physical-left edge now skips forward instead of backward")
    func rightToLeftFlipsBands() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        configuration.skipInterval = 15
        let (view, _) = attachedView(configuration: configuration)
        view.isRightToLeftLayoutOverride = true
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.handleDoubleTap(at: CGPoint(x: 10, y: 100))

        #expect(events.contains(.skipTapped(by: 15)))
        #expect(!events.contains(.skipTapped(by: -15)))
    }

    @Test("Given a right-to-left layout, a tap at the physical-right edge now skips backward instead of forward")
    func rightToLeftFlipsTrailingBandToo() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        configuration.skipInterval = 15
        let (view, _) = attachedView(configuration: configuration)
        view.isRightToLeftLayoutOverride = true
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.handleDoubleTap(at: CGPoint(x: 290, y: 100))

        #expect(events.contains(.skipTapped(by: -15)))
    }

    @Test("Given VoiceOver is running, a double tap in an active band does nothing")
    func voiceOverSuppressesDoubleTap() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        let (view, _) = attachedView(configuration: configuration)
        view.isVoiceOverRunningProvider = { true }
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.handleDoubleTap(at: CGPoint(x: 10, y: 100))

        #expect(events.isEmpty)
    }

    @Test("Given a no-op tap in a disabled configuration's coordinate space, handleDoubleTap does nothing even mid-band — the .disabled guard short-circuits first")
    func disabledConfigurationIgnoresDoubleTap() {
        let (view, _) = attachedView()
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.handleDoubleTap(at: CGPoint(x: 10, y: 100))

        #expect(events.isEmpty)
    }

    @Test("Given providesHapticFeedback is enabled (the default) and an active band is tapped, the haptic seam fires exactly once")
    func hapticFiresOnceWhenEnabled() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        let (view, _) = attachedView(configuration: configuration)
        var hapticCallCount = 0
        view.performHapticFeedback = { _ in hapticCallCount += 1 }

        view.handleDoubleTap(at: CGPoint(x: 10, y: 100))

        #expect(hapticCallCount == 1)
    }

    @Test("Given providesHapticFeedback is disabled, the haptic seam never fires")
    func hapticNeverFiresWhenDisabled() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        configuration.providesHapticFeedback = false
        let (view, _) = attachedView(configuration: configuration)
        var hapticCallCount = 0
        view.performHapticFeedback = { _ in hapticCallCount += 1 }

        view.handleDoubleTap(at: CGPoint(x: 10, y: 100))

        #expect(hapticCallCount == 0)
    }

    @Test("Given a neutral-band tap, the haptic seam never fires either — only an accepted seek triggers it")
    func hapticDoesNotFireForNeutralBand() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
        let (view, _) = attachedView(configuration: configuration)
        var hapticCallCount = 0
        view.performHapticFeedback = { _ in hapticCallCount += 1 }

        view.handleDoubleTap(at: CGPoint(x: 150, y: 100))

        #expect(hapticCallCount == 0)
    }
}

@Suite("Controls touch passthrough only gives up on itself, never on a resolved descendant", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPlayerControlsTouchPassthroughTests {
    @Test("Given .never (default) with controls hidden, hit-testing empty space still resolves to the overlay itself — the existing interactiveControlHitTesting contract")
    func neverKeepsExistingBehaviorWhenHidden() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.touchPassthrough = .never
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        view.setControlsVisible(false, animated: false)
        view.layoutIfNeeded()

        #expect(view.hitTest(CGPoint(x: 150, y: 100), with: nil) === view)
    }

    @Test("Given .whenControlsHidden with controls hidden, empty-space hit-testing passes through (returns nil)")
    func whenControlsHiddenPassesThroughWhenHidden() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.touchPassthrough = .whenControlsHidden
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        view.setControlsVisible(false, animated: false)
        view.layoutIfNeeded()

        #expect(view.hitTest(CGPoint(x: 150, y: 100), with: nil) == nil)
    }

    @Test("Given .whenControlsHidden with controls visible, empty-space hit-testing does not pass through — controlsContentView (interaction-enabled while visible) still claims it, the same as .never would")
    func whenControlsHiddenKeepsHitTestingWhenVisible() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.touchPassthrough = .whenControlsHidden
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        view.layoutIfNeeded()

        // The top-left corner, away from the centered transport row and the
        // bottom-anchored seek bar/time-label row — genuinely empty space.
        // While visible, `controlsContentView` (not `self`) is what actually
        // claims empty space by default UIKit hit-testing (it spans the full
        // overlay and is interaction-enabled whenever visible) — passthrough
        // only ever has a `self`-shaped hit to give up on (see `hitTest`'s
        // `hit === self` gate), so it can never engage here regardless of
        // configuration; the meaningful assertion is simply that the touch
        // isn't passed through (a non-nil result), not a literal `=== view`
        // identity check.
        #expect(view.hitTest(CGPoint(x: 10, y: 10), with: nil) != nil)
        #expect(view.hitTest(CGPoint(x: 10, y: 10), with: nil) !== view.playPauseButton)
    }

    @Test("Given .always with controls visible, hitting an actual control still wins — passthrough never beats the priority order")
    func alwaysStillYieldsToAnActualControl() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.touchPassthrough = .always
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        view.layoutIfNeeded()

        let center = view.playPauseButton.convert(
            CGPoint(x: view.playPauseButton.bounds.midX, y: view.playPauseButton.bounds.midY),
            to: view
        )
        #expect(view.hitTest(center, with: nil) === view.playPauseButton)
    }

    @Test("Given .always, an accessory view overlapping the seek bar still wins over passthrough")
    func alwaysStillYieldsToAnAccessoryOverlappingTheSeekBar() {
        let source = ABMediaSource(url: URL(string: "https://example.com/passthrough-accessory.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        var configuration = ABPlayerControlsConfiguration()
        configuration.touchPassthrough = .always
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.player = player
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        let accessoryButton = UIButton(type: .custom)
        accessoryButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accessoryButton.widthAnchor.constraint(equalToConstant: 44),
            accessoryButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        view.accessoryViews = [accessoryButton]
        view.layoutIfNeeded()
        #expect(view.renderedSeekBarFrame.intersects(accessoryButton.convert(accessoryButton.bounds, to: view)))

        let center = accessoryButton.convert(
            CGPoint(x: accessoryButton.bounds.midX, y: accessoryButton.bounds.midY),
            to: view
        )
        #expect(view.hitTest(center, with: nil) === accessoryButton)
    }
}
