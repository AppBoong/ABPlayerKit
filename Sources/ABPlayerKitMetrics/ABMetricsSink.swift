import ABPlayerKit
import Foundation
import OSLog

public protocol ABMetricsSink: Sendable {
    func record(_ event: ABMetricEvent)
}

public final class ABInMemoryMetricsSink: ABMetricsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [ABMetricEvent] = []

    public init() {}

    public var events: [ABMetricEvent] {
        lock.lock()
        let snapshot = storedEvents
        lock.unlock()
        return snapshot
    }

    public func record(_ event: ABMetricEvent) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }
}

/// Writes newline-delimited JSON records. Every write, retry, and rotation
/// happens on `queue`, which also owns the lazily-opened `FileHandle` — kept
/// open across records rather than reopened per write.
///
/// Never throws out of ``record(_:)`` — a metrics sink is an observation
/// path and must not be able to disrupt playback. Persistent write failures
/// surface through ``writeFailureCount``/``lastWriteErrorDescription`` and a
/// single `OSLog` `.error` line instead.
public final class ABJSONLinesMetricsSink: ABMetricsSink, @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "ABPlayerKitMetrics.JSONLines")
    private let maxFileSizeBytes: Int?
    private let maxRotatedFiles: Int
    private let logger = Logger(subsystem: "ABPlayerKitMetrics", category: "JSONLinesSink")

    // Confined to `queue`.
    private var handle: FileHandle?
    private var currentSize: UInt64 = 0
    private var writeFailureCountStorage = 0
    private var lastWriteErrorDescriptionStorage: String?

    /// - Parameters:
    ///   - fileURL: Where records are appended as newline-delimited JSON.
    ///   - maxFileSizeBytes: `nil` (the default) disables rotation — the
    ///     v1 behavior of an unbounded file.
    ///   - maxRotatedFiles: How many rotated files (`.1`, `.2`, …) to keep
    ///     once rotation is enabled. Ignored while `maxFileSizeBytes == nil`.
    public init(
        fileURL: URL,
        maxFileSizeBytes: Int? = nil,
        maxRotatedFiles: Int = 1
    ) {
        self.fileURL = fileURL
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxRotatedFiles = maxRotatedFiles
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    deinit {
        try? handle?.close()
    }

    /// Incremented every time a record fails to write even after the
    /// one-shot reopen retry.
    public var writeFailureCount: Int {
        queue.sync { writeFailureCountStorage }
    }

    public var lastWriteErrorDescription: String? {
        queue.sync { lastWriteErrorDescriptionStorage }
    }

    public func record(_ event: ABMetricEvent) {
        queue.async { [self] in
            guard let data = Self.encode(event) else { return }
            var payload = data
            payload.append(0x0A)
            if handle == nil {
                openHandle()
            }
            rotateIfNeeded(nextWriteSize: payload.count)
            write(payload)
        }
    }

    /// Blocks until every record enqueued so far has been written and
    /// `synchronize()`d to disk.
    public func flush() {
        queue.sync {
            try? handle?.synchronize()
        }
    }

    // MARK: - Queue-confined I/O

    private func openHandle() {
        handle = try? FileHandle(forWritingTo: fileURL)
        guard let handle, let offset = try? handle.seekToEnd() else {
            currentSize = 0
            return
        }
        currentSize = offset
    }

    private func write(_ data: Data) {
        if let handle, performWrite(data, using: handle) {
            return
        }
        try? handle?.close()
        handle = nil
        openHandle()
        if let handle, performWrite(data, using: handle) {
            return
        }
        recordWriteFailure("failed to write a metrics record after a reopen retry")
    }

    private func performWrite(_ data: Data, using handle: FileHandle) -> Bool {
        do {
            try handle.write(contentsOf: data)
            currentSize += UInt64(data.count)
            return true
        } catch {
            return false
        }
    }

    private func recordWriteFailure(_ description: String) {
        writeFailureCountStorage += 1
        lastWriteErrorDescriptionStorage = description
        logger.error("ABJSONLinesMetricsSink write failed: \(description, privacy: .public)")
    }

    private func rotateIfNeeded(nextWriteSize: Int) {
        guard let maxFileSizeBytes,
              currentSize + UInt64(nextWriteSize) > UInt64(maxFileSizeBytes) else { return }
        try? handle?.close()
        handle = nil

        let fileManager = FileManager.default
        guard maxRotatedFiles > 0 else {
            try? fileManager.removeItem(at: fileURL)
            fileManager.createFile(atPath: fileURL.path, contents: nil)
            currentSize = 0
            return
        }

        try? fileManager.removeItem(at: rotatedURL(index: maxRotatedFiles))
        var index = maxRotatedFiles
        while index > 1 {
            let source = rotatedURL(index: index - 1)
            let destination = rotatedURL(index: index)
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.removeItem(at: destination)
                try? fileManager.moveItem(at: source, to: destination)
            }
            index -= 1
        }
        try? fileManager.moveItem(at: fileURL, to: rotatedURL(index: 1))
        fileManager.createFile(atPath: fileURL.path, contents: nil)
        currentSize = 0
    }

    private func rotatedURL(index: Int) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.lastPathComponent + ".\(index)")
    }

    // MARK: - Encoding

    /// Stable strings for JSONL keys/aggregation, since
    /// `String(describing:)` on an associated-value case (e.g.
    /// `itemFailed(description:)`) would embed the payload and break key
    /// stability. `default` covers cases added after this mapping was
    /// written — non-exhaustive by the same convention as `ABPlayerError`
    /// itself.
    static func kindName(_ kind: ABPlayerError) -> String {
        switch kind {
        case .itemFailed: return "itemFailed"
        case .prerollTimedOut: return "prerollTimedOut"
        case .prerollFailed: return "prerollFailed"
        case .invalidGradeForSource: return "invalidGradeForSource"
        case .cacheUnavailable: return "cacheUnavailable"
        case .audioSessionOperationFailed: return "audioSessionOperationFailed"
        case .itemErrorLogEntry: return "itemErrorLogEntry"
        @unknown default: return "unknown"
        }
    }

    private static func encode(_ event: ABMetricEvent) -> Data? {
        guard let object = jsonObject(for: event) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func jsonObject(for event: ABMetricEvent) -> [String: Any]? {
        switch event {
        case .ttff(let sample):
            var sampleObject: [String: Any] = [
                "playerID": sample.playerID.description,
                "startedAt": sample.startedAt,
                "outcome": outcomeObject(sample.outcome)
            ]
            if let resumedFromTime = sample.resumedFromTime {
                sampleObject["resumedFromTime"] = resumedFromTime
            }
            return ["event": "ttff", "sample": sampleObject]

        case .stall(let playerID, let time):
            return ["event": "stall", "playerID": playerID.description, "at": time]

        case .preloadStarted(let playerID, let time):
            return ["event": "preloadStarted", "playerID": playerID.description, "at": time]

        case .itemDetached(let playerID, let reason, let access):
            var item: [String: Any] = [
                "event": "itemDetached",
                "playerID": playerID.description,
                "reason": String(describing: reason)
            ]
            if let access {
                item["access"] = accessObject(access)
            }
            return item

        case .tuning(let playerID, let role):
            return [
                "event": "tuning",
                "playerID": playerID.description,
                "role": String(describing: role)
            ]

        case .sessionStarted(let anchor):
            var item: [String: Any] = [
                "event": "sessionStarted",
                "playerID": anchor.playerID.description,
                "startedAt": anchor.startedAt,
                "wallClockEpoch": anchor.wallClockEpoch,
                "isPartial": anchor.isPartial
            ]
            if let sourceURL = anchor.sourceURL {
                item["sourceURL"] = sourceURL
            }
            return item

        case .buffering(let interval):
            return [
                "event": "buffering",
                "playerID": interval.playerID.description,
                "sessionStartedAt": interval.sessionStartedAt,
                "startedAt": interval.startedAt,
                "endedAt": interval.endedAt,
                "milliseconds": interval.milliseconds,
                "phase": phaseName(interval.phase),
                "trigger": triggerName(interval.trigger),
                "end": endName(interval.end)
            ]

        case .failure(let record):
            var item: [String: Any] = [
                "event": "failure",
                "playerID": record.playerID.description,
                "at": record.at,
                "isTerminal": record.failure.isTerminal,
                "kind": kindName(record.failure.kind),
                "description": String(describing: record.failure.kind)
            ]
            if let sessionStartedAt = record.sessionStartedAt {
                item["sessionStartedAt"] = sessionStartedAt
            }
            if let origin = record.failure.origin {
                item["domain"] = origin.domain
                item["code"] = origin.code
            }
            return item

        case .sessionSummary(let summary):
            // `.active` is a live snapshot for display, never sunk.
            guard summary.endReason != .active else { return nil }
            var item: [String: Any] = [
                "event": "sessionSummary",
                "playerID": summary.playerID.description,
                "startedAt": summary.startedAt,
                "wallClockEpoch": summary.wallClockEpoch,
                "endedAt": summary.endedAt,
                "endReason": endReasonName(summary.endReason),
                "isPartial": summary.isPartial,
                "hasDisplayedFirstFrame": summary.hasDisplayedFirstFrame,
                "watchedMilliseconds": summary.watchedMilliseconds,
                "startupBufferMilliseconds": summary.startupBufferMilliseconds,
                "rebufferMilliseconds": summary.rebufferMilliseconds,
                "rebufferCount": summary.rebufferCount,
                "stallEventCount": summary.stallEventCount,
                "terminalFailureCount": summary.terminalFailureCount,
                "diagnosticCount": summary.diagnosticCount,
                "playedToEnd": summary.playedToEnd
            ]
            if let sourceURL = summary.sourceURL {
                item["sourceURL"] = sourceURL
            }
            if let startupOutcome = summary.startupOutcome {
                item["startupOutcome"] = outcomeObject(startupOutcome)
            }
            if let lastPositionSeconds = summary.lastPositionSeconds {
                item["lastPositionSeconds"] = lastPositionSeconds
            }
            if let durationSeconds = summary.durationSeconds {
                item["durationSeconds"] = durationSeconds
            }
            if let rebufferRatio = summary.rebufferRatio {
                item["rebufferRatio"] = rebufferRatio
            }
            if let completionRatio = summary.completionRatio {
                item["completionRatio"] = completionRatio
            }
            if let access = summary.access {
                item["access"] = accessObject(access)
            }
            return item
        }
    }

    private static func outcomeObject(_ outcome: ABMetricSample.Outcome) -> [String: Any] {
        switch outcome {
        case .hit:
            return ["kind": "hit"]
        case .waited(let milliseconds):
            return ["kind": "waited", "milliseconds": milliseconds]
        case .abandoned:
            return ["kind": "abandoned"]
        }
    }

    private static func accessObject(_ access: ABAccessSnapshot) -> [String: Any] {
        var object: [String: Any] = [
            "numberOfBytesTransferred": access.numberOfBytesTransferred,
            "indicatedBitrate": access.indicatedBitrate,
            "observedBitrate": access.observedBitrate,
            "startupTime": access.startupTime,
            "stallCount": access.stallCount,
            "totalBytesTransferred": access.totalBytesTransferred,
            "totalStallCount": access.totalStallCount,
            "droppedVideoFrameCount": access.droppedVideoFrameCount,
            "bitrateSwitchCount": access.bitrateSwitchCount,
            "segmentsDownloadedCount": access.segmentsDownloadedCount,
            "mediaRequestCount": access.mediaRequestCount,
            "durationWatchedSeconds": access.durationWatchedSeconds,
            "observedBitrateAverage": access.observedBitrateAverage,
            "entryCount": access.entryCount
        ]
        if let initialStartupTimeSeconds = access.initialStartupTimeSeconds {
            object["initialStartupTimeSeconds"] = initialStartupTimeSeconds
        }
        return object
    }

    private static func phaseName(_ phase: ABBufferingInterval.Phase) -> String {
        switch phase {
        case .startup: return "startup"
        case .rebuffer: return "rebuffer"
        }
    }

    private static func triggerName(_ trigger: ABBufferingInterval.Trigger) -> String {
        switch trigger {
        case .buffering: return "buffering"
        case .stall: return "stall"
        }
    }

    private static func endName(_ end: ABBufferingInterval.End) -> String {
        switch end {
        case .resumed: return "resumed"
        case .detached: return "detached"
        case .failed: return "failed"
        case .finalized: return "finalized"
        }
    }

    private static func endReasonName(_ endReason: ABSessionSummary.EndReason) -> String {
        switch endReason {
        case .active: return "active"
        case .detached(let reason): return "detached:\(String(describing: reason))"
        case .finalized: return "finalized"
        }
    }
}

public struct ABOSLogMetricsSink: ABMetricsSink {
    private let logger: Logger

    public init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func record(_ event: ABMetricEvent) {
        logger.info("\(String(describing: event), privacy: .public)")
    }
}
