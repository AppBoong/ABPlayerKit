import ABPlayerKit
@preconcurrency import AVFoundation
import Foundation

// AVFoundation invokes this delegate on the configured serial queue; mutable task state is lock-protected.
final class ABResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    // AVAssetResourceLoadingRequest is confined to the delegate task and AVFoundation's serial callback queue.
    private final class LoadingRequestBox: @unchecked Sendable {
        let request: AVAssetResourceLoadingRequest

        init(_ request: AVAssetResourceLoadingRequest) {
            self.request = request
        }
    }

    private let source: ABMediaSource
    private let store: ABCacheStore
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

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
        let identifier = ObjectIdentifier(loadingRequest)
        let requestBox = LoadingRequestBox(loadingRequest)
        let task = Task { [source, store, weak self] in
            defer { self?.removeTask(identifier) }
            do {
                let request = requestBox.request
                let metadata = try await store.metadata(for: source)
                guard !Task.isCancelled, !request.isCancelled else { return }
                if let contentInformationRequest = request.contentInformationRequest {
                    contentInformationRequest.contentType = metadata.contentType
                    if let contentLength = metadata.contentLength {
                        contentInformationRequest.contentLength = contentLength
                        contentInformationRequest.isByteRangeAccessSupported = true
                    } else {
                        contentInformationRequest.isByteRangeAccessSupported = false
                    }
                }

                guard let dataRequest = request.dataRequest else {
                    request.finishLoading()
                    return
                }
                var currentOffset = dataRequest.currentOffset
                let upperBound: Int64?
                if !dataRequest.requestsAllDataToEndOfResource {
                    upperBound = currentOffset + Int64(dataRequest.requestedLength) - 1
                } else {
                    upperBound = nil
                }
                guard let contentLength = metadata.contentLength else {
                    let resource = try await store.load(
                        source,
                        range: ABByteRange(lowerBound: currentOffset, upperBound: upperBound)
                    )
                    guard !Task.isCancelled, !request.isCancelled else { return }
                    dataRequest.respond(with: resource.data)
                    request.finishLoading()
                    return
                }
                let requiredEndOffset = Swift.min(
                    upperBound ?? (contentLength - 1),
                    contentLength - 1
                )

                while currentOffset <= requiredEndOffset {
                    let resource = try await store.load(
                        source,
                        range: ABByteRange(
                            lowerBound: currentOffset,
                            upperBound: requiredEndOffset
                        )
                    )
                    guard !Task.isCancelled, !request.isCancelled else { return }
                    guard !resource.data.isEmpty else {
                        throw ABCacheStore.StoreError.shortRead
                    }
                    dataRequest.respond(with: resource.data)
                    currentOffset += Int64(resource.data.count)
                }
                request.finishLoading()
            } catch {
                guard !Task.isCancelled, !requestBox.request.isCancelled else { return }
                requestBox.request.finishLoading(with: error)
            }
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
