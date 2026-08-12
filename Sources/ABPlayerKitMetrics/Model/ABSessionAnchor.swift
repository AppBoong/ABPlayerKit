import ABPlayerKit
import Foundation
@preconcurrency import QuartzCore

/// Broadcast once, at session open. Maps this session's monotonic timeline
/// onto a wall-clock instant for joining against server logs — every other
/// v2 event stays purely monotonic (see ``ABClock``).
public struct ABSessionAnchor: Sendable, Equatable {
    public let playerID: ABPlayerID
    /// This session's join key — equal to every v2 event's `sessionStartedAt`
    /// for the same session.
    public let startedAt: CFTimeInterval
    /// Seconds since the Unix epoch, captured once at session open.
    public let wallClockEpoch: TimeInterval
    public let sourceURL: String?
    public let isPartial: Bool

    public init(
        playerID: ABPlayerID,
        startedAt: CFTimeInterval,
        wallClockEpoch: TimeInterval,
        sourceURL: String? = nil,
        isPartial: Bool = false
    ) {
        self.playerID = playerID
        self.startedAt = startedAt
        self.wallClockEpoch = wallClockEpoch
        self.sourceURL = sourceURL
        self.isPartial = isPartial
    }
}
