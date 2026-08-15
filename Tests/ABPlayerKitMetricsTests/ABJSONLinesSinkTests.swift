import ABPlayerKit
import ABTestSupport
import Foundation
@preconcurrency import QuartzCore
import Testing
@testable import ABPlayerKitMetrics

private func makeTempFileURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ABPlayerKitMetrics-Sink-Tests", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jsonl")
}

private func readLines(at url: URL) -> [String] {
    guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
    return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}

private func readJSONObjects(at url: URL) -> [[String: Any]] {
    readLines(at: url).compactMap { line -> [String: Any]? in
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

@Suite("ABJSONLinesMetricsSink", .timeLimit(abScaledMinutes(3)))
struct ABJSONLinesSinkTests {
    @Test("A v1 stall record is byte-identical to the v1 shape")
    func goldenStallEventIsByteIdentical() {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        let playerID = ABPlayerID()

        sink.record(.stall(playerID: playerID, at: 12.5))
        sink.flush()

        #expect(readLines(at: url) == [
            "{\"at\":12.5,\"event\":\"stall\",\"playerID\":\"\(playerID.description)\"}"
        ])
    }

    @Test("Every v1 record type keeps the v1 key/value shape")
    func v1RecordShapesAreUnchanged() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        let playerID = ABPlayerID()

        sink.record(.ttff(ABMetricSample(playerID: playerID, startedAt: 1, outcome: .hit)))
        sink.record(.ttff(ABMetricSample(playerID: playerID, startedAt: 2, outcome: .waited(ms: 250), resumedFromTime: 12.5)))
        sink.record(.ttff(ABMetricSample(playerID: playerID, startedAt: 3, outcome: .abandoned)))
        sink.record(.stall(playerID: playerID, at: 4))
        sink.record(.preloadStarted(playerID: playerID, at: 5))
        sink.record(.itemDetached(playerID: playerID, reason: .release, access: nil))
        sink.record(.tuning(playerID: playerID, role: .current))
        sink.flush()

        let objects = readJSONObjects(at: url)
        #expect(objects.count == 7)

        #expect(objects[0]["event"] as? String == "ttff")
        let hitSample = try #require(objects[0]["sample"] as? [String: Any])
        #expect(hitSample["playerID"] as? String == playerID.description)
        #expect(hitSample["startedAt"] as? Double == 1)
        #expect((hitSample["outcome"] as? [String: Any])?["kind"] as? String == "hit")
        #expect(hitSample["resumedFromTime"] == nil)

        let waitedSample = try #require(objects[1]["sample"] as? [String: Any])
        let waitedOutcome = try #require(waitedSample["outcome"] as? [String: Any])
        #expect(waitedOutcome["kind"] as? String == "waited")
        #expect(waitedOutcome["milliseconds"] as? Double == 250)
        #expect(waitedSample["resumedFromTime"] as? Double == 12.5)

        let abandonedSample = try #require(objects[2]["sample"] as? [String: Any])
        #expect((abandonedSample["outcome"] as? [String: Any])?["kind"] as? String == "abandoned")

        #expect(objects[3] as NSDictionary == ["event": "stall", "playerID": playerID.description, "at": 4] as NSDictionary)
        #expect(objects[4] as NSDictionary == ["event": "preloadStarted", "playerID": playerID.description, "at": 5] as NSDictionary)
        #expect(objects[5] as NSDictionary == ["event": "itemDetached", "playerID": playerID.description, "reason": "release"] as NSDictionary)
        #expect(objects[6] as NSDictionary == ["event": "tuning", "playerID": playerID.description, "role": "current"] as NSDictionary)
    }

    @Test("itemDetached keeps its 5 legacy access values as new keys are added")
    func itemDetachedAccessKeepsLegacyKeys() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        let playerID = ABPlayerID()
        let access = ABAccessSnapshot(
            numberOfBytesTransferred: 1_000,
            indicatedBitrate: 900_000,
            observedBitrate: 800_000,
            startupTime: 1.5,
            stallCount: 2,
            totalBytesTransferred: 5_000,
            totalStallCount: 4,
            droppedVideoFrameCount: 3,
            bitrateSwitchCount: 1,
            segmentsDownloadedCount: 0,
            mediaRequestCount: 6,
            durationWatchedSeconds: 30,
            observedBitrateAverage: 850_000,
            initialStartupTimeSeconds: 1.0,
            entryCount: 4
        )
        sink.record(.itemDetached(playerID: playerID, reason: .sourceChanged, access: access))
        sink.flush()

        let object = try #require(readJSONObjects(at: url).first)
        let accessObject = try #require(object["access"] as? [String: Any])
        #expect(accessObject["numberOfBytesTransferred"] as? Int64 == 1_000)
        #expect(accessObject["indicatedBitrate"] as? Double == 900_000)
        #expect(accessObject["observedBitrate"] as? Double == 800_000)
        #expect(accessObject["startupTime"] as? Double == 1.5)
        #expect(accessObject["stallCount"] as? Int == 2)
        #expect(accessObject["totalBytesTransferred"] as? Int64 == 5_000)
        #expect(accessObject["bitrateSwitchCount"] as? Int == 1)
        #expect(accessObject["initialStartupTimeSeconds"] as? Double == 1.0)
    }

    @Test("sessionStarted omits sourceURL when nil")
    func sessionStartedOmitsNilSourceURL() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        let playerID = ABPlayerID()
        sink.record(.sessionStarted(ABSessionAnchor(
            playerID: playerID, startedAt: 1, wallClockEpoch: 2, sourceURL: nil, isPartial: true
        )))
        sink.flush()

        let object = try #require(readJSONObjects(at: url).first)
        #expect(object["sourceURL"] == nil)
        #expect(object["isPartial"] as? Bool == true)
        #expect(Set(object.keys) == ["event", "playerID", "startedAt", "wallClockEpoch", "isPartial"])
    }

    @Test("buffering serializes phase/trigger/end as stable strings")
    func bufferingSerializesEnumsAsStrings() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        let playerID = ABPlayerID()
        sink.record(.buffering(ABBufferingInterval(
            playerID: playerID,
            sessionStartedAt: 0,
            startedAt: 1,
            endedAt: 2,
            phase: .rebuffer,
            trigger: .stall,
            end: .detached
        )))
        sink.flush()

        let object = try #require(readJSONObjects(at: url).first)
        #expect(object["phase"] as? String == "rebuffer")
        #expect(object["trigger"] as? String == "stall")
        #expect(object["end"] as? String == "detached")
        #expect(object["milliseconds"] as? Double == 1_000)
    }

    @Test("failure omits sessionStartedAt/domain/code when unset and includes them when known")
    func failureOmitsOptionalKeysWhenUnset() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        let playerID = ABPlayerID()
        sink.record(.failure(ABFailureRecord(playerID: playerID, at: 3, failure: ABPlayerFailure(kind: .prerollFailed))))
        sink.record(.failure(ABFailureRecord(
            playerID: playerID,
            sessionStartedAt: 1,
            at: 4,
            failure: ABPlayerFailure(
                kind: .itemFailed(description: "x"),
                origin: ABErrorOrigin(domain: "NSURLErrorDomain", code: -1_009)
            )
        )))
        sink.flush()

        let objects = readJSONObjects(at: url)
        #expect(objects[0]["sessionStartedAt"] == nil)
        #expect(objects[0]["domain"] == nil)
        #expect(objects[0]["kind"] as? String == "prerollFailed")

        #expect(objects[1]["sessionStartedAt"] as? Double == 1)
        #expect(objects[1]["domain"] as? String == "NSURLErrorDomain")
        #expect(objects[1]["code"] as? Int == -1_009)
        #expect(objects[1]["kind"] as? String == "itemFailed")
    }

    @Test("sessionSummary omits nil optional fields and never serializes .active")
    func sessionSummaryOmitsNilFieldsAndSkipsActive() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        let playerID = ABPlayerID()
        let active = ABSessionSummary(playerID: playerID, startedAt: 0, wallClockEpoch: 0, endedAt: 1, endReason: .active)
        sink.record(.sessionSummary(active))
        let closed = ABSessionSummary(
            playerID: playerID,
            startedAt: 0,
            wallClockEpoch: 100,
            endedAt: 5,
            endReason: .detached(.release),
            watchedMilliseconds: 4_000,
            playedToEnd: false
        )
        sink.record(.sessionSummary(closed))
        sink.flush()

        let objects = readJSONObjects(at: url)
        #expect(objects.count == 1)
        #expect(objects[0]["endReason"] as? String == "detached:release")
        #expect(objects[0]["sourceURL"] == nil)
        #expect(objects[0]["completionRatio"] == nil)
        #expect(objects[0]["watchedMilliseconds"] as? Double == 4_000)
    }

    @Test("Rotation moves the current file to .1 and drops the overflow")
    func rotationMovesCurrentFileAndDropsOverflow() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("metrics.jsonl")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sink = ABJSONLinesMetricsSink(fileURL: url, maxFileSizeBytes: 60, maxRotatedFiles: 1)
        let playerID = ABPlayerID()

        for index in 0..<10 {
            sink.record(.stall(playerID: playerID, at: CFTimeInterval(index)))
        }
        sink.flush()

        let rotatedURL = directory.appendingPathComponent("metrics.jsonl.1")
        #expect(FileManager.default.fileExists(atPath: rotatedURL.path))
        #expect(FileManager.default.fileExists(atPath: url.path))
        let secondRotated = directory.appendingPathComponent("metrics.jsonl.2")
        #expect(!FileManager.default.fileExists(atPath: secondRotated.path))
        for line in readLines(at: url) {
            #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil)
        }
    }

    @Test("A persistent write failure increments the counter without throwing")
    func writeFailureIsCountedNotThrown() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("metrics.jsonl")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        // Replace the file with a directory at the same path — FileHandle(forWritingTo:)
        // can never open a directory as a file, forcing every write to fail
        // deterministically regardless of the running user's permissions.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        sink.record(.stall(playerID: ABPlayerID(), at: 1))
        sink.flush()

        #expect(sink.writeFailureCount > 0)
        #expect(sink.lastWriteErrorDescription != nil)
    }

    @Test("flush() guarantees every enqueued record is fully written")
    func flushGuaranteesCompleteWrites() {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        let playerID = ABPlayerID()

        for index in 0..<50 {
            sink.record(.stall(playerID: playerID, at: CFTimeInterval(index)))
        }
        sink.flush()

        let lines = readLines(at: url)
        #expect(lines.count == 50)
        for line in lines {
            #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil)
        }
    }
}
