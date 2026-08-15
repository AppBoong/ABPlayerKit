import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// A tiny async gate so concurrency tests can force one `Task` to run to a
/// specific point before releasing another, without falling back to
/// sleep-based or fixed-iteration polling. `open()` is idempotent and wakes
/// every waiter, including ones that call `wait()` after it already opened.
private actor ABAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiters = waiters
        self.waiters = []
        for waiter in waiters { waiter.resume() }
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Direct concurrency coverage for `ABAVPlaybackTarget.ReadyWaitState` — the
/// lock-guarded coordinator that ensures exactly one of {KVO resolve,
/// timeout, cancellation} wins the race to resume a suspended continuation.
/// `ReadyWaitState`/`ReadyWaitResult` were promoted from `private` to
/// internal (no production behavior change) specifically so this suite can
/// reach them via `@testable import`.
@Suite("ABAVPlaybackTarget.ReadyWaitState resolves exactly once under concurrent contention", .timeLimit(abScaledMinutes(3)))
struct ABReadyWaitStateConcurrencyTests {
    @Test("Concurrently resolving from many tasks yields exactly one winning result")
    func concurrentResolveYieldsSingleWinner() async {
        let candidates: [ABAVPlaybackTarget.ReadyWaitResult] = [.ready, .timedOut, .cancelled, .failed]

        for _ in 0..<50 {
            let state = ABAVPlaybackTarget.ReadyWaitState()

            enum Outcome {
                case continuationResumed(ABAVPlaybackTarget.ReadyWaitResult)
                case resolveWon(ABAVPlaybackTarget.ReadyWaitResult)
                case resolveLost
            }

            let outcomes = await withTaskGroup(of: Outcome.self) { group in
                group.addTask {
                    let resumed = await withCheckedContinuation { continuation in
                        state.install(continuation)
                    }
                    return .continuationResumed(resumed)
                }
                // Fire KVO-resolve, timeout, and cancellation-style resolves
                // concurrently. Only the first `resolve(_:)` call may win —
                // every other one must report `false` and leave the state
                // untouched.
                for candidate in candidates {
                    group.addTask {
                        state.resolve(candidate) ? .resolveWon(candidate) : .resolveLost
                    }
                }
                var collected: [Outcome] = []
                for await outcome in group {
                    collected.append(outcome)
                }
                return collected
            }

            let wins = outcomes.compactMap { outcome -> ABAVPlaybackTarget.ReadyWaitResult? in
                if case .resolveWon(let result) = outcome { return result }
                return nil
            }
            let resumed = outcomes.compactMap { outcome -> ABAVPlaybackTarget.ReadyWaitResult? in
                if case .continuationResumed(let result) = outcome { return result }
                return nil
            }

            // round3 Phase1+2 review m2: the previous assertion accepted
            // any of the four candidate results, which can never fail — a
            // lock bug that let two `resolve` calls both "win" would have
            // passed silently. This checks the real oracle instead: exactly
            // one `resolve` call reports itself the winner (`resolve`'s
            // `@discardableResult -> Bool`, mirroring
            // `ABCacheStore.ABCacheProgressWaiter.resolve()`), and the
            // continuation resumes with that exact value.
            #expect(wins.count == 1)
            #expect(resumed == wins)
        }
    }

    @Test("Cancellation arriving before continuation installation still resolves exactly once")
    func cancellationBeforeInstallStillResolvesOnce() async {
        for _ in 0..<50 {
            let state = ABAVPlaybackTarget.ReadyWaitState()
            let gate = ABAsyncGate()

            enum Outcome {
                case resolved(won: Bool)
                case installed(ABAVPlaybackTarget.ReadyWaitResult)
            }

            let outcomes = await withTaskGroup(of: Outcome.self) { group in
                group.addTask {
                    // Mirrors `waitUntilReady`'s `onCancel` handler, which
                    // runs on its own (unspecified) execution context,
                    // concurrently with the `withCheckedContinuation`
                    // closure below.
                    let won = state.resolve(.cancelled)
                    await gate.open()
                    return .resolved(won: won)
                }
                group.addTask {
                    // Gated so `resolve(.cancelled)` above is guaranteed to
                    // have already run before `install` — deterministically
                    // exercising "cancellation raced ahead of install" from
                    // a genuinely different `Task` (round3 Phase1+2 review
                    // m3), unlike the previous version's two sequential
                    // calls in one synchronous scope, which could never
                    // actually race regardless of how many times it looped.
                    await gate.wait()
                    let resumed = await withCheckedContinuation { continuation in
                        state.install(continuation)
                    }
                    return .installed(resumed)
                }
                var collected: [Outcome] = []
                for await outcome in group {
                    collected.append(outcome)
                }
                return collected
            }

            for outcome in outcomes {
                switch outcome {
                case .resolved(let won):
                    #expect(won)
                case .installed(let resumed):
                    #expect(resumed == .cancelled)
                }
            }

            // A second resolve after the state is already settled must be a
            // silent no-op — no crash, no double-resume, and it must
            // report that it did not win.
            #expect(state.resolve(.ready) == false)
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
    func installObservationInvalidatorRunsWhenAlreadyResolved() {
        let state = ABAVPlaybackTarget.ReadyWaitState()
        state.resolve(.failed)

        final class InvalidatedFlag {
            var invalidated = false
        }
        let flag = InvalidatedFlag()
        state.installObservationInvalidator {
            flag.invalidated = true
        }

        // `installObservationInvalidator` invokes the invalidator
        // synchronously, inline, when the state is already resolved — no
        // `Task` hop, so no polling is needed to observe it (round3
        // Phase1+2 review m4: the previous version wrapped this in a
        // `Task` and polled up to 1000 `Task.yield()`s, the exact stale
        // busy-loop pattern WP8 otherwise removed).
        #expect(flag.invalidated)
    }
}

/// Integration coverage for `ABAVPlaybackTarget.waitUntilReady(item:timeout:)`
/// against a real `AVPlayerItem` on the simulator — exercising the actual
/// KVO/timeout/failure paths this type coordinates in production, not just
/// the isolated `ReadyWaitState` lock logic above.
@Suite("ABAVPlaybackTarget.waitUntilReady against a real AVPlayerItem", .timeLimit(abScaledMinutes(3)))
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
