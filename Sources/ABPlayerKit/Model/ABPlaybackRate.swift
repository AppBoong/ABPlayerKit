import Foundation

/// Playback-rate validation and common presets.
public enum ABPlaybackRate {
    /// Rates accepted by ABPlayerKit.
    public static let allowedRange: ClosedRange<Float> = 0.25...4.0

    /// Common playback-rate choices for user interfaces.
    public static let common: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    /// Returns `rate` constrained to ``allowedRange``.
    public static func clamped(_ rate: Float) -> Float {
        guard !rate.isNaN else { return 1.0 }
        return min(max(rate, allowedRange.lowerBound), allowedRange.upperBound)
    }
}
