import ABPlayerKit
@preconcurrency import AVFoundation
@preconcurrency import Foundation

enum ABHLSDownloadResult: Sendable {
    case success(URL)
    case failure
}

typealias ABHLSDownloadStart = @Sendable (
    UUID,
    ABMediaSource,
    Double?,
    @escaping @Sendable (ABHLSDownloadResult) -> Void
) -> (@Sendable () -> Void)?

public struct ABHLSPrefetchHandle: Sendable, Hashable {
    private let id: UUID
    private let cancellation: @Sendable (UUID) -> Void

    init(id: UUID, cancellation: @escaping @Sendable (UUID) -> Void) {
        self.id = id
        self.cancellation = cancellation
    }

    public func cancel() {
        cancellation(id)
    }

    public static func == (lhs: ABHLSPrefetchHandle, rhs: ABHLSPrefetchHandle) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// All mutable bookkeeping lives in the lock-protected state object; closures are Sendable.
public final class ABHLSPrefetcher: @unchecked Sendable {
    private let state: ABHLSPrefetchState
    private let startDownload: ABHLSDownloadStart
    private let invalidateDownload: @Sendable () -> Void
    private let sessionOwner: AnyObject?

    public init(configuration: ABCacheConfiguration = .init()) {
        let state = ABHLSPrefetchState(configuration: configuration)
        let coordinator = ABHLSDownloadCoordinator.shared
        self.state = state
        self.sessionOwner = coordinator
        self.invalidateDownload = {
            coordinator.invalidate()
        }
        self.startDownload = { id, source, bitrate, completion in
            coordinator.start(
                id: id,
                source: source,
                minimumRequiredMediaBitrate: bitrate,
                completion: completion
            )
        }
    }

    init(
        configuration: ABCacheConfiguration,
        startDownload: @escaping ABHLSDownloadStart,
        invalidateDownload: @escaping @Sendable () -> Void = {}
    ) {
        self.state = ABHLSPrefetchState(configuration: configuration)
        self.startDownload = startDownload
        self.invalidateDownload = invalidateDownload
        self.sessionOwner = nil
    }

    @discardableResult
    public func prefetch(
        _ source: ABMediaSource,
        minimumRequiredMediaBitrate: Double? = nil
    ) -> ABHLSPrefetchHandle {
        let id = UUID()
        guard source.kind == .hls else {
            return ABHLSPrefetchHandle(id: id) { _ in }
        }

        let key = ABCacheKey.derive(from: source)
        state.reserve(id: id, key: key)
        let cancellation = startDownload(id, source, minimumRequiredMediaBitrate) { [state] result in
            state.complete(id: id, result: result)
        }
        if let cancellation {
            state.installCancellation(cancellation, for: id)
        } else {
            state.complete(id: id, result: .failure)
        }

        return ABHLSPrefetchHandle(id: id) { [state] id in
            state.cancel(id: id)
        }
    }

    public func cancelAll() {
        state.cancelAll()
    }

    public func invalidate() {
        state.cancelAll()
        invalidateDownload()
    }

    public func localAsset(for source: ABMediaSource) -> AVURLAsset? {
        guard source.kind == .hls,
              let url = state.localURL(for: ABCacheKey.derive(from: source))
        else { return nil }
        return AVURLAsset(url: url)
    }

    public func remove(_ source: ABMediaSource) async {
        state.remove(key: ABCacheKey.derive(from: source))
    }

    var activeTaskCount: Int {
        state.activeTaskCount
    }
}

// Prefetch task and location maps are shared only through lock-protected methods.
private final class ABHLSPrefetchState: @unchecked Sendable {
    private struct ActiveTask {
        let key: String
        var cancellation: (@Sendable () -> Void)?
    }

    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let indexURL: URL
    private let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    private var activeTasks: [UUID: ActiveTask] = [:]
    private var localURLs: [String: URL]

