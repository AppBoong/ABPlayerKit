@preconcurrency import AVFoundation
import CoreGraphics
import Testing
@testable import ABPlayerKit

@Suite("Seek bar geometry maps touches to progress", .timeLimit(.minutes(3)))
struct ABSeekBarGeometryTests {
    @Test("Given thumb width, touches at corrected track ends map to zero and one")
    func correctedEndsMapExactly() {
        let geometry = ABSeekBarGeometry(trackWidth: 100, thumbWidth: 20)

        #expect(geometry.progress(forTouchX: 10) == 0)
        #expect(geometry.progress(forTouchX: 90) == 1)
    }

    @Test("Given touches outside the track, progress remains clamped")
    func outsideTouchesClamp() {
        let geometry = ABSeekBarGeometry(trackWidth: 100, thumbWidth: 20)

        #expect(geometry.progress(forTouchX: -100) == 0)
        #expect(geometry.progress(forTouchX: 200) == 1)
    }

    @Test("Given no usable width, mapping avoids division by zero")
    func noUsableWidthIsSafe() {
        #expect(ABSeekBarGeometry(trackWidth: 0, thumbWidth: 0).progress(forTouchX: 5) == 0)
        #expect(ABSeekBarGeometry(trackWidth: 20, thumbWidth: 20).progress(forTouchX: 10) == 0)
    }

    @Test("Given a thumbless slim track, both physical ends remain reachable")
    func thumblessTrackUsesFullWidth() {
        let geometry = ABSeekBarGeometry(trackWidth: 100, thumbWidth: 0)

        #expect(geometry.progress(forTouchX: 0) == 0)
        #expect(geometry.progress(forTouchX: 100) == 1)
    }

    @Test("Given valid geometry, progress and thumb position round-trip")
    func progressAndPositionRoundTrip() {
        let geometry = ABSeekBarGeometry(trackWidth: 320, thumbWidth: 18, horizontalInset: 12)
        let center = geometry.thumbCenterX(forProgress: 0.375)

        #expect(abs(geometry.progress(forTouchX: center) - 0.375) < 0.000_001)
    }

    @Test("Given horizontal insets, their corrected ends map to zero and one")
    func insetEndsMapExactly() {
        let geometry = ABSeekBarGeometry(trackWidth: 100, thumbWidth: 0, horizontalInset: 10)

        #expect(geometry.progress(forTouchX: 10) == 0)
        #expect(geometry.progress(forTouchX: 90) == 1)
    }

    @Test("Given an inset larger than half the width, track and progress collapse together")
    func oversizedInsetCollapsesTrackAndProgressTogether() {
        let geometry = ABSeekBarGeometry(trackWidth: 100, thumbWidth: 20, horizontalInset: 80)

        #expect(geometry.thumbCenterX(forProgress: 0) == 50)
        #expect(geometry.thumbCenterX(forProgress: 1) == 50)
        #expect(geometry.progressWidth(forProgress: 1) == 0)
    }

    @Test("Given missing, zero, or indefinite duration, progress cannot produce time")
    func invalidDurationsHaveNoTime() {
        #expect(ABSeekBarGeometry.time(forProgress: 0.5, duration: nil) == nil)
        #expect(ABSeekBarGeometry.time(forProgress: 0.5, duration: .zero) == nil)
        #expect(ABSeekBarGeometry.time(forProgress: 0.5, duration: .indefinite) == nil)
    }

    @Test("Given valid duration, progress and time round-trip")
    func progressAndTimeRoundTrip() {
        let duration = CMTime(seconds: 240, preferredTimescale: 600)
        let time = ABSeekBarGeometry.time(forProgress: 0.625, duration: duration)

        #expect(time != nil)
        #expect(abs((ABSeekBarGeometry.progress(forTime: time!, duration: duration) ?? 0) - 0.625) < 0.000_001)
    }

    @Test("Given time beyond duration, derived progress clamps to one")
    func timeBeyondDurationClamps() {
        let duration = CMTime(seconds: 100, preferredTimescale: 600)
        let time = CMTime(seconds: 150, preferredTimescale: 600)

        #expect(ABSeekBarGeometry.progress(forTime: time, duration: duration) == 1)
    }
}

