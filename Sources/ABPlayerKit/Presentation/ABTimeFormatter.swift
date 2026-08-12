@preconcurrency import AVFoundation
import Foundation

/// Locale-independent playback time formatting.
public enum ABTimeFormatter {
    public static let liveMarker = "LIVE"

    /// Formats seconds as `M:SS`, or `H:MM:SS` once the hours field is needed
    /// (0 → `"0:00"`, 3599 → `"59:59"`, 3600 → `"1:00:00"`). Design contract,
    /// semver-stable as of v0.2.
    /// Consumers that specifically want an always-`HH:MM:SS`, zero-padded
    /// clock display (e.g. `ABPlayerControlsConfiguration.TimeLabelFormat.fixedHours`)
    /// build that themselves; this default favors the minimal, locale-independent
    /// form a bare timestamp reads best in (matching common media-player
    /// convention), which also stays reasonable for downstream short-form UI
    /// reuse (this type is public specifically so `ABShortsKit` can share it)
    /// where a bare `HH:MM:SS` reads oddly for a 15-second clip.
    public static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalSeconds = Int(max(0, seconds).rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        guard hours > 0 else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    /// Formats a numeric `CMTime`, returning a placeholder for invalid or indefinite values.
    public static func string(from time: CMTime) -> String {
        guard time.isNumeric else { return "--:--" }
        return string(from: CMTimeGetSeconds(time))
    }

    /// Formats the nonnegative time remaining with a leading minus sign
    /// (e.g. `"-3:33"`; `current > duration` clamps to `"-0:00"`).
    public static func remainingString(current: TimeInterval, duration: TimeInterval?) -> String {
        guard current.isFinite, let duration, duration.isFinite else { return "--:--" }
        return "-\(string(from: max(0, duration - current)))"
    }

    /// Formats seconds as `MM:SS`, or `HH:MM:SS` once the hours field is needed.
    ///
    /// The hours field is shown when `referenceDuration` (or `seconds` itself, when no
    /// reference is supplied) is at least one hour. Passing the same `referenceDuration`
    /// to both an elapsed and a total-time call keeps their field widths consistent.
    public static func automaticString(from seconds: TimeInterval, referenceDuration: TimeInterval? = nil) -> String {
        let hourBasis = referenceDuration ?? seconds
        let showsHours = hourBasis.isFinite && hourBasis >= 3_600
        guard seconds.isFinite else { return showsHours ? "--:--:--" : "--:--" }
        let totalSeconds = Int(max(0, seconds).rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        guard showsHours else {
            return String(format: "%02d:%02d", minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    /// `CMTime` overload of ``automaticString(from:referenceDuration:)``.
    public static func automaticString(from time: CMTime, referenceDuration: CMTime? = nil) -> String {
        let referenceSeconds = referenceDuration.flatMap { $0.isNumeric ? CMTimeGetSeconds($0) : nil }
        guard time.isNumeric else {
            let showsHours = (referenceSeconds ?? 0) >= 3_600
            return showsHours ? "--:--:--" : "--:--"
        }
        return automaticString(from: CMTimeGetSeconds(time), referenceDuration: referenceSeconds)
    }
}
