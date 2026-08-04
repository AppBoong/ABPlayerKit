import Foundation
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Records every call `ABAudioSessionCoordinator` makes to
/// `ABAudioSessionControlling` so tests can assert on apply/restore
/// ordering without touching the real, process-global `AVAudioSession`
/// (WP2, Q4 in DESIGN-OPEN-QUESTIONS.md). Not actor-isolated — matches the
/// production protocol (round3 Phase3 group A) — but every call the
/// coordinator makes is already serialized through its own lock, so a
/// plain array is safe here.
final class ABFakeAudioSessionController: ABAudioSessionControlling {
    enum Call: Equatable {
        case snapshotCurrentCategory
        case activate(ABAudioSessionPolicy)
        case restore(ABAudioSessionCategorySnapshot, deactivate: Bool)
    }

    private(set) var calls: [Call] = []

    /// A stand-in for "whatever category the host app had configured".
    var priorSnapshot = ABAudioSessionCategorySnapshot(
        category: .soloAmbient,
        mode: .default,
        options: []
    )

    var activateError: Error?
    var restoreError: Error?

    func snapshotCurrentCategory() -> ABAudioSessionCategorySnapshot {
        calls.append(.snapshotCurrentCategory)
        return priorSnapshot
    }

    func activate(_ policy: ABAudioSessionPolicy) throws {
        calls.append(.activate(policy))
        if let activateError {
            throw activateError
        }
    }

    func restore(_ snapshot: ABAudioSessionCategorySnapshot, deactivate: Bool) throws {
        calls.append(.restore(snapshot, deactivate: deactivate))
        if let restoreError {
            throw restoreError
        }
    }
}
