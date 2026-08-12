@preconcurrency import AVFoundation
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
    /// `nil` leaves `AVFoundation`'s own default algorithm unchanged.
    /// Exposes `AVPlayerItem.audioTimePitchAlgorithm` so a consumer using
    /// non-1.0 playback rates can opt into (or out of) time-pitch
    /// correction. Added at the end of the parameter list to keep existing
    /// positional-adjacent call sites source-compatible.
    public var audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm?

    /// Defaults mirror `.displayCapped` (Q2 in DESIGN-OPEN-QUESTIONS.md's
    /// confirmed `.current` default) so a bare `ABPlaybackTuning()` is a
    /// sensible, semver-safe starting point for a new tuning value added in
    /// a minor release.
    public init(
        preferredPeakBitRate: Double = 0,
        preferredForwardBufferDuration: TimeInterval = 0,
        preferredMaximumResolution: CGSize = displaySizeSentinel,
        automaticallyWaitsToMinimizeStalling: Bool = true,
        audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm? = nil
    ) {
        self.preferredPeakBitRate = preferredPeakBitRate
        self.preferredForwardBufferDuration = preferredForwardBufferDuration
        self.preferredMaximumResolution = preferredMaximumResolution
        self.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling
        self.audioTimePitchAlgorithm = audioTimePitchAlgorithm
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
    /// via `displaySizeSentinel`, resolved at apply time.
    public static let displaySizeSentinel = CGSize(width: -1, height: -1)

    /// Delegates to the bare `init()` rather than repeating its defaults —
    /// the two are byte-identical (round3 Phase1+2 review m11), and this
    /// keeps them from drifting apart if either changes independently.
    public static let displayCapped = ABPlaybackTuning()

    /// Alternative preset that caps the bandwidth ceiling via rendition
    /// selection instead (cellular-oriented).
    public static let resolutionCapped = ABPlaybackTuning(
        preferredPeakBitRate: 2_000_000,
        preferredForwardBufferDuration: 5,
        preferredMaximumResolution: CGSize(width: 960, height: 540),
        automaticallyWaitsToMinimizeStalling: true
    )

    /// Returns a copy with `displaySizeSentinel` (if present) replaced
    /// by `displaySize`. Pure — the caller supplies the actual screen size so
    /// this type stays free of `UIKit`.
    public func resolved(displaySize: CGSize) -> ABPlaybackTuning {
        guard preferredMaximumResolution == Self.displaySizeSentinel else { return self }
        var copy = self
        copy.preferredMaximumResolution = displaySize
        return copy
    }
}
