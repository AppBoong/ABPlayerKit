import ABTestSupport
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Control buttons resolve style-driven icons safely", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABControlButtonTests {
    @Test("Given a valid system symbol, the button displays its configured image")
    func systemSymbolDisplays() {
        let button = ABControlButton()

        button.apply(icon: .system("play.fill"), style: ABPlayerControlsStyle())

        #expect(button.image(for: .normal) != nil)
        #expect(!button.isHidden)
    }

    @Test("Given an unknown system symbol, the button hides without crashing")
    func unknownSymbolHides() {
        let button = ABControlButton()

        button.apply(icon: .system("abplayerkit.symbol.does.not.exist"), style: ABPlayerControlsStyle())

        #expect(button.image(for: .normal) == nil)
        #expect(button.isHidden)
    }

    @Test("Given a consumer image, the button displays that image")
    func customImageDisplays() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 4, height: 4)))
        }
        let button = ABControlButton()

        button.apply(icon: .image(image), style: ABPlayerControlsStyle())

        #expect(button.image(for: .normal) != nil)
        #expect(!button.isHidden)
    }

    @Test("Given no icon, the button clears its image and hides")
    func noneHides() {
        let button = ABControlButton()
        button.apply(icon: .system("play.fill"), style: ABPlayerControlsStyle())

        button.apply(icon: .none, style: ABPlayerControlsStyle())

        #expect(button.image(for: .normal) == nil)
        #expect(button.isHidden)
    }

    @Test("Given a visual size below 44 points, hit testing expands to the minimum target")
    func hitTargetExpands() {
        let button = ABControlButton(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

        #expect(button.point(inside: CGPoint(x: -10, y: 10), with: nil))
        #expect(!button.point(inside: CGPoint(x: -13, y: 10), with: nil))
    }

    @Test("Given highlighted state, alpha follows the configured style and restores")
    func highlightUsesStyleAlpha() {
        var style = ABPlayerControlsStyle()
        style.buttonHighlightedAlpha = 0.4
        let button = ABControlButton()
        button.apply(icon: .system("play.fill"), style: style)

        button.isHighlighted = true
        #expect(abs(button.alpha - 0.4) < 0.000_1)
        button.isHighlighted = false
        #expect(button.alpha == 1)
    }
}
