import ABTestSupport
@preconcurrency import AVKit
import Foundation
import Observation
import os
import Testing
@testable import ABPlayerKit

/// Coverage for `ABPictureInPictureSession`'s binding lifecycle and mirror
/// discipline — the parts that don't require actual device PiP support,
/// which the simulator generally lacks. Real start/stop/render behavior is
/// out of scope here and can only be confirmed by manual on-device
/// verification.
@Suite("ABPictureInPictureSession binds to at most one view and mirrors state without redundant notifications", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPictureInPictureSessionTests {
    @Test("An unbound session's start() is a safe no-op")
    func unboundSessionStartIsSafeNoOp() {
        let session = ABPictureInPictureSession()
        session.start()
        #expect(!session.isActive)
        #expect(session.controller == nil)
    }

    @Test("Binding a session to a second view severs the first view's binding")
    func bindingToASecondViewSeversTheFirst() {
        let session = ABPictureInPictureSession()
        let viewA = ABPlayerView()
        let viewB = ABPlayerView()

        viewA.pictureInPictureSession = session
        #expect(session.boundView === viewA)

        viewB.pictureInPictureSession = session
        #expect(session.boundView === viewB)
        #expect(session.boundView !== viewA)
    }

    @Test("Reassigning the same value is a no-op that doesn't rebind")
    func reassigningTheSameSessionIsANoOp() {
        let session = ABPictureInPictureSession()
        let view = ABPlayerView()

        view.pictureInPictureSession = session
        let boundAfterFirstAssignment = session.boundView
        view.pictureInPictureSession = session

        #expect(session.boundView === boundAfterFirstAssignment)
    }

    @Test("Binding to a second view while active on the first is refused and recorded as a failure")
    func bindingToASecondViewWhileActiveOnTheFirstIsRefused() {
        let session = ABPictureInPictureSession()
        let viewA = ABPlayerView()
        let viewB = ABPlayerView()

        viewA.pictureInPictureSession = session
        session.updateIsActive(true)
        #expect(session.lastFailure == nil)

        viewB.pictureInPictureSession = session

        #expect(session.boundView === viewA)
        #expect(session.lastFailure != nil)
    }

    @Test("Mirror discipline: reasserting the same isPossible/isActive value does not re-fire Observation")
    func sameValueReassignmentDoesNotRefireObservation() async {
        let session = ABPictureInPictureSession()
        let possibleFlag = ObservationFlag()
        let activeFlag = ObservationFlag()

        withObservationTracking {
            _ = session.isPossible
        } onChange: {
            possibleFlag.markFired()
        }
        withObservationTracking {
            _ = session.isActive
        } onChange: {
            activeFlag.markFired()
        }

        session.updateIsPossible(session.isPossible)
        session.updateIsActive(session.isActive)

        await Task.yield()
        await Task.yield()

        #expect(!possibleFlag.hasFired)
        #expect(!activeFlag.hasFired)
    }

    @Test("A session drops its strong hold on the bound view once isActive returns to false")
    func sessionDropsItsHoldOnceInactive() async throws {
        let session = ABPictureInPictureSession()
        weak var weakView: ABPlayerView?

        do {
            let view = ABPlayerView()
            weakView = view
            view.pictureInPictureSession = session
            session.updateIsActive(true)
        }
        // The session's own strong hold (not any local reference) is what
        // keeps the view alive here, since every other reference was
        // scoped out above.
        #expect(weakView != nil)

        session.updateIsActive(false)

        try await waitUntil { weakView == nil }
    }

    @Test("Whether AVPictureInPictureController retains its playerLayer strongly — informs whether this type needs its own explicit hold on the layer")
    func controllerPlayerLayerRetentionCheck() {
        guard ABPictureInPictureSession.isSupported else {
            // Nothing to construct against in this environment — this
            // check is inconclusive here, not a pass or a fail. This
            // library doesn't depend on the answer either way: while
            // active, the session already holds the bound *view* strongly,
            // which transitively keeps its backing layer alive regardless
            // of whatever `AVPictureInPictureController` itself does.
            return
        }
        weak var weakLayer: AVPlayerLayer?
        var controller: AVPictureInPictureController?
        autoreleasepool {
            let layer = AVPlayerLayer()
            weakLayer = layer
            controller = AVPictureInPictureController(playerLayer: layer)
        }
        guard controller != nil else { return }
        // If the controller retains the layer strongly, `weakLayer`
        // survives past the scope above even though no other reference to
        // it remains — `controller` is the only thing that could be
        // keeping it alive.
        #expect(weakLayer != nil)
        _ = controller
    }

    /// Genuinely `Sendable` (not `@unchecked`): `OSAllocatedUnfairLock<Bool>`
    /// is itself `Sendable`, so wrapping the single `Bool` in it, as a
    /// `let`, makes the whole type checked-Sendable with no unsafe opt-out.
    private final class ObservationFlag: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: false)

        func markFired() {
            state.withLock { $0 = true }
        }

        var hasFired: Bool {
            state.withLock { $0 }
        }
    }
}
