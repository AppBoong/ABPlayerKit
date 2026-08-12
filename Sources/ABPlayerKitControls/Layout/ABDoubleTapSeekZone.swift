import CoreGraphics

/// Which physical horizontal band a double-tap landed in — pure and
/// RTL-unaware by design (always physical coordinates); the caller flips
/// `.backward`/`.forward` for right-to-left layouts. Kept as a value type,
/// tested by table rather than through a live gesture recognizer, matching
/// `ABSeekBarGeometry`/`ABControlsLayout`.
enum ABDoubleTapSeekZone: Equatable {
    case backward
    case neutral
    case forward

    /// `edgeFraction` is clamped to `0.1...0.5`. `width <= 0` always yields
    /// `.neutral`.
    static func zone(forX x: CGFloat, width: CGFloat, edgeFraction: Double) -> Self {
        guard width > 0 else { return .neutral }
        let clampedFraction = min(max(edgeFraction, 0.1), 0.5)
        let edgeWidth = width * CGFloat(clampedFraction)
        if x < edgeWidth { return .backward }
        if x > width - edgeWidth { return .forward }
        return .neutral
    }

    var flippedHorizontally: Self {
        switch self {
        case .backward: .forward
        case .forward: .backward
        case .neutral: .neutral
        }
    }
}
