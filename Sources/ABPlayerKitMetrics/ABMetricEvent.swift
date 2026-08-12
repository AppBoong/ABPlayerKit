import ABPlayerKit
import Foundation

public struct ABMetricSample: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case hit
        case waited(ms: Double)
        case abandoned
    }

    public let playerID: ABPlayerID
    public let startedAt: CFTimeInterval
    public let outcome: Outcome
    public let resumedFromTime: CFTimeInterval?

    public init(
        playerID: ABPlayerID,
        startedAt: CFTimeInterval,
        outcome: Outcome,
        resumedFromTime: CFTimeInterval? = nil
    ) {
        self.playerID = playerID
        self.startedAt = startedAt
        self.outcome = outcome
        self.resumedFromTime = resumedFromTime
    }
}

/// Treat this enum as non-exhaustive, the same convention documented on
/// `ABPlayerEvent`: minor releases may add cases, so switches outside this
/// package should include a `default` branch to remain source-compatible.
public enum ABMetricEvent: Sendable, Equatable {
    case ttff(ABMetricSample)
    case stall(playerID: ABPlayerID, at: CFTimeInterval)
    case preloadStarted(playerID: ABPlayerID, at: CFTimeInterval)
    case itemDetached(playerID: ABPlayerID, reason: ABDetachReason, access: ABAccessSnapshot?)
    case tuning(playerID: ABPlayerID, role: ABTuningRole)
    case sessionStarted(ABSessionAnchor)
    case buffering(ABBufferingInterval)
    case failure(ABFailureRecord)
    case sessionSummary(ABSessionSummary)
}

public struct ABAccessSnapshot: Sendable, Equatable {
    public let numberOfBytesTransferred: Int64
    public let indicatedBitrate: Double
    public let observedBitrate: Double
    public let startupTime: Double
    public let stallCount: Int
    /// Sum of `numberOfBytesTransferred` across every access-log entry
    /// (unlike ``numberOfBytesTransferred``, which is the last entry only).
    public let totalBytesTransferred: Int64
    /// Sum of `numberOfStalls` across every entry.
    public let totalStallCount: Int
    /// Sum of `numberOfDroppedVideoFrames` across every entry.
    public let droppedVideoFrameCount: Int
    /// Count of adjacent entries whose `indicatedBitrate` differs, counted
    /// only when both sides are known (> 0).
    public let bitrateSwitchCount: Int
    /// Sum of `AVPlayerItemAccessLogEvent.numberOfSegmentsDownloaded` across
    /// every entry. Always `0` on this platform: that property has been
    /// API-unavailable in Swift since iOS 7, superseded by
    /// ``mediaRequestCount``. Kept in the schema for forward compatibility.
    public let segmentsDownloadedCount: Int
    /// Sum of `numberOfMediaRequests` across every entry.
    public let mediaRequestCount: Int
    /// Sum of `durationWatched` across every entry, in seconds.
    public let durationWatchedSeconds: Double
    /// `observedBitrate` averaged across entries, weighted by each entry's
    /// `durationWatched`. `0` when the weights sum to `0`.
    public let observedBitrateAverage: Double
    /// The first non-negative `startupTime` across entries, in seconds.
    public let initialStartupTimeSeconds: Double?
    public let entryCount: Int

    public init(
        numberOfBytesTransferred: Int64,
        indicatedBitrate: Double,
        observedBitrate: Double,
        startupTime: Double,
        stallCount: Int,
        totalBytesTransferred: Int64 = 0,
        totalStallCount: Int = 0,
        droppedVideoFrameCount: Int = 0,
        bitrateSwitchCount: Int = 0,
        segmentsDownloadedCount: Int = 0,
        mediaRequestCount: Int = 0,
        durationWatchedSeconds: Double = 0,
        observedBitrateAverage: Double = 0,
        initialStartupTimeSeconds: Double? = nil,
        entryCount: Int = 0
    ) {
        self.numberOfBytesTransferred = numberOfBytesTransferred
        self.indicatedBitrate = indicatedBitrate
        self.observedBitrate = observedBitrate
        self.startupTime = startupTime
        self.stallCount = stallCount
        self.totalBytesTransferred = totalBytesTransferred
        self.totalStallCount = totalStallCount
        self.droppedVideoFrameCount = droppedVideoFrameCount
        self.bitrateSwitchCount = bitrateSwitchCount
        self.segmentsDownloadedCount = segmentsDownloadedCount
        self.mediaRequestCount = mediaRequestCount
        self.durationWatchedSeconds = durationWatchedSeconds
        self.observedBitrateAverage = observedBitrateAverage
        self.initialStartupTimeSeconds = initialStartupTimeSeconds
        self.entryCount = entryCount
    }
}
