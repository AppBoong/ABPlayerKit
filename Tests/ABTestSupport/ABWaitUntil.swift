// Test-only helpers, shared by every test target.
//
// Wrapped in `#if os(iOS)` because this package builds for iOS only. These
// helpers use `Duration`, which needs a macOS 13 deployment target the
// package deliberately no longer declares — so on a host build this target
// compiles to nothing, leaving the explanation in
// `Sources/ABPlayerKit/PlatformSupport.swift` to stand on its own.
#if os(iOS)
import Foundation
import Testing

/// Multiplies every `waitUntil` deadline, for environments where the work
/// being waited on is legitimately slower rather than stuck.
///
/// A sanitizer run instruments every memory access, and the CI runner has
/// three cores to the development machine's ten, so an AVFoundation load
/// that settles in well under a second locally can take several here. Left
/// unscaled, those runs report a timeout — a failure that looks identical
/// to a genuine deadlock but is only a slow machine.
private let deadlineScale: Double = {
    guard let raw = ProcessInfo.processInfo.environment["ABPLAYERKIT_WAIT_SCALE"],
          let scale = Double(raw),
          scale >= 1
    else { return 1 }
    return scale
}()

/// Scales an ad-hoc timeout by the same factor ``waitUntil`` applies to its
/// own deadline.
///
/// Some tests can't express their wait as a predicate — a `withTaskGroup`
/// race where one branch sleeps and reports `.timedOut` needs a real
/// duration, not a poll. Those deadlines are subject to exactly the same
/// slowdown ``waitUntil`` exists to absorb, so they must be scaled the same
/// way; a bare `Task.sleep(for: .seconds(2))` silently opts out and reports a
/// slow machine as a product failure.
///
/// Only for a bound the *success* path has to beat. A deliberately long
/// sleep standing in for work that should be cancelled must stay unscaled —
/// stretching it delays detection of the failure it exists to catch.
public func abScaledTimeout(_ duration: Duration) -> Duration {
    duration * deadlineScale
}

/// Scales a `.timeLimit` trait by the same factor ``waitUntil`` applies to
/// its own deadlines.
///
/// A suite's time limit is a hang detector, not a performance budget: it
/// exists so a deadlocked test fails in minutes instead of holding the job
/// open until the runner kills it. But Swift Testing runs tests in parallel,
/// so on a three-core CI runner every in-flight test shares a wall clock that
/// a ten-core development machine never stretches — and when the limit fires
/// it fires on all of them at once, reporting a slow machine as hundreds of
/// simultaneous product failures. Scaling keeps the detector while letting a
/// legitimately slow run finish; the workflow's own `timeout-minutes` stays
/// the outer bound.
///
/// Swift Testing accepts whole minutes only, so the scaled value rounds up.
///
/// The result is capped at ``abMaximumScaledMinutes``. The scale exists to
/// size *deadlines*, which are seconds, and a factor large enough for those
/// would push a limit whose base is already minutes past the workflow's own
/// `timeout-minutes` — at which point the job's timeout fires first and the
/// per-test limit stops being a hang detector at all. The cap keeps the two
/// bounds ordered no matter how far the scale is raised.
public func abScaledMinutes(_ minutes: Int) -> TimeLimitTrait.Duration {
    let scaled = Int((Double(minutes) * deadlineScale).rounded(.up))
    return .minutes(min(scaled, Swift.max(minutes, abMaximumScaledMinutes)))
}

/// The ceiling ``abScaledMinutes(_:)`` applies.
///
/// Fifteen minutes against the workflow's 45-minute `timeout-minutes`: tests
/// run in parallel, so one hung test costs this much wall clock once, leaving
/// the job room to check out, build, boot a simulator, and still report the
/// hang itself rather than being killed mid-run.
public let abMaximumScaledMinutes = 15

/// Deterministic polling helper shared by every test target: waits for a
/// predicate against a `ContinuousClock` deadline, polling on a fixed
/// interval so the awaiting task never spins the scheduler.
///
/// On timeout, records a Swift Testing `Issue` (so the failure reads as a
/// normal, located test failure instead of a bare downstream `#expect`
/// miss) and throws, so callers propagate it via `try await waitUntil(...)`
/// from a `throws` test function.
@MainActor
public func waitUntil(
    _ deadline: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ predicate: @MainActor () -> Bool
) async throws {
    let scaled = deadline * deadlineScale
    let clock = ContinuousClock()
    let start = clock.now
    while !predicate() {
        if clock.now - start >= scaled {
            Issue.record(
                "waitUntil timed out after \(scaled) without the predicate becoming true",
                sourceLocation: sourceLocation
            )
            throw ABWaitUntilTimedOut()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

public struct ABWaitUntilTimedOut: Error {
    public init() {}
}
#endif
