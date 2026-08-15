import ABPlayerKit
import ABTestSupport
import Foundation
import Testing
@testable import ABPlayerKitMetrics

/// `ABOSLogMetricsSink` used to interpolate the whole event as
/// `privacy: .public`, which put a signed `sourceURL` into a device-wide log
/// that a sysdiagnose collects — defeating `ABMetricsRecorder`'s
/// `includesSourceURL` for every consumer who left it at its `true` default.
///
/// An `OSLog` privacy attribute is not observable from a test, so the sink
/// splits the line first and these pin the split: whatever ends up in the
/// unredacted half must never carry a payload.
@Suite("ABOSLogMetricsSink keeps payloads out of the unredacted half", .timeLimit(abScaledMinutes(3)))
struct ABOSLogSinkRedactionTests {
    private static let signedURL =
        "https://cdn.example.com/v.m3u8?Policy=eyJTdGF0ZW1lbnQi&Signature=SECRETTOKEN123"

    @Test("A session anchor's signed sourceURL stays out of the public half")
    func sessionStartedKeepsSignedURLPrivate() {
        let event = ABMetricEvent.sessionStarted(ABSessionAnchor(
            playerID: ABPlayerID(),
            startedAt: 1,
            wallClockEpoch: 2,
            sourceURL: Self.signedURL
        ))
        let parts = ABOSLogMetricsSink.logParts(for: event)

        #expect(parts.kind == "sessionStarted")
        #expect(parts.kind.contains("SECRETTOKEN123") == false)
        #expect(parts.kind.contains("cdn.example.com") == false)
        // Not merely dropped — the detail still carries it, under redaction.
        #expect(parts.detail.contains("SECRETTOKEN123"))
    }

    @Test("A session summary's signed sourceURL stays out of the public half")
    func sessionSummaryKeepsSignedURLPrivate() {
        let event = ABMetricEvent.sessionSummary(ABSessionSummary(
            playerID: ABPlayerID(),
            startedAt: 1,
            wallClockEpoch: 2,
            endedAt: 3,
            endReason: .finalized,
            sourceURL: Self.signedURL
        ))
        let parts = ABOSLogMetricsSink.logParts(for: event)

        #expect(parts.kind == "sessionSummary")
        #expect(parts.kind.contains("SECRETTOKEN123") == false)
        #expect(parts.detail.contains("SECRETTOKEN123"))
    }

    @Test("The public half is the bare case name, carrying no associated value")
    func publicHalfIsTheBareCaseName() {
        let playerID = ABPlayerID()
        let parts = ABOSLogMetricsSink.logParts(for: .stall(playerID: playerID, at: 12_345))

        #expect(parts.kind == "stall")
        #expect(parts.kind.contains(playerID.description) == false)
        #expect(parts.kind.contains("12345") == false)
        #expect(parts.detail.contains(playerID.description))
    }

    @Test("The log kind and the JSONL discriminator are the same string")
    func logKindMatchesTheJSONLDiscriminator() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ab-oslog-kind-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let event = ABMetricEvent.stall(playerID: ABPlayerID(), at: 1)
        let sink = ABJSONLinesMetricsSink(fileURL: url)
        sink.record(event)
        sink.flush()

        let line = try #require(
            String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n")
                .first
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        #expect(object["event"] as? String == ABOSLogMetricsSink.logParts(for: event).kind)
    }
}
