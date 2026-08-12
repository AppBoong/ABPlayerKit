import ABPlayerKit
@preconcurrency import AVFoundation
import Foundation

// AVFoundation invokes this delegate on the configured serial queue; mutable task state is lock-protected.
final class ABResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private let source: ABMediaSource
    private let store: ABCacheStore
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// One asset session per delegate instance (`ABCacheAssetFactory`
    /// creates a fresh delegate per `makeAsset(for:)` call) — the first
    /// loading request this delegate ever services marks the session for
    /// revalidation; later requests on the same
    /// delegate are the same session and don't re-mark.
    private var hasBegunSession = false

    init(source: ABMediaSource, store: ABCacheStore) {
        self.source = source
        self.store = store
    }

    deinit {
        lock.lock()
        let retainedTasks = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        for task in retainedTasks {
            task.cancel()
        }
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard loadingRequest.request.url?.scheme == "ab-cache" else { return false }

        lock.lock()
        let isFirstSessionRequest = !hasBegunSession
        hasBegunSession = true
        lock.unlock()
        if isFirstSessionRequest {
            // Synchronous, not inside the `Task` below — a loading request
            // spawned from that `Task` must never be able to read stale
            // metadata before this session's revalidation claim is even
            // registered.
            store.beginAssetSession(for: source)
        }

        let identifier = ObjectIdentifier(loadingRequest)
        let adapter = ABAVLoadingRequestAdapter(loadingRequest)
        let task = Task { [source, store, weak self] in
            await ABLoadingRequestServicer.service(adapter, source: source, store: store)
            self?.removeTask(identifier)
        }
        lock.lock()
        tasks[identifier] = task
        lock.unlock()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let identifier = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: identifier)
        lock.unlock()
        task?.cancel()
    }

    private func removeTask(_ identifier: ObjectIdentifier) {
        lock.lock()
        tasks[identifier] = nil
        lock.unlock()
    }
}
