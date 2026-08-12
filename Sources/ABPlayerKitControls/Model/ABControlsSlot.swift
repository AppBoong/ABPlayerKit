/// A position within the controls overlay where consumer-provided accessory
/// views can be placed — see ``ABPlayerControlsView/accessoryViews(in:)``.
///
/// Treat this enum as non-exhaustive, the same convention documented on
/// `ABPlayerEvent`: minor releases may add cases, so switches outside this
/// package should include a `default` branch. `CaseIterable`'s `allCases`
/// stays source-compatible either way — a future case is simply appended to
/// it — but an exhaustive `switch` is not.
public enum ABControlsSlot: Sendable, Hashable, CaseIterable {
    /// The overlay's top trailing corner.
    case topTrailing
    /// The trailing edge of the centered transport cluster. The cluster
    /// keeps its own centering — this slot's views sit in a separate stack
    /// anchored to the cluster's trailing edge, not inside it.
    case transportTrailing
    /// The bottom row, between the time label and the rate control. The
    /// same position as the legacy ``ABPlayerControlsView/accessoryViews``,
    /// which is now an alias for this slot.
    case bottomTrailing
}
