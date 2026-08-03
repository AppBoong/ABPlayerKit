import ABPlayerKit
import Foundation
import Testing
@testable import ABPlayerKitCache

@Suite("ABCacheKey derivation")
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

@Suite("ABByteRange parsing and merging")
struct ABByteRangeTests {
    @Test("Parses bounded and open-ended single ranges")
    func parsesRanges() {
        #expect(ABByteRange.parse("bytes=0-499") == ABByteRange(lowerBound: 0, upperBound: 499))
        #expect(ABByteRange.parse(" Bytes = 500- ") == ABByteRange(lowerBound: 500, upperBound: nil))
    }

    @Test("Rejects suffix, reversed, negative, and multipart ranges")
    func rejectsUnsupportedRanges() {
        #expect(ABByteRange.parse("bytes=-500") == nil)
        #expect(ABByteRange.parse("bytes=500-400") == nil)
        #expect(ABByteRange.parse("bytes=-1-20") == nil)
        #expect(ABByteRange.parse("bytes=0-10,20-30") == nil)
        #expect(ABByteRange.parse("items=0-10") == nil)
    }

    @Test("Merges overlapping and adjacent ranges")
    func mergesRanges() {
        let ranges = [
            ABByteRange(lowerBound: 20, upperBound: 29),
            ABByteRange(lowerBound: 0, upperBound: 9),
            ABByteRange(lowerBound: 8, upperBound: 19),
            ABByteRange(lowerBound: 40, upperBound: nil),
            ABByteRange(lowerBound: 35, upperBound: 39)
        ]

        #expect(ABByteRange.merge(ranges) == [
            ABByteRange(lowerBound: 0, upperBound: 29),
            ABByteRange(lowerBound: 35, upperBound: nil)
        ])
    }
}

@Suite("ABCacheIndex LRU and persistence")
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
