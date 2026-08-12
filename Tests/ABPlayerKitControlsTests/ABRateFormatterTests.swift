import Foundation
import Testing
@testable import ABPlayerKitControls

@Suite("ABRateFormatter renders locale-aware rate values, no UIView required", .timeLimit(.minutes(3)))
struct ABRateFormatterTests {
    @Test("Given en_US, whole numbers drop the decimal and fractional rates use a dot separator", arguments: [
        (Float(0.5), "0.5"),
        (Float(1), "1"),
        (Float(1.25), "1.25"),
        (Float(1.5), "1.5"),
        (Float(2), "2"),
        (Float(4), "4")
    ])
    func enUSFormatting(rate: Float, expected: String) {
        let formatter = ABRateFormatter(locale: Locale(identifier: "en_US"))
        #expect(formatter.string(from: rate) == expected)
    }

    @Test("Given de_DE, the fractional separator is a comma", arguments: [
        (Float(0.5), "0,5"),
        (Float(1), "1"),
        (Float(1.25), "1,25"),
        (Float(1.5), "1,5"),
        (Float(2), "2"),
        (Float(4), "4")
    ])
    func deDEFormatting(rate: Float, expected: String) {
        let formatter = ABRateFormatter(locale: Locale(identifier: "de_DE"))
        #expect(formatter.string(from: rate) == expected)
    }

    @Test("Given fr_FR, the fractional separator is a comma, matching de_DE's behavior")
    func frFRFormatting() {
        let formatter = ABRateFormatter(locale: Locale(identifier: "fr_FR"))
        #expect(formatter.string(from: 1.5) == "1,5")
        #expect(formatter.string(from: 2) == "2")
    }

    @Test("Given ko_KR, formatting matches en_US's dot separator and undecorated whole numbers")
    func koKRFormatting() {
        let formatter = ABRateFormatter(locale: Locale(identifier: "ko_KR"))
        #expect(formatter.string(from: 0.5) == "0.5")
        #expect(formatter.string(from: 1) == "1")
        #expect(formatter.string(from: 1.5) == "1.5")
    }

    @Test("No grouping separator is ever introduced, even for a rate large enough to have one")
    func neverGroups() {
        let formatter = ABRateFormatter(locale: Locale(identifier: "en_US"))
        #expect(formatter.string(from: 1_000) == "1000")
    }

    @Test("At most two fraction digits are ever shown")
    func clampsToTwoFractionDigits() {
        let formatter = ABRateFormatter(locale: Locale(identifier: "en_US"))
        #expect(formatter.string(from: 1.256) == "1.26")
    }
}
