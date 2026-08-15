import ABTestSupport
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls backgrounds replace their rendered content cleanly", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABControlsBackgroundViewTests {
    @Test("Given no background, the view remains transparent and empty")
    func noneIsTransparent() {
        let view = ABControlsBackgroundView()

        view.apply(.none)

        #expect(view.backgroundColor == UIColor.clear)
        #expect(view.renderedContentView == nil)
        #expect(view.gradientLayer == nil)
    }

    @Test("Given a color background, the requested color fills the view")
    func colorFillsView() {
        let view = ABControlsBackgroundView()

        view.apply(.color(.systemRed))

        #expect(view.backgroundColor == UIColor.systemRed)
        #expect(view.renderedContentView == nil)
        #expect(view.gradientLayer == nil)
    }

    @Test("Given a gradient background, its layer follows the view bounds")
    func gradientFollowsBounds() {
        let view = ABControlsBackgroundView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))

        view.apply(.gradient(top: .clear, bottom: .black))
        view.layoutIfNeeded()

        #expect(view.gradientLayer?.frame == view.bounds)
        #expect(view.gradientLayer?.colors?.count == 2)
    }

    @Test("Given a blur background, one visual-effect view fills the container")
    func blurFillsContainer() {
        let view = ABControlsBackgroundView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))

        view.apply(.blur(.systemMaterial))
        view.layoutIfNeeded()

        #expect(view.renderedContentView is UIVisualEffectView)
        #expect(view.renderedContentView?.frame == view.bounds)
    }

    @Test("Given repeated mode replacements, old subviews and layers are removed")
    func replacementCleansOldContent() {
        let view = ABControlsBackgroundView()

        view.apply(.blur(.systemMaterial))
        let oldBlur = view.renderedContentView
        view.apply(.gradient(top: .clear, bottom: .black))
        let oldGradient = view.gradientLayer
        view.apply(.color(.blue))

        #expect(oldBlur?.superview == nil)
        #expect(oldGradient?.superlayer == nil)
        #expect(view.subviews.isEmpty)
        #expect(view.layer.sublayers?.contains { $0 is CAGradientLayer } != true)
    }

    @Test("Given hidden controls, their background hides with the content")
    func visibilityIncludesBackground() {
        let view = ABPlayerControlsView()

        view.setControlsVisible(false, animated: false)

        #expect(view.controlsContentAlpha == 0)
        #expect(view.backgroundContentAlpha == 0)
    }
}
