import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for WP2 (Q4 in DESIGN-OPEN-QUESTIONS.md): `audioSessionPolicy`
/// defaults to `.unmanaged` (zero `AVAudioSession` calls), opt-in auto-apply
/// snapshots the prior category before activating, and restore runs on the
/// two documented triggers — the policy switching back to `.unmanaged`, and
/// `release()`.
@Suite("ABPlayer applies and restores audioSessionPolicy through ABAudioSessionControlling")
@MainActor
struct ABAudioSessionPolicyTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    private func makePlayer(
        policy: ABAudioSessionPolicy
    ) -> (ABPlayer, ABFakePlaybackTarget, ABFakeAudioSessionController) {
        let target = ABFakePlaybackTarget()
        let audioSession = ABFakeAudioSessionController()
        let configuration = ABPlayerConfiguration(backgroundPolicy: .ignore, audioSessionPolicy: policy)
        let player = ABPlayer(configuration: configuration, target: target, audioSessionController: audioSession)
        return (player, target, audioSession)
    }

    @Test("Default .unmanaged policy never touches AVAudioSession")
    func unmanagedPolicyAppliesNothing() {
        let (player, _, audioSession) = makePlayer(policy: .unmanaged)

        player.set(source: source, grade: .current)
        player.play()
        player.release()

        #expect(audioSession.calls.isEmpty)
    }

    @Test("Promoting to .current with a managed policy snapshots then activates, in order")
    func promotionSnapshotsThenActivates() {
        let policy = ABAudioSessionPolicy.playback(mixWithOthers: false)
        let (player, _, audioSession) = makePlayer(policy: policy)

        player.set(source: source, grade: .current)

        #expect(audioSession.calls == [.snapshotCurrentCategory, .activate(policy)])
    }

    @Test("play() does not re-apply an already-applied policy")
    func playDoesNotDoubleApply() {
        let policy = ABAudioSessionPolicy.ambient
        let (player, _, audioSession) = makePlayer(policy: policy)

        player.set(source: source, grade: .current)
        player.play()

        #expect(audioSession.calls == [.snapshotCurrentCategory, .activate(policy)])
    }

    @Test("release() restores the snapshot captured at apply time")
    func releaseRestoresSnapshot() {
        let policy = ABAudioSessionPolicy.playback(mixWithOthers: true)
        let (player, _, audioSession) = makePlayer(policy: policy)

        player.set(source: source, grade: .current)
        player.release()

        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(policy),
            .restore(audioSession.priorSnapshot),
        ])
    }

    @Test("Switching the policy back to .unmanaged restores immediately, without waiting for release()")
    func switchingToUnmanagedRestoresImmediately() {
        let policy = ABAudioSessionPolicy.playback(mixWithOthers: false)
        let (player, _, audioSession) = makePlayer(policy: policy)

        player.set(source: source, grade: .current)
        player.configuration.audioSessionPolicy = .unmanaged

        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(policy),
            .restore(audioSession.priorSnapshot),
        ])

        // A later release() must not restore a second time.
        player.release()
        #expect(audioSession.calls.count == 3)
    }

    @Test("Switching between two managed policies re-activates without re-snapshotting")
    func switchingBetweenManagedPoliciesReusesSnapshot() {
        let (player, _, audioSession) = makePlayer(policy: .ambient)

        player.set(source: source, grade: .current)
        player.configuration.audioSessionPolicy = .playback(mixWithOthers: true)

        #expect(audioSession.calls == [
            .snapshotCurrentCategory,
            .activate(.ambient),
            .activate(.playback(mixWithOthers: true)),
        ])
    }

    @Test("Apply failure surfaces as .failed and does not mark the policy applied")
    func applyFailureSurfacesEvent() {
        let policy = ABAudioSessionPolicy.playback(mixWithOthers: false)
        let (player, _, audioSession) = makePlayer(policy: policy)
        let underlying = NSError(domain: "test.audioSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "denied"])
        audioSession.activateError = underlying

        var events: [ABPlayerEvent] = []
        let token = player.addObserver { events.append($0) }
        defer { token.cancel() }

        player.set(source: source, grade: .current)

        let expectedError = ABPlayerError.audioSessionOperationFailed(description: underlying.localizedDescription)
        #expect(player.lastError == expectedError)
        #expect(events.contains(.failed(expectedError)))

        // Since apply failed, nothing should be considered "applied" — a
        // later release() must not attempt to restore a snapshot that was
        // never successfully activated.
        player.release()
        #expect(!audioSession.calls.contains { if case .restore = $0 { return true } else { return false } })
    }

    @Test("Restore failure surfaces as .failed without throwing out of release()")
    func restoreFailureSurfacesEvent() {
        let policy = ABAudioSessionPolicy.ambient
        let (player, _, audioSession) = makePlayer(policy: policy)
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
}
