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

/// The pieces of `AVAudioSession` state ``ABPlayer`` saves before applying an
/// opt-in ``ABAudioSessionPolicy`` so it can restore exactly what the host
/// app had configured (Q4 in DESIGN-OPEN-QUESTIONS.md — restoration failures
/// are surfaced as events, never thrown).
struct ABAudioSessionCategorySnapshot: Sendable, Equatable {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
}

/// Test seam between ``ABPlayer`` and `AVAudioSession`. `ABPlayer` only ever
/// talks to `AVAudioSession` through this protocol, so
/// `ABPlayerKitTests` can fake apply/restore ordering without touching the
/// real, process-global audio session.
@MainActor
protocol ABAudioSessionControlling: AnyObject {
    func snapshotCurrentCategory() -> ABAudioSessionCategorySnapshot
    func activate(_ policy: ABAudioSessionPolicy) throws
    /// Restores a previously captured snapshot and deactivates the session.
    func restore(_ snapshot: ABAudioSessionCategorySnapshot) throws
}

/// The real `AVAudioSession`-backed conformer, forwarding activation to
/// ``ABAudioSession`` and adding the snapshot/restore pair that opt-in
/// ``ABAudioSessionPolicy`` auto-apply needs.
final class ABAudioSessionAdapter: ABAudioSessionControlling {
    func snapshotCurrentCategory() -> ABAudioSessionCategorySnapshot {
        let session = AVAudioSession.sharedInstance()
        return ABAudioSessionCategorySnapshot(
            category: session.category,
            mode: session.mode,
            options: session.categoryOptions
        )
    }

    func activate(_ policy: ABAudioSessionPolicy) throws {
        try ABAudioSession.activate(policy)
    }

    func restore(_ snapshot: ABAudioSessionCategorySnapshot) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(snapshot.category, mode: snapshot.mode, options: snapshot.options)
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
