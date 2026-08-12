import ABPlayerKit
import Foundation
@preconcurrency import QuartzCore

/// A closed (or, via ``ABMetricsRecorder/snapshot(for:)``, still-open) playback
/// session rolled up into QoE-shaped totals.
public struct ABSessionSummary: Sendable, Equatable {
    public enum EndReason: Sendable, Equatable {
        /// Only produced by ``ABMetricsRecorder/snapshot(for:)`` — never sunk to JSONL.
        case active
        case detached(ABDetachReason)
        case finalized
    }

    public let playerID: ABPlayerID
    public let startedAt: CFTimeInterval
    public let wallClockEpoch: TimeInterval
    public let endedAt: CFTimeInterval
    public let endReason: EndReason
    public let isPartial: Bool
    public let sourceURL: String?

    public let startupOutcome: ABMetricSample.Outcome?
    /// Whether the item attached to this session ever displayed a frame —
    /// the denominator ``ABQoESummary/aggregate(_:)`` uses for completion
    /// rate, since a session abandoned before its first frame is an exit,
    /// not an incomplete watch (see `ABPlaybackStatistics/abandonRate`).
    public let hasDisplayedFirstFrame: Bool
    public let watchedMilliseconds: Double
    public let startupBufferMilliseconds: Double
    public let rebufferMilliseconds: Double
    public let rebufferCount: Int
    public let stallEventCount: Int
    public let terminalFailureCount: Int
    public let diagnosticCount: Int
    public let lastFailure: ABPlayerFailure?
    public let playedToEnd: Bool
    public let lastPositionSeconds: Double?
    public let durationSeconds: Double?
    public let access: ABAccessSnapshot?

    public init(
        playerID: ABPlayerID,
        startedAt: CFTimeInterval,
        wallClockEpoch: TimeInterval,
        endedAt: CFTimeInterval,
        endReason: EndReason,
        isPartial: Bool = false,
        sourceURL: String? = nil,
        startupOutcome: ABMetricSample.Outcome? = nil,
        hasDisplayedFirstFrame: Bool = false,
        watchedMilliseconds: Double = 0,
        startupBufferMilliseconds: Double = 0,
        rebufferMilliseconds: Double = 0,
        rebufferCount: Int = 0,
        stallEventCount: Int = 0,
        terminalFailureCount: Int = 0,
        diagnosticCount: Int = 0,
        lastFailure: ABPlayerFailure? = nil,
        playedToEnd: Bool = false,
        lastPositionSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        access: ABAccessSnapshot? = nil
    ) {
        self.playerID = playerID
        self.startedAt = startedAt
        self.wallClockEpoch = wallClockEpoch
        self.endedAt = endedAt
        self.endReason = endReason
        self.isPartial = isPartial
        self.sourceURL = sourceURL
        self.startupOutcome = startupOutcome
        self.hasDisplayedFirstFrame = hasDisplayedFirstFrame
        self.watchedMilliseconds = watchedMilliseconds
        self.startupBufferMilliseconds = startupBufferMilliseconds
        self.rebufferMilliseconds = rebufferMilliseconds
        self.rebufferCount = rebufferCount
        self.stallEventCount = stallEventCount
        self.terminalFailureCount = terminalFailureCount
        self.diagnosticCount = diagnosticCount
        self.lastFailure = lastFailure
        self.playedToEnd = playedToEnd
        self.lastPositionSeconds = lastPositionSeconds
        self.durationSeconds = durationSeconds
        self.access = access
    }

    /// `rebufferMilliseconds / (rebufferMilliseconds + watchedMilliseconds)`.
    /// `nil` when the denominator is zero.
    public var rebufferRatio: Double? {
        let denominator = rebufferMilliseconds + watchedMilliseconds
        guard denominator > 0 else { return nil }
        return rebufferMilliseconds / denominator
    }

    /// `1.0` when the session played to end; otherwise
    /// `lastPositionSeconds / durationSeconds` when both are known. `nil`
    /// (never `0`) when there isn't enough information to tell.
    public var completionRatio: Double? {
        if playedToEnd { return 1.0 }
        guard let lastPositionSeconds, let durationSeconds, durationSeconds > 0 else { return nil }
        return min(max(lastPositionSeconds / durationSeconds, 0), 1)
    }

    /// The waited TTFF duration, when `startupOutcome == .waited`.
    public var startupMilliseconds: Double? {
        guard let startupOutcome, case .waited(let milliseconds) = startupOutcome else { return nil }
        return milliseconds
    }
}
