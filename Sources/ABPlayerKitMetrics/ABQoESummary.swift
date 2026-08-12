import Foundation

/// A cross-session QoE rollup, folded from `.sessionSummary` events only —
/// every other ``ABMetricEvent`` case is ignored.
public struct ABQoESummary: Sendable, Equatable {
    public let sessionCount: Int
    public let partialSessionCount: Int
    public let firstFrameSessionCount: Int
    public let completedSessionCount: Int
    public let failedSessionCount: Int
    public let watchedMilliseconds: Double
    public let rebufferMilliseconds: Double
    public let rebufferCount: Int
    public let droppedVideoFrameCount: Int
    public let bitrateSwitchCount: Int

    public init(
        sessionCount: Int = 0,
        partialSessionCount: Int = 0,
        firstFrameSessionCount: Int = 0,
        completedSessionCount: Int = 0,
        failedSessionCount: Int = 0,
        watchedMilliseconds: Double = 0,
        rebufferMilliseconds: Double = 0,
        rebufferCount: Int = 0,
        droppedVideoFrameCount: Int = 0,
        bitrateSwitchCount: Int = 0
    ) {
        self.sessionCount = sessionCount
        self.partialSessionCount = partialSessionCount
        self.firstFrameSessionCount = firstFrameSessionCount
        self.completedSessionCount = completedSessionCount
        self.failedSessionCount = failedSessionCount
        self.watchedMilliseconds = watchedMilliseconds
        self.rebufferMilliseconds = rebufferMilliseconds
        self.rebufferCount = rebufferCount
        self.droppedVideoFrameCount = droppedVideoFrameCount
        self.bitrateSwitchCount = bitrateSwitchCount
    }

    public var rebufferRatio: Double? {
        let denominator = rebufferMilliseconds + watchedMilliseconds
        guard denominator > 0 else { return nil }
        return rebufferMilliseconds / denominator
    }

    /// Sessions that played to end, over sessions that displayed a first
    /// frame — an abandonment before the first frame is an exit, not an
    /// incomplete watch.
    public var completionRate: Double? {
        guard firstFrameSessionCount > 0 else { return nil }
        return Double(completedSessionCount) / Double(firstFrameSessionCount)
    }

    public var terminalFailureRate: Double? {
        guard sessionCount > 0 else { return nil }
        return Double(failedSessionCount) / Double(sessionCount)
    }

    public var rebuffersPerHourWatched: Double? {
        let hoursWatched = watchedMilliseconds / 3_600_000
        guard hoursWatched > 0 else { return nil }
        return Double(rebufferCount) / hoursWatched
    }

    public static func aggregate(_ events: [ABMetricEvent]) -> ABQoESummary {
        var sessionCount = 0
        var partialSessionCount = 0
        var firstFrameSessionCount = 0
        var completedSessionCount = 0
        var failedSessionCount = 0
        var watchedMilliseconds: Double = 0
        var rebufferMilliseconds: Double = 0
        var rebufferCount = 0
        var droppedVideoFrameCount = 0
        var bitrateSwitchCount = 0

        for event in events {
            guard case .sessionSummary(let summary) = event, summary.endReason != .active else { continue }
            sessionCount += 1
            if summary.isPartial { partialSessionCount += 1 }
            if summary.hasDisplayedFirstFrame { firstFrameSessionCount += 1 }
            if summary.playedToEnd { completedSessionCount += 1 }
            if summary.terminalFailureCount > 0 { failedSessionCount += 1 }
            watchedMilliseconds += summary.watchedMilliseconds
            rebufferMilliseconds += summary.rebufferMilliseconds
            rebufferCount += summary.rebufferCount
            if let access = summary.access {
                droppedVideoFrameCount += access.droppedVideoFrameCount
                bitrateSwitchCount += access.bitrateSwitchCount
            }
        }

        return ABQoESummary(
            sessionCount: sessionCount,
            partialSessionCount: partialSessionCount,
            firstFrameSessionCount: firstFrameSessionCount,
            completedSessionCount: completedSessionCount,
            failedSessionCount: failedSessionCount,
            watchedMilliseconds: watchedMilliseconds,
            rebufferMilliseconds: rebufferMilliseconds,
            rebufferCount: rebufferCount,
            droppedVideoFrameCount: droppedVideoFrameCount,
            bitrateSwitchCount: bitrateSwitchCount
        )
    }
}
