import ABPlayerKit
import Foundation
import Testing
@testable import ABPlayerKitCache

@Suite("ABCacheKey derivation", .timeLimit(.minutes(3)))
struct ABCacheKeyTests {
    @Test("Normalizes host, default port, query order, fragments, and transient tokens")
    func normalizesURLs() {
        let first = ABMediaSource(url: URL(string:
            "HTTPS://EXAMPLE.COM:443/video.mp4?quality=hd&token=one&lang=en#frame"
        )!)
        let second = ABMediaSource(url: URL(string:
            "https://example.com/video.mp4?lang=en&quality=hd&token=two"
        )!)

        #expect(ABCacheKey.derive(from: first) == ABCacheKey.derive(from: second))
    }

    @Test("Preserves non-authentication query values")
    func preservesContentQueries() {
        let hd = ABMediaSource(url: URL(string: "https://example.com/video.mp4?quality=hd")!)
        let sd = ABMediaSource(url: URL(string: "https://example.com/video.mp4?quality=sd")!)

        #expect(ABCacheKey.derive(from: hd) != ABCacheKey.derive(from: sd))
    }
}

@Suite("ABByteRange parsing", .timeLimit(.minutes(3)))
struct ABByteRangeTests {
    @Test("Parses bounded and open-ended single ranges")
    func parsesRanges() {
        #expect(ABByteRange.parse("bytes=0-499") == ABByteRange(lowerBound: 0, upperBound: 499))
        #expect(ABByteRange.parse(" Bytes = 500- ") == ABByteRange(lowerBound: 500, upperBound: nil))
    }

    @Test("Parses suffix ranges and rejects invalid edge cases")
    func rejectsUnsupportedRanges() {
        #expect(ABByteRange.parse("bytes=-500")?.suffixLength == 500)
        #expect(ABByteRange.parse("bytes=-0") == nil)
        #expect(ABByteRange.parse("bytes=500-400") == nil)
        #expect(ABByteRange.parse("bytes=-1-20") == nil)
        #expect(ABByteRange.parse("bytes=0-10,20-30") == nil)
        #expect(ABByteRange.parse("items=0-10") == nil)
    }

}

@Suite("ABContentRange parsing", .timeLimit(.minutes(3)))
struct ABContentRangeTests {
    @Test("Parses a fully-specified Content-Range header")
    func parsesFullyKnownRange() {
        let parsed = ABContentRange.parse("bytes 3-5/6")
        #expect(parsed == ABContentRange(start: 3, end: 5, total: 6))
    }

    @Test("Parses a Content-Range header with an unknown total")
    func parsesUnknownTotal() {
        let parsed = ABContentRange.parse("bytes 0-9/*")
        #expect(parsed == ABContentRange(start: 0, end: 9, total: nil))
    }

    @Test("Parses a Content-Range header with an unknown range but known total")
    func parsesUnknownRangeKnownTotal() {
        let parsed = ABContentRange.parse("bytes */1234")
        #expect(parsed == ABContentRange(start: nil, end: nil, total: 1234))
    }

    @Test("Rejects malformed Content-Range headers")
    func rejectsMalformedHeaders() {
        #expect(ABContentRange.parse("bytes */*") == nil)
        #expect(ABContentRange.parse("items 0-9/10") == nil)
        #expect(ABContentRange.parse("bytes 10-5/20") == nil)
        #expect(ABContentRange.parse("not-a-content-range") == nil)
    }
}

@Suite("ABCacheIndex LRU and persistence", .timeLimit(.minutes(3)))
struct ABCacheIndexTests {
    @Test("Evicts least-recently-used entries until under the limit")
    func evictsLRU() {
        let base = Date(timeIntervalSince1970: 1_000)
        let entries = [
            "old": ABCacheIndex.Entry(key: "old", size: 40, lastAccessedAt: base),
            "middle": ABCacheIndex.Entry(key: "middle", size: 30, lastAccessedAt: base.addingTimeInterval(1)),
            "new": ABCacheIndex.Entry(key: "new", size: 20, lastAccessedAt: base.addingTimeInterval(2))
        ]
        var index = ABCacheIndex(entries: entries)

        let evicted = index.evictLRU(to: 50)

        #expect(evicted.map(\.key) == ["old"])
        #expect(index.totalSize == 50)
    }

    @Test("Eviction skips entries with active readers")
    func excludesActiveReaders() {
        let base = Date(timeIntervalSince1970: 1_000)
        var index = ABCacheIndex(entries: [
            "active": .init(key: "active", size: 40, lastAccessedAt: base),
            "next": .init(key: "next", size: 30, lastAccessedAt: base.addingTimeInterval(1)),
            "new": .init(key: "new", size: 20, lastAccessedAt: base.addingTimeInterval(2))
        ])

        let evicted = index.evictLRU(to: 60, excluding: ["active"])

        #expect(evicted.map(\.key) == ["next"])
        #expect(Set(index.entries.keys) == ["active", "new"])
    }

    @Test("Codable round-trip preserves all entry metadata")
    func codableRoundTrip() throws {
        let entry = ABCacheIndex.Entry(
            key: "key",
            size: 123,
            contentLength: 456,
            contentType: "video/mp4",
            isComplete: false,
            lastAccessedAt: Date(timeIntervalSince1970: 2_000)
        )
        let original = ABCacheIndex(entries: [entry.key: entry])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ABCacheIndex.self, from: data)

        #expect(decoded == original)
    }
}
