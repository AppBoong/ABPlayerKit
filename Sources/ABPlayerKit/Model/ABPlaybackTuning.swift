import CoreGraphics
import Foundation

/// The bundle of tuning knobs applied to an `AVPlayerItem`/`AVPlayer`. Both
/// promotion and demotion apply this exact same type through the exact same
/// code path, which is what makes the two symmetric by construction
/// (DESIGN-ABPlayerKit.md §10, weakness #1).
public struct ABPlaybackTuning: Sendable, Equatable {
    /// Bits per second. `0` means unlimited (matches `AVPlayerItem` convention).
    public var preferredPeakBitRate: Double
    /// Seconds. `0` means automatic.
    public var preferredForwardBufferDuration: TimeInterval
    /// `.zero` means no cap.
    public var preferredMaximumResolution: CGSize
    public var automaticallyWaitsToMinimizeStalling: Bool

    public init(
        preferredPeakBitRate: Double,
        preferredForwardBufferDuration: TimeInterval,
        preferredMaximumResolution: CGSize,
        automaticallyWaitsToMinimizeStalling: Bool
    ) {
        self.preferredPeakBitRate = preferredPeakBitRate
        self.preferredForwardBufferDuration = preferredForwardBufferDuration
        self.preferredMaximumResolution = preferredMaximumResolution
        self.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling
    }

    /// No cap at all — the landing-cell default.
    public static let unrestricted = ABPlaybackTuning(
        preferredPeakBitRate: 0,
        preferredForwardBufferDuration: 0,
        preferredMaximumResolution: .zero,
        automaticallyWaitsToMinimizeStalling: true
    )

    /// The empirically-derived preload cap the reference implementation used
    /// (2Mbps / 5s). Note: `preferredForwardBufferDuration` is a soft hint on
    /// streams with segments ≥6s — a documented limitation, not a bug.
    public static let conservativePreload = ABPlaybackTuning(
        preferredPeakBitRate: 2_000_000,
        preferredForwardBufferDuration: 5,
        preferredMaximumResolution: .zero,
        automaticallyWaitsToMinimizeStalling: true
    )

    /// The `.current` default. Caps `preferredMaximumResolution` to the
    /// screen's pixel size (no perceptible quality loss, blocks over-rendition)
    /// via the `.displaySize` sentinel, resolved at apply time.
    public static let displayCapped = ABPlaybackTuning(
        preferredPeakBitRate: 0,
        preferredForwardBufferDuration: 0,
        preferredMaximumResolution: .displaySize,
        automaticallyWaitsToMinimizeStalling: true
    )

    /// Alternative preset that caps the bandwidth ceiling via rendition
    /// selection instead (cellular-oriented).
    public static let resolutionCapped = ABPlaybackTuning(
        preferredPeakBitRate: 2_000_000,
        preferredForwardBufferDuration: 5,
        preferredMaximumResolution: CGSize(width: 960, height: 540),
        automaticallyWaitsToMinimizeStalling: true
    )

    /// Returns a copy with the `.displaySize` sentinel (if present) replaced
    /// by `displaySize`. Pure — the caller supplies the actual screen size so
    /// this type stays free of `UIKit`.
    public func resolved(displaySize: CGSize) -> ABPlaybackTuning {
        guard preferredMaximumResolution == .displaySize else { return self }
        var copy = self
        copy.preferredMaximumResolution = displaySize
        return copy
    }
}

extension CGSize {
    /// Sentinel value meaning "cap to the screen's native pixel size at apply
    /// time" — never a real resolution, so it can't collide with a legitimate
    /// cap. Resolved by `ABPlaybackTuning.resolved(displaySize:)`.
    public static let displaySize = CGSize(width: -1, height: -1)
}
