import Foundation

public struct ABPlaybackStatistics: Sendable, Equatable {
    public let sampleCount: Int
    public let hitCount: Int
    public let abandonedCount: Int
    public let p50: Double
    public let p95: Double
    public let max: Double

    public init(
        sampleCount: Int,
        hitCount: Int,
        abandonedCount: Int,
        p50: Double,
        p95: Double,
        max: Double
    ) {
        self.sampleCount = sampleCount
        self.hitCount = hitCount
        self.abandonedCount = abandonedCount
        self.p50 = p50
        self.p95 = p95
        self.max = max
    }

    public var hitRate: Double {
        guard sampleCount > 0 else { return 0 }
        return Double(hitCount) / Double(sampleCount)
    }

    public var abandonRate: Double {
        guard sampleCount > 0 else { return 0 }
        return Double(abandonedCount) / Double(sampleCount)
    }

    public static func aggregate(_ samples: [ABMetricSample]) -> ABPlaybackStatistics {
        var hitCount = 0
        var abandonedCount = 0
        var successfulDurations: [Double] = []

        for sample in samples {
            switch sample.outcome {
            case .hit:
                hitCount += 1
                successfulDurations.append(0)
            case .waited(let milliseconds):
                successfulDurations.append(milliseconds)
            case .abandoned:
                abandonedCount += 1
            }
        }

        successfulDurations.sort()
        return ABPlaybackStatistics(
            sampleCount: samples.count,
            hitCount: hitCount,
            abandonedCount: abandonedCount,
            p50: percentile(0.50, values: successfulDurations),
            p95: percentile(0.95, values: successfulDurations),
            max: successfulDurations.last ?? 0
        )
    }

    private static func percentile(_ percentile: Double, values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let rank = Swift.max(1, Int(ceil(percentile * Double(values.count))))
        return values[rank - 1]
    }
}
