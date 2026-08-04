import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for WP2 (Q4 in DESIGN-OPEN-QUESTIONS.md) plus the round3
/// Phase1+2 review's WP2 rework (group A: C1, C2, M1, M2, M4):
/// `audioSessionPolicy` defaults to `.unmanaged` (zero `AVAudioSession`
/// calls); opt-in auto-apply routes through the process-wide
/// `ABAudioSessionCoordinator` so concurrent players share one snapshot and
/// refcount instead of stomping each other's state (C1); restore never
/// force-deactivates a session this player didn't itself activate (C2);
/// `play()`/promotion always reactivates rather than memoizing "already
/// applied" (M1); a failed activate still leaves the snapshot restorable
/// (M2); and `deinit` leaves the coordinator even without `release()` (M4).
@Suite("ABPlayer applies and restores audioSessionPolicy through ABAudioSessionCoordinator", .timeLimit(.minutes(1)))
@MainActor
struct ABAudioSessionPolicyTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    private func makePlayer(
        policy: ABAudioSessionPolicy,
        coordinator: ABAudioSessionCoordinator? = nil
    ) -> (ABPlayer, ABFakePlaybackTarget, ABFakeAudioSessionController, ABAudioSessionCoordinator) {
        let target = ABFakePlaybackTarget()
        let audioSession = ABFakeAudioSessionController()
        let resolvedCoordinator = coordinator ?? ABAudioSessionCoordinator(controller: audioSession)
        let configuration = ABPlayerConfiguration(backgroundPolicy: .ignore, audioSessionPolicy: policy)
        let player = ABPlayer(
            configuration: configuration,
            target: target,
            audioSessionCoordinator: resolvedCoordinator
        )
        return (player, target, audioSession, resolvedCoordinator)
    }

    @Test("Default .unmanaged policy never touches AVAudioSession")
    func unmanagedPolicyAppliesNothing() {
        let (player, _, audioSession, _) = makePlayer(policy: .unmanaged)

        player.set(source: source, grade: .current)
        player.play()
        player.release()

        #expect(audioSession.calls.isEmpty)
    }

    @Test("Promoting to .current with a managed policy snapshots then activates, in order")
    func promotionSnapshotsThenActivates() {
        let policy = ABAudioSessionPolicy.playback(mixWithOthers: false)
        let (player, _, audioSession, _) = makePlayer(policy: policy)

        player.set(source: source, grade: .current)

        #expect(audioSession.calls == [.snapshotCurrentCategory, .activate(policy)])
    }

    @Test("play() reactivates rather than memoizing an already-applied policy (interruption recovery)")
    func playReactivatesForInterruptionRecovery() {
        let policy = ABAudioSessionPolicy.ambient
        let (player, _, audioSession, _) = makePlayer(policy: policy)

        player.set(source: source, grade: .current)
        player.play()

        // iOS deactivates the session on an interruption; the app must call
        // `setActive(true)` again once playback resumes. Memoizing "already
        // applied" (round3 Phase1+2 review M1) made `play()` a permanent
        // no-op after the first apply, so the session never reactivated.
        // There's no snapshot re-capture — only the second `activate`.
        #expect(audioSession.calls == [.snapshotCurrentCategory, .activate(policy), .activate(policy)])
    }

    @Test("release() restores the snapshot captured at apply time, deactivating since this player activated it")
    func releaseRestoresSnapshot() {
        let policy = ABAudioSessionPolicy.playback(mixWithOthers: true)
        let (player, _, audioSession, _) = makePlayer(policy: policy)

        player.set(source: source, grade: .current)
        player.release()

        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(policy),
            .restore(audioSession.priorSnapshot, deactivate: true),
        ])
    }

    @Test("Switching the policy back to .unmanaged restores immediately, without waiting for release()")
    func switchingToUnmanagedRestoresImmediately() {
        let policy = ABAudioSessionPolicy.playback(mixWithOthers: false)
        let (player, _, audioSession, _) = makePlayer(policy: policy)

        player.set(source: source, grade: .current)
        player.configuration.audioSessionPolicy = .unmanaged

        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(policy),
            .restore(audioSession.priorSnapshot, deactivate: true),
        ])

        // A later release() must not restore a second time.
        player.release()
        #expect(audioSession.calls.count == 3)
    }

    @Test("Switching between two managed policies re-activates without re-snapshotting")
    func switchingBetweenManagedPoliciesReusesSnapshot() {
        let (player, _, audioSession, _) = makePlayer(policy: .ambient)

        player.set(source: source, grade: .current)
        player.configuration.audioSessionPolicy = .playback(mixWithOthers: true)

        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(.ambient),
            .activate(.playback(mixWithOthers: true)),
        ])
    }

    @Test("Apply failure surfaces as .failed but keeps the snapshot restorable on release()")
    func applyFailureSurfacesEventAndKeepsSnapshotRestorable() {
        let policy = ABAudioSessionPolicy.playback(mixWithOthers: false)
        let (player, _, audioSession, _) = makePlayer(policy: policy)
        let underlying = NSError(domain: "test.audioSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "denied"])
        audioSession.activateError = underlying

        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .current)

        let expectedError = ABPlayerError.audioSessionOperationFailed(description: underlying.localizedDescription)
        #expect(player.lastError == expectedError)
        #expect(events.contains(.failed(expectedError)))

        // round3 Phase1+2 review M2: a partial failure (e.g. `setCategory`
        // succeeded but `setActive` threw) can still have overwritten the
        // host's category, so release() must still restore it — just
        // without force-deactivating, since this player never actually
        // succeeded in activating the session.
        player.release()
        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(policy),
            .restore(audioSession.priorSnapshot, deactivate: false),
        ])
    }

    @Test("Restore failure surfaces as .failed without throwing out of release()")
    func restoreFailureSurfacesEvent() {
        let policy = ABAudioSessionPolicy.ambient
        let (player, _, audioSession, _) = makePlayer(policy: policy)
        let underlying = NSError(domain: "test.audioSession", code: 2, userInfo: [NSLocalizedDescriptionKey: "busy"])
        audioSession.restoreError = underlying

        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .current)
        player.release()

        let expectedError = ABPlayerError.audioSessionOperationFailed(description: underlying.localizedDescription)
        #expect(player.lastError == expectedError)
        #expect(events.contains(.failed(expectedError)))
    }

    // MARK: - Multi-player scenarios (round3 Phase1+2 review C1)

    @Test("Two players sharing a coordinator: the session survives the first release() and restores only on the second")
    func twoPlayersShareSessionUntilLastRelease() {
        let audioSession = ABFakeAudioSessionController()
        let coordinator = ABAudioSessionCoordinator(controller: audioSession)
        let (playerA, _, _, _) = makePlayer(policy: .ambient, coordinator: coordinator)
        let (playerB, _, _, _) = makePlayer(policy: .playback(mixWithOthers: true), coordinator: coordinator)

        playerA.set(source: source, grade: .current)
        playerB.set(source: source, grade: .current)

        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(.ambient),
            .activate(.playback(mixWithOthers: true)),
        ])

        playerA.release()
        // B is still a participant — no restore yet, and the session stays
        // active on whatever B most recently activated.
        #expect(!audioSession.calls.contains { if case .restore = $0 { return true } else { return false } })

        playerB.release()
        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(.ambient),
            .activate(.playback(mixWithOthers: true)),
            .restore(audioSession.priorSnapshot, deactivate: true),
        ])
    }

    @Test("A player demoted (not released) keeps participating, so a later player's release() never sees a contaminated snapshot")
    func demotedParticipantPreventsSnapshotContamination() {
        // Exact reproduction from round3 Phase1+2 review C1: player A goes
        // .current then demotes to .preloaded (still holding the item, not
        // released) while player B becomes .current with a different
        // policy. Before the coordinator redesign, B's snapshot would have
        // captured A's already-applied category instead of the host's, and
        // A's release() would have restored (and deactivated) the session
        // out from under B.
        let audioSession = ABFakeAudioSessionController()
        let coordinator = ABAudioSessionCoordinator(controller: audioSession)
        let (playerA, _, _, _) = makePlayer(policy: .playback(mixWithOthers: false), coordinator: coordinator)
        let (playerB, _, _, _) = makePlayer(policy: .ambient, coordinator: coordinator)

        playerA.set(source: source, grade: .current)
        playerA.promote(to: .preloaded)
        playerB.set(source: source, grade: .current)

        // Only one snapshot was ever taken — the host's, before A's apply —
        // regardless of A's subsequent demotion and B's later promotion.
        #expect(audioSession.calls.filter { $0 == .snapshotCurrentCategory }.count == 1)

        playerA.release()
        #expect(!audioSession.calls.contains { if case .restore = $0 { return true } else { return false } })

        playerB.release()
        #expect(audioSession.calls.last == .restore(audioSession.priorSnapshot, deactivate: true))
    }

    // MARK: - deinit (round3 Phase1+2 review M4)

    @Test("ABPlayer.deinit leaves the coordinator even without release()")
    func deinitLeavesCoordinator() async throws {
        let policy = ABAudioSessionPolicy.ambient
        let audioSession = ABFakeAudioSessionController()
        let coordinator = ABAudioSessionCoordinator(controller: audioSession)
        let configuration = ABPlayerConfiguration(backgroundPolicy: .ignore, audioSessionPolicy: policy)

        weak var weakTarget: ABFakePlaybackTarget?
        do {
            let target = ABFakePlaybackTarget()
            weakTarget = target
            let player = ABPlayer(configuration: configuration, target: target, audioSessionCoordinator: coordinator)
            player.set(source: source, grade: .current)
            #expect(audioSession.calls == [.snapshotCurrentCategory, .activate(policy)])
            // `player` goes out of scope here without calling `release()`.
        }

        try await waitUntil { weakTarget == nil }
        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(policy),
            .restore(audioSession.priorSnapshot, deactivate: true),
        ])
    }
}
