@preconcurrency import AVFoundation
import CoreGraphics

/// Converts between seek-bar view coordinates, playback progress, and media time.
///
/// `trackWidth` is the full width of the coordinate space supplied to
/// ``progress(forTouchX:)``. The usable track is derived by removing
/// `horizontalInset` from both edges and reserving half of `thumbWidth`.
public struct ABSeekBarGeometry: Sendable, Equatable {
    /// The full coordinate-space width before horizontal insets are applied.
    public let trackWidth: CGFloat
    /// The visual thumb width reserved inside the usable track.
    public let thumbWidth: CGFloat
    /// The inset applied to each horizontal edge of `trackWidth`.
    public let horizontalInset: CGFloat

    /// Creates geometry in a coordinate space whose horizontal range is
    /// `0...trackWidth`.
    public init(trackWidth: CGFloat, thumbWidth: CGFloat, horizontalInset: CGFloat = 0) {
        self.trackWidth = max(0, trackWidth)
        self.thumbWidth = max(0, thumbWidth)
        self.horizontalInset = max(0, horizontalInset)
    }

    /// Maps a view-space horizontal touch coordinate to `0...1`.
    public func progress(forTouchX x: CGFloat) -> Double {
        let bounds = usableBounds
        guard bounds.length > 0 else { return 0 }
        return Self.clampedProgress(Double((x - bounds.lower) / bounds.length))
    }

    /// Maps `0...1` to the thumb's center in view coordinates.
    public func thumbCenterX(forProgress progress: Double) -> CGFloat {
        let bounds = usableBounds
        return bounds.lower + (bounds.length * CGFloat(Self.clampedProgress(progress)))
    }

    /// Returns the progress layer width, extending from the track inset to the thumb center.
    public func progressWidth(forProgress progress: Double) -> CGFloat {
        max(0, thumbCenterX(forProgress: progress) - min(horizontalInset, trackWidth / 2))
    }

    /// Converts progress into media time when duration is finite and positive.
    public static func time(forProgress progress: Double, duration: CMTime?) -> CMTime? {
        guard let duration, duration.isNumeric else { return nil }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return nil }
        return CMTime(
            seconds: durationSeconds * clampedProgress(progress),
            preferredTimescale: duration.timescale > 0 ? duration.timescale : 600
        )
    }

    /// Converts media time into progress when duration is finite and positive.
    public static func progress(forTime time: CMTime, duration: CMTime?) -> Double? {
        guard let duration, duration.isNumeric, time.isNumeric else { return nil }
        let durationSeconds = CMTimeGetSeconds(duration)
        let timeSeconds = CMTimeGetSeconds(time)
        guard durationSeconds.isFinite, durationSeconds > 0, timeSeconds.isFinite else { return nil }
        return clampedProgress(timeSeconds / durationSeconds)
    }

    private var usableBounds: (lower: CGFloat, length: CGFloat) {
        let boundedInset = min(horizontalInset, trackWidth / 2)
        let insetLower = boundedInset
        let insetUpper = max(insetLower, trackWidth - boundedInset)
        let boundedHalfThumb = min(thumbWidth / 2, (insetUpper - insetLower) / 2)
        let lower = insetLower + boundedHalfThumb
        let upper = insetUpper - boundedHalfThumb
        return (lower, max(0, upper - lower))
    }

    private static func clampedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }
}
