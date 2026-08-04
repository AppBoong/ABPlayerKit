@preconcurrency import AVFoundation
import Foundation

/// A point-in-time snapshot used to render playback progress.
public struct ABPlaybackTime: Sendable, Equatable {
    public let currentTime: CMTime
    /// The finite item duration, or `nil` for live and unresolved streams.
    public let duration: CMTime?
    /// The end of the loaded range containing ``currentTime``.
    public let bufferedUntil: CMTime?

    public init(currentTime: CMTime, duration: CMTime?, bufferedUntil: CMTime?) {
        self.currentTime = currentTime
        self.duration = Self.validDuration(duration)
        self.bufferedUntil = bufferedUntil
    }

    /// The current position constrained to `0...1`, if duration is known.
    public var progress: Double? {
        Self.ratio(currentTime, duration: duration)
    }

    /// The buffered position constrained to `0...1`, if both values are known.
    public var bufferedProgress: Double? {
        guard let bufferedUntil else { return nil }
        return Self.ratio(bufferedUntil, duration: duration)
    }

    public static let zero = ABPlaybackTime(
        currentTime: .zero,
        duration: nil,
        bufferedUntil: nil
    )

    private static func validDuration(_ duration: CMTime?) -> CMTime? {
        guard let duration, duration.isNumeric else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return duration
    }

    private static func ratio(_ time: CMTime, duration: CMTime?) -> Double? {
        guard let duration, time.isNumeric else { return nil }
        let seconds = CMTimeGetSeconds(time)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, durationSeconds.isFinite, durationSeconds > 0 else { return nil }
        return min(max(seconds / durationSeconds, 0), 1)
    }
}
