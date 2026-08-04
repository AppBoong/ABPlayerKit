@preconcurrency import AVFoundation
import ABPlayerKit
import SwiftUI
import Testing
@testable import ABPlayerKitControls

@Suite("SwiftUI convenience player composes video and controls")
@MainActor
struct ABVideoPlayerWithControlsTests {
    @Test("Given a player, the convenience view builds its layered body")
    func buildsBody() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        var configuration = ABPlayerControlsConfiguration()
        configuration.skipInterval = 15

        let view = ABVideoPlayerWithControls(
            player: player,
            style: .minimal,
            configuration: configuration
        )

        _ = view.body
    }

    @Test("Given a fixed SwiftUI container, controls fill the complete video overlay")
    func controlsFillVideoOverlay() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let rootView = ABVideoPlayerWithControls(player: player)
            .frame(width: 320, height: 180)
        let hostingController = UIHostingController(rootView: rootView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        window.rootViewController = hostingController
        window.isHidden = false
        defer { window.isHidden = true }
        hostingController.view.frame = CGRect(x: 0, y: 0, width: 320, height: 180)

        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        let controlsView = hostingController.view.firstDescendant(of: ABPlayerControlsView.self)
        #expect(controlsView != nil)
        #expect(controlsView?.frame.size == CGSize(width: 320, height: 180))
        #expect(controlsView?.alpha == 1)
        #expect(controlsView?.isHidden == false)
        #expect(controlsView?.hitTest(CGPoint(x: 160, y: 45), with: nil) != nil)
    }

    @Test("Given mounted SwiftUI controls, window hit testing reaches every interactive control")
    func mountedControlsReceiveTouches() throws {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(
            source: ABMediaSource(url: URL(string: "https://example.com/touch-test.mp4")!),
            grade: .current
        )
        let rootView = ABVideoPlayerWithControls(player: player)
            .frame(width: 390, height: 220)
        let hostingController = UIHostingController(rootView: rootView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.rootViewController = hostingController
        window.isHidden = false
        defer { window.isHidden = true }
        hostingController.view.frame = window.bounds
        hostingController.view.layoutIfNeeded()
        let controlsView = try #require(
            hostingController.view.firstDescendant(of: ABPlayerControlsView.self)
        )
        controlsView.handlePlayerEvent(.periodicTime(ABPlaybackTime(
            currentTime: CMTime(seconds: 30, preferredTimescale: 600),
            duration: CMTime(seconds: 120, preferredTimescale: 600),
            bufferedUntil: nil
        )))
        hostingController.view.layoutIfNeeded()

        for control in [
            controlsView.skipBackwardButton,
            controlsView.playPauseButton,
            controlsView.skipForwardButton,
            controlsView.rateButton,
            controlsView.seekBar
        ] {
            let center = control.convert(
                CGPoint(x: control.bounds.midX, y: control.bounds.midY),
                to: hostingController.view
            )
            #expect(hostingController.view.hitTest(center, with: nil) === control)
        }
    }
}

private extension UIView {
    func firstDescendant<View: UIView>(of type: View.Type) -> View? {
        if let match = self as? View {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}
