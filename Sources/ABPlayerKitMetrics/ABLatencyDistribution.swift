import Foundation

/// Percentiles over one set of latency samples, in milliseconds.
public struct ABLatencyDistribution: Sendable, Equatable {
    public let count: Int
    public let p50: Double
    public let p95: Double
    public let max: Double

    public init(count: Int, p50: Double, p95: Double, max: Double) {
        self.count = count
        self.p50 = p50
        self.p95 = p95
        self.max = max
    }

    public static let empty = ABLatencyDistribution(count: 0, p50: 0, p95: 0, max: 0)

    static func build(from values: [Double]) -> ABLatencyDistribution {
        guard !values.isEmpty else { return .empty }
        let sorted = values.sorted()
        return ABLatencyDistribution(
            count: sorted.count,
            p50: percentile(0.50, values: sorted),
            p95: percentile(0.95, values: sorted),
            max: sorted.last ?? 0
        )
    }

    private static func percentile(_ percentile: Double, values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let rank = Swift.max(1, Int(ceil(percentile * Double(values.count))))
        return values[rank - 1]
    }
}
