import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Direct concurrency coverage for `ABAVPlaybackTarget.ReadyWaitState` — the
/// lock-guarded coordinator that ensures exactly one of {KVO resolve,
/// timeout, cancellation} wins the race to resume a suspended continuation.
/// `ReadyWaitState`/`ReadyWaitResult` were promoted from `private` to
/// internal (no production behavior change) specifically so this suite can
/// reach them via `@testable import`.
@Suite("ABAVPlaybackTarget.ReadyWaitState resolves exactly once under concurrent contention")
struct ABReadyWaitStateConcurrencyTests {
    @Test("Concurrently resolving from many tasks yields exactly one winning result")
    func concurrentResolveYieldsSingleWinner() async {
        for _ in 0..<50 {
            let state = ABAVPlaybackTarget.ReadyWaitState()
            let outcome = await withTaskGroup(of: ABAVPlaybackTarget.ReadyWaitResult?.self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        state.install(continuation)
                    }
                }
                // Fire KVO-resolve, timeout, and cancellation-style resolves
                // concurrently. Only the first `resolve(_:)` call may win —
                // every other one must be a no-op.
                group.addTask {
                    state.resolve(.ready)
                    return nil
                }
                group.addTask {
                    state.resolve(.timedOut)
                    return nil
                }
                group.addTask {
                    state.resolve(.cancelled)
                    return nil
                }
                group.addTask {
                    state.resolve(.failed)
                    return nil
                }

                var winner: ABAVPlaybackTarget.ReadyWaitResult?
                for await value in group {
                    if let value {
                        winner = value
                    }
                }
                return winner
            }

            // Exactly one of the four candidate results must have won — the
            // continuation resumed with a single, well-defined value.
            let validOutcomes: [ABAVPlaybackTarget.ReadyWaitResult] = [.ready, .timedOut, .cancelled, .failed]
            #expect(outcome != nil)
            if let outcome {
                #expect(validOutcomes.contains(outcome))
            }
        }
    }

    @Test("Cancellation arriving before continuation installation still resolves exactly once")
    func cancellationBeforeInstallStillResolvesOnce() async {
        for _ in 0..<50 {
            let state = ABAVPlaybackTarget.ReadyWaitState()

            // Simulate cancellation racing ahead of `install(_:)` by
            // resolving first, then installing — mirrors
            // `waitUntilReady`'s own `guard !Task.isCancelled` path, where
            // `state.resolve(.cancelled)` can run before the continuation
            // is installed.
            state.resolve(.cancelled)

            let result = await withCheckedContinuation { (continuation: CheckedContinuation<ABAVPlaybackTarget.ReadyWaitResult, Never>) in
                state.install(continuation)
            }
            #expect(result == .cancelled)

            // A second resolve after the state is already settled must be a
            // silent no-op — no crash, no double-resume.
            state.resolve(.ready)
        }
    }

    @Test("installTimeoutTask cancels the task immediately if already resolved")
    func installTimeoutTaskCancelsWhenAlreadyResolved() async {
        let state = ABAVPlaybackTarget.ReadyWaitState()
        state.resolve(.ready)

        actor RanFlag {
            private(set) var ran = false
            func markRan() { ran = true }
        }
        let ranFlag = RanFlag()
        let task = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await ranFlag.markRan()
        }
        state.installTimeoutTask(task)

        // `installTimeoutTask` must have cancelled `task` synchronously
        // since `state` was already resolved — awaiting its value should
        // return promptly without needing the 30s sleep to elapse.
        _ = await task.value
        #expect(await ranFlag.ran == false)
    }

    @Test("installObservationInvalidator invokes the invalidator immediately if already resolved")
    func installObservationInvalidatorRunsWhenAlreadyResolved() async {
        let state = ABAVPlaybackTarget.ReadyWaitState()
        state.resolve(.failed)

        actor InvalidatedFlag {
            private(set) var invalidated = false
            func markInvalidated() { invalidated = true }
        }
        let flag = InvalidatedFlag()
        state.installObservationInvalidator {
            Task { await flag.markInvalidated() }
        }

        // Poll deterministically for the synchronously-triggered `Task` to
        // run — no sleep-based waiting.
        var iterations = 0
        while await flag.invalidated == false, iterations < 1000 {
            await Task.yield()
            iterations += 1
        }
        #expect(await flag.invalidated == true)
    }
}

/// Integration coverage for `ABAVPlaybackTarget.waitUntilReady(item:timeout:)`
/// against a real `AVPlayerItem` on the simulator — exercising the actual
/// KVO/timeout/failure paths this type coordinates in production, not just
/// the isolated `ReadyWaitState` lock logic above.
@Suite("ABAVPlaybackTarget.waitUntilReady against a real AVPlayerItem")
@MainActor
struct ABAVPlaybackTargetWaitUntilReadyTests {
    @Test("A valid bundled asset reaches .ready")
    func validAssetReachesReady() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
        let target = ABAVPlaybackTarget()
        let item = AVPlayerItem(url: url)
        // `AVPlayerItem.status` only progresses past `.unknown` once the
        // item is associated with an `AVPlayer` — mirrors how
        // `ABAVPlaybackTarget.attachItem` always calls
        // `avPlayer?.replaceCurrentItem(with:)` before anything awaits
        // readiness.
        let player = AVPlayer(playerItem: item)

        let result = await target.waitUntilReady(item: item, timeout: 10)

        #expect(result == .ready)
        _ = player
    }

    @Test("A nonexistent file URL resolves to .failed")
    func nonexistentFileURLResolvesToFailed() async {
        let target = ABAVPlaybackTarget()
        let missingURL = URL(fileURLWithPath: "/private/tmp/abplayerkit-does-not-exist-\(UUID().uuidString).mp4")
        let item = AVPlayerItem(url: missingURL)
        let player = AVPlayer(playerItem: item)

        let result = await target.waitUntilReady(item: item, timeout: 10)

        #expect(result == .failed)
        _ = player
    }

    @Test("A near-zero timeout against a still-loading item resolves to .timedOut")
    func nearZeroTimeoutResolvesToTimedOut() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "tiny", withExtension: "mp4"),
            "tiny.mp4 test fixture must be bundled with ABPlayerKitTests"
        )
        let target = ABAVPlaybackTarget()
        let item = AVPlayerItem(url: url)
        // Deliberately *not* attached to an `AVPlayer` here — without one,
        // `.status` never leaves `.unknown` (confirmed above), so the
        // timeout path is guaranteed to win instead of racing a real load.
        let result = await target.waitUntilReady(item: item, timeout: 0.01)

        #expect(result == .timedOut)
    }
}
