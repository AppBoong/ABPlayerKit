import Foundation
import Testing

// Intentionally duplicated verbatim across `ABPlayerKitTests`,
// `ABPlayerKitCacheTests`, and `ABPlayerKitControlsTests` (round3 Phase1+2
// review m7) — each is a separate SPM test target with no shared test
// support target to host one copy, and introducing one is out of scope for
// this cleanup. Keep all three in sync by hand if this helper changes.

/// Deterministic polling helper (round-3 Phase 2, WP8): replaces ad hoc
/// `while !x { await Task.yield() }` / `for _ in 0..<N { await Task.yield() }`
/// busy-loops scattered across this target's tests with a single
/// deadline-bounded wait against a `ContinuousClock`.
///
/// On timeout, records a Swift Testing `Issue` (so the failure reads as a
/// normal, located test failure instead of a bare downstream `#expect`
/// miss) and throws, so callers propagate it via `try await waitUntil(...)`
/// from a `throws` test function.
@MainActor
func waitUntil(
    _ deadline: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ predicate: @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let start = clock.now
    while !predicate() {
        if clock.now - start >= deadline {
            Issue.record(
                "waitUntil timed out after \(deadline) without the predicate becoming true",
                sourceLocation: sourceLocation
            )
            throw ABWaitUntilTimedOut()
        }
        await Task.yield()
    }
}

struct ABWaitUntilTimedOut: Error {}
