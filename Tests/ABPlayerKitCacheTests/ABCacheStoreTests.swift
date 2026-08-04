import ABPlayerKit
import Foundation
import Testing
@testable import ABPlayerKitCache

private final class ABFakeHTTPFetcher: ABHTTPFetching, @unchecked Sendable {
    struct DataReply: Sendable {
        let data: Data
        let response: ABHTTPResponse
    }

    private let lock = NSLock()
    private var dataReplies: [DataReply]
    private var streamReplies: [[ABHTTPFetchEvent]]
    private var recordedRequests: [URLRequest] = []

    init(dataReplies: [DataReply], streamReplies: [[ABHTTPFetchEvent]]) {
        self.dataReplies = dataReplies
        self.streamReplies = streamReplies
    }

    var requests: [URLRequest] {
        lock.lock()
        let requests = recordedRequests
        lock.unlock()
        return requests
    }

    func data(for request: URLRequest) async throws -> (Data, ABHTTPResponse) {
        guard let reply = takeDataReply(for: request) else {
            throw URLError(.resourceUnavailable)
        }
        return (reply.data, reply.response)
    }

    private func takeDataReply(for request: URLRequest) -> DataReply? {
        lock.lock()
        recordedRequests.append(request)
        let reply = dataReplies.isEmpty ? nil : dataReplies.removeFirst()
        lock.unlock()
        return reply
    }

    func stream(for request: URLRequest) -> AsyncThrowingStream<ABHTTPFetchEvent, any Error> {
        lock.lock()
        recordedRequests.append(request)
        let events = streamReplies.isEmpty ? [] : streamReplies.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
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

@Suite("ABCacheStore scenarios")
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
        for _ in 0..<200 where store.activeReaderKeys().isEmpty {
            await Task.yield()
        }
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
        for _ in 0..<200 where !store.activeReaderKeys().isEmpty {
            await Task.yield()
        }
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
