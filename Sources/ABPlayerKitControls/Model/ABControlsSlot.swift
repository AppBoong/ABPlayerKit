/// A position within the controls overlay where consumer-provided accessory
/// views can be placed — see ``ABPlayerControlsView/accessoryViews(in:)``.
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
