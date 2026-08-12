import Foundation

/// One `AVPlayerItemAccessLogEvent`, translated to an AVFoundation-free
/// value so ``ABAccessLogFolder`` stays a pure function. A negative field
/// means "unknown" — `AVFoundation`'s own convention for an access log
/// entry that never resolved that measurement.
struct ABAccessLogEntry: Equatable {
    var numberOfBytesTransferred: Int64
    var indicatedBitrate: Double
    var observedBitrate: Double
    var startupTime: Double
    var numberOfStalls: Int
    var numberOfDroppedVideoFrames: Int
    var durationWatched: Double
    var segmentsDownloadedCount: Int
    var numberOfMediaRequests: Int
}

/// Folds a whole access log into one ``ABAccessSnapshot`` — the last-entry
/// fields v1 already reported, plus totals/switches/averages across every
/// entry. Unknown (negative) fields are excluded from sums rather than
/// treated as zero, so a stream with mostly-unknown measurements doesn't
/// read as "zero activity".
enum ABAccessLogFolder {
    static func fold(_ entries: [ABAccessLogEntry]) -> ABAccessSnapshot {
        guard let last = entries.last else {
            return ABAccessSnapshot(
                numberOfBytesTransferred: 0,
                indicatedBitrate: 0,
                observedBitrate: 0,
                startupTime: 0,
                stallCount: 0
            )
        }

        var totalBytesTransferred: Int64 = 0
        var totalStallCount = 0
        var droppedVideoFrameCount = 0
        var segmentsDownloadedCount = 0
        var mediaRequestCount = 0
        var durationWatchedSeconds: Double = 0
        var weightedObservedBitrate: Double = 0
        var initialStartupTimeSeconds: Double?

        for entry in entries {
            if entry.numberOfBytesTransferred >= 0 {
                totalBytesTransferred += entry.numberOfBytesTransferred
            }
            if entry.numberOfStalls >= 0 {
                totalStallCount += entry.numberOfStalls
            }
            if entry.numberOfDroppedVideoFrames >= 0 {
                droppedVideoFrameCount += entry.numberOfDroppedVideoFrames
            }
            if entry.segmentsDownloadedCount >= 0 {
                segmentsDownloadedCount += entry.segmentsDownloadedCount
            }
            if entry.numberOfMediaRequests >= 0 {
                mediaRequestCount += entry.numberOfMediaRequests
            }
            if entry.durationWatched >= 0 {
                durationWatchedSeconds += entry.durationWatched
                if entry.observedBitrate >= 0 {
                    weightedObservedBitrate += entry.observedBitrate * entry.durationWatched
                }
            }
            if initialStartupTimeSeconds == nil, entry.startupTime >= 0 {
                initialStartupTimeSeconds = entry.startupTime
            }
        }

        var bitrateSwitchCount = 0
        for (previous, current) in zip(entries, entries.dropFirst()) {
            guard previous.indicatedBitrate > 0, current.indicatedBitrate > 0 else { continue }
            if previous.indicatedBitrate != current.indicatedBitrate {
                bitrateSwitchCount += 1
            }
        }

        return ABAccessSnapshot(
            numberOfBytesTransferred: last.numberOfBytesTransferred,
            indicatedBitrate: last.indicatedBitrate,
            observedBitrate: last.observedBitrate,
            startupTime: last.startupTime,
            stallCount: last.numberOfStalls,
            totalBytesTransferred: totalBytesTransferred,
            totalStallCount: totalStallCount,
            droppedVideoFrameCount: droppedVideoFrameCount,
            bitrateSwitchCount: bitrateSwitchCount,
            segmentsDownloadedCount: segmentsDownloadedCount,
            mediaRequestCount: mediaRequestCount,
            durationWatchedSeconds: durationWatchedSeconds,
            observedBitrateAverage: durationWatchedSeconds > 0 ? weightedObservedBitrate / durationWatchedSeconds : 0,
            initialStartupTimeSeconds: initialStartupTimeSeconds,
            entryCount: entries.count
        )
    }
}
