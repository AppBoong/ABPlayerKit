import ABPlayerKit
import Foundation
@preconcurrency import QuartzCore

/// One `.failureReported` occurrence. `sessionStartedAt` is `nil` when the
/// failure lands outside any open session (e.g. before `.itemAttached` or
/// after the session already closed) — the failure is still worth keeping,
/// just without a session to join it to.
public struct ABFailureRecord: Sendable, Equatable {
    public let playerID: ABPlayerID
    public let sessionStartedAt: CFTimeInterval?
    public let at: CFTimeInterval
    public let failure: ABPlayerFailure

    public init(
        playerID: ABPlayerID,
        sessionStartedAt: CFTimeInterval? = nil,
        at: CFTimeInterval,
        failure: ABPlayerFailure
    ) {
        self.playerID = playerID
        self.sessionStartedAt = sessionStartedAt
        self.at = at
        self.failure = failure
    }
}
