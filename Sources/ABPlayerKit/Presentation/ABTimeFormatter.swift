@preconcurrency import AVFoundation
import Foundation

/// Locale-independent playback time formatting.
public enum ABTimeFormatter {
    public static let liveMarker = "LIVE"

    /// Formats seconds as `HH:MM:SS`, always including the hours field.
    public static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--:--" }
        let totalSeconds = Int(max(0, seconds).rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    /// Formats a numeric `CMTime`, returning a placeholder for invalid or indefinite values.
    public static func string(from time: CMTime) -> String {
        guard time.isNumeric else { return "--:--:--" }
        return string(from: CMTimeGetSeconds(time))
    }

    /// Formats the nonnegative time remaining with a leading minus sign.
    public static func remainingString(current: TimeInterval, duration: TimeInterval?) -> String {
        guard current.isFinite, let duration, duration.isFinite else { return "--:--:--" }
        return "-\(string(from: max(0, duration - current)))"
    }
}
