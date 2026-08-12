import ABPlayerKit
@preconcurrency import AVFoundation
import Foundation

/// Abstracts `AVAssetResourceLoadingRequest` — it has no
/// public initializer, so tests drive `ABLoadingRequestServicer` against a
/// fake conforming to this protocol instead of a real `AVURLAsset`/
/// `AVAssetResourceLoader`, which would depend on real media payloads and
/// AVFoundation timing.
protocol ABLoadingRequesting: AnyObject {
    var isCancelled: Bool { get }
    var contentInformation: (any ABLoadingContentInformation)? { get }
    var dataRequest: (any ABLoadingDataRequesting)? { get }
    func finishLoading()
    func finishLoading(with error: (any Error)?)
}

protocol ABLoadingContentInformation: AnyObject {
    var contentType: String? { get set }
    var contentLength: Int64 { get set }
    var isByteRangeAccessSupported: Bool { get set }
}

protocol ABLoadingDataRequesting: AnyObject {
    var currentOffset: Int64 { get }
    var requestedLength: Int { get }
    var requestsAllDataToEndOfResource: Bool { get }
    func respond(with data: Data)
}

/// Services one loading request end to end — resolves metadata, populates
/// `contentInformation`, and streams `dataRequest`'s range from the store in
/// cache-sized pieces. Extracted from `ABResourceLoaderDelegate` as a pure
/// function of the protocol above so it can run against a fake request in
/// tests instead of a real `AVAssetResourceLoadingRequest`.
enum ABLoadingRequestServicer {
    static func service(
        _ request: any ABLoadingRequesting,
        source: ABMediaSource,
        store: ABCacheStore
    ) async {
        do {
            let metadata = try await store.metadata(for: source)
            guard !Task.isCancelled, !request.isCancelled else { return }
            if let contentInformation = request.contentInformation {
                contentInformation.contentType = metadata.contentType
                if let contentLength = metadata.contentLength {
                    contentInformation.contentLength = contentLength
                    contentInformation.isByteRangeAccessSupported = true
                } else {
                    contentInformation.isByteRangeAccessSupported = false
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
            guard !Task.isCancelled, !request.isCancelled else { return }
            request.finishLoading(with: error)
        }
    }
}

private final class ABAVLoadingContentInformationAdapter: ABLoadingContentInformation {
    private let request: AVAssetResourceLoadingContentInformationRequest

    init(_ request: AVAssetResourceLoadingContentInformationRequest) {
        self.request = request
    }

    var contentType: String? {
        get { request.contentType }
        set { request.contentType = newValue }
    }

    var contentLength: Int64 {
        get { request.contentLength }
        set { request.contentLength = newValue }
    }

    var isByteRangeAccessSupported: Bool {
        get { request.isByteRangeAccessSupported }
        set { request.isByteRangeAccessSupported = newValue }
    }
}

private final class ABAVLoadingDataRequestAdapter: ABLoadingDataRequesting {
    private let request: AVAssetResourceLoadingDataRequest

    init(_ request: AVAssetResourceLoadingDataRequest) {
        self.request = request
    }

    var currentOffset: Int64 { request.currentOffset }
    var requestedLength: Int { request.requestedLength }
    var requestsAllDataToEndOfResource: Bool { request.requestsAllDataToEndOfResource }

    func respond(with data: Data) {
        request.respond(with: data)
    }
}

// AVAssetResourceLoadingRequest is confined to the delegate task and AVFoundation's serial callback queue.
final class ABAVLoadingRequestAdapter: ABLoadingRequesting, @unchecked Sendable {
    let request: AVAssetResourceLoadingRequest

    init(_ request: AVAssetResourceLoadingRequest) {
        self.request = request
    }

    var isCancelled: Bool { request.isCancelled }

    var contentInformation: (any ABLoadingContentInformation)? {
        request.contentInformationRequest.map(ABAVLoadingContentInformationAdapter.init)
    }

    var dataRequest: (any ABLoadingDataRequesting)? {
        request.dataRequest.map(ABAVLoadingDataRequestAdapter.init)
    }

    func finishLoading() {
        request.finishLoading()
    }

    func finishLoading(with error: (any Error)?) {
        request.finishLoading(with: error)
    }
}
