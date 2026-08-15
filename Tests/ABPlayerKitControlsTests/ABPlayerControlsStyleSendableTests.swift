import ABTestSupport
import Testing
import UIKit
@testable import ABPlayerKitControls

/// Compiling at all is the actual proof here — a non-Sendable type crossing
/// a `Task.detached` boundary is a compile error, not a runtime failure.
/// Each `#expect` below is just a sanity check that the value survived the
/// crossing intact.
@Suite("The five style types compile as Sendable, usable across an isolation boundary without @unchecked", .timeLimit(abScaledMinutes(3)))
struct ABPlayerControlsStyleSendableTests {
    @Test("ABPlayerControlsStyle crosses a Task.detached boundary")
    func styleCrossesIsolationBoundary() async {
        let style = await Task.detached { () -> ABPlayerControlsStyle in
            var value = ABPlayerControlsStyle()
            value.tintColor = .systemBlue
            return value
        }.value

        #expect(style.tintColor == .systemBlue)
    }

    @Test("ABControlIcon crosses a Task.detached boundary")
    func iconCrossesIsolationBoundary() async {
        let icon = await Task.detached { () -> ABControlIcon in .system("play.fill") }.value

        #expect(icon == .system("play.fill"))
    }

    @Test("ABControlsBackgroundStyle crosses a Task.detached boundary")
    func backgroundStyleCrossesIsolationBoundary() async {
        let background = await Task.detached { () -> ABControlsBackgroundStyle in .color(.black) }.value

        #expect(background == .color(.black))
    }

    @Test("ABTrackCornerRadius crosses a Task.detached boundary")
    func trackCornerRadiusCrossesIsolationBoundary() async {
        let radius = await Task.detached { () -> ABTrackCornerRadius in .fixed(4) }.value

        #expect(radius == .fixed(4))
    }

    @Test("ABRateLabelStyle crosses a Task.detached boundary")
    func rateLabelStyleCrossesIsolationBoundary() async {
        let rateStyle = await Task.detached { () -> ABRateLabelStyle in
            .text(font: .systemFont(ofSize: 12), format: "%@×")
        }.value

        #expect(rateStyle == .text(font: .systemFont(ofSize: 12), format: "%@×"))
    }

    @Test("The default/minimal/tinted presets are readable from a detached task now that ABPlayerControlsStyle no longer needs @MainActor isolation to be stored globally")
    func presetsAreReadableWithoutMainActorIsolation() async {
        let (defaultStyle, minimalStyle, tintedStyle) = await Task.detached {
            (ABPlayerControlsStyle.default, ABPlayerControlsStyle.minimal, ABPlayerControlsStyle.tinted)
        }.value

        #expect(defaultStyle == ABPlayerControlsStyle())
        #expect(minimalStyle.trackHeight == 2)
        #expect(tintedStyle.tintColor == .systemBlue)
    }
}
