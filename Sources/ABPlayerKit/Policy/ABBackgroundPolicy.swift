/// How an `ABPlayer` reacts to app background/foreground transitions.
public enum ABBackgroundPolicy: Sendable, Equatable {
    /// Do nothing (the reference implementation's current behavior — kept as
    /// an explicit opt-in rather than removed).
    case ignore
    /// Pause on background entry, restore the prior playback state on
    /// foreground return.
    case pause
    /// Pause + detach `AVPlayerLayer.player` (releases the decoder).
    /// Re-attached on return.
    case pauseAndDetachLayer
    /// Pause + demote the grade to `.instanceOnly` (blocks network entirely).
    /// Restores the prior grade on return.
    case demoteToInstance
}
