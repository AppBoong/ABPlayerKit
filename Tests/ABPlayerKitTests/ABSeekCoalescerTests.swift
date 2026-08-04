@preconcurrency import AVFoundation
import Testing
@testable import ABPlayerKit

@Suite("Scrubbing coalesces seeks and never issues a stale target")
struct ABSeekCoalescerTests {
    private let first = CMTime(seconds: 1, preferredTimescale: 600)
    private let middle = CMTime(seconds: 2, preferredTimescale: 600)
    private let latest = CMTime(seconds: 3, preferredTimescale: 600)

    @Test("Given three rapid requests, only the first issues and only the latest remains pending")
    func rapidRequestsKeepLatest() {
        var coalescer = ABSeekCoalescer()

        #expect(coalescer.request(first, tolerance: .scrubbing) == .issue(first, tolerance: .scrubbing))
        #expect(coalescer.request(middle, tolerance: .scrubbing) == .hold)
        #expect(coalescer.request(latest, tolerance: .nearest) == .hold)
        #expect(coalescer.inFlight == first)
        #expect(coalescer.pending == .init(time: latest, tolerance: .nearest))
    }

    @Test("Given a pending destination, completion issues it and clears pending state")
    func completionIssuesPending() {
        var coalescer = ABSeekCoalescer()
        _ = coalescer.request(first, tolerance: .scrubbing)
        _ = coalescer.request(latest, tolerance: .nearest)

        #expect(coalescer.completed() == .issue(latest, tolerance: .nearest))
        #expect(coalescer.inFlight == latest)
        #expect(coalescer.pending == nil)
    }

    @Test("Given no pending destination, completion holds")
    func completionWithoutPendingHolds() {
        var coalescer = ABSeekCoalescer()
        _ = coalescer.request(first, tolerance: .scrubbing)

        #expect(coalescer.completed() == .hold)
        #expect(coalescer.inFlight == nil)
    }

    @Test("Given a pending destination and no in-flight seek, flushing issues it precisely")
    func flushIssuesPendingPrecisely() {
        var coalescer = ABSeekCoalescer(
            inFlight: nil,
            pending: .init(time: latest, tolerance: .scrubbing)
        )

        #expect(coalescer.flush(finalTolerance: .precise) == .issue(latest, tolerance: .precise))
    }

    @Test("Given an in-flight seek, flushing queues a precise final seek after completion")
    func flushWaitsForInFlightSeek() {
        var coalescer = ABSeekCoalescer()
        _ = coalescer.request(first, tolerance: .scrubbing)
        _ = coalescer.request(latest, tolerance: .scrubbing)

        #expect(coalescer.flush(finalTolerance: .precise) == .hold)
        #expect(coalescer.completed() == .issue(latest, tolerance: .precise))
    }

    @Test("Given reset state, a late completion cannot issue discarded work")
    func resetIgnoresLateCompletion() {
        var coalescer = ABSeekCoalescer()
        _ = coalescer.request(first, tolerance: .scrubbing)
        _ = coalescer.request(latest, tolerance: .scrubbing)

        coalescer.reset()

        #expect(coalescer.completed() == .hold)
        #expect(coalescer.inFlight == nil)
        #expect(coalescer.pending == nil)
    }
}
