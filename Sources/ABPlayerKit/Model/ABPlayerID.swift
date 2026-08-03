import Foundation

/// Opaque identifier for an `ABPlayer` instance. Used to correlate events and
/// metrics samples without exposing the class itself.
public struct ABPlayerID: Hashable, Sendable, CustomStringConvertible {
    private let rawValue: UUID

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}
