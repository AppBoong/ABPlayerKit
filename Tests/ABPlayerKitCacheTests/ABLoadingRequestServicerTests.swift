import ABPlayerKit
import Foundation
import Testing
@testable import ABPlayerKitCache

private final class ABFakeLoadingContentInformation: ABLoadingContentInformation {
    var contentType: String?
    var contentLength: Int64 = 0
    var isByteRangeAccessSupported = false
}

private final class ABFakeLoadingDataRequest: ABLoadingDataRequesting {
    let currentOffset: Int64
    let requestedLength: Int
    let requestsAllDataToEndOfResource: Bool
    private(set) var respondedChunks: [Data] = []

    init(currentOffset: Int64, requestedLength: Int, requestsAllDataToEndOfResource: Bool = false) {
        self.currentOffset = currentOffset
        self.requestedLength = requestedLength
        self.requestsAllDataToEndOfResource = requestsAllDataToEndOfResource
    }

    func respond(with data: Data) {
        respondedChunks.append(data)
    }
}

private final class ABFakeLoadingRequest: ABLoadingRequesting, @unchecked Sendable {
    var isCancelled = false
    var contentInformation: (any ABLoadingContentInformation)?
    var dataRequest: (any ABLoadingDataRequesting)?
    private(set) var finishLoadingCallCount = 0
    private(set) var finishLoadingWithErrorCallCount = 0
    private(set) var lastError: (any Error)?

    func finishLoading() {
        finishLoadingCallCount += 1
    }

    func finishLoading(with error: (any Error)?) {
        finishLoadingWithErrorCallCount += 1
        lastError = error
    }
}

/// Minimal `ABHTTPFetching` fake for driving `ABCacheStore` under
/// `ABLoadingRequestServicer`. `dataReplies` back `data(for:)`
/// (HEAD) calls in order; `streamReplies` back `stream(for:)` calls in
/// order; once `streamReplies` is exhausted, `stream(for:)` falls back to
/// converting the next `dataReplies` entry into a one-shot stream (mirrors
/// the shim in `ABCacheStoreTests.swift` — `passthrough`/`rawPassthrough`
/// route through `stream(for:)` for memory bounding). `stallsFill: true` makes
/// the *first* `stream(for:)` call (the fill) hang after yielding its
/// queued events instead of finishing, until `finishPending()` is called —
/// for exercising a fill that's still in flight when `removeAll()` runs.
private final class ABServicerFakeFetcher: ABHTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var dataReplies: [(Data, ABHTTPResponse)]
    private var streamReplies: [[ABHTTPFetchEvent]]
    private var pendingContinuations: [AsyncThrowingStream<ABHTTPFetchEvent, any Error>.Continuation] = []
    private let stallsFill: Bool

    init(
        dataReplies: [(Data, ABHTTPResponse)] = [],
        streamReplies: [[ABHTTPFetchEvent]] = [],
        stallsFill: Bool = false
    ) {
        self.dataReplies = dataReplies
        self.streamReplies = streamReplies
        self.stallsFill = stallsFill
    }

    func data(for request: URLRequest) async throws -> (Data, ABHTTPResponse) {
        guard let reply = takeDataReply() else { throw URLError(.resourceUnavailable) }
        return reply
    }

    private func takeDataReply() -> (Data, ABHTTPResponse)? {
        lock.lock()
        defer { lock.unlock() }
        guard !dataReplies.isEmpty else { return nil }
        return dataReplies.removeFirst()
    }

    func stream(for request: URLRequest) -> AsyncThrowingStream<ABHTTPFetchEvent, any Error> {
        lock.lock()
        if stallsFill, pendingContinuations.isEmpty, !streamReplies.isEmpty {
            let events = streamReplies.removeFirst()
            lock.unlock()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                self.lock.lock()
                self.pendingContinuations.append(continuation)
                self.lock.unlock()
            }
        }
        if !streamReplies.isEmpty {
            let events = streamReplies.removeFirst()
            lock.unlock()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
        guard !dataReplies.isEmpty else {
            lock.unlock()
            return AsyncThrowingStream { $0.finish(throwing: URLError(.resourceUnavailable)) }
        }
        let (data, response) = dataReplies.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            continuation.yield(.response(response))
            if !data.isEmpty { continuation.yield(.data(data)) }
            continuation.finish()
        }
    }

    func finishPending() {
        lock.lock()
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        lock.unlock()
        continuations.forEach { $0.finish() }
    }
}

