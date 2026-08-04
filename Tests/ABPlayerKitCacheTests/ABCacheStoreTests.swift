import ABPlayerKit
import Foundation
import Testing
@testable import ABPlayerKitCache

/// WP7 error-injection struct — a generic, `Equatable` marker error distinct
/// from any `StoreError` case, so injected-error tests can assert the
/// *store's own* error mapping (e.g. `.requestFailed`) rather than
/// accidentally passing because the injected error happened to match.
private struct ABFakeFetchError: Error, Equatable {
    let id: String
}

private final class ABFakeHTTPFetcher: ABHTTPFetching, @unchecked Sendable {
    struct DataReply: Sendable {
        let data: Data
        let response: ABHTTPResponse
    }

    private let lock = NSLock()
    private var dataReplies: [DataReply]
    /// Parallel to `dataReplies`: if non-nil for a given `data(for:)` call,
    /// thrown instead of returning a reply (WP7 error-injection).
    private var dataErrors: [Error?]
    private var streamReplies: [[ABHTTPFetchEvent]]
    /// Parallel to `streamReplies`: if non-nil for a given `stream(for:)`
    /// call, the returned stream yields that call's queued events (if any)
    /// and then finishes by throwing this error instead of finishing
    /// normally (WP7 error-injection, including "mid-stream throw" after
    /// some data already yielded).
    private var streamErrors: [Error?]
    private var recordedRequests: [URLRequest] = []

    init(
        dataReplies: [DataReply],
        dataErrors: [Error?] = [],
        streamReplies: [[ABHTTPFetchEvent]],
        streamErrors: [Error?] = []
    ) {
        self.dataReplies = dataReplies
        self.dataErrors = dataErrors
        self.streamReplies = streamReplies
        self.streamErrors = streamErrors
    }

    var requests: [URLRequest] {
        lock.lock()
        let requests = recordedRequests
        lock.unlock()
        return requests
    }

    func data(for request: URLRequest) async throws -> (Data, ABHTTPResponse) {
        let (error, reply) = takeDataReply(for: request)
        if let error { throw error }
        guard let reply else { throw URLError(.resourceUnavailable) }
        return (reply.data, reply.response)
    }

    private func takeDataReply(for request: URLRequest) -> (Error?, DataReply?) {
        lock.lock()
        recordedRequests.append(request)
        let error = dataErrors.isEmpty ? nil : dataErrors.removeFirst()
        let reply = dataReplies.isEmpty ? nil : dataReplies.removeFirst()
        lock.unlock()
        return (error, reply)
    }

    func stream(for request: URLRequest) -> AsyncThrowingStream<ABHTTPFetchEvent, any Error> {
        let (events, error) = takeStreamReply(for: request)
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    private func takeStreamReply(for request: URLRequest) -> ([ABHTTPFetchEvent], Error?) {
        lock.lock()
        recordedRequests.append(request)
        let events = streamReplies.isEmpty ? [] : streamReplies.removeFirst()
        let error = streamErrors.isEmpty ? nil : streamErrors.removeFirst()
        lock.unlock()
        return (events, error)
    }
}

private final class ABControlledHTTPFetcher: ABHTTPFetching, @unchecked Sendable {
    typealias Continuation = AsyncThrowingStream<ABHTTPFetchEvent, any Error>.Continuation

    private let lock = NSLock()
    private var dataReplies: [ABFakeHTTPFetcher.DataReply]
    private var initialStreamEvents: [[ABHTTPFetchEvent]]
    private var continuations: [Continuation] = []

    init(
        dataReplies: [ABFakeHTTPFetcher.DataReply],
        initialStreamEvents: [[ABHTTPFetchEvent]]
    ) {
        self.dataReplies = dataReplies
        self.initialStreamEvents = initialStreamEvents
    }

    func data(for request: URLRequest) async throws -> (Data, ABHTTPResponse) {
        guard let reply = takeDataReply() else { throw URLError(.resourceUnavailable) }
        return (reply.data, reply.response)
    }

    func stream(for request: URLRequest) -> AsyncThrowingStream<ABHTTPFetchEvent, any Error> {
        AsyncThrowingStream { continuation in
            let events = register(continuation)
            for event in events {
                continuation.yield(event)
            }
        }
    }

