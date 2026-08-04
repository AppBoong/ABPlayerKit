@preconcurrency import AVFoundation

/// The tolerated range around a requested seek time.
public enum ABSeekTolerance: Sendable, Equatable {
    /// A frame-accurate seek with zero tolerance before and after the target.
    case precise
    /// A seek that may land within the supplied tolerances.
    case coarse(before: CMTime, after: CMTime)

    /// A balanced tolerance for interactive scrubbing.
    public static let scrubbing = ABSeekTolerance.coarse(
        before: CMTime(seconds: 0.5, preferredTimescale: 600),
        after: CMTime(seconds: 0.5, preferredTimescale: 600)
    )

    /// The widest tolerance, allowing the player to choose a nearby keyframe.
    public static let nearest = ABSeekTolerance.coarse(
        before: .positiveInfinity,
        after: .positiveInfinity
    )

    var before: CMTime {
        switch self {
        case .precise:
            .zero
        case .coarse(let before, _):
            before
        }
    }

    var after: CMTime {
        switch self {
        case .precise:
            .zero
        case .coarse(_, let after):
            after
        }
    }
}
