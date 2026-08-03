import Foundation
@preconcurrency import QuartzCore

public protocol ABClock: Sendable {
    var now: CFTimeInterval { get }
}

public struct ABMonotonicClock: ABClock {
    public init() {}

    public var now: CFTimeInterval {
        CACurrentMediaTime()
    }
}
