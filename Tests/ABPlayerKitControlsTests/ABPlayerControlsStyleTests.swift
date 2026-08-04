import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Control styles provide stable defaults and presets")
@MainActor
struct ABPlayerControlsStyleTests {
    @Test("Given a fresh style, it equals the documented default preset")
    func defaultPresetMatchesInitializer() {
        #expect(ABPlayerControlsStyle() == .default)
        #expect(ABPlayerControlsStyle.default.playIcon == .system("play.fill"))
        #expect(ABPlayerControlsStyle.default.trackHeight == 3)
        #expect(ABPlayerControlsStyle.default.thumbSize == CGSize(width: 12, height: 12))
    }

    @Test("Given the minimal preset, decorative background, buffer, and shadow are removed")
    func minimalPresetSnapshot() {
        let style = ABPlayerControlsStyle.minimal

        #expect(style.backgroundStyle == .none)
        #expect(style.bufferedColor == .clear)
        #expect(style.trackHeight == 2)
        #expect(style.thumbShadowOpacity == 0)
    }

    @Test("Given the tinted preset, accent colors and material background agree")
    func tintedPresetSnapshot() {
        let style = ABPlayerControlsStyle.tinted

        #expect(style.tintColor == .systemBlue)
        #expect(style.progressColor == .systemBlue)
        #expect(style.thumbColor == .systemBlue)
        #expect(style.backgroundStyle == .blur(.systemMaterial))
    }
}
