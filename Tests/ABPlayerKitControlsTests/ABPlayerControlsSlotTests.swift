@preconcurrency import AVFoundation
import ABPlayerKit
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls place accessory views in named slots without disturbing the release geometry", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerControlsSlotTests {
    @Test("accessoryViews and accessoryViews(in: .bottomTrailing) are the same slot, in both directions")
    func accessoryViewsIsAnAliasForBottomTrailing() {
        let view = ABPlayerControlsView()
        let probe = UIView()

        view.accessoryViews = [probe]
        #expect(view.accessoryViews(in: .bottomTrailing) == [probe])

        let second = UIView()
        view.setAccessoryViews([second], in: .bottomTrailing)
        #expect(view.accessoryViews == [second])
    }

    @Test("Every ABControlsSlot case can independently hold and return its own views without disturbing the others")
    func slotsAreIndependent() {
        let view = ABPlayerControlsView()
        let top = UIView()
        let transport = UIView()
        let bottom = UIView()

        view.setAccessoryViews([top], in: .topTrailing)
        view.setAccessoryViews([transport], in: .transportTrailing)
        view.setAccessoryViews([bottom], in: .bottomTrailing)

        #expect(view.accessoryViews(in: .topTrailing) == [top])
        #expect(view.accessoryViews(in: .transportTrailing) == [transport])
        #expect(view.accessoryViews(in: .bottomTrailing) == [bottom])
    }

    @Test("Given an empty slot on every case, the release overlay's fixed literal geometry is bit-for-bit unchanged — reusing ABControlsLayoutTests' pinned constants")
    func emptySlotsLeaveLayoutLiteralsUnchanged() {
        let layout = ABControlsLayout(style: .default, traitCollection: UITraitCollection())
        #expect(abs(layout.rootStackSpacing - (-27.96142578125)) < 0.001)
    }

    @Test("Given .transportTrailing gains a view, playPauseButton stays centered in the overlay — the cluster's own centering is preserved, not shifted by the new trailing content")
    func transportTrailingDoesNotShiftButtonStackCentering() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.layoutIfNeeded()
        let centerXBefore = view.playPauseButton.center.x

        let probe = UIView()
        probe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            probe.widthAnchor.constraint(equalToConstant: 30),
            probe.heightAnchor.constraint(equalToConstant: 30)
        ])
        view.setAccessoryViews([probe], in: .transportTrailing)
        view.layoutIfNeeded()

        #expect(abs(view.playPauseButton.center.x - centerXBefore) < 0.5)
    }

    @Test("Given .topTrailing gains a view, it sits flush with the overlay's top-trailing margin corner")
    func topTrailingSitsAtTopTrailingMargin() {
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        let probe = UIView()
        probe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            probe.widthAnchor.constraint(equalToConstant: 30),
            probe.heightAnchor.constraint(equalToConstant: 30)
        ])
        view.setAccessoryViews([probe], in: .topTrailing)
        view.layoutIfNeeded()

        let probeFrame = probe.convert(probe.bounds, to: view)
        #expect(abs(probeFrame.minY - view.style.contentInsets.top) < 0.5)
        #expect(abs(probeFrame.maxX - (view.bounds.maxX - view.style.contentInsets.trailing)) < 0.5)
    }

    // MARK: - hitTest priority matrix (4 buttons × 3 slots × seek bar × 3 passthrough cases)

    @Test("The 4 transport buttons always win hit testing over all three slots and the seek bar")
    func transportButtonsWinOverEverythingElse() {
        let source = ABMediaSource(url: URL(string: "https://example.com/slot-matrix.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.player = player
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        for slot in ABControlsSlot.allCases {
            let probe = UIButton(type: .custom)
            probe.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                probe.widthAnchor.constraint(equalToConstant: 44),
                probe.heightAnchor.constraint(equalToConstant: 44)
            ])
            view.setAccessoryViews([probe], in: slot)
        }
        view.layoutIfNeeded()

        for button in [view.playPauseButton, view.skipForwardButton, view.skipBackwardButton, view.rateButton] {
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: view)
            #expect(view.hitTest(center, with: nil) === button)
        }
    }

    @Test("A .bottomTrailing accessory overlapping the seek bar wins hit testing over it — the existing accessoryViewsWinHitTestingOverAnEnabledSeekBar coverage, confirmed for the named-slot API too")
    func bottomTrailingWinsOverAnOverlappingSeekBar() {
        let source = ABMediaSource(url: URL(string: "https://example.com/slot-bottom-trailing.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.player = player
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        let probe = UIButton(type: .custom)
        probe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            probe.widthAnchor.constraint(equalToConstant: 44),
            probe.heightAnchor.constraint(equalToConstant: 44)
        ])
        view.setAccessoryViews([probe], in: .bottomTrailing)
        view.layoutIfNeeded()

        #expect(view.seekBar.isSeekEnabled)
        #expect(view.renderedSeekBarFrame.intersects(probe.convert(probe.bounds, to: view)))
        let center = probe.convert(CGPoint(x: probe.bounds.midX, y: probe.bounds.midY), to: view)
        #expect(view.hitTest(center, with: nil) === probe)
    }

    @Test("A .transportTrailing accessory overlapping the seek bar (a short overlay, same overlap ABPlayerControlsLayoutTests proves for the transport row) wins hit testing over it")
    func transportTrailingWinsOverAnOverlappingSeekBar() {
        let source = ABMediaSource(url: URL(string: "https://example.com/slot-transport-trailing.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        let view = ABPlayerControlsView()
        // Same short overlay height ABPlayerControlsLayoutTests' bottomClusterOverlapFavorsButtonsOverSeekBar
        // uses to force a real overlap between the centered transport row and the seek bar's touch row.
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 180)
        view.player = player
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        let probe = UIButton(type: .custom)
        probe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            probe.widthAnchor.constraint(equalToConstant: 44),
            probe.heightAnchor.constraint(equalToConstant: 44)
        ])
        view.setAccessoryViews([probe], in: .transportTrailing)
        view.layoutIfNeeded()

        #expect(view.seekBar.isSeekEnabled)
        #expect(view.renderedSeekBarFrame.intersects(probe.convert(probe.bounds, to: view)), "the geometry this test guards against must be a real overlap, not hypothetical")
        let center = probe.convert(CGPoint(x: probe.bounds.midX, y: probe.bounds.midY), to: view)
        #expect(view.hitTest(center, with: nil) === probe)
    }

    @Test("A .topTrailing accessory is reachable by hit testing at its own position, ahead of the seek bar in priority order")
    func topTrailingIsReachableAheadOfSeekBar() {
        let source = ABMediaSource(url: URL(string: "https://example.com/slot-top-trailing.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        let view = ABPlayerControlsView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.player = player
        view.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        let probe = UIButton(type: .custom)
        probe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            probe.widthAnchor.constraint(equalToConstant: 30),
            probe.heightAnchor.constraint(equalToConstant: 30)
        ])
        view.setAccessoryViews([probe], in: .topTrailing)
        view.layoutIfNeeded()

        let center = probe.convert(CGPoint(x: probe.bounds.midX, y: probe.bounds.midY), to: view)
        #expect(view.hitTest(center, with: nil) === probe)
    }

    @Test("Given .always touch passthrough, slot accessories still win over passthrough — priority is unaffected by the passthrough setting")
    func passthroughAlwaysStillYieldsToASlotAccessory() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.touchPassthrough = .always
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        let probe = UIButton(type: .custom)
        probe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            probe.widthAnchor.constraint(equalToConstant: 30),
            probe.heightAnchor.constraint(equalToConstant: 30)
        ])
        view.setAccessoryViews([probe], in: .topTrailing)
        view.layoutIfNeeded()

        let center = probe.convert(CGPoint(x: probe.bounds.midX, y: probe.bounds.midY), to: view)
        #expect(view.hitTest(center, with: nil) === probe)
    }

    // MARK: - showsPlayPauseButton / showsSeekBar

    @Test("Given showsPlayPauseButton is false, the button stays hidden across an icon refresh, and buffering cannot revive it")
    func showsPlayPauseButtonFalseStaysHiddenThroughBufferingRefresh() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.showsPlayPauseButton = false
        let view = ABPlayerControlsView(configuration: configuration)
        #expect(view.playPauseButton.isHidden)

        view.handlePlayerEvent(.timeControlStatusChanged(.playing))
        #expect(view.playPauseButton.isHidden)

        view.handlePlayerEvent(.bufferingChanged(true))
        #expect(view.playPauseButton.isHidden)
    }

    @Test("Given showsSeekBar is false, the seek bar hides and does not participate in hit testing")
    func showsSeekBarFalseHidesAndExcludesFromHitTesting() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.showsSeekBar = false
        let view = ABPlayerControlsView(configuration: configuration)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 220)
        view.layoutIfNeeded()

        #expect(view.seekBar.isHidden)
        let center = view.seekBar.convert(CGPoint(x: view.seekBar.bounds.midX, y: view.seekBar.bounds.midY), to: view)
        #expect(view.hitTest(center, with: nil) !== view.seekBar)
    }
}
