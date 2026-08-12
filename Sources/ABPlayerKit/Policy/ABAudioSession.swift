@preconcurrency import AVFoundation

/// Shared body for `ABAudioSession.activate(_:)`'s `@MainActor` facade and
/// `ABAudioSessionAdapter.activate(_:)`'s deliberately non-isolated
/// counterpart (see that type's doc comment for why it can't just forward
/// to the facade) — one copy of the actual `AVAudioSession` calls instead
/// of two byte-identical ones. `AVAudioSession`'s category/activation APIs
/// are documented safe to call off the main thread, so a free `nonisolated`
/// function is safe to call from either isolation context.
nonisolated func abActivateAudioSession(_ policy: ABAudioSessionPolicy) throws {
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

/// Explicit-call-only facade over `AVAudioSession`. `ABPlayer` never calls
/// this on the consumer's behalf — see `ABAudioSessionPolicy`.
@MainActor
public enum ABAudioSession {
    public static func activate(_ policy: ABAudioSessionPolicy) throws {
        try abActivateAudioSession(policy)
    }

    public static func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// The pieces of `AVAudioSession` state ``ABPlayer`` saves before applying an
/// opt-in ``ABAudioSessionPolicy`` so it can restore exactly what the host
/// app had configured — restoration failures are surfaced as events, never
/// thrown.
struct ABAudioSessionCategorySnapshot: Sendable, Equatable {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
}

/// Test seam between ``ABAudioSessionCoordinator`` and `AVAudioSession`.
/// Deliberately **not** actor-isolated: ``ABPlayer/deinit`` is nonisolated
/// and must be able to unwind an unreleased participant from any thread,
/// so ``ABAudioSessionCoordinator`` serializes
/// every call through its own lock instead of relying on actor isolation.
/// `AVAudioSession`'s category/activation APIs are documented safe to call
/// off the main thread.
protocol ABAudioSessionControlling: AnyObject {
    func snapshotCurrentCategory() -> ABAudioSessionCategorySnapshot
    func activate(_ policy: ABAudioSessionPolicy) throws
    /// Restores a previously captured snapshot. Only deactivates the
    /// session when `deactivate` is `true` — the caller passes `true` only
    /// when it previously succeeded in activating the session itself:
    /// unconditional deactivation can silence a host app that was already
    /// playing before this policy applied, or a sibling participant that is
    /// still relying on the session.
    func restore(_ snapshot: ABAudioSessionCategorySnapshot, deactivate: Bool) throws
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

    /// Deliberately does not forward to the public, `@MainActor`-isolated
    /// ``ABAudioSession/activate(_:)`` — this adapter must stay callable
    /// from any thread (see the protocol doc above), and the public facade
    /// keeps its own actor isolation for API-compatibility reasons
    /// unrelated to this internal plumbing. Shares its actual body with
    /// the facade via `abActivateAudioSession(_:)` instead of duplicating
    /// it.
    func activate(_ policy: ABAudioSessionPolicy) throws {
        try abActivateAudioSession(policy)
    }

    func restore(_ snapshot: ABAudioSessionCategorySnapshot, deactivate: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(snapshot.category, mode: snapshot.mode, options: snapshot.options)
        guard deactivate else { return }
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
