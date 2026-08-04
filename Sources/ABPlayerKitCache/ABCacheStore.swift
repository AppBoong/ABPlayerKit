import ABPlayerKit
@preconcurrency import Foundation
import UniformTypeIdentifiers

struct ABCachedMetadata: Sendable, Equatable {
    let contentLength: Int64?
    let contentType: String
}

struct ABCachedResource: Sendable, Equatable {
    let data: Data
    let contentLength: Int64?
    let contentType: String
    let isEndOfResource: Bool
}

// Reader counts are accessed across actor reentrancy while protected by the lock.
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

/// One `waitForProgress` waiter. Coordinates the normal resume path (an
/// actor-isolated call once fill progress lands) against task cancellation
/// (a synchronous, non-actor-isolated `onCancel` handler) without letting
/// either path resume the continuation twice. Cancellation may arrive
/// before the continuation is installed, so — same pattern as
/// `ABAVPlaybackTarget.ReadyWaitState` — the "resolved" state is retained
/// until installation completes.
private final class ABCacheProgressWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            continuation.resume()
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    /// Idempotent — the second caller (whichever of "fill progress" or
    /// "cancelled" loses the race) observes `false` and does nothing.
    @discardableResult
    func resolve() -> Bool {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return false
        }
        isResolved = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
        return true
    }
}

/// Tracks in-flight `waitForProgress` waiters by key and UUID. Deliberately
/// **not** actor-isolated (mirrors `ABCacheReaderRegistry` just above): the
/// `onCancel` side of `withTaskCancellationHandler` runs synchronously,
/// outside actor isolation, and still needs to remove exactly the one
/// waiter that was cancelled so it stops blocking LRU eviction (WP4 —
/// previously a cancelled waiter stayed in this registry, and by extension
/// `load(_:range:)` never returned, keeping `readerRegistry` retained for
/// that key forever).
private final class ABCacheProgressWaiterRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [String: [UUID: ABCacheProgressWaiter]] = [:]

    func add(key: String, id: UUID, waiter: ABCacheProgressWaiter) {
        lock.lock()
        waiters[key, default: [:]][id] = waiter
        lock.unlock()
    }

    /// Removes a single waiter. Safe to call after it has already resolved
    /// (the cancellation path) or after normal completion (a no-op) —
    /// removal never resolves a waiter itself.
    func remove(key: String, id: UUID) {
        lock.lock()
        waiters[key]?.removeValue(forKey: id)
        if waiters[key]?.isEmpty == true {
            waiters[key] = nil
        }
        lock.unlock()
    }

    /// Removes and resolves every waiter for `key` — the fill
    /// progress/completion path.
    func resolveAll(for key: String) {
        lock.lock()
        let removed = waiters.removeValue(forKey: key)?.values
        lock.unlock()
        removed?.forEach { $0.resolve() }
    }

    /// Removes and resolves every waiter across every key — store teardown.
    func resolveEverything() {
        lock.lock()
        let all = waiters.values.flatMap(\.values)
        waiters.removeAll()
        lock.unlock()
        all.forEach { $0.resolve() }
    }
}

