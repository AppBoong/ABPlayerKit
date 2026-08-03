import ABPlayerKit
@preconcurrency import Foundation
import UniformTypeIdentifiers

struct ABCachedMetadata: Sendable, Equatable {
    let contentLength: Int64
    let contentType: String
}

struct ABCachedResource: Sendable, Equatable {
    let data: Data
    let contentLength: Int64
    let contentType: String
    let isEndOfResource: Bool
}

private final class ABCacheReaderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func retain(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
    }

    func release(_ key: String) {
        lock.lock()
        if let count = counts[key], count > 1 {
            counts[key] = count - 1
        } else {
            counts[key] = nil
        }
        lock.unlock()
    }

    var activeKeys: Set<String> {
        lock.lock()
        let keys = Set(counts.keys)
        lock.unlock()
        return keys
    }
}

actor ABCacheStore {
    private struct RemoteMetadata: Sendable {
        let contentLength: Int64
        let contentType: String
    }

    enum StoreError: Error, Sendable, Equatable {
        case invalidResponse
        case entryTooLarge
        case shortRead
        case requestFailed
    }

    private let configuration: ABCacheConfiguration
    private let fileManager: FileManager
    private let httpFetcher: any ABHTTPFetching
    private let dataDirectory: URL
    private let indexURL: URL
    nonisolated private let readerRegistry = ABCacheReaderRegistry()
    private var index: ABCacheIndex
    private var metadataCache: [String: RemoteMetadata] = [:]
    private var fills: [String: Task<Void, Never>] = [:]
    private var fillResponses: [String: ABHTTPResponse] = [:]
    private var fillErrors: [String: StoreError] = [:]
    private var progressWaiters: [String: [UUID: CheckedContinuation<Void, Never>]] = [:]
    private var indexIsDirty = false
    private var indexFlushTask: Task<Void, Never>?

    init(
        configuration: ABCacheConfiguration,
        fileManager: FileManager = .default,
        httpFetcher: any ABHTTPFetching = ABURLSessionHTTPFetcher()
    ) throws {
        self.configuration = configuration
        self.fileManager = fileManager
        self.httpFetcher = httpFetcher
        self.dataDirectory = configuration.directory.appendingPathComponent("Progressive", isDirectory: true)
        self.indexURL = configuration.directory.appendingPathComponent("progressive-index.json")

        try fileManager.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var loadedIndex: ABCacheIndex
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode(ABCacheIndex.self, from: data) {
            loadedIndex = decoded
        } else {
            loadedIndex = ABCacheIndex()
        }
        for entry in loadedIndex.entries.values {
            let url = dataDirectory.appendingPathComponent(entry.fileName)
            guard fileManager.fileExists(atPath: url.path) else {
                loadedIndex.remove(key: entry.key)
                continue
            }
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            var reconciledEntry = entry
            reconciledEntry.size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            reconciledEntry.isComplete = reconciledEntry.contentLength.map {
                reconciledEntry.size >= $0
            } ?? false
            loadedIndex.upsert(reconciledEntry)
        }
        self.index = loadedIndex
        let indexData = try JSONEncoder().encode(loadedIndex)
        try indexData.write(to: indexURL, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: indexURL.path
        )
    }

    nonisolated func retainReader(for source: ABMediaSource) {
        readerRegistry.retain(ABCacheKey.derive(from: source))
    }

    nonisolated func releaseReader(for source: ABMediaSource) {
        readerRegistry.release(ABCacheKey.derive(from: source))
    }

    func totalSize() -> Int64 {
        index.totalSize
    }

    func remove(_ source: ABMediaSource) throws {
        let key = ABCacheKey.derive(from: source)
        cancelFill(for: key)
        metadataCache[key] = nil
        if let entry = index.remove(key: key) {
            try? fileManager.removeItem(at: fileURL(for: entry))
            markIndexDirty()
            try flushIndexNow()
        }
    }

    func removeAll() throws {
        for task in fills.values {
            task.cancel()
        }
        fills.removeAll()
        fillResponses.removeAll()
        fillErrors.removeAll()
        metadataCache.removeAll()
        resumeAllWaiters()
        if fileManager.fileExists(atPath: dataDirectory.path) {
            try fileManager.removeItem(at: dataDirectory)
        }
        try fileManager.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        index = ABCacheIndex()
        markIndexDirty()
        try flushIndexNow()
    }

    func metadata(for source: ABMediaSource) async throws -> ABCachedMetadata {
        let key = ABCacheKey.derive(from: source)
        if let entry = index.entries[key],
           let contentLength = entry.contentLength,
           let contentType = entry.contentType {
            return ABCachedMetadata(contentLength: contentLength, contentType: contentType)
        }
        if let metadata = metadataCache[key] {
            return ABCachedMetadata(
                contentLength: metadata.contentLength,
                contentType: metadata.contentType
            )
        }
        let metadata = try await remoteMetadata(for: source)
        metadataCache[key] = metadata
        return ABCachedMetadata(
            contentLength: metadata.contentLength,
            contentType: metadata.contentType
        )
    }

    func load(_ source: ABMediaSource, range: ABByteRange) async throws -> ABCachedResource {
        let key = ABCacheKey.derive(from: source)
        readerRegistry.retain(key)
        defer { readerRegistry.release(key) }

        let metadata = try await resolvedMetadata(for: source, key: key)
        if metadata.contentLength > cacheableEntryLimit {
            removeCachedEntry(for: key)
            return try await passthrough(source, range: range, metadata: metadata)
        }

        guard let resolvedRange = range.resolved(contentLength: metadata.contentLength) else {
            throw StoreError.invalidResponse
        }
        if resolvedRange.lowerBound >= metadata.contentLength {
            return ABCachedResource(
                data: Data(),
                contentLength: metadata.contentLength,
                contentType: metadata.contentType,
                isEndOfResource: true
            )
        }

        if index.entries[key]?.isComplete != true {
            startFillIfNeeded(source, key: key, metadata: metadata)
        }

        while true {
            if let entry = index.entries[key], entry.size > resolvedRange.lowerBound {
                index.touch(key: key, at: Date())
                markIndexDirty()
                return try resource(
                    from: entry,
                    range: resolvedRange,
                    metadata: metadata
                )
            }
            if index.entries[key]?.isComplete == true {
                return ABCachedResource(
                    data: Data(),
                    contentLength: metadata.contentLength,
                    contentType: metadata.contentType,
                    isEndOfResource: true
                )
            }
            if fills[key] == nil, let error = fillErrors[key] {
                if error == .entryTooLarge {
                    removeCachedEntry(for: key)
                    return try await passthrough(source, range: resolvedRange, metadata: metadata)
                }
                throw error
            }
            guard fills[key] != nil else { throw StoreError.shortRead }
            await waitForProgress(key: key)
            try Task.checkCancellation()
        }
    }

    private func resolvedMetadata(for source: ABMediaSource, key: String) async throws -> RemoteMetadata {
        if let entry = index.entries[key],
           let contentLength = entry.contentLength,
           let contentType = entry.contentType {
            return RemoteMetadata(contentLength: contentLength, contentType: contentType)
        }
        if let metadata = metadataCache[key] {
            return metadata
        }
        let metadata = try await remoteMetadata(for: source)
        metadataCache[key] = metadata
        return metadata
    }

    private func startFillIfNeeded(
        _ source: ABMediaSource,
        key: String,
        metadata: RemoteMetadata
    ) {
        guard fills[key] == nil else { return }
        fillErrors[key] = nil
        let request = fillRequest(for: source, offset: index.entries[key]?.size ?? 0)
        let stream = httpFetcher.stream(for: request)
        fills[key] = Task { [weak self] in
            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    guard let self else { return }
                    switch event {
                    case .response(let response):
                        try await self.prepareFill(
                            key: key,
                            metadata: metadata,
                            response: response
                        )
                    case .data(let data):
                        try await self.append(data, key: key)
                    }
                }
                await self?.completeFill(key: key)
            } catch let error as StoreError {
                await self?.failFill(key: key, error: error)
            } catch is CancellationError {
                await self?.failFill(key: key, error: .requestFailed)
            } catch {
                await self?.failFill(key: key, error: .requestFailed)
            }
        }
    }

    private func prepareFill(
        key: String,
        metadata: RemoteMetadata,
        response: ABHTTPResponse
    ) throws {
        guard (200...299).contains(response.statusCode) else {
            throw StoreError.invalidResponse
        }
        var entry = index.entries[key] ?? ABCacheIndex.Entry(
            key: key,
            size: 0,
            contentLength: metadata.contentLength,
            contentType: metadata.contentType,
            lastAccessedAt: Date()
        )
        let destinationURL = fileURL(for: entry)
        if !fileManager.fileExists(atPath: destinationURL.path) {
            fileManager.createFile(
                atPath: destinationURL.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            entry.size = 0
        } else {
            entry.size = fileSize(at: destinationURL)
        }
        if response.statusCode == 200, entry.size > 0 {
            let handle = try FileHandle(forWritingTo: destinationURL)
            try handle.truncate(atOffset: 0)
            try handle.close()
            entry.size = 0
        }
        entry.contentLength = Self.totalLength(from: response) ?? metadata.contentLength
        entry.contentType = Self.contentType(
            from: response,
            fallback: metadata.contentType
        )
        guard entry.contentLength.map({ $0 <= cacheableEntryLimit }) != false else {
            throw StoreError.entryTooLarge
        }
        entry.isComplete = false
        entry.lastAccessedAt = Date()
        index.upsert(entry)
        fillResponses[key] = response
        markIndexDirty()
        resumeWaiters(for: key)
    }

    private func append(_ data: Data, key: String) throws {
        guard !data.isEmpty else { return }
        guard var entry = index.entries[key], fillResponses[key] != nil else {
            throw StoreError.invalidResponse
        }
        guard entry.size + Int64(data.count) <= cacheableEntryLimit else {
            throw StoreError.entryTooLarge
        }
        let handle = try FileHandle(forWritingTo: fileURL(for: entry))
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
        entry.size += Int64(data.count)
        entry.lastAccessedAt = Date()
        index.upsert(entry)
        markIndexDirty()
        let evicted = evictIfNeeded(protecting: key)
        if evicted {
            try flushIndexNow()
        }
        resumeWaiters(for: key)
    }

    private func completeFill(key: String) {
        guard var entry = index.entries[key], let response = fillResponses[key] else {
            failFill(key: key, error: .invalidResponse)
            return
        }
        entry.isComplete = entry.contentLength.map { entry.size >= $0 }
            ?? (response.statusCode == 200)
        entry.lastAccessedAt = Date()
        index.upsert(entry)
        fills[key] = nil
        fillResponses[key] = nil
        if entry.isComplete {
            fillErrors[key] = nil
        } else {
            fillErrors[key] = .shortRead
        }
        markIndexDirty()
        _ = evictIfNeeded(protecting: key)
        try? flushIndexNow()
        resumeWaiters(for: key)
    }

    private func failFill(key: String, error: StoreError) {
        fills[key] = nil
        fillResponses[key] = nil
        fillErrors[key] = error
        if error == .entryTooLarge {
            removeCachedEntry(for: key)
        }
        markIndexDirty()
        try? flushIndexNow()
        resumeWaiters(for: key)
    }

    private func passthrough(
        _ source: ABMediaSource,
        range: ABByteRange,
        metadata: RemoteMetadata
    ) async throws -> ABCachedResource {
        guard let resolvedRange = range.resolved(contentLength: metadata.contentLength) else {
            throw StoreError.invalidResponse
        }
        var request = request(for: source)
        request.setValue(resolvedRange.headerValue, forHTTPHeaderField: "Range")
        let (receivedData, response) = try await httpFetcher.data(for: request)
        guard (200...299).contains(response.statusCode) else {
            throw StoreError.invalidResponse
        }

        let requestedUpperBound = Swift.min(
            resolvedRange.upperBound ?? (metadata.contentLength - 1),
            metadata.contentLength - 1
        )
        let expectedCount = Int(requestedUpperBound - resolvedRange.lowerBound + 1)
        let data: Data
        if response.statusCode == 200 {
            guard resolvedRange.lowerBound < Int64(receivedData.count) else {
                throw StoreError.shortRead
            }
            let upperBound = Swift.min(Int64(receivedData.count) - 1, requestedUpperBound)
            data = receivedData.subdata(
                in: Int(resolvedRange.lowerBound)..<Int(upperBound + 1)
            )
        } else {
            data = receivedData.prefix(expectedCount)
        }
        guard data.count == expectedCount else { throw StoreError.shortRead }

        return ABCachedResource(
            data: data,
            contentLength: metadata.contentLength,
            contentType: Self.contentType(from: response, fallback: metadata.contentType),
            isEndOfResource: requestedUpperBound == metadata.contentLength - 1
        )
    }

    private func remoteMetadata(for source: ABMediaSource) async throws -> RemoteMetadata {
        var request = request(for: source)
        request.httpMethod = "HEAD"
        if let (_, response) = try? await httpFetcher.data(for: request),
           let metadata = Self.metadata(from: response, source: source) {
            return metadata
        }

        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await httpFetcher.data(for: request)
        guard let metadata = Self.metadata(from: response, source: source) else {
            throw StoreError.invalidResponse
        }
        return metadata
    }

    private func resource(
        from entry: ABCacheIndex.Entry,
        range: ABByteRange,
        metadata: RemoteMetadata
    ) throws -> ABCachedResource {
        let requestedUpperBound = Swift.min(
            range.upperBound ?? (metadata.contentLength - 1),
            metadata.contentLength - 1
        )
        let upperBound = Swift.min(requestedUpperBound, entry.size - 1)
        guard upperBound >= range.lowerBound else { throw StoreError.shortRead }

        let handle = try FileHandle(forReadingFrom: fileURL(for: entry))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let count = Int(upperBound - range.lowerBound + 1)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw StoreError.shortRead }
        return ABCachedResource(
            data: data,
            contentLength: metadata.contentLength,
            contentType: entry.contentType ?? metadata.contentType,
            isEndOfResource: upperBound == metadata.contentLength - 1
        )
    }

    private func fillRequest(for source: ABMediaSource, offset: Int64) -> URLRequest {
        var request = request(for: source)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        return request
    }

    private func request(for source: ABMediaSource) -> URLRequest {
        var request = URLRequest(url: source.url)
        for (field, value) in source.httpHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    private func waitForProgress(key: String) async {
        await withCheckedContinuation { continuation in
            progressWaiters[key, default: [:]][UUID()] = continuation
        }
    }

    private func resumeWaiters(for key: String) {
        let waiters = progressWaiters.removeValue(forKey: key)?.values ?? [:].values
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func resumeAllWaiters() {
        let waiters = progressWaiters.values.flatMap(\.values)
        progressWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func cancelFill(for key: String) {
        fills.removeValue(forKey: key)?.cancel()
        fillResponses[key] = nil
        fillErrors[key] = nil
        resumeWaiters(for: key)
    }

    private func removeCachedEntry(for key: String) {
        guard let entry = index.remove(key: key) else { return }
        try? fileManager.removeItem(at: fileURL(for: entry))
        markIndexDirty()
    }

    @discardableResult
    private func evictIfNeeded(protecting protectedKey: String) -> Bool {
        var excludedKeys = readerRegistry.activeKeys
        excludedKeys.formUnion(fills.keys)
        excludedKeys.insert(protectedKey)
        let evicted = index.evictLRU(
            to: configuration.maximumDiskSize,
            excluding: excludedKeys
        )
        for entry in evicted {
            try? fileManager.removeItem(at: fileURL(for: entry))
        }
        if !evicted.isEmpty {
            markIndexDirty()
        }
        return !evicted.isEmpty
    }

    private func markIndexDirty() {
        indexIsDirty = true
        guard indexFlushTask == nil else { return }
        indexFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.flushDebouncedIndex()
        }
    }

    private func flushDebouncedIndex() {
        indexFlushTask = nil
        try? flushIndexNow()
    }

    private func flushIndexNow() throws {
        indexFlushTask?.cancel()
        indexFlushTask = nil
        guard indexIsDirty else { return }
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: indexURL.path
        )
        indexIsDirty = false
    }

    private func fileURL(for entry: ABCacheIndex.Entry) -> URL {
        dataDirectory.appendingPathComponent(entry.fileName)
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private var cacheableEntryLimit: Int64 {
        Swift.max(0, Swift.min(configuration.maximumEntrySize, configuration.maximumDiskSize))
    }

    private static func metadata(
        from response: ABHTTPResponse,
        source: ABMediaSource
    ) -> RemoteMetadata? {
        guard (200...299).contains(response.statusCode),
              let contentLength = totalLength(from: response),
              contentLength > 0
        else { return nil }
        return RemoteMetadata(
            contentLength: contentLength,
            contentType: contentType(from: response, fallback: fallbackContentType(for: source))
        )
    }

    private static func totalLength(from response: ABHTTPResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let total = contentRange.split(separator: "/").last,
           let value = Int64(total) {
            return value
        }
        return response.expectedContentLength
    }

    private static func contentType(from response: ABHTTPResponse, fallback: String) -> String {
        guard let mimeType = response.mimeType,
              let type = UTType(mimeType: mimeType)
        else { return fallback }
        return type.identifier
    }

    private static func fallbackContentType(for source: ABMediaSource) -> String {
        guard !source.url.pathExtension.isEmpty,
              let type = UTType(filenameExtension: source.url.pathExtension)
        else { return UTType.data.identifier }
        return type.identifier
    }
}
