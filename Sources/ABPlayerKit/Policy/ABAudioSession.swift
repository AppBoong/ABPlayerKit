@preconcurrency import AVFoundation

/// Explicit-call-only facade over `AVAudioSession`. `ABPlayer` never calls
/// this on the consumer's behalf — see `ABAudioSessionPolicy`.
@MainActor
public enum ABAudioSession {
    public static func activate(_ policy: ABAudioSessionPolicy) throws {
        let session = AVAudioSession.sharedInstance()
        switch policy {
        case .unmanaged:
            return
        case .playback(let mixWithOthers):
            try session.setCategory(
                .playback,
                options: mixWithOthers ? [.mixWithOthers] : []
            )
            try session.setActive(true)
        case .ambient:
            try session.setCategory(.ambient)
            try session.setActive(true)
        }
    }

    public static func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
