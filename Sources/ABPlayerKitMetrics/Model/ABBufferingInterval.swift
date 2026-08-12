import ABPlayerKit
import Foundation
@preconcurrency import QuartzCore

/// One closed buffering-or-stall span. Emitted once, when the span closes —
/// never while it's still open.
public struct ABBufferingInterval: Sendable, Equatable {
    /// Buffering before the first frame is measured by TTFF already;
    /// `.startup` keeps it out of the rebuffer ratio's numerator so the two
    /// metrics don't double-count the same wait.
    public enum Phase: Sendable, Equatable {
        case startup
        case rebuffer
    }

    public enum Trigger: Sendable, Equatable {
        case buffering
        case stall
    }

    public enum End: Sendable, Equatable {
        case resumed
        case detached
        case failed
        case finalized
    }

    public let playerID: ABPlayerID
    public let sessionStartedAt: CFTimeInterval
    public let startedAt: CFTimeInterval
    public let endedAt: CFTimeInterval
    public let phase: Phase
    public let trigger: Trigger
    public let end: End

    public init(
        playerID: ABPlayerID,
        sessionStartedAt: CFTimeInterval,
        startedAt: CFTimeInterval,
        endedAt: CFTimeInterval,
        phase: Phase,
        trigger: Trigger,
        end: End
    ) {
        self.playerID = playerID
        self.sessionStartedAt = sessionStartedAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.phase = phase
        self.trigger = trigger
        self.end = end
    }

    public var milliseconds: Double {
        max(0, endedAt - startedAt) * 1_000
    }
}
