/// The library never touches `AVAudioSession` implicitly — it's an
/// app-global resource. A policy only takes effect through an explicit
/// `ABAudioSession.activate(_:)` call.
public enum ABAudioSessionPolicy: Sendable, Equatable {
    /// Default. Zero `AVAudioSession` calls made on the consumer's behalf.
    case unmanaged
    case playback(mixWithOthers: Bool)
    /// Honors the silent switch, keeps other apps' audio alive.
    case ambient
}
