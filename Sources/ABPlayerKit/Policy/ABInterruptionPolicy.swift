/// How an `ABPlayer` reacts to `AVAudioSession` interruptions (phone calls,
/// Siri, another app taking the session).
///
/// Independent of `ABPlayerConfiguration/pausesOnRouteChangeDeviceUnavailable`
/// (headphone-disconnect handling), which is its own opt-out flag rather
/// than a case here — the two notifications warrant different default
/// behavior.
public enum ABInterruptionPolicy: Sendable, Equatable {
    /// Default. `ABPlayer` does not observe `AVAudioSession` interruptions
    /// at all — matches `ABBackgroundPolicy/ignore`'s "do nothing, kept as
    /// an explicit opt-in" convention.
    case ignore
    /// Pauses when an interruption begins (phone call, Siri, another app
    /// taking the session) while this player is `.current`, and resumes
    /// once the interruption ends if `AVAudioSessionInterruptionOptionKey`
    /// reports `.shouldResume` *and* this player was actually playing when
    /// the interruption began. Resuming reactivates the audio session
    /// through the same `ABAudioSessionCoordinator` path `play()` already
    /// uses, so this composes with
    /// `ABPlayerConfiguration/audioSessionPolicy` automatically.
    case pauseAndResume
}
