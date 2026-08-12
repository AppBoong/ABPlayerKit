import ABPlayerKit
import Testing
@testable import ABPlayerKitControls

@Suite("ABControlsTimeLabelFormatter formats elapsed/duration strings from plain seconds, no CMTime or UIView required", .timeLimit(.minutes(3)))
struct ABControlsTimeLabelFormatterTests {
    // MARK: - .automatic × each TimeLabelLayout

    @Test("Given .automatic and .elapsedAndTotal, both fields share the wider field width")
    func automaticElapsedAndTotal() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedAndTotal)

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "01:05/02:05")
    }

    @Test("Given .automatic and .elapsedAndRemaining, the secondary field is the minus-prefixed time left")
    func automaticElapsedAndRemaining() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedAndRemaining)

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "01:05/-01:00")
    }

    @Test("Given .automatic and .elapsedOnly, no secondary field is appended")
    func automaticElapsedOnly() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedOnly)

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "01:05")
    }

    // MARK: - .fixedHours × each TimeLabelLayout

    @Test("Given .fixedHours and .elapsedAndTotal, both fields are always HH:MM:SS")
    func fixedHoursElapsedAndTotal() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .fixedHours, timeLabelLayout: .elapsedAndTotal)

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "00:01:05/00:02:05")
    }

    @Test("Given .fixedHours and .elapsedAndRemaining, the secondary field is the minus-prefixed HH:MM:SS time left")
    func fixedHoursElapsedAndRemaining() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .fixedHours, timeLabelLayout: .elapsedAndRemaining)

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "00:01:05/-00:01:00")
    }

    @Test("Given .fixedHours and .elapsedOnly, no secondary field is appended")
    func fixedHoursElapsedOnly() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .fixedHours, timeLabelLayout: .elapsedOnly)

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "00:01:05")
    }

    // MARK: - .custom contract (round3 Phase4 WP12): never combined with timeLabelLayout

    @Test("Given .custom, the formatter's return value is used verbatim regardless of timeLabelLayout — proving the contract that timeLabelLayout's combination never applies to .custom")
    func customBypassesTimeLabelLayoutCombination() {
        let formatter = ABControlsTimeLabelFormatter(
            timeFormat: .custom { elapsed, duration in "E\(Int(elapsed))D\(Int(duration ?? -1))" },
            // .elapsedAndTotal would append a second field for every other
            // format — if this leaked into .custom's output, this assertion
            // would fail, since the caller's string alone has no such field.
            timeLabelLayout: .elapsedAndTotal
        )

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "E65D125")
    }

    @Test("Given .custom with a nil (non-numeric) elapsed, the shared placeholder is used instead of calling the consumer's formatter")
    func customUsesPlaceholderWhenElapsedIsNil() {
        let formatter = ABControlsTimeLabelFormatter(
            timeFormat: .custom { _, _ in "should not be called" },
            timeLabelLayout: .elapsedOnly
        )

        #expect(formatter.label(elapsedSeconds: nil, durationSeconds: 125) == "--:--:--")
    }

    // MARK: - Live (nil duration) and unknown (nil elapsed) placeholders

    @Test("Given .automatic and .elapsedAndTotal with no duration (live), the secondary field is the LIVE marker")
    func automaticElapsedAndTotalLiveDuration() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedAndTotal)

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: nil) == "01:05/\(ABControlsLocalization.string("controls.liveMarker"))")
    }

    @Test("Given .automatic with a nil (non-numeric) elapsed and a sub-hour duration reference, the short placeholder is used")
    func automaticPlaceholderIsShortUnderAnHour() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedAndTotal)

        #expect(formatter.label(elapsedSeconds: nil, durationSeconds: 125) == "--:--/02:05")
    }

    @Test("Given .automatic with a nil (non-numeric) elapsed and an hour-plus duration reference, the placeholder grows to include an hours field")
    func automaticPlaceholderGrowsAtAnHour() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedOnly)

        #expect(formatter.label(elapsedSeconds: nil, durationSeconds: 4_000) == "--:--:--")
    }

    // MARK: - Negative remaining clamp (elapsed past duration)

    @Test("Given elapsed past duration under .elapsedAndRemaining, the remaining field clamps to zero instead of going negative")
    func remainingClampsToZeroPastDuration() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedAndRemaining)

        #expect(formatter.label(elapsedSeconds: 200, durationSeconds: 125) == "03:20/-00:00")
    }

    // MARK: - accessibilityValue: independent of timeFormat/timeLabelLayout

    @Test("Given finite elapsed and duration, accessibilityValue is non-empty regardless of the configured timeFormat")
    func accessibilityValueIsNonEmptyWhenBothAreKnown() {
        let formatter = ABControlsTimeLabelFormatter(
            timeFormat: .custom { _, _ in "irrelevant to accessibilityValue" },
            timeLabelLayout: .elapsedAndTotal
        )

        #expect(formatter.accessibilityValue(elapsedSeconds: 72, durationSeconds: 225).isEmpty == false)
    }

    @Test("Given a nil duration (live), accessibilityValue falls back to the localized live string")
    func accessibilityValueFallsBackToLiveWhenDurationIsNil() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedAndTotal)

        #expect(formatter.accessibilityValue(elapsedSeconds: 72, durationSeconds: nil) == ABControlsLocalization.string("controls.live"))
    }

    @Test("Given a nil (non-numeric) elapsed, accessibilityValue falls back to the localized live string")
    func accessibilityValueFallsBackToLiveWhenElapsedIsNil() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .automatic, timeLabelLayout: .elapsedAndTotal)

        #expect(formatter.accessibilityValue(elapsedSeconds: nil, durationSeconds: 225) == ABControlsLocalization.string("controls.live"))
    }

    // MARK: - timeLabelSeparator

    @Test("Given the default 2-argument initializer, timeLabelSeparator defaults to \"/\", byte-identical to the historical hardcoded value")
    func timeLabelSeparatorDefaultsToSlash() {
        let formatter = ABControlsTimeLabelFormatter(timeFormat: .fixedHours, timeLabelLayout: .elapsedAndTotal)

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "00:01:05/00:02:05")
    }

    @Test("Given an explicit timeLabelSeparator, it replaces \"/\" between the elapsed and secondary fields")
    func explicitTimeLabelSeparatorReplacesSlash() {
        let formatter = ABControlsTimeLabelFormatter(
            timeFormat: .fixedHours,
            timeLabelLayout: .elapsedAndTotal,
            timeLabelSeparator: " — "
        )

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "00:01:05 — 00:02:05")
    }

    @Test("Given .elapsedOnly, timeLabelSeparator is irrelevant — there's no secondary field to join")
    func timeLabelSeparatorIsIrrelevantForElapsedOnly() {
        let formatter = ABControlsTimeLabelFormatter(
            timeFormat: .fixedHours,
            timeLabelLayout: .elapsedOnly,
            timeLabelSeparator: " — "
        )

        #expect(formatter.label(elapsedSeconds: 65, durationSeconds: 125) == "00:01:05")
    }
}