@Suite("ABLoadingRequestServicer", .timeLimit(.minutes(3)))
struct ABLoadingRequestServicerTests {
    @Test("A resolved contentInformation request receives type, length, and byte-range support")
    func populatesContentInformation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("content-information.mp4")
        try seedComplete(source: source, data: Data("0123456789".utf8), directory: directory)
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: ABServicerFakeFetcher())
        let request = ABFakeLoadingRequest()
        let contentInformation = ABFakeLoadingContentInformation()
        request.contentInformation = contentInformation
        request.dataRequest = ABFakeLoadingDataRequest(currentOffset: 0, requestedLength: 10)

        await ABLoadingRequestServicer.service(request, source: source, store: store)

        #expect(contentInformation.contentType == "public.mpeg-4")
        #expect(contentInformation.contentLength == 10)
        #expect(contentInformation.isByteRangeAccessSupported == true)
    }

    @Test("An unknown content length disables byte-range support and finishes after one response")
    func unknownContentLengthDisablesByteRangeSupport() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("unknown-length.mp4")
        let fetcher = ABServicerFakeFetcher(
            dataReplies: [(Data(), ABHTTPResponse(statusCode: 200, expectedContentLength: nil, mimeType: "video/mp4"))],
            streamReplies: [[
                .response(.init(statusCode: 206, expectedContentLength: 4, mimeType: "video/mp4")),
                .data(Data("data".utf8))
            ]]
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)
        let request = ABFakeLoadingRequest()
        let contentInformation = ABFakeLoadingContentInformation()
        request.contentInformation = contentInformation
        let dataRequest = ABFakeLoadingDataRequest(currentOffset: 0, requestedLength: 4)
        request.dataRequest = dataRequest

        await ABLoadingRequestServicer.service(request, source: source, store: store)

        #expect(contentInformation.isByteRangeAccessSupported == false)
        #expect(dataRequest.respondedChunks == [Data("data".utf8)])
        #expect(request.finishLoadingCallCount == 1)
        #expect(request.finishLoadingWithErrorCallCount == 0)
    }

    @Test("A range spanning more than one passthrough chunk is served across multiple respond(with:) calls, finishing once")
    func chunkedRangeRespondsMultipleTimesThenFinishesOnce() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("chunked.mp4")
        let megabyte: Int64 = 1_024 * 1_024
        let contentLength = megabyte + megabyte / 2
        let chunk1 = Data(repeating: 0xA1, count: Int(megabyte))
        let chunk2 = Data(repeating: 0xB2, count: Int(megabyte / 2))
        let fetcher = ABServicerFakeFetcher(
            dataReplies: [(Data(), ABHTTPResponse(statusCode: 200, expectedContentLength: contentLength, mimeType: "video/mp4"))],
            streamReplies: [
                [.response(.init(statusCode: 206, expectedContentLength: Int64(chunk1.count), mimeType: "video/mp4")), .data(chunk1)],
                [.response(.init(statusCode: 206, expectedContentLength: Int64(chunk2.count), mimeType: "video/mp4")), .data(chunk2)]
            ]
        )
        // A tiny `maximumEntrySize` forces every read through `passthrough`
        // (never cached), and `passthrough` caps each round trip to
        // `passthroughChunkSize` (1MB) — the same mechanism the store-level
        // chunking test exercises, driven here through the servicer's own
        // `while currentOffset <= requiredEndOffset` loop instead.
        let store = try ABCacheStore(
            configuration: .init(directory: directory, maximumDiskSize: 100, maximumEntrySize: 4),
            httpFetcher: fetcher
        )
        let request = ABFakeLoadingRequest()
        let dataRequest = ABFakeLoadingDataRequest(currentOffset: 0, requestedLength: Int(contentLength))
        request.dataRequest = dataRequest

        await ABLoadingRequestServicer.service(request, source: source, store: store)

        #expect(dataRequest.respondedChunks == [chunk1, chunk2])
        #expect(request.finishLoadingCallCount == 1)
    }

    @Test("requestsAllDataToEndOfResource serves through contentLength - 1")
    func requestsAllDataToEndOfResourceServesToEnd() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("to-end.mp4")
        try seedComplete(source: source, data: Data("ABCDE".utf8), directory: directory)
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: ABServicerFakeFetcher())
        let request = ABFakeLoadingRequest()
        let dataRequest = ABFakeLoadingDataRequest(currentOffset: 0, requestedLength: 0, requestsAllDataToEndOfResource: true)
        request.dataRequest = dataRequest

        await ABLoadingRequestServicer.service(request, source: source, store: store)

        #expect(dataRequest.respondedChunks == [Data("ABCDE".utf8)])
        #expect(request.finishLoadingCallCount == 1)
    }

    @Test("A store error finishes the request with that error, never calling the success finishLoading()")
    func storeErrorFinishesWithError() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("store-error.mp4")
        let fetcher = ABServicerFakeFetcher(
            dataReplies: [(Data(), ABHTTPResponse(statusCode: 200, expectedContentLength: 8, mimeType: "video/mp4"))],
            streamReplies: [[.response(.init(statusCode: 404, expectedContentLength: 8, mimeType: "video/mp4"))]]
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)
        let request = ABFakeLoadingRequest()
        request.dataRequest = ABFakeLoadingDataRequest(currentOffset: 0, requestedLength: 8)

        await ABLoadingRequestServicer.service(request, source: source, store: store)

        #expect(request.finishLoadingCallCount == 0)
        #expect(request.finishLoadingWithErrorCallCount == 1)
        #expect(request.lastError as? ABCacheStore.StoreError == .invalidResponse)
    }

    @Test("A cancelled request calls neither finishLoading variant")
    func cancelledRequestCallsNoFinishVariant() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("cancelled.mp4")
        let fetcher = ABServicerFakeFetcher(
            dataReplies: [(Data(), ABHTTPResponse(statusCode: 200, expectedContentLength: 8, mimeType: "video/mp4"))]
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)
        let request = ABFakeLoadingRequest()
        request.isCancelled = true
        request.dataRequest = ABFakeLoadingDataRequest(currentOffset: 0, requestedLength: 8)

        await ABLoadingRequestServicer.service(request, source: source, store: store)

        #expect(request.finishLoadingCallCount == 0)
        #expect(request.finishLoadingWithErrorCallCount == 0)
    }

    @Test("A store purge mid-service (removeAll) finishes the loading request without an error")
    func removeAllDuringServiceFinishesWithoutError() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = mediaSource("purge-during-service.mp4")
        let fetcher = ABServicerFakeFetcher(
            dataReplies: [
                (Data(), ABHTTPResponse(statusCode: 200, expectedContentLength: 8, mimeType: "video/mp4")),
                (Data("network!".utf8), ABHTTPResponse(statusCode: 200, expectedContentLength: 8, mimeType: "video/mp4"))
            ],
            streamReplies: [[.response(.init(statusCode: 200, expectedContentLength: 8, mimeType: "video/mp4"))]],
            stallsFill: true
        )
        let store = try ABCacheStore(configuration: .init(directory: directory), httpFetcher: fetcher)
        let request = ABFakeLoadingRequest()
        let dataRequest = ABFakeLoadingDataRequest(currentOffset: 0, requestedLength: 8)
        request.dataRequest = dataRequest

        let serviceTask = Task {
            await ABLoadingRequestServicer.service(request, source: source, store: store)
        }
        try await waitUntil { !store.activeReaderKeys().isEmpty }

        try await store.removeAll()
        fetcher.finishPending()
        await serviceTask.value

        #expect(dataRequest.respondedChunks == [Data("network!".utf8)])
        #expect(request.finishLoadingCallCount == 1)
        #expect(request.finishLoadingWithErrorCallCount == 0)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func mediaSource(_ name: String) -> ABMediaSource {
        ABMediaSource(url: URL(string: "https://example.com/\(name)")!)
    }

    private func seedComplete(source: ABMediaSource, data: Data, directory: URL) throws {
        let dataDirectory = directory.appendingPathComponent("Progressive", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let key = ABCacheKey.derive(from: source)
        let entry = ABCacheIndex.Entry(
            key: key,
            size: Int64(data.count),
            contentLength: Int64(data.count),
            contentType: "public.mpeg-4",
            isComplete: true,
            lastAccessedAt: Date()
        )
        try data.write(to: dataDirectory.appendingPathComponent(entry.fileName))
        let index = ABCacheIndex(entries: [key: entry])
        try JSONEncoder().encode(index).write(
            to: directory.appendingPathComponent("progressive-index.json")
        )
    }
}