@Suite("Time labels format every duration shape", .timeLimit(.minutes(3)))
struct ABTimeFormatterTests {
    // Design contract (docs/DESIGN-v0.2-CONTROLS.md §5.4): minimal M:SS,
    // growing to H:MM:SS only once the hours field is needed — not a
    // permanently-padded HH:MM:SS. `ABPlayerControlsConfiguration.TimeLabelFormat.fixedHours`
    // is where the always-padded clock look lives instead.
    @Test("Given boundary second values, labels use the minimal M:SS/H:MM:SS form", arguments: [
        (0.0, "0:00"),
        (59.0, "0:59"),
        (60.0, "1:00"),
        (3_599.0, "59:59"),
        (3_600.0, "1:00:00")
    ])
    func formatsBoundaries(seconds: TimeInterval, expected: String) {
        #expect(ABTimeFormatter.string(from: seconds) == expected)
    }

    @Test("Given negative seconds, the label clamps to zero")
    func clampsNegativeSeconds() {
        #expect(ABTimeFormatter.string(from: -12) == "0:00")
    }

    @Test("Given non-finite seconds, the label uses a placeholder")
    func rejectsNonFiniteSeconds() {
        #expect(ABTimeFormatter.string(from: .nan) == "--:--")
        #expect(ABTimeFormatter.string(from: .infinity) == "--:--")
    }

    @Test("Given invalid or indefinite CMTime, the label uses a placeholder")
    func rejectsInvalidMediaTime() {
        #expect(ABTimeFormatter.string(from: .invalid) == "--:--")
        #expect(ABTimeFormatter.string(from: .indefinite) == "--:--")
    }

    @Test("Given elapsed and total time, the remaining label is derived")
    func derivesRemainingTime() {
        #expect(ABTimeFormatter.remainingString(current: 12, duration: 225) == "-3:33")
    }

    @Test("Given elapsed time beyond duration, remaining clamps to negative zero")
    func clampsRemainingTime() {
        #expect(ABTimeFormatter.remainingString(current: 250, duration: 225) == "-0:00")
    }

    @Test("Given no duration, remaining uses a placeholder")
    func missingDurationHasNoRemainingTime() {
        #expect(ABTimeFormatter.remainingString(current: 12, duration: nil) == "--:--")
    }

    @Test("Given no reference duration, automatic formatting derives hours from the value itself", arguments: [
        (0.0, "00:00"),
        (59.0, "00:59"),
        (599.0, "09:59"),
        (3_599.0, "59:59"),
        (3_600.0, "01:00:00"),
        (3_661.0, "01:01:01")
    ])
    func automaticFormattingWithoutReference(seconds: TimeInterval, expected: String) {
        #expect(ABTimeFormatter.automaticString(from: seconds) == expected)
    }

    @Test("Given a reference duration under one hour, short values stay MM:SS")
    func automaticFormattingShortReferenceStaysCompact() {
        #expect(ABTimeFormatter.automaticString(from: 12, referenceDuration: 200) == "00:12")
    }

    @Test("Given a reference duration at or beyond one hour, short values still show hours")
    func automaticFormattingLongReferenceShowsHours() {
        #expect(ABTimeFormatter.automaticString(from: 61, referenceDuration: 4_000) == "00:01:01")
    }

    @Test("Given non-finite seconds, automatic formatting uses a placeholder matching the reference width")
    func automaticFormattingRejectsNonFiniteSeconds() {
        #expect(ABTimeFormatter.automaticString(from: .nan) == "--:--")
        #expect(ABTimeFormatter.automaticString(from: .nan, referenceDuration: 4_000) == "--:--:--")
    }

    @Test("Given valid CMTime, automatic formatting matches the TimeInterval overload")
    func automaticFormattingMatchesCMTimeOverload() {
        let time = CMTime(seconds: 90, preferredTimescale: 600)
        let duration = CMTime(seconds: 4_000, preferredTimescale: 600)

        #expect(ABTimeFormatter.automaticString(from: time, referenceDuration: duration) == "00:01:30")
    }

    @Test("Given invalid or indefinite CMTime, automatic formatting uses a placeholder")
    func automaticFormattingRejectsInvalidMediaTime() {
        #expect(ABTimeFormatter.automaticString(from: .invalid) == "--:--")
        #expect(ABTimeFormatter.automaticString(from: .indefinite) == "--:--")
    }
}
