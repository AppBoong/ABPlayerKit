import Foundation
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Records every call `ABPlayer` makes to `ABAudioSessionControlling` so
/// tests can assert on apply/restore ordering without touching the real,
/// process-global `AVAudioSession` (WP2, Q4 in DESIGN-OPEN-QUESTIONS.md).
@MainActor
final class ABFakeAudioSessionController: ABAudioSessionControlling {
    enum Call: Equatable {
        case snapshotCurrentCategory
        case activate(ABAudioSessionPolicy)
        case restore(ABAudioSessionCategorySnapshot)
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

    func restore(_ snapshot: ABAudioSessionCategorySnapshot) throws {
        calls.append(.restore(snapshot))
        if let restoreError {
            throw restoreError
        }
    }
}
