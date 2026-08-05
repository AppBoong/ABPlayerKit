import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Control styles provide stable defaults and presets", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerControlsStyleTests {
    @Test("Given a fresh style, it equals the documented default preset")
    func defaultPresetMatchesInitializer() {
        #expect(ABPlayerControlsStyle() == .default)
        #expect(ABPlayerControlsStyle.default.playIcon == .system("play.fill"))
        #expect(ABPlayerControlsStyle.default.trackHeight == 3)
        #expect(ABPlayerControlsStyle.default.thumbSize == CGSize(width: 12, height: 12))
        #expect(ABPlayerControlsStyle.default.tintColor == .white)
        #expect(ABPlayerControlsStyle.default.timeLabelColor == .white)
        #expect(ABPlayerControlsStyle.default.progressColor == .white)
        #expect(ABPlayerControlsStyle.default.thumbColor == .white)
        #expect(ABPlayerControlsStyle.default.trackColor == UIColor.white.withAlphaComponent(0.3))
        #expect(ABPlayerControlsStyle.default.backgroundStyle == .gradient(
            top: UIColor.black.withAlphaComponent(0.08),
            bottom: UIColor.black.withAlphaComponent(0.3)
        ))
    }

    @Test("Given the minimal preset, its scrim and timeline decoration stay lightweight")
    func minimalPresetSnapshot() {
        let style = ABPlayerControlsStyle.minimal

        #expect(style.backgroundStyle == .gradient(
            top: .clear,
            bottom: UIColor.black.withAlphaComponent(0.16)
        ))
        #expect(style.bufferedColor == .clear)
        #expect(style.trackColor == UIColor.white.withAlphaComponent(0.24))
        #expect(style.trackHeight == 2)
        #expect(style.thumbShadowOpacity == 0)
    }

    @Test("Given the tinted preset, accents sit over a translucent scrim instead of material")
    func tintedPresetSnapshot() {
        let style = ABPlayerControlsStyle.tinted

        #expect(style.tintColor == .systemBlue)
        #expect(style.progressColor == .systemBlue)
        #expect(style.thumbColor == .systemBlue)
        #expect(style.trackColor == UIColor.white.withAlphaComponent(0.28))
        #expect(style.bufferedColor == UIColor.systemBlue.withAlphaComponent(0.42))
        #expect(style.backgroundStyle == .gradient(
            top: UIColor.systemBlue.withAlphaComponent(0.04),
            bottom: UIColor.black.withAlphaComponent(0.24)
        ))
    }
}
