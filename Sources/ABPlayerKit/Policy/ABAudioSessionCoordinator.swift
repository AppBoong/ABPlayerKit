import Foundation

/// Process-wide owner of opt-in ``ABAudioSessionPolicy`` apply/restore.
///
/// `AVAudioSession` is a single, process-global resource, but this library
/// supports many concurrent ``ABPlayer`` instances — the feed use case this
/// library exists for (`Model/ABPlaybackTuning.swift`'s "landing-cell"
/// preload/current design). Modeling apply/restore as *per-instance* state
/// let two players stomp each other's snapshot and deactivate a session a
/// sibling player was still using (round3 Phase1+2 review C1/C2/M1/M2/M4).
/// This coordinator instead tracks every participating player by token,
/// snapshotting only on the first arrival and restoring only once the last
/// one leaves.
///
/// Lock-protected (`@unchecked Sendable`) rather than actor-isolated —
/// mirrors `ABAVPlaybackTarget.ReadyWaitState`/`ABCacheStore`'s
/// `ABCacheProgressWaiter` — because `ABPlayer.deinit` is nonisolated and
/// must be able to call `leave(_:)` from whatever thread drops the last
/// strong reference (M4).
final class ABAudioSessionCoordinator: @unchecked Sendable {
    /// The process-wide instance every non-test ``ABPlayer`` shares.
    static let shared = ABAudioSessionCoordinator()

    private let controller: any ABAudioSessionControlling
    private let lock = NSLock()
    /// Policy currently requested by each participating player, keyed by a
    /// stable per-instance token (`ObjectIdentifier(player)`).
    private var participants: [ObjectIdentifier: ABAudioSessionPolicy] = [:]
    /// The host's category/mode/options, captured immediately before the
    /// *first* participant's apply — never overwritten while any
    /// participant remains, so a second (or third...) player releasing
    /// always restores what the host actually had, regardless of what an
    /// earlier participant changed it to in between (C1).
    private var hostSnapshot: ABAudioSessionCategorySnapshot?
    /// Whether this coordinator's own `activate(_:)` call last *succeeded*
    /// in flipping the session active. `leave` only ever deactivates when
    /// this is `true` — a category-only partial failure (M2) or a host
    /// session this coordinator never actually activated must not be
    /// force-deactivated (C2).
    private var didActivateSession = false

    init(controller: any ABAudioSessionControlling = ABAudioSessionAdapter()) {
        self.controller = controller
    }

    /// Registers `token` as wanting `policy` applied and (re)activates.
    /// Always calls through to `activate` — never memoized/short-circuited
    /// on "already applied" — so a grade promotion or `play()` after an
    /// interruption reactivates the session instead of silently staying
    /// inactive (M1). Snapshots the host's prior category only when `token`
    /// is the first participant (C1).
    @discardableResult
    func apply(_ policy: ABAudioSessionPolicy, for token: ObjectIdentifier) -> Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }
        if participants.isEmpty {
            hostSnapshot = controller.snapshotCurrentCategory()
        }
        participants[token] = policy
        do {
            try controller.activate(policy)
            didActivateSession = true
            return .success(())
        } catch {
            // M2: keep `hostSnapshot` and the `participants` entry even on
            // failure — `setCategory` may already have taken effect even
            // though `setActive` threw, so the original category is still
            // exactly what must be restored once the last participant
            // leaves. `didActivateSession` deliberately stays unchanged:
            // this failed call did not itself activate the session, but an
            // earlier participant's successful activation (if any) still
            // did.
            return .failure(error)
        }
    }

    /// Unregisters `token`. Only the last remaining participant leaving
    /// triggers a restore (C1) — siblings still holding a policy are left
    /// completely untouched. Safe to call for a `token` that never applied
    /// anything (a no-op, returns `nil`) — every release/deinit path can
    /// therefore call this unconditionally.
    @discardableResult
    func leave(_ token: ObjectIdentifier) -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard participants.removeValue(forKey: token) != nil else { return nil }
        guard participants.isEmpty, let snapshot = hostSnapshot else { return nil }
        hostSnapshot = nil
        let shouldDeactivate = didActivateSession
        didActivateSession = false
        do {
            try controller.restore(snapshot, deactivate: shouldDeactivate)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
