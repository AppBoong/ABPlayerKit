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

/// Tracks assets that owe a one-time conditional revalidation at the start
/// of a playback session. Deliberately not
/// actor-isolated — mirrors `ABCacheReaderRegistry`/`ABCacheProgressWaiterRegistry`
/// above: `ABResourceLoaderDelegate` marks a key synchronously, outside
/// actor isolation, the instant a new asset session begins, so no loading
/// request for that session can race ahead of the mark.
private final class ABCacheRevalidationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Set<String> = []

    func markPending(_ key: String) {
        lock.lock()
        pending.insert(key)
        lock.unlock()
    }

    /// Test-and-clear: returns `true` at most once per `markPending` call,
    /// so exactly one caller ever performs the revalidation; every other
    /// concurrent caller for the same key observes `false` and falls
    /// through to the normal coalescing path instead.
    func claimPending(_ key: String) -> Bool {
        lock.lock()
        let wasPending = pending.remove(key) != nil
        lock.unlock()
        return wasPending
    }

    func clearPending(_ key: String) {
        lock.lock()
        pending.remove(key)
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        pending.removeAll()
        lock.unlock()
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

    /// Thrown from `prepareFill` when a resume validation mismatch forces a
    /// restart on a *replacement* fill (`launchFill` already installed it).
    /// The originating fill's own task must not treat this as a failure —
    /// doing so would call `failFill`, which would nil out the replacement
    /// fill's just-installed state out from under it.
    private struct FillSuperseded: Error {}

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
    /// Writer handle held open for a fill's whole lifetime —
    /// `fillHandles[key] != nil` iff `fillResponses[key] != nil`. Both are
    /// installed together in `prepareFill` and released together, only from
    /// `completeFill`/`failFill`/`cancelFill`/`removeAll` via
    /// `closeFillHandle(for:)`, so no fill-lifecycle transition can leak a
    /// handle. `FileHandle` also closes its fd on dealloc, so even a path
    /// that somehow missed one of those four call sites would not leak past
    /// this store's own deinit.
    private var fillHandles: [String: FileHandle] = [:]
    /// Bumped by `remove`/`removeAll` before they resume waiters — lets
    /// `load`'s wait loop distinguish "this key's entry is absent because
    /// it was just purged out from under an in-flight read" from "this
    /// key's entry is absent because its fill hasn't produced one yet"
    /// (the latter must keep surfacing `fillErrors` untouched).
    private var purgeGeneration: UInt64 = 0
    nonisolated private let revalidationRegistry = ABCacheRevalidationRegistry()
    /// In-flight `remoteMetadata` requests, keyed by cache key, so N
    /// concurrent cold-key callers share one HEAD instead of each issuing
    /// their own (round3 Phase1+2 review M5 — `fills` already coalesced the
    /// GET via the synchronous `guard fills[key] == nil` in
    /// `startFillIfNeeded`, but `resolvedMetadata`/`metadata(for:)` had no
    /// equivalent for the HEAD that precedes it).
    ///
    /// Values are wrapped in a reference-type holder (rather than storing
    /// `Task` directly) so cleanup can compare identity (round4 review
    /// N12): if `reset()` — or a second HEAD that arrived after this key's
    /// entry was already cleared — has since installed a *different*
    /// holder for the same key, cleanup must not clobber it out from under
    /// whoever owns it now.
    ///
    /// Caching the result and clearing the slot both happen from *inside*
    /// the task's own body (`finishMetadataRequest`, called from the `Task`
    /// closure below), not from whichever caller's `resolvedMetadata` call
    /// happens to be awaiting it (round4 review mn-4, completing N12): an
    /// unstructured `Task` doesn't stop running just because one awaiter's
    /// `try await request.value` gets cancelled — cancelling that await
    /// only makes *that call* throw `CancellationError`, it doesn't cancel
    /// the task. The old code tied caching/cleanup to the *first* caller's
    /// `defer`, so a cancelled first caller left the task to finish with
    /// nothing recording its result: the slot stayed cleared, a second
    /// caller launched an entirely new HEAD, and the orphaned first task's
    /// eventual result was silently discarded uncached. Tying both to the
    /// task's own completion instead means every path out — success,
    /// thrown error, or the task's own cancellation via `removeAll()` —
    /// finishes exactly once, regardless of how many callers were
    /// awaiting it or whether any of them got cancelled first.
    private final class PendingMetadataRequest {
        /// Compared by value (not `===`) from inside the coalesced `Task`'s
        /// closure, which — being `@Sendable` — can't capture this
        /// non-`Sendable` class instance itself without either an
        /// actor-isolation data-race diagnostic or `@unchecked Sendable`
        /// (banned in this codebase — see `DESIGN-OPEN-QUESTIONS.md` Q13's
        /// rationale, same reasoning as banning `MainActor.assumeIsolated`
        /// as a compile-error workaround). A plain `UUID` is trivially
        /// `Sendable` and serves the identity comparison just as well.
        let id = UUID()
        var task: Task<RemoteMetadata, Error>!
    }
    private var pendingMetadataRequests: [String: PendingMetadataRequest] = [:]
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

    /// Test-only introspection: the number of writer handles currently held
    /// open across all in-flight fills. Every fill lifecycle path must
    /// leave this at 0 once it's done — a leaked entry here means
    /// `closeFillHandle(for:)` was skipped somewhere.
    func fillHandleCount() -> Int {
        fillHandles.count
    }

    /// Marks `source`'s cache key as owing a one-time conditional
    /// revalidation the next time its metadata is resolved. Called
    /// synchronously from `ABResourceLoaderDelegate` — outside
    /// actor isolation and before any `Task` is spawned — so the mark is in
    /// place before that asset session's first loading request can reach
    /// `resolvedMetadata`.
    nonisolated func beginAssetSession(for source: ABMediaSource) {
        revalidationRegistry.markPending(ABCacheKey.derive(from: source))
    }

    func remove(_ source: ABMediaSource) throws {
        let key = ABCacheKey.derive(from: source)
        purgeGeneration += 1
        cancelFill(for: key)
        removeCachedMetadata(for: key)
        revalidationRegistry.clearPending(key)
        if let entry = index.remove(key: key) {
            try? fileManager.removeItem(at: fileURL(for: entry))
            markIndexDirty()
            try flushIndexNow()
        }
    }

    func removeAll() throws {
        purgeGeneration += 1
        for task in fills.values {
            task.cancel()
        }
        fills.removeAll()
        fillResponses.removeAll()
        for handle in fillHandles.values {
            try? handle.close()
        }
        fillHandles.removeAll()
        fillErrors.removeAll()
        for pending in pendingMetadataRequests.values {
            pending.task.cancel()
        }
        pendingMetadataRequests.removeAll()
        metadataCache.removeAll()
        metadataCacheOrder.removeAll()
        revalidationRegistry.clearAll()
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
        let entryGeneration = purgeGeneration
        guard let contentLength = metadata.contentLength else {
            removeCachedEntry(for: key)
            return try await rawPassthrough(source, range: range, metadata: metadata, key: key)
        }
        if contentLength > cacheableEntryLimit {
            removeCachedEntry(for: key)
            return try await passthrough(source, range: range, metadata: metadata, key: key)
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

        // Swift actor execution is non-preemptive: when this call is the
        // one that starts a fresh resume fill for an existing on-disk
        // prefix, the loop below runs its first pass before that fill's
        // Task has any chance to run — so an unconditional "serve from
        // cache if the size covers it" check would hand back that prefix's
        // bytes before the fill's own response has validated them against
        // the origin at all. Wait for at least one fill-progress signal
        // first in that specific case — every path out of `prepareFill`
        // that isn't the resume-mismatch restart calls `resumeWaiters`
        // only after its own validation has run, so one signal is
        // sufficient. An entry that's already complete needs no such
        // wait — `startFillIfNeeded` won't even start a fill for it, and
        // waiting would hang forever.
        let entryWasComplete = index.entries[key]?.isComplete == true
        let hadExistingPrefix = (index.entries[key]?.size ?? 0) > 0
        let isStartingFreshFill = fills[key] == nil
        if !entryWasComplete {
            startFillIfNeeded(source, key: key, metadata: metadata)
        }
        let mustObserveFillProgressBeforeServing = isStartingFreshFill && hadExistingPrefix && !entryWasComplete
        var hasObservedFillProgress = false

        while true {
            if (!mustObserveFillProgressBeforeServing || hasObservedFillProgress),
               let entry = index.entries[key], entry.size > resolvedRange.lowerBound {
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
                return try await passthrough(source, range: resolvedRange, metadata: metadata, key: key)
            }
            // The entry vanished because `remove`/`removeAll`
            // purged it out from under this in-flight read (not because its
            // fill simply hasn't produced one yet, which `purgeGeneration`
            // being unchanged rules out) — demote to a one-off network read
            // instead of surfacing `.shortRead` and failing playback. The
            // next `load` call starts a fresh fill and the cache refills
            // from the current position onward.
            if purgeGeneration != entryGeneration, index.entries[key] == nil {
                return try await passthrough(source, range: resolvedRange, metadata: metadata, key: key)
            }
            if fills[key] == nil, let error = fillErrors[key] {
                if error == .entryTooLarge {
                    removeCachedEntry(for: key)
                    return try await passthrough(source, range: resolvedRange, metadata: metadata, key: key)
                }
                throw error
            }
            guard fills[key] != nil else { throw StoreError.shortRead }
            await waitForProgress(key: key)
            hasObservedFillProgress = true
            try Task.checkCancellation()
        }
    }

    private func resolvedMetadata(for source: ABMediaSource, key: String) async throws -> RemoteMetadata {
        // A session-start revalidation claim must be
        // checked, synchronously, *before* the index/LRU fast paths below —
        // otherwise a completed entry would return straight from the index
        // forever, and `If-Range` (which only fires on resume) never gets a
        // chance to notice the origin changed. `claimPending` is
        // test-and-clear, so at most one concurrent caller for this key
        // ever sees `true`; every other caller falls through unchanged and
        // coalesces via `pendingMetadataRequests` at step 3 below — this
        // order is fixed, see the type's doc comment above
        // `pendingMetadataRequests`.
        let needsRevalidation = revalidationRegistry.claimPending(key)
        if !needsRevalidation {
            if let entry = index.entries[key],
               let contentLength = entry.contentLength,
               let contentType = entry.contentType {
                return RemoteMetadata(contentLength: contentLength, contentType: contentType)
            }
            if let metadata = cachedMetadata(for: key) {
                return metadata
            }
        }
        // Coalesce concurrent cold-key requests onto a single in-flight
        // HEAD (M5): the first caller creates the task and stores it before
        // its first suspension point, so every other caller that arrives
        // before it completes awaits the same `Task` instead of issuing its
        // own request.
        if let pending = pendingMetadataRequests[key] {
            return try await pending.task.value
        }
        // `holder` is installed (with its `task` filled in) before any
        // suspension point below, so every other caller that arrives before
        // it completes awaits the same `Task` instead of issuing its own
        // request. `finishMetadataRequest` — called from *inside* the task,
        // not from this call's own completion — does the caching and slot
        // cleanup exactly once, regardless of whether this specific await
        // gets cancelled (see this type's doc comment, round4 mn-4).
        let holder = PendingMetadataRequest()
        let holderID = holder.id
        pendingMetadataRequests[key] = holder
        let request = Task { [weak self] () throws -> RemoteMetadata in
            guard let self else { throw StoreError.requestFailed }
            do {
                let metadata: RemoteMetadata
                if needsRevalidation {
                    metadata = try await self.revalidatedMetadata(for: source, key: key)
                } else {
                    metadata = try await self.remoteMetadata(for: source)
                }
                await self.finishMetadataRequest(key: key, holderID: holderID, metadata: metadata)
                return metadata
            } catch {
                await self.finishMetadataRequest(key: key, holderID: holderID, metadata: nil)
                throw error
            }
        }
        holder.task = request
        return try await request.value
    }

    /// One-time conditional revalidation for an asset session — closes the
    /// residual staleness hole `If-Range` can't
    /// reach: a *complete* entry never resumes, so it never revalidates on
    /// its own. Fail-open by design: a network failure or an unexpected
    /// status leaves the cached metadata in place rather than blocking
    /// playback on a revalidation round trip succeeding.
    private func revalidatedMetadata(for source: ABMediaSource, key: String) async throws -> RemoteMetadata {
        guard let entry = index.entries[key],
              let contentLength = entry.contentLength,
              let contentType = entry.contentType
        else {
            return try await remoteMetadata(for: source)
        }
        var request = request(for: source)
        request.httpMethod = "HEAD"
        if let etag = entry.validator?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        } else if let lastModified = entry.validator?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        let cached = RemoteMetadata(contentLength: contentLength, contentType: contentType)
        guard let (_, response) = try? await httpFetcher.data(for: request) else {
            return cached
        }
        if response.statusCode == 304 {
            return cached
        }
        guard (200...299).contains(response.statusCode) else {
            return cached
        }

        let newContentLength = Self.totalLength(from: response) ?? contentLength
        let newValidator = Self.validator(from: response)
        let changed: Bool
        if let oldValidator = entry.validator, oldValidator.etag != nil || oldValidator.lastModified != nil {
            changed = newValidator != oldValidator
        } else {
            changed = newContentLength != contentLength
        }
        guard changed else { return cached }

        cancelFill(for: key)
        removeCachedEntry(for: key)
        return RemoteMetadata(
            contentLength: newContentLength,
            contentType: Self.contentType(from: response, fallback: Self.fallbackContentType(for: source))
        )
    }

    /// Runs from inside `resolvedMetadata`'s coalesced `Task`, once, on
    /// whichever outcome (success or failure) that task itself reaches —
    /// never tied to any particular caller's own await.
    private func finishMetadataRequest(key: String, holderID: UUID, metadata: RemoteMetadata?) {
        if let metadata {
            cacheMetadata(metadata, for: key)
        }
        // Only clear the slot if it's still the holder this task's call
        // installed — `removeAll()`/`reset()` (or a later caller for the
        // same key, in principle) may have already replaced or cleared it,
        // and blindly nil-ing the slot here would either resurrect a
        // coalescing gap (drop a newer, still in-flight holder) or be a
        // harmless no-op. Comparing identity by `id` makes this exact
        // instead of "last one out wins" (round4 N12).
        if pendingMetadataRequests[key]?.id == holderID {
            pendingMetadataRequests[key] = nil
        }
    }

    private func startFillIfNeeded(
        _ source: ABMediaSource,
        key: String,
        metadata: RemoteMetadata
    ) {
        guard fills[key] == nil else { return }
        fillErrors[key] = nil
        launchFill(source: source, key: key, metadata: metadata, offset: index.entries[key]?.size ?? 0)
    }

    /// Installs `fills[key]` and its backing stream/task. Shared by
    /// `startFillIfNeeded` (normal start/resume) and `prepareFill`'s resume
    /// mismatch path — the latter calls this
    /// synchronously, before throwing `FillSuperseded`, to replace the
    /// current (now-abandoned) fill with a fresh one at `offset` without an
    /// intervening suspension point.
    private func launchFill(
        source: ABMediaSource,
        key: String,
        metadata: RemoteMetadata,
        offset: Int64
    ) {
        let validator = offset > 0 ? index.entries[key]?.validator : nil
        let request = fillRequest(for: source, offset: offset, validator: validator)
        let stream = httpFetcher.stream(for: request)
        fills[key] = Task { [weak self] in
            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    guard let self else { return }
                    switch event {
                    case .response(let response):
                        try await self.prepareFill(
                            source: source,
                            key: key,
                            metadata: metadata,
                            response: response
                        )
                    case .data(let data):
                        try await self.append(data, key: key)
                    }
                }
                await self?.completeFill(key: key)
            } catch is FillSuperseded {
                // A replacement fill already installed its own state above
                // — nothing to fail or clean up for this abandoned one.
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
        source: ABMediaSource,
        key: String,
        metadata: RemoteMetadata,
        response: ABHTTPResponse
    ) throws {
        // The caller's own `Task.checkCancellation()` (at the top of its
        // event loop) only proves this fill wasn't cancelled *before* this
        // call started — cancellation can still land while this call is
        // hopping onto the actor, and nothing after that point re-checks
        // it. Without this guard, a fill cancelled during that hop would
        // resurrect an entry in the index moments after `removeAll`/`remove`
        // just cleared it, orphaning it permanently (no active fill left to
        // finish it, no error recorded to explain its absence). Checking
        // again here, before any mutation, is safe: once this passes, the
        // rest of this call runs atomically (actor isolation, no further
        // suspension) before another call can cancel it out from under us.
        try Task.checkCancellation()
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
        let priorContentLength = entry.contentLength
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
        let priorSize = entry.size
        let newTotal = Self.totalLength(from: response)

        switch response.statusCode {
        case 200:
            // Either a from-scratch fill (`priorSize == 0`), or the origin
            // ignored `Range`/`If-Range` and fell back to the full body —
            // the same "discard prefix, keep consuming this stream from
            // byte 0" recovery either way.
            if priorSize > 0 {
                try truncateFile(at: destinationURL)
                entry.size = 0
            }
        case 206:
            guard let contentRangeHeader = response.value(forHTTPHeaderField: "Content-Range"),
                  let contentRange = ABContentRange.parse(contentRangeHeader),
                  let start = contentRange.start
            else {
                throw StoreError.invalidResponse
            }
            let totalMismatch = newTotal.map { total in
                priorContentLength.map { $0 != total } ?? false
            } ?? false
            if start != priorSize || totalMismatch {
                // The origin changed underneath us (or violated the byte
                // range it was asked for) and is already streaming from an
                // offset this now-truncated file can't align with — the
                // current stream can't be rewound, so abandon it and refill
                // from scratch instead.
                try truncateFile(at: destinationURL)
                entry.size = 0
                index.upsert(entry)
                markIndexDirty()
                launchFill(source: source, key: key, metadata: metadata, offset: 0)
                throw FillSuperseded()
            }
        default:
            throw StoreError.invalidResponse
        }

        entry.contentLength = newTotal ?? metadata.contentLength
        entry.contentType = Self.contentType(
            from: response,
            fallback: Self.fallbackContentType(for: source)
        )
        guard entry.contentLength.map({ $0 <= cacheableEntryLimit }) != false else {
            throw StoreError.entryTooLarge
        }
        entry.isComplete = false
        entry.lastAccessedAt = Date()
        // Recorded from the fill response — the one that actually supplied
        // these bytes — never from a HEAD, which has no authority over
        // resume decisions for bytes it didn't produce.
        entry.validator = Self.validator(from: response)
        index.upsert(entry)
        removeCachedMetadata(for: key)
        fillResponses[key] = response
        let handle = try FileHandle(forWritingTo: destinationURL)
        try handle.seekToEnd()
        fillHandles[key] = handle
        markIndexDirty()
        resumeWaiters(for: key)
    }

    private func append(_ data: Data, key: String) throws {
        // Same rationale as the check at the top of `prepareFill`.
        try Task.checkCancellation()
        guard !data.isEmpty else { return }
        guard var entry = index.entries[key], let handle = fillHandles[key] else {
            throw StoreError.invalidResponse
        }
        guard entry.size + Int64(data.count) <= cacheableEntryLimit else {
            throw StoreError.entryTooLarge
        }
        try handle.write(contentsOf: data)
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
        closeFillHandle(for: key)
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
        closeFillHandle(for: key)
        fillErrors[key] = error
        if error == .entryTooLarge {
            removeCachedEntry(for: key)
        }
        markIndexDirty()
        try? flushIndexNow()
        resumeWaiters(for: key)
    }

    /// Sole release point for a fill's writer handle other than
    /// `completeFill`/`failFill`/`cancelFill`/`removeAll` themselves — all
    /// four are the only fill-lifecycle transitions, so every handle
    /// `prepareFill` opens is closed by exactly one of them.
    private func closeFillHandle(for key: String) {
        guard let handle = fillHandles.removeValue(forKey: key) else { return }
        try? handle.close()
    }

    private func truncateFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
    }

    private func passthrough(
        _ source: ABMediaSource,
        range: ABByteRange,
        metadata: RemoteMetadata,
        key: String
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
        let expectedCount = Int(requestedUpperBound - resolvedRange.lowerBound + 1)
        // Streamed and skip-then-collect bounded rather than
        // buffered whole via `data(for:)` — a Range-ignoring origin that
        // answers 200 with its entire body no longer forces that whole
        // body into memory; `boundedData` discards the leading
        // `resolvedRange.lowerBound` bytes as they arrive and stops once
        // `expectedCount` bytes are collected.
        let (data, response) = try await boundedData(
            for: request,
            lowerBound: resolvedRange.lowerBound,
            count: expectedCount
        )
        guard (200...299).contains(response.statusCode) else {
            throw StoreError.invalidResponse
        }
        reconcilePassthroughValidator(key: key, response: response)

        guard data.count == expectedCount else { throw StoreError.shortRead }

        return ABCachedResource(
            data: data,
            contentLength: contentLength,
            contentType: Self.contentType(from: response, fallback: Self.fallbackContentType(for: source)),
            isEndOfResource: requestedUpperBound == contentLength - 1
        )
    }

    private func rawPassthrough(
        _ source: ABMediaSource,
        range: ABByteRange,
        metadata: RemoteMetadata,
        key: String
    ) async throws -> ABCachedResource {
        var request = request(for: source)
        request.setValue(range.headerValue, forHTTPHeaderField: "Range")
        let expectedCount = range.upperBound.map {
            Int($0 - range.lowerBound + 1)
        }
        // `count: nil` (an open-ended "to end of resource" range) is capped
        // internally at `unboundedPassthroughLimit` — see `boundedData`.
        let (data, response) = try await boundedData(
            for: request,
            lowerBound: range.lowerBound,
            count: expectedCount
        )
        guard (200...299).contains(response.statusCode) else {
            throw StoreError.invalidResponse
        }
        reconcilePassthroughValidator(key: key, response: response)

        guard !data.isEmpty,
              expectedCount.map({ data.count == $0 }) != false
        else { throw StoreError.shortRead }

        return ABCachedResource(
            data: data,
            contentLength: Self.totalLength(from: response),
            contentType: Self.contentType(from: response, fallback: Self.fallbackContentType(for: source)),
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
        // Bounded to 1 byte — a HEAD-unsupported origin that
        // answers this probe with its entire body no longer pays for that
        // body in memory just to learn its length/type; `boundedData` stops
        // the transfer the instant the first byte lands.
        let (_, response) = try await boundedData(for: request, lowerBound: 0, count: 1)
        guard let metadata = Self.metadata(from: response, source: source) else {
            throw StoreError.invalidResponse
        }
        return metadata
    }

    /// Reconciles a passthrough response's validator against the entry
    /// currently on disk for `key`. `passthrough`/`rawPassthrough` serve
    /// directly from the network — each response is self-consistent on its
    /// own — but the *same playback session* can mix a passthrough range
    /// with cached-prefix ranges from a different, stale response. A
    /// mismatch here proves the cached prefix is stale. Only acts when
    /// `fills[key] == nil`: an in-flight fill already owns this key's
    /// validation, so deferring to it here avoids a new race between the
    /// two.
    private func reconcilePassthroughValidator(key: String, response: ABHTTPResponse) {
        guard fills[key] == nil,
              let cachedValidator = index.entries[key]?.validator,
              let responseValidator = Self.validator(from: response),
              responseValidator != cachedValidator
        else { return }
        removeCachedEntry(for: key)
    }

    /// Streams `request`, discarding the leading `lowerBound` bytes when
    /// the response is a Range-ignoring 200 (206 responses already start at
    /// the requested offset, so nothing is discarded), and collects at most
    /// `count` bytes — or `unboundedPassthroughLimit` when `count` is nil —
    /// before ending the transfer. Bounds peak memory to
    /// `count`/`unboundedPassthroughLimit` regardless of how large the
    /// origin's actual response body is. Ending the `for try await` loop
    /// early deinitializes the stream's iterator, which triggers
    /// `onTermination` on the underlying fetcher (see
    /// `ABURLSessionHTTPFetcher.stream(for:)`) and cancels the in-flight
    /// network task — the remaining body is never transferred.
    private func boundedData(
        for request: URLRequest,
        lowerBound: Int64,
        count: Int?
    ) async throws -> (Data, ABHTTPResponse) {
        let stream = httpFetcher.stream(for: request)
        var response: ABHTTPResponse?
        var collected = Data()
        var skipRemaining: Int64 = 0
        let collectLimit = count.map(Int64.init) ?? unboundedPassthroughLimit

        eventLoop: for try await event in stream {
            switch event {
            case .response(let receivedResponse):
                guard (200...299).contains(receivedResponse.statusCode) else {
                    return (Data(), receivedResponse)
                }
                response = receivedResponse
                skipRemaining = receivedResponse.statusCode == 200 ? lowerBound : 0
            case .data(var chunk):
                guard response != nil else { continue }
                if skipRemaining > 0 {
                    let skipCount = Int(Swift.min(skipRemaining, Int64(chunk.count)))
                    chunk.removeFirst(skipCount)
                    skipRemaining -= Int64(skipCount)
                    guard !chunk.isEmpty else { continue }
                }
                let remainingCapacity = collectLimit - Int64(collected.count)
                guard remainingCapacity > 0 else { break eventLoop }
                if Int64(chunk.count) > remainingCapacity {
                    collected.append(chunk.prefix(Int(remainingCapacity)))
                } else {
                    collected.append(chunk)
                }
                if Int64(collected.count) >= collectLimit { break eventLoop }
            }
        }
        guard let response else { throw StoreError.invalidResponse }
        if count == nil, Int64(collected.count) >= unboundedPassthroughLimit {
            throw StoreError.entryTooLarge
        }
        return (collected, response)
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

    private func fillRequest(for source: ABMediaSource, offset: Int64, validator: ABCacheValidator?) -> URLRequest {
        var request = request(for: source)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            // RFC 9110 forbids weak comparison in range requests — only a
            // strong `ETag` is sent as `If-Range`; a weak one is stored
            // (for revalidation's equality check) but never sent here.
            if let etag = validator?.etag, validator?.isStrongETag == true {
                request.setValue(etag, forHTTPHeaderField: "If-Range")
            } else if let lastModified = validator?.lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Range")
            }
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
        closeFillHandle(for: key)
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

    /// Fixed cap for a passthrough read whose length isn't
    /// known up front (`rawPassthrough`'s "to end of resource" case, and
    /// the metadata GET probe) — bounds peak memory the same way
    /// `passthroughChunkSize` bounds a length-bounded passthrough.
    private var unboundedPassthroughLimit: Int64 { 8 * 1_024 * 1_024 }

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
           let parsed = ABContentRange.parse(contentRange) {
            return parsed.total
        }
        return response.statusCode == 206 ? nil : response.expectedContentLength
    }

    /// Captures the validator carried by a response, if any — used both to
    /// record what a fill response actually supplied and to compare
    /// against on session-start revalidation. `nil` when
    /// the origin sent neither header, distinguishing "no validator" from
    /// "validator known to be absent/empty".
    private static func validator(from response: ABHTTPResponse) -> ABCacheValidator? {
        let etag = response.value(forHTTPHeaderField: "ETag")
        let lastModified = response.value(forHTTPHeaderField: "Last-Modified")
        guard etag != nil || lastModified != nil else { return nil }
        return ABCacheValidator(etag: etag, lastModified: lastModified)
    }

    /// A server-declared MIME type wins unless it only names a generic
    /// supertype (`public.data`/`public.content`/`public.item`) that the
    /// URL-extension-derived `fallback` refines — e.g. an origin answering
    /// `application/octet-stream` for a `.mp4` URL shouldn't shadow the
    /// extension's more specific guess. A server naming a
    /// *specific* type is trusted over the extension guess in every other
    /// case.
    private static func contentType(from response: ABHTTPResponse, fallback: String) -> String {
        guard let mimeType = response.mimeType else { return fallback }
        let sanitizedMimeType = mimeType.split(separator: ";").first.map(String.init) ?? mimeType
        guard let responseType = UTType(mimeType: sanitizedMimeType.trimmingCharacters(in: .whitespaces)) else {
            return fallback
        }
        guard let fallbackType = UTType(fallback) else { return responseType.identifier }
        let genericSupertypes: Set<UTType> = [.data, .content, .item]
        if genericSupertypes.contains(responseType),
           fallbackType.conforms(to: responseType),
           fallbackType != responseType {
            return fallbackType.identifier
        }
        return responseType.identifier
    }

    private static func fallbackContentType(for source: ABMediaSource) -> String {
        guard !source.url.pathExtension.isEmpty,
              let type = UTType(filenameExtension: source.url.pathExtension)
        else { return UTType.data.identifier }
        return type.identifier
    }
}
