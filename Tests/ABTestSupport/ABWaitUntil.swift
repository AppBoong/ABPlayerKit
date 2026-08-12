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
