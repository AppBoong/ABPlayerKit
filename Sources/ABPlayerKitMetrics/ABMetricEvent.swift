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

public enum ABMetricEvent: Sendable, Equatable {
    case ttff(ABMetricSample)
    case stall(playerID: ABPlayerID, at: CFTimeInterval)
    case preloadStarted(playerID: ABPlayerID, at: CFTimeInterval)
    case itemDetached(playerID: ABPlayerID, reason: ABDetachReason, access: ABAccessSnapshot?)
    case tuning(playerID: ABPlayerID, role: ABTuningRole)
}

public struct ABAccessSnapshot: Sendable, Equatable {
    public let numberOfBytesTransferred: Int64
    public let indicatedBitrate: Double
    public let observedBitrate: Double
    public let startupTime: Double
    public let stallCount: Int

    public init(
        numberOfBytesTransferred: Int64,
        indicatedBitrate: Double,
        observedBitrate: Double,
        startupTime: Double,
        stallCount: Int
    ) {
        self.numberOfBytesTransferred = numberOfBytesTransferred
        self.indicatedBitrate = indicatedBitrate
        self.observedBitrate = observedBitrate
        self.startupTime = startupTime
        self.stallCount = stallCount
    }
}