actor ABCacheStore {
    private struct RemoteMetadata: Sendable {
        let contentLength: Int64?
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
    private var metadataCacheOrder: [String] = []
    private var fills: [String: Task<Void, Never>] = [:]
    private var fillResponses: [String: ABHTTPResponse] = [:]
    private var fillErrors: [String: StoreError] = [:]
    /// In-flight `remoteMetadata` requests, keyed by cache key, so N
    /// concurrent cold-key callers share one HEAD instead of each issuing
    /// their own (round3 Phase1+2 review M5 — `fills` already coalesced the
    /// GET via the synchronous `guard fills[key] == nil` in
    /// `startFillIfNeeded`, but `resolvedMetadata`/`metadata(for:)` had no
    /// equivalent for the HEAD that precedes it).
    private var pendingMetadataRequests: [String: Task<RemoteMetadata, Error>] = [:]
    nonisolated private let progressWaiters = ABCacheProgressWaiterRegistry()
    private var indexIsDirty = false
    private var indexFlushTask: Task<Void, Never>?
    private var recordedEvictionShortfallCount = 0

    private let metadataCacheLimit = 32

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

    /// Resolves any `waitForProgress` waiters still suspended when this
    /// store deallocates — without it, their continuations (and whatever
    /// `load(_:range:)` callers are awaiting them) leak forever, since
    /// nothing else will ever call `resumeWaiters`/`resolveAll` for a
    /// deallocated store (round3 Phase1+2 review m12; `resolveEverything()`
    /// already existed for `removeAll()`, just not for teardown).
    /// `progressWaiters` is `nonisolated`, so this is safe to run from
    /// `deinit` (nonisolated even on an `actor`) without needing any
    /// workaround for the actor-isolated storage elsewhere in this type.
    deinit {
        progressWaiters.resolveEverything()
    }

    func totalSize() -> Int64 {
        index.totalSize
    }

    func evictionShortfallCount() -> Int {
        recordedEvictionShortfallCount
    }

    func metadataCacheCount() -> Int {
        metadataCache.count
    }

    /// Test-only introspection (WP7): a snapshot of the metadata LRU order,
    /// oldest (next to evict) first. Lets tests assert that re-touching a
    /// key (a second `metadata(for:)` call) moves it to the
    /// most-recently-used end instead of letting it evict on the next
    /// insert.
    func metadataCacheOrderSnapshot() -> [String] {
        metadataCacheOrder
    }

    /// Test-only introspection (WP4 regression coverage): the set of keys
    /// `load(_:range:)` currently has an active reader for. A cancelled
    /// `waitForProgress` waiter that fails to unwind `load(_:range:)`
    /// promptly would leave its key in here forever, blocking that key from
    /// LRU eviction.
    nonisolated func activeReaderKeys() -> Set<String> {
        readerRegistry.activeKeys
    }

    func remove(_ source: ABMediaSource) throws {
        let key = ABCacheKey.derive(from: source)
        cancelFill(for: key)
        removeCachedMetadata(for: key)
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
        for task in pendingMetadataRequests.values {
            task.cancel()
        }
        pendingMetadataRequests.removeAll()
        metadataCache.removeAll()
        metadataCacheOrder.removeAll()
        recordedEvictionShortfallCount = 0
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
        let metadata = try await resolvedMetadata(for: source, key: key)
        return ABCachedMetadata(contentLength: metadata.contentLength, contentType: metadata.contentType)
    }

    func load(_ source: ABMediaSource, range: ABByteRange) async throws -> ABCachedResource {
        let key = ABCacheKey.derive(from: source)
        readerRegistry.retain(key)
        defer { readerRegistry.release(key) }

        let metadata = try await resolvedMetadata(for: source, key: key)
        guard let contentLength = metadata.contentLength else {
            removeCachedEntry(for: key)
            return try await rawPassthrough(source, range: range, metadata: metadata)
        }
        if contentLength > cacheableEntryLimit {
            removeCachedEntry(for: key)
            return try await passthrough(source, range: range, metadata: metadata)
        }

        guard let resolvedRange = range.resolved(contentLength: contentLength) else {
            throw StoreError.invalidResponse
        }
        if resolvedRange.lowerBound >= contentLength {
            return ABCachedResource(
                data: Data(),
                contentLength: contentLength,
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
                    contentLength: contentLength,
                    contentType: metadata.contentType,
                    isEndOfResource: true
                )
            }
            // WP11: a request far ahead of the linear fill's current
            // prefix would otherwise wait for that fill to sequentially
            // crawl all the way there — unbounded for a distant seek
            // against a non-faststart file. Serve it directly instead of
            // ever calling `waitForProgress` for it. The background fill
            // keeps crawling forward untouched; this is a one-off
            // passthrough for this caller only, not a fill restart.
            let currentPrefixEnd = index.entries[key]?.size ?? 0
            if resolvedRange.lowerBound - currentPrefixEnd >= configuration.passthroughGapThreshold {
                return try await passthrough(source, range: resolvedRange, metadata: metadata)
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
        if let metadata = cachedMetadata(for: key) {
            return metadata
        }
        // Coalesce concurrent cold-key requests onto a single in-flight
        // HEAD (M5): the first caller creates the task and stores it before
        // its first suspension point, so every other caller that arrives
        // before it completes awaits the same `Task` instead of issuing its
        // own request.
        if let pending = pendingMetadataRequests[key] {
            return try await pending.value
        }
        let request = Task { [weak self] () throws -> RemoteMetadata in
            guard let self else { throw StoreError.requestFailed }
            return try await self.remoteMetadata(for: source)
        }
        pendingMetadataRequests[key] = request
        defer { pendingMetadataRequests[key] = nil }
        let metadata = try await request.value
        cacheMetadata(metadata, for: key)
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
        removeCachedMetadata(for: key)
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
        guard let contentLength = metadata.contentLength,
              let resolvedRange = range.resolved(contentLength: contentLength) else {
            throw StoreError.invalidResponse
        }
        let fullUpperBound = Swift.min(
            resolvedRange.upperBound ?? (contentLength - 1),
            contentLength - 1
        )
        // Cap each round trip to `passthroughChunkSize` (round3 Phase4
        // WP11.2) so a caller streaming a large range —
        // `ABResourceLoaderDelegate`'s loop, which already re-requests
        // from `currentOffset` after every response — gets it back in
        // bounded pieces instead of one large in-memory `Data` allocation
        // per round trip.
        let requestedUpperBound = Swift.min(fullUpperBound, resolvedRange.lowerBound + passthroughChunkSize - 1)
        var request = request(for: source)
        request.setValue(
            ABByteRange(lowerBound: resolvedRange.lowerBound, upperBound: requestedUpperBound).headerValue,
            forHTTPHeaderField: "Range"
        )
        let (receivedData, response) = try await httpFetcher.data(for: request)
        guard (200...299).contains(response.statusCode) else {
            throw StoreError.invalidResponse
        }

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
            contentLength: contentLength,
            contentType: Self.contentType(from: response, fallback: metadata.contentType),
            isEndOfResource: requestedUpperBound == contentLength - 1
        )
    }

    private func rawPassthrough(
        _ source: ABMediaSource,
        range: ABByteRange,
        metadata: RemoteMetadata
    ) async throws -> ABCachedResource {
        var request = request(for: source)
        request.setValue(range.headerValue, forHTTPHeaderField: "Range")
        let (receivedData, response) = try await httpFetcher.data(for: request)
        guard (200...299).contains(response.statusCode) else {
            throw StoreError.invalidResponse
        }

        let expectedCount = range.upperBound.map {
            Int($0 - range.lowerBound + 1)
        }
        let data: Data
        if response.statusCode == 200, range.lowerBound > 0 {
            guard range.lowerBound < Int64(receivedData.count) else {
                throw StoreError.shortRead
            }
            let upperBound = range.upperBound.map {
                Swift.min(Int64(receivedData.count) - 1, $0)
            } ?? (Int64(receivedData.count) - 1)
            data = receivedData.subdata(
                in: Int(range.lowerBound)..<Int(upperBound + 1)
            )
        } else if let expectedCount {
            data = receivedData.prefix(expectedCount)
        } else {
            data = receivedData
        }
        guard !data.isEmpty,
              expectedCount.map({ data.count == $0 }) != false
        else { throw StoreError.shortRead }

        return ABCachedResource(
            data: data,
            contentLength: Self.totalLength(from: response),
            contentType: Self.contentType(from: response, fallback: metadata.contentType),
            isEndOfResource: true
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
        guard let contentLength = metadata.contentLength else {
            throw StoreError.invalidResponse
        }
        let requestedUpperBound = Swift.min(
            range.upperBound ?? (contentLength - 1),
            contentLength - 1
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
            contentLength: contentLength,
            contentType: entry.contentType ?? metadata.contentType,
            isEndOfResource: upperBound == contentLength - 1
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

    /// Suspends until either fill progress lands for `key` (the normal
    /// path, resolved via `resumeWaiters(for:)`) or the awaiting `Task` is
    /// cancelled. On cancellation, `onCancel` resumes this specific waiter
    /// (keyed by `id`) and removes it from `progressWaiters` immediately —
    /// synchronously, from a non-actor-isolated context — so the caller's
    /// following `Task.checkCancellation()` throws promptly instead of
    /// leaving a dead entry that blocks LRU eviction (WP4).
    private func waitForProgress(key: String) async {
        let id = UUID()
        let waiter = ABCacheProgressWaiter()
        progressWaiters.add(key: key, id: id, waiter: waiter)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.install(continuation)
            }
        } onCancel: {
            waiter.resolve()
            progressWaiters.remove(key: key, id: id)
        }
        // Normal-completion cleanup — a no-op if `onCancel` already removed
        // this waiter.
        progressWaiters.remove(key: key, id: id)
    }

    private func resumeWaiters(for key: String) {
        progressWaiters.resolveAll(for: key)
    }

    private func resumeAllWaiters() {
        progressWaiters.resolveEverything()
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
        if index.totalSize > configuration.maximumDiskSize {
            recordedEvictionShortfallCount += 1
        }
        return !evicted.isEmpty
    }

    private func cachedMetadata(for key: String) -> RemoteMetadata? {
        guard let metadata = metadataCache[key] else { return nil }
        metadataCacheOrder.removeAll { $0 == key }
        metadataCacheOrder.append(key)
        return metadata
    }

    private func cacheMetadata(_ metadata: RemoteMetadata, for key: String) {
        metadataCache[key] = metadata
        metadataCacheOrder.removeAll { $0 == key }
        metadataCacheOrder.append(key)
        while metadataCacheOrder.count > metadataCacheLimit {
            let evictedKey = metadataCacheOrder.removeFirst()
            metadataCache[evictedKey] = nil
        }
    }

    private func removeCachedMetadata(for key: String) {
        metadataCache[key] = nil
        metadataCacheOrder.removeAll { $0 == key }
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

    /// Per-round-trip cap for `passthrough` responses (round3 Phase4
    /// WP11.2) — fixed, not configurable, since it bounds an in-memory
    /// `Data` allocation rather than expressing a cache policy tradeoff.
    private var passthroughChunkSize: Int64 { 1_024 * 1_024 }

    private static func metadata(
        from response: ABHTTPResponse,
        source: ABMediaSource
    ) -> RemoteMetadata? {
        guard (200...299).contains(response.statusCode) else { return nil }
        return RemoteMetadata(
            contentLength: totalLength(from: response),
            contentType: contentType(from: response, fallback: fallbackContentType(for: source))
        )
    }

    private static func totalLength(from response: ABHTTPResponse) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let total = contentRange.split(separator: "/").last,
           let value = Int64(total) {
            return value
        }
        return response.statusCode == 206 ? nil : response.expectedContentLength
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