    func finishStreams(with tails: [Data] = []) {
        lock.lock()
        let continuations = self.continuations
        self.continuations.removeAll()
        lock.unlock()
        for (index, continuation) in continuations.enumerated() {
            if tails.indices.contains(index), !tails[index].isEmpty {
                continuation.yield(.data(tails[index]))
            }
            continuation.finish()
        }
    }

    private func takeDataReply() -> ABFakeHTTPFetcher.DataReply? {
        lock.lock()
        let reply = dataReplies.isEmpty ? nil : dataReplies.removeFirst()
        lock.unlock()
        return reply
    }

    private func register(_ continuation: Continuation) -> [ABHTTPFetchEvent] {
        lock.lock()
        continuations.append(continuation)
        let events = initialStreamEvents.isEmpty ? [] : initialStreamEvents.removeFirst()
        lock.unlock()
        return events
    }
}

@Suite("ABCacheStore scenarios", .timeLimit(.minutes(1)))
struct ABCacheStoreTests {
    @Test("Unknown content length bypasses caching and serves the raw range")
    func unknownLengthPassesThrough() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("chunked.mp4")
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [
                .init(
                    data: Data(),
                    response: .init(
                        statusCode: 200,
                        expectedContentLength: nil,
                        mimeType: "video/mp4"
                    )
                ),
                .init(
                    data: Data("data".utf8),
                    response: .init(
                        statusCode: 206,
                        expectedContentLength: 4,
                        mimeType: "video/mp4"
                    )
                )
            ],
            streamReplies: []
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory),
            httpFetcher: fetcher
        )

        let metadata = try await store.metadata(for: source)
        let resource = try await store.load(
            source,
            range: ABByteRange(lowerBound: 0, upperBound: 3)
        )

        #expect(metadata.contentLength == nil)
        #expect(resource.data == Data("data".utf8))
        #expect(await store.totalSize() == 0)
        #expect(fetcher.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=0-3")
    }

    @Test("Load returns an available prefix while the fill tail is withheld")
    func returnsPrefixBeforeFillCompletes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("progressive.mp4")
        let fetcher = ABControlledHTTPFetcher(
            dataReplies: [metadataReply(length: 6)],
            initialStreamEvents: [[
                .response(.init(
                    statusCode: 200,
                    expectedContentLength: 6,
                    mimeType: "video/mp4"
                )),
                .data(Data("abc".utf8))
            ]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory),
            httpFetcher: fetcher
        )

        let prefix = try await store.load(
            source,
            range: ABByteRange(lowerBound: 0, upperBound: 5)
        )

        #expect(prefix.data == Data("abc".utf8))
        #expect(!prefix.isEndOfResource)
        fetcher.finishStreams(with: [Data("def".utf8)])
        let tail = try await store.load(
            source,
            range: ABByteRange(lowerBound: 3, upperBound: 5)
        )
        #expect(tail.data == Data("def".utf8))
    }

    @Test("Metadata lookup never starts a progressive fill")
    func metadataDoesNotStartFill() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("metadata-only.mp4")
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [metadataReply(length: 10)],
            streamReplies: [[.data(Data("unexpected".utf8))]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory),
            httpFetcher: fetcher
        )

        let metadata = try await store.metadata(for: source)

        #expect(metadata.contentLength == 10)
        #expect(fetcher.requests.count == 1)
        #expect(fetcher.requests.first?.httpMethod == "HEAD")
        #expect(await store.totalSize() == 0)
    }

    @Test("Metadata cache retains only its bounded LRU capacity")
    func boundsMetadataCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: (0..<40).map { _ in metadataReply(length: 10) },
            streamReplies: []
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory),
            httpFetcher: fetcher
        )

        for index in 0..<40 {
            _ = try await store.metadata(for: mediaSource("metadata-\(index).mp4"))
        }

        #expect(await store.metadataCacheCount() == 32)
    }

    @Test("In-flight fills record an observable eviction shortfall")
    func recordsEvictionShortfall() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSource = mediaSource("active-a.mp4")
        let secondSource = mediaSource("active-b.mp4")
        let response = ABHTTPResponse(
            statusCode: 200,
            expectedContentLength: 8,
            mimeType: "video/mp4"
        )
        let fetcher = ABControlledHTTPFetcher(
            dataReplies: [metadataReply(length: 8), metadataReply(length: 8)],
            initialStreamEvents: [
                [.response(response), .data(Data("aaaaaaaa".utf8))],
                [.response(response), .data(Data("bbbbbbbb".utf8))]
            ]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory, maximumDiskSize: 10, maximumEntrySize: 10),
            httpFetcher: fetcher
        )

        _ = try await store.load(
            firstSource,
            range: ABByteRange(lowerBound: 0, upperBound: 7)
        )
        _ = try await store.load(
            secondSource,
            range: ABByteRange(lowerBound: 0, upperBound: 7)
        )

        #expect(await store.totalSize() == 16)
        #expect(await store.evictionShortfallCount() > 0)
        fetcher.finishStreams()
    }

    @Test("A partial entry resumes with a 206 response")
    func resumesPartialEntry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("resume.mp4")
        try seed(
            source: source,
            data: Data("abc".utf8),
            contentLength: 6,
            lastAccessedAt: Date(timeIntervalSince1970: 1),
            directory: directory
        )
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [metadataReply(length: 6)],
            streamReplies: [[
                .response(.init(
                    statusCode: 206,
                    expectedContentLength: 3,
                    mimeType: "video/mp4",
                    headers: ["Content-Range": "bytes 3-5/6"]
                )),
                .data(Data("def".utf8))
            ]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory, maximumDiskSize: 100, maximumEntrySize: 100),
            httpFetcher: fetcher
        )

        let data = try await collect(store: store, source: source, length: 6)

        #expect(data == Data("abcdef".utf8))
        #expect(fetcher.requests.contains {
            $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Range") == "bytes=3-"
        })
    }

    @Test("A server ignoring Range truncates the partial file before refilling")
    func truncatesWhenServerIgnoresRange() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("ignored-range.mp4")
        try seed(
            source: source,
            data: Data("old".utf8),
            contentLength: 7,
            lastAccessedAt: Date(timeIntervalSince1970: 1),
            directory: directory
        )
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [metadataReply(length: 7)],
            streamReplies: [[
                .response(.init(
                    statusCode: 200,
                    expectedContentLength: 7,
                    mimeType: "video/mp4"
                )),
                .data(Data("newdata".utf8))
            ]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory, maximumDiskSize: 100, maximumEntrySize: 100),
            httpFetcher: fetcher
        )

        let suffix = try await store.load(
            source,
            range: ABByteRange(lowerBound: 3, upperBound: 6)
        )
        let complete = try await store.load(
            source,
            range: ABByteRange(lowerBound: 0, upperBound: 6)
        )

        #expect(suffix.data == Data("data".utf8))
        #expect(complete.data == Data("newdata".utf8))
        #expect(fetcher.requests.contains {
            $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Range") == "bytes=3-"
        })
    }

    @Test("An oversized entry bypasses disk storage")
    func bypassesOversizedEntry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("oversized.mp4")
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [
                metadataReply(length: 8),
                .init(
                    data: Data("cdef".utf8),
                    response: .init(
                        statusCode: 206,
                        expectedContentLength: 4,
                        mimeType: "video/mp4",
                        headers: ["Content-Range": "bytes 2-5/8"]
                    )
                )
            ],
            streamReplies: []
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory, maximumDiskSize: 100, maximumEntrySize: 4),
            httpFetcher: fetcher
        )

        let resource = try await store.load(
            source,
            range: ABByteRange(lowerBound: 2, upperBound: 5)
        )

        #expect(resource.data == Data("cdef".utf8))
        #expect(await store.totalSize() == 0)
        #expect(fetcher.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=2-5")
    }

    @Test("Store eviction removes the oldest unreferenced entry first")
    func evictsOldestEntry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldSource = mediaSource("old.mp4")
        let middleSource = mediaSource("middle.mp4")
        let newSource = mediaSource("new.mp4")
        try seed(
            entries: [
                (oldSource, Data("old!".utf8), Date(timeIntervalSince1970: 1)),
                (middleSource, Data("mid!".utf8), Date(timeIntervalSince1970: 2))
            ],
            directory: directory
        )
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [metadataReply(length: 4)],
            streamReplies: [[
                .response(.init(
                    statusCode: 200,
                    expectedContentLength: 4,
                    mimeType: "video/mp4"
                )),
                .data(Data("new!".utf8))
            ]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory, maximumDiskSize: 10, maximumEntrySize: 10),
            httpFetcher: fetcher
        )

        _ = try await store.load(
            newSource,
            range: ABByteRange(lowerBound: 0, upperBound: 3)
        )

        #expect(await store.totalSize() == 8)
        #expect(!cacheFileExists(for: oldSource, directory: directory))
        #expect(cacheFileExists(for: middleSource, directory: directory))
        #expect(cacheFileExists(for: newSource, directory: directory))
    }

    // MARK: - WP7: concurrency dedup

    @Test("10 concurrent loads for the same key dedupe to a single HEAD and a single fill GET, and agree on the result")
    func concurrentLoadsForSameKeyDedupeToOneFill() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("dedup.mp4")
        let response = ABHTTPResponse(statusCode: 200, expectedContentLength: 8, mimeType: "video/mp4")
        // Exactly one metadata reply queued (round3 Phase3 group C, M5):
        // `resolvedMetadata` now coalesces concurrent cold-key HEAD requests
        // onto a single in-flight `Task`, so a second reply being available
        // would mask a regression back to "every racing caller issues its
        // own HEAD" instead of catching it.
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [metadataReply(length: 8)],
            streamReplies: [[.response(response), .data(Data("abcdefgh".utf8))]]
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)

        let results = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let resource = try await store.load(
                        source,
                        range: ABByteRange(lowerBound: 0, upperBound: 7)
                    )
                    return resource.data
                }
            }
            var collected: [Data] = []
            for try await data in group {
                collected.append(data)
            }
            return collected
        }

        #expect(results.count == 10)
        #expect(results.allSatisfy { $0 == Data("abcdefgh".utf8) })
        #expect(fetcher.requests.filter { $0.httpMethod == "HEAD" }.count == 1)
        // `fillRequest`/`stream(for:)` requests have no explicit HTTP
        // method set, so `URLRequest.httpMethod` defaults to "GET" —
        // exactly one such request must have been issued for the fill.
        #expect(fetcher.requests.filter { $0.httpMethod == "GET" }.count == 1)
    }

    // MARK: - round3 Phase4 WP11: passthrough fallback for a distant offset

    @Test("A request far ahead of the fill prefix returns via passthrough without waiting for the fill")
    func distantOffsetRequestUsesPassthroughWithoutWaitingForFill() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("distant.mp4")
        let contentLength: Int64 = 5 * 1_024 * 1_024
        let payload = Data("distant-bytes".utf8)
        let passthroughResponse = ABHTTPResponse(
            statusCode: 206,
            expectedContentLength: Int64(payload.count),
            mimeType: "video/mp4"
        )
        // The fill's stream never yields anything (`initialStreamEvents:
        // [[]]`, and `finishStreams` is never called) — its prefix stays
        // stuck at 0 for the entire test, so a distant-offset `load` can
        // only return promptly if it genuinely bypasses waiting on it.
        let fetcher = ABControlledHTTPFetcher(
            dataReplies: [
                metadataReply(length: contentLength),
                ABFakeHTTPFetcher.DataReply(data: payload, response: passthroughResponse)
            ],
            initialStreamEvents: [[]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory, passthroughGapThreshold: 2 * 1_024 * 1_024),
            httpFetcher: fetcher
        )

        let distantOffset: Int64 = 3 * 1_024 * 1_024
        let resource = try await store.load(
            source,
            range: ABByteRange(lowerBound: distantOffset, upperBound: distantOffset + Int64(payload.count) - 1)
        )

        #expect(resource.data == payload)
        // Nothing was ever written to the cache file — proves this really
        // was served by a direct network passthrough, not by the fill
        // somehow having made progress.
        #expect(await store.totalSize() == 0)
    }

    @Test("A request within the gap threshold still waits for the fill instead of using passthrough")
    func nearOffsetRequestStillWaitsForFill() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("near.mp4")
        let fetcher = ABControlledHTTPFetcher(
            dataReplies: [metadataReply(length: 6)],
            initialStreamEvents: [[
                .response(.init(statusCode: 200, expectedContentLength: 6, mimeType: "video/mp4")),
                .data(Data("abc".utf8))
            ]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory, passthroughGapThreshold: 2 * 1_024 * 1_024),
            httpFetcher: fetcher
        )

        // Offset 1 is well within the 2MB gap threshold of prefix 0, so
        // this must resolve through the normal cached-prefix path once the
        // fill's already-queued "abc" lands — not through passthrough
        // (which would need a second queued `dataReplies` entry this test
        // never supplies; an accidental passthrough here would throw
        // instead of hanging, making this a real regression guard).
        let resource = try await store.load(source, range: ABByteRange(lowerBound: 1, upperBound: 2))

        #expect(resource.data == Data("bc".utf8))
    }

    // MARK: - WP7: error paths

    @Test("A non-2xx fill response throws StoreError.invalidResponse")
    func nonSuccessFillResponseThrowsInvalidResponse() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("invalid-response.mp4")
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [metadataReply(length: 8)],
            streamReplies: [[
                .response(.init(statusCode: 404, expectedContentLength: 8, mimeType: "video/mp4"))
            ]]
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)

        await #expect(throws: ABCacheStore.StoreError.invalidResponse) {
            _ = try await store.load(source, range: ABByteRange(lowerBound: 0, upperBound: 7))
        }
    }

    @Test("An entry that grows past maximumEntrySize mid-fill falls back to an uncached passthrough instead of throwing")
    func entryTooLargeMidFillFallsBackToPassthrough() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("entry-too-large.mp4")
        // Metadata declares a length (8) that fits the configured limit
        // (8), so `load(_:range:)`'s early bypass check does not trigger —
        // this exercises the *internal* `prepareFill` "entry.contentLength
        // > cacheableEntryLimit" throw instead, by having the fill response
        // itself report a much larger length (1000) than metadata did.
        let fillResponse = ABHTTPResponse(statusCode: 200, expectedContentLength: 1000, mimeType: "video/mp4")
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [
                metadataReply(length: 8),
                .init(
                    data: Data("abcdef".utf8),
                    response: .init(
                        statusCode: 206,
                        expectedContentLength: 6,
                        mimeType: "video/mp4",
                        headers: ["Content-Range": "bytes 0-5/8"]
                    )
                )
            ],
            streamReplies: [[.response(fillResponse)]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory, maximumDiskSize: 100, maximumEntrySize: 8),
            httpFetcher: fetcher
        )

        // `StoreError.entryTooLarge` is intentionally recovered, not
        // propagated: `load(_:range:)`'s wait loop special-cases it to
        // remove the (now-invalid) cached entry and retry via
        // `passthrough`, so the caller observes a successful, uncached
        // read rather than a thrown error — verified below by asserting
        // `totalSize() == 0` alongside the correct data.
        let resource = try await store.load(source, range: ABByteRange(lowerBound: 0, upperBound: 5))

        #expect(resource.data == Data("abcdef".utf8))
        #expect(await store.totalSize() == 0)
    }

    @Test("A fill stream that throws before any event surfaces as StoreError.requestFailed")
    func fillStreamThrowingImmediatelySurfacesAsRequestFailed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("request-failed.mp4")
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [metadataReply(length: 8)],
            streamReplies: [[]],
            streamErrors: [ABFakeFetchError(id: "immediate")]
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)

        await #expect(throws: ABCacheStore.StoreError.requestFailed) {
            _ = try await store.load(source, range: ABByteRange(lowerBound: 0, upperBound: 7))
        }
    }

    @Test("A fill stream that throws mid-stream, after partial data, surfaces as StoreError.requestFailed for a range beyond what landed")
    func fillStreamThrowingMidStreamSurfacesAsRequestFailed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("mid-stream-failure.mp4")
        let response = ABHTTPResponse(statusCode: 200, expectedContentLength: 8, mimeType: "video/mp4")
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: [metadataReply(length: 8)],
            streamReplies: [[.response(response), .data(Data("ab".utf8))]],
            streamErrors: [ABFakeFetchError(id: "mid-stream")]
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)

        // Requesting a range beyond the 2 bytes that landed before the
        // stream failed forces the wait loop past its "prefix already
        // available" fast path and into the fill-error branch, instead of
        // silently succeeding with a short/partial read.
        await #expect(throws: ABCacheStore.StoreError.requestFailed) {
            _ = try await store.load(source, range: ABByteRange(lowerBound: 5, upperBound: 7))
        }
    }

    // MARK: - WP7: index recovery

    @Test("A corrupted index file recovers as an empty index instead of throwing")
    func corruptedIndexRecoversAsEmpty() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not valid json at all".utf8).write(
            to: directory.appendingPathComponent("progressive-index.json")
        )
        let fetcher = ABFakeHTTPFetcher(dataReplies: [], streamReplies: [])

        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)

        #expect(await store.totalSize() == 0)
    }

    @Test("An index entry whose backing file is missing is dropped on load instead of crashing")
    func indexEntryWithMissingFileIsDropped() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("missing-file.mp4")
        let key = ABCacheKey.derive(from: source)
        let entry = ABCacheIndex.Entry(
            key: key,
            size: 4,
            contentLength: 4,
            contentType: "public.mpeg-4",
            isComplete: true,
            lastAccessedAt: Date()
        )
        // Write only the index — deliberately never create
        // `Progressive/<key>.data` on disk, simulating an index that
        // outlived its backing file (e.g. an external process/crash
        // deleted the data directory contents but not the index).
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = ABCacheIndex(entries: [key: entry])
        try JSONEncoder().encode(index).write(to: directory.appendingPathComponent("progressive-index.json"))
        let fetcher = ABFakeHTTPFetcher(dataReplies: [], streamReplies: [])

        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)

        #expect(await store.totalSize() == 0)
        #expect(!cacheFileExists(for: source, directory: directory))
    }

    // MARK: - WP7: metadata LRU correctness

    @Test("Re-touching the oldest metadata cache key protects it from eviction on the next insert")
    func retouchingOldestMetadataKeyProtectsItFromEviction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = ABFakeHTTPFetcher(
            dataReplies: (0..<33).map { _ in metadataReply(length: 10) },
            streamReplies: []
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)

        var sources: [ABMediaSource] = []
        for index in 0..<32 {
            let source = mediaSource("lru-\(index).mp4")
            sources.append(source)
            _ = try await store.metadata(for: source)
        }
        #expect(await store.metadataCacheCount() == 32)

        // Re-touch the oldest (first-inserted) key — a cache *hit*, so it
        // consumes no additional `dataReplies` entry — moving it to the
        // most-recently-used end of the LRU order.
        _ = try await store.metadata(for: sources[0])

        // One more distinct key forces an eviction. Without the re-touch,
        // `sources[0]` would be the true LRU victim; with it,
        // `sources[1]` becomes the victim instead.
        _ = try await store.metadata(for: mediaSource("lru-new.mp4"))

        let order = await store.metadataCacheOrderSnapshot()
        let retouchedKey = ABCacheKey.derive(from: sources[0])
        let evictedKey = ABCacheKey.derive(from: sources[1])
        #expect(order.contains(retouchedKey))
        #expect(!order.contains(evictedKey))
        #expect(await store.metadataCacheCount() == 32)
    }

    /// WP4 regression: `waitForProgress` used to be a bare
    /// `withCheckedContinuation` that ignored cancellation. A `load(_:range:)`
    /// call waiting on a fill that never makes progress would then hang
    /// forever once cancelled, leaving its key in `readerRegistry` and
    /// blocking that key from LRU eviction.
    @Test("Cancelling a load waiting on stalled fill progress throws promptly and frees the reader")
    func cancellingStalledLoadThrowsPromptlyAndFreesReader() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("stuck.mp4")
        let response = ABHTTPResponse(statusCode: 200, expectedContentLength: 8, mimeType: "video/mp4")
        let fetcher = ABControlledHTTPFetcher(
            dataReplies: [metadataReply(length: 8)],
            // Only `.response` — no `.data` — so the fill starts but never
            // makes progress.
            initialStreamEvents: [[.response(response)]]
        )
        let store = try ABCacheStore(
            configuration: .init(directory: directory),
            httpFetcher: fetcher
        )

        let loadTask = Task {
            try await store.load(source, range: ABByteRange(lowerBound: 0, upperBound: 7))
        }

        // Wait for `load` to actually retain a reader (i.e. it has reached
        // the stalled-fill wait loop) before cancelling.
        try await waitUntil { !store.activeReaderKeys().isEmpty }
        #expect(!store.activeReaderKeys().isEmpty)

        loadTask.cancel()

        // Race the cancelled load against a generous timeout so a
        // regression (the pre-fix hang) fails the test instead of hanging
        // the suite forever.
        enum Outcome: Equatable { case cancelled, completedUnexpectedly, timedOut }
        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                do {
                    _ = try await loadTask.value
                    return .completedUnexpectedly
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return .completedUnexpectedly
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }

        #expect(outcome == .cancelled)

        // The cancelled waiter must not linger in `readerRegistry` — that
        // would keep this key excluded from LRU eviction forever.
        try await waitUntil { store.activeReaderKeys().isEmpty }
        #expect(store.activeReaderKeys().isEmpty)

        fetcher.finishStreams()
    }

    private func collect(
        store: ABCacheStore,
        source: ABMediaSource,
        length: Int64
    ) async throws -> Data {
        var result = Data()
        var offset: Int64 = 0
        while offset < length {
            let resource = try await store.load(
                source,
                range: ABByteRange(lowerBound: offset, upperBound: length - 1)
            )
            guard !resource.data.isEmpty else { throw ABCacheStore.StoreError.shortRead }
            result.append(resource.data)
            offset += Int64(resource.data.count)
        }
        return result
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func mediaSource(_ name: String) -> ABMediaSource {
        ABMediaSource(url: URL(string: "https://example.com/\(name)")!)
    }

    private func metadataReply(length: Int64) -> ABFakeHTTPFetcher.DataReply {
        .init(
            data: Data(),
            response: .init(
                statusCode: 200,
                expectedContentLength: length,
                mimeType: "video/mp4"
            )
        )
    }

    private func seed(
        source: ABMediaSource,
        data: Data,
        contentLength: Int64,
        lastAccessedAt: Date,
        directory: URL
    ) throws {
        try seed(
            entries: [(source, data, lastAccessedAt)],
            contentLength: contentLength,
            directory: directory
        )
    }

    private func seed(
        entries: [(ABMediaSource, Data, Date)],
        contentLength: Int64? = nil,
        directory: URL
    ) throws {
        let dataDirectory = directory.appendingPathComponent("Progressive", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        var indexEntries: [String: ABCacheIndex.Entry] = [:]
        for (source, data, date) in entries {
            let key = ABCacheKey.derive(from: source)
            let length = contentLength ?? Int64(data.count)
            let entry = ABCacheIndex.Entry(
                key: key,
                size: Int64(data.count),
                contentLength: length,
                contentType: "public.mpeg-4",
                isComplete: Int64(data.count) >= length,
                lastAccessedAt: date
            )
            try data.write(to: dataDirectory.appendingPathComponent(entry.fileName))
            indexEntries[key] = entry
        }
        let index = ABCacheIndex(entries: indexEntries)
        try JSONEncoder().encode(index).write(
            to: directory.appendingPathComponent("progressive-index.json")
        )
    }

    private func cacheFileExists(for source: ABMediaSource, directory: URL) -> Bool {
        let key = ABCacheKey.derive(from: source)
        let url = directory
            .appendingPathComponent("Progressive", isDirectory: true)
            .appendingPathComponent("\(key).data")
        return FileManager.default.fileExists(atPath: url.path)
    }
}
