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

@Suite("ABCacheStore scenarios")
struct ABCacheStoreTests {
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
