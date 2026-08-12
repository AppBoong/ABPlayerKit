import Foundation

public struct ABPlaybackStatistics: Sendable, Equatable {
    public let sampleCount: Int
    public let hitCount: Int
    public let abandonedCount: Int
    /// Legacy distribution over every successful sample, `.hit` folded in as
    /// `0` ms. New code should read ``waited`` instead — a feed with a lot
    /// of preload hits collapses this distribution's lower percentiles
    /// toward zero.
    public let p50: Double
    public let p95: Double
    public let max: Double
    /// The `.waited` samples only, `.hit` excluded — the distribution that
    /// actually reflects how long a viewer waited when they did wait.
    public let waited: ABLatencyDistribution

    public init(
        sampleCount: Int,
        hitCount: Int,
        abandonedCount: Int,
        p50: Double,
        p95: Double,
        max: Double,
        waited: ABLatencyDistribution = .empty
    ) {
        self.sampleCount = sampleCount
        self.hitCount = hitCount
        self.abandonedCount = abandonedCount
        self.p50 = p50
        self.p95 = p95
        self.max = max
        self.waited = waited
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
        var waitedDurations: [Double] = []

        for sample in samples {
            switch sample.outcome {
            case .hit:
                hitCount += 1
                successfulDurations.append(0)
            case .waited(let milliseconds):
                successfulDurations.append(milliseconds)
                waitedDurations.append(milliseconds)
            case .abandoned:
                abandonedCount += 1
            }
        }

        let legacy = ABLatencyDistribution.build(from: successfulDurations)
        return ABPlaybackStatistics(
            sampleCount: samples.count,
            hitCount: hitCount,
            abandonedCount: abandonedCount,
            p50: legacy.p50,
            p95: legacy.p95,
            max: legacy.max,
            waited: ABLatencyDistribution.build(from: waitedDurations)
        )
    }
}
