import ABPlayerKit
@preconcurrency import AVFoundation
import Foundation

final class ABResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
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
                let dataRequest = request.dataRequest
                let lowerBound = dataRequest?.currentOffset ?? 0
                let upperBound: Int64?
                if let dataRequest, !dataRequest.requestsAllDataToEndOfResource {
                    upperBound = lowerBound + Int64(dataRequest.requestedLength) - 1
                } else {
                    upperBound = nil
                }
                let resource = try await store.load(
                    source,
                    range: ABByteRange(lowerBound: lowerBound, upperBound: upperBound)
                )
                guard !Task.isCancelled, !request.isCancelled else { return }
                if let contentInformationRequest = request.contentInformationRequest {
                    let allowedTypes = contentInformationRequest.allowedContentTypes ?? []
                    contentInformationRequest.contentType = allowedTypes.isEmpty
                        || allowedTypes.contains(resource.contentType)
                        ? resource.contentType
                        : allowedTypes[0]
                    contentInformationRequest.contentLength = resource.contentLength
                    contentInformationRequest.isByteRangeAccessSupported = true
                }
                dataRequest?.respond(with: resource.data)
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
