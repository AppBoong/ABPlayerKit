import ABPlayerKit
import Foundation

/// Pure time-label string formatting for `ABPlayerControlsView` — depends only
/// on `timeFormat`/`timeLabelLayout`, the same reason `ABControlsLayout` is a
/// value type with no `UIView` dependency, so the whole surface can be unit
/// tested without a `UIView` instance.
struct ABControlsTimeLabelFormatter {
    let timeFormat: ABPlayerControlsConfiguration.TimeLabelFormat
    let timeLabelLayout: ABPlayerControlsConfiguration.TimeLabelLayout
    /// Placed between the elapsed and secondary fields. Defaulted so every
    /// existing call site (this type predates the option) keeps rendering
    /// byte-identical output.
    let timeLabelSeparator: String

    init(
        timeFormat: ABPlayerControlsConfiguration.TimeLabelFormat,
        timeLabelLayout: ABPlayerControlsConfiguration.TimeLabelLayout,
        timeLabelSeparator: String = "/"
    ) {
        self.timeFormat = timeFormat
        self.timeLabelLayout = timeLabelLayout
        self.timeLabelSeparator = timeLabelSeparator
    }

    /// `elapsedSeconds`/`durationSeconds` are `nil` exactly when the
    /// corresponding `CMTime` isn't numeric (unknown elapsed time, or a live/
    /// unknown-duration item) — callers resolve that once, at the `CMTime`
    /// boundary, so this type never needs to know about `CMTime` itself.
    ///
    /// `.custom` contract (round3 Phase4 WP12): the formatter receives both
    /// the elapsed seconds and the reference duration in one call and is
    /// expected to produce the *entire* label text itself — `timeLabelLayout`'s
    /// elapsed/secondary combination does not apply, since the consumer
    /// already has both values and full control over layout. Combining on top
    /// of an already-complete `.custom` string produced the
    /// `"12s/90s/90s/90s"`-shaped double-combination bug this replaces.
    func label(elapsedSeconds: TimeInterval?, durationSeconds: TimeInterval?) -> String {
        if case .custom(let formatter) = timeFormat {
            guard let elapsedSeconds else {
                return placeholder(referenceDuration: durationSeconds)
            }
            return formatter(elapsedSeconds, durationSeconds)
        }

        let elapsed = elapsedSeconds.map { formattedTime($0, referenceDuration: durationSeconds) }
            ?? placeholder(referenceDuration: durationSeconds)
        let secondary: String?
        switch timeLabelLayout {
        case .elapsedAndTotal:
            secondary = durationSeconds.map { formattedTime($0, referenceDuration: durationSeconds) }
                ?? ABControlsLocalization.string("controls.liveMarker")
        case .elapsedAndRemaining:
            if let durationSeconds, let elapsedSeconds, elapsedSeconds.isFinite {
                let remaining = max(0, durationSeconds - elapsedSeconds)
                secondary = "-\(formattedTime(remaining, referenceDuration: durationSeconds))"
            } else {
                secondary = placeholder(referenceDuration: durationSeconds)
            }
        case .elapsedOnly:
            secondary = nil
        }
        return secondary.map { "\(elapsed)\(timeLabelSeparator)\($0)" } ?? elapsed
    }

    /// Independent of `timeFormat`/`timeLabelLayout` — VoiceOver always hears
    /// spoken elapsed/duration, regardless of how the visible label is
    /// formatted (including under `.custom`, which only replaces the on-screen
    /// text).
    func accessibilityValue(elapsedSeconds: TimeInterval?, durationSeconds: TimeInterval?) -> String {
        guard let elapsedSeconds, let durationSeconds else {
            return ABControlsLocalization.string("controls.live")
        }
        return ABControlsLocalization.format(
            "controls.timelineValue",
            ABControlsLocalization.spokenTime(elapsedSeconds),
            ABControlsLocalization.spokenTime(durationSeconds)
        )
    }

    /// Formats `seconds` per `.automatic`/`.fixedHours`. `referenceDuration` is
    /// passed to `.automatic` so every label in a render pass (elapsed, total,
    /// remaining) agrees on field width. Never called for `.custom` — `label`
    /// branches on `.custom` once, at its own entry point, before this helper
    /// is ever reached (round3 Phase4 fix — REVIEW-round3-final.md N14: the
    /// pre-extraction `formattedTime` carried a `.custom` case that was always
    /// dead code for exactly this reason, silently).
    private func formattedTime(_ seconds: TimeInterval, referenceDuration: TimeInterval?) -> String {
        switch timeFormat {
        case .automatic:
            return ABTimeFormatter.automaticString(from: seconds, referenceDuration: referenceDuration)
        case .fixedHours:
            return Self.fixedHoursString(from: seconds)
        case .custom:
            assertionFailure("formattedTime must not be reached for .custom — label(elapsedSeconds:durationSeconds:) branches on .custom before calling it")
            return ""
        }
    }

    /// Always `HH:MM:SS`, zero-padded, including the hours field even when
    /// zero. `.fixedHours`'s own formatter, not `ABTimeFormatter.string(from:)`
    /// — that core API's default contract is the minimal `M:SS`/`H:MM:SS` form
    /// (see `docs/DESIGN-v0.2-CONTROLS.md` §5.4); `.fixedHours` exists
    /// specifically for consumers who want the always-padded clock look
    /// instead, so it can't delegate to a formatter with different semantics.
    private static func fixedHoursString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--:--" }
        let totalSeconds = Int(max(0, seconds).rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    private func placeholder(referenceDuration: TimeInterval?) -> String {
        switch timeFormat {
        case .automatic:
            (referenceDuration ?? 0) >= 3_600 ? "--:--:--" : "--:--"
        case .fixedHours, .custom:
            "--:--:--"
        }
    }
}
