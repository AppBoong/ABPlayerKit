/// How an `ABPlayer` reacts to app background/foreground transitions.
///
/// Treat this enum as non-exhaustive, the same convention documented on
/// ``ABPlayerEvent``: minor releases may add cases, so switches outside
/// ABPlayerKit should include a `default` branch to remain source-compatible.
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
    /// Keep playing audio in the background; detach `AVPlayerLayer.player`
    /// (the condition iOS requires for backgrounded audio to continue).
    /// Re-attached on return. Requires the host app's `UIBackgroundModes`
    /// to include `audio` and `ABPlayerConfiguration/audioSessionPolicy` to
    /// be set to something other than `.unmanaged` — without both, this
    /// behaves like ``pause`` (the system suspends playback anyway, and
    /// this policy resumes it on foreground return the same way `.pause`
    /// does).
    case continueAudioOnly
}

extension ABBackgroundPolicy {
    /// Whether this policy detaches `AVPlayerLayer.player` on background
    /// entry — the property `applyConfigurationChange` re-attaches against
    /// when switching away from a detaching policy, so every detaching
    /// policy (not just ``pauseAndDetachLayer``) re-attaches correctly.
    var detachesLayerInBackground: Bool {
        switch self {
        case .pauseAndDetachLayer, .continueAudioOnly: true
        case .ignore, .pause, .demoteToInstance: false
        }
    }
}
