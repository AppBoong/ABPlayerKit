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

public final class ABJSONLinesMetricsSink: ABMetricsSink, @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "ABPlayerKitMetrics.JSONLines")

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    public func record(_ event: ABMetricEvent) {
        let fileURL = fileURL
        queue.async {
            guard let data = Self.encode(event) else { return }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data([0x0A]))
            } catch {
                return
            }
        }
    }

    func flush() {
        queue.sync {}
    }

    private static func encode(_ event: ABMetricEvent) -> Data? {
        let object: [String: Any]
        switch event {
        case .ttff(let sample):
            let outcome: [String: Any]
            switch sample.outcome {
            case .hit:
                outcome = ["kind": "hit"]
            case .waited(let milliseconds):
                outcome = ["kind": "waited", "milliseconds": milliseconds]
            case .abandoned:
                outcome = ["kind": "abandoned"]
            }
            var sampleObject: [String: Any] = [
                "playerID": sample.playerID.description,
                "startedAt": sample.startedAt,
                "outcome": outcome
            ]
            if let resumedFromTime = sample.resumedFromTime {
                sampleObject["resumedFromTime"] = resumedFromTime
            }
            object = ["event": "ttff", "sample": sampleObject]
        case .stall(let playerID, let time):
            object = ["event": "stall", "playerID": playerID.description, "at": time]
        case .preloadStarted(let playerID, let time):
            object = ["event": "preloadStarted", "playerID": playerID.description, "at": time]
        case .itemDetached(let playerID, let reason, let access):
            var item: [String: Any] = [
                "event": "itemDetached",
                "playerID": playerID.description,
                "reason": String(describing: reason)
            ]
            if let access {
                item["access"] = [
                    "numberOfBytesTransferred": access.numberOfBytesTransferred,
                    "indicatedBitrate": access.indicatedBitrate,
                    "observedBitrate": access.observedBitrate,
                    "startupTime": access.startupTime,
                    "stallCount": access.stallCount
                ]
            }
            object = item
        case .tuning(let playerID, let role):
            object = [
                "event": "tuning",
                "playerID": playerID.description,
                "role": String(describing: role)
            ]
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
