import Foundation
@preconcurrency import QuartzCore

public protocol ABClock: Sendable {
    var now: CFTimeInterval { get }
    /// Seconds since the Unix epoch. Defaults to `Date().timeIntervalSince1970`.
    var wallClockEpoch: TimeInterval { get }
}

extension ABClock {
    public var wallClockEpoch: TimeInterval { Date().timeIntervalSince1970 }
}

public struct ABMonotonicClock: ABClock {
    public init() {}

    public var now: CFTimeInterval {
        CACurrentMediaTime()
    }
}
