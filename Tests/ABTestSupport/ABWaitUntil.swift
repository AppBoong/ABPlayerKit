import Testing

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
        try await Task.sleep(for: .milliseconds(5))
    }
}

public struct ABWaitUntilTimedOut: Error {
    public init() {}
}
