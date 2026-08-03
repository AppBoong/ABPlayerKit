/// The single source of truth for how much resource a player currently holds.
/// Replaces the ad-hoc `Set<Int>` membership + `index == currentIndex` comparison
/// pattern this library's reference implementation used (see DESIGN-ABPlayerKit.md §4.1).
public enum ABPlaybackGrade: Int, Sendable, CaseIterable, Comparable {
    /// No `AVPlayer` instance. All resources returned.
    case released = 0
    /// `AVPlayer` instance exists only. `currentItem == nil` → zero network.
    case instanceOnly = 1
    /// `AVPlayerItem` attached. Preload tuning (capped) applied, stopped, preroll target.
    case preloaded = 2
    /// `AVPlayerItem` attached. Playback tuning (uncapped) applied, `play()` allowed.
    case current = 3

    public var holdsItem: Bool { self >= .preloaded }
    public var holdsInstance: Bool { self >= .instanceOnly }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