    init(configuration: ABCacheConfiguration) {
        let containerHomeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.indexURL = configuration.directory.appendingPathComponent("hls-index.json")
        try? fileManager.createDirectory(
            at: configuration.directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        if let data = try? Data(contentsOf: indexURL),
           let paths = try? JSONDecoder().decode([String: String].self, from: data) {
            self.localURLs = paths.compactMapValues { path in
                Self.localURL(fromPersistedPath: path, homeDirectory: containerHomeDirectory)
            }
        } else {
            self.localURLs = [:]
        }
        removeMissingLocations()
        persistIndex()
    }

    var activeTaskCount: Int {
        lock.lock()
        let count = activeTasks.count
        lock.unlock()
        return count
    }

    func reserve(id: UUID, key: String) {
        lock.lock()
        let duplicateIDs = activeTasks.filter { $0.value.key == key }.map(\.key)
        let duplicateCancellations = duplicateIDs.compactMap { activeTasks.removeValue(forKey: $0)?.cancellation }
        activeTasks[id] = ActiveTask(key: key, cancellation: nil)
        lock.unlock()
        for cancellation in duplicateCancellations {
            cancellation()
        }
    }

    func installCancellation(_ cancellation: @escaping @Sendable () -> Void, for id: UUID) {
        lock.lock()
        if activeTasks[id] != nil {
            activeTasks[id]?.cancellation = cancellation
            lock.unlock()
        } else {
            lock.unlock()
            cancellation()
        }
    }

    func complete(id: UUID, result: ABHLSDownloadResult) {
        lock.lock()
        guard let task = activeTasks.removeValue(forKey: id) else {
            lock.unlock()
            return
        }
        if case .success(let url) = result {
            localURLs[task.key] = url
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            persistIndexLocked()
        }
        lock.unlock()
    }

    func cancel(id: UUID) {
        lock.lock()
        let cancellation = activeTasks.removeValue(forKey: id)?.cancellation
        lock.unlock()
        cancellation?()
    }

    func cancelAll() {
        lock.lock()
        let cancellations = activeTasks.values.compactMap(\.cancellation)
        activeTasks.removeAll()
        lock.unlock()
        for cancellation in cancellations {
            cancellation()
        }
    }

    func localURL(for key: String) -> URL? {
        lock.lock()
        guard let url = localURLs[key], fileManager.fileExists(atPath: url.path) else {
            localURLs[key] = nil
            persistIndexLocked()
            lock.unlock()
            return nil
        }
        lock.unlock()
        return url
    }

    func remove(key: String) {
        lock.lock()
        let matchingIDs = activeTasks.filter { $0.value.key == key }.map(\.key)
        let cancellations = matchingIDs.compactMap { activeTasks.removeValue(forKey: $0)?.cancellation }
        let url = localURLs.removeValue(forKey: key)
        persistIndexLocked()
        lock.unlock()

        for cancellation in cancellations {
            cancellation()
        }
        if let url {
            try? fileManager.removeItem(at: url)
        }
    }

    private func removeMissingLocations() {
        localURLs = localURLs.filter { fileManager.fileExists(atPath: $0.value.path) }
    }

    private func persistIndex() {
        lock.lock()
        persistIndexLocked()
        lock.unlock()
    }

    private func persistIndexLocked() {
        let paths = localURLs.compactMapValues {
            Self.homeRelativePath(for: $0, homeDirectory: homeDirectory)
        }
        guard let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: indexURL, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: indexURL.path
        )
    }

    private static func localURL(fromPersistedPath path: String, homeDirectory: URL) -> URL? {
        if path.hasPrefix("/") {
            return homeRelativePath(
                for: URL(fileURLWithPath: path),
                homeDirectory: homeDirectory
            ).map {
                URL(fileURLWithPath: $0, relativeTo: homeDirectory).standardizedFileURL
            }
        }
        return URL(fileURLWithPath: path, relativeTo: homeDirectory).standardizedFileURL
    }

    private static func homeRelativePath(for url: URL, homeDirectory: URL) -> String? {
        let homePath = homeDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return nil }
        return String(path.dropFirst(homePath.count + 1))
    }
}

enum ABHLSBackgroundSession {
    static let identifier = "ABPlayerKitCache.HLS"
}

// AVAssetDownloadURLSession callbacks may arrive concurrently; jobs and session creation are lock-protected.
private final class ABHLSDownloadCoordinator: NSObject, AVAssetDownloadDelegate, @unchecked Sendable {
    static let shared = ABHLSDownloadCoordinator()

    private struct Job {
        let id: UUID
        let completion: @Sendable (ABHLSDownloadResult) -> Void
        var location: URL?
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private var session: AVAssetDownloadURLSession?
    private var isInvalidating = false

    func invalidate() {
        lock.lock()
        guard let session, !isInvalidating else {
            lock.unlock()
            return
        }
        isInvalidating = true
        lock.unlock()
        session.finishTasksAndInvalidate()
    }

    private func downloadSession() -> AVAssetDownloadURLSession? {
        lock.lock()
        guard !isInvalidating else {
            lock.unlock()
            return nil
        }
        if let session {
            lock.unlock()
            return session
        }
        let configuration = URLSessionConfiguration.background(
            withIdentifier: ABHLSBackgroundSession.identifier
        )
        let session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: nil
        )
        self.session = session
        lock.unlock()
        return session
    }

    func start(
        id: UUID,
        source: ABMediaSource,
        minimumRequiredMediaBitrate: Double?,
        completion: @escaping @Sendable (ABHLSDownloadResult) -> Void
    ) -> (@Sendable () -> Void)? {
        let asset = AVURLAsset(url: source.url)
        let downloadConfiguration = AVAssetDownloadConfiguration(
            asset: asset,
            title: ABCacheKey.derive(from: source)
        )
        if let minimumRequiredMediaBitrate {
            let predicate = NSPredicate(
                format: "averageBitRate >= %f",
                minimumRequiredMediaBitrate
            )
            downloadConfiguration.primaryContentConfiguration.variantQualifiers = [
                AVAssetVariantQualifier(predicate: predicate)
            ]
        }
        guard let session = downloadSession() else {
            completion(.failure)
            return nil
        }
        let task = session.makeAssetDownloadTask(
            downloadConfiguration: downloadConfiguration
        )
        lock.lock()
        jobs[task.taskIdentifier] = Job(id: id, completion: completion, location: nil)
        lock.unlock()
        task.resume()
        return { task.cancel() }
    }

    @available(iOS, introduced: 10.0, deprecated: 18.0)
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        store(location: location, for: assetDownloadTask.taskIdentifier)
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        store(location: location, for: assetDownloadTask.taskIdentifier)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        lock.lock()
        let job = jobs.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let job else { return }
        if error == nil, let location = job.location {
            job.completion(.success(location))
        } else {
            job.completion(.failure)
        }
    }

    func urlSession(
        _ session: URLSession,
        didBecomeInvalidWithError error: (any Error)?
    ) {
        lock.lock()
        if self.session === session {
            self.session = nil
            isInvalidating = false
        }
        lock.unlock()
    }

    private func store(location: URL, for taskIdentifier: Int) {
        lock.lock()
        jobs[taskIdentifier]?.location = location
        lock.unlock()
    }
}
