import ABPlayerKit
@preconcurrency import AVFoundation
import Foundation

public final class ABMediaCache: Sendable {
    private let store: ABCacheStore

    public init(configuration: ABCacheConfiguration = .init()) throws {
        self.store = try ABCacheStore(configuration: configuration)
    }

    public func makeAssetFactory(
        hlsPrefetcher: ABHLSPrefetcher? = nil
    ) -> any ABAssetFactory {
        ABCacheAssetFactory(store: store, hlsPrefetcher: hlsPrefetcher)
    }

    public func totalSize() async -> Int64 {
        await store.totalSize()
    }

    public func evictionShortfallCount() async -> Int {
        await store.evictionShortfallCount()
    }

    public func remove(_ source: ABMediaSource) async {
        try? await store.remove(source)
    }

    public func removeAll() async {
        try? await store.removeAll()
    }
}

// Factory mutation is protected by its lock and AVFoundation uses one shared serial delegate queue.
private final class ABCacheAssetFactory: ABAssetFactory, @unchecked Sendable {
    private struct RetainedDelegate {
        weak var asset: AVURLAsset?
        let delegate: ABResourceLoaderDelegate
    }

    private let store: ABCacheStore
    private let hlsPrefetcher: ABHLSPrefetcher?
    private let delegateQueue = DispatchQueue(label: "ABPlayerKitCache.ResourceLoader")
    private let lock = NSLock()
    private var retainedDelegates: [RetainedDelegate] = []

    init(store: ABCacheStore, hlsPrefetcher: ABHLSPrefetcher?) {
        self.store = store
        self.hlsPrefetcher = hlsPrefetcher
    }

    func makeAsset(for source: ABMediaSource) -> AVURLAsset {
        guard source.kind == .progressive else {
            return hlsPrefetcher?.localAsset(for: source) ?? AVURLAsset(url: source.url)
        }

        guard var components = URLComponents(url: source.url, resolvingAgainstBaseURL: false) else {
            return AVURLAsset(url: source.url)
        }
        components.scheme = "ab-cache"
        guard let cacheURL = components.url else { return AVURLAsset(url: source.url) }

        let asset = AVURLAsset(url: cacheURL)
        let delegate = ABResourceLoaderDelegate(source: source, store: store)
        asset.resourceLoader.setDelegate(delegate, queue: delegateQueue)

        lock.lock()
        retainedDelegates.removeAll { $0.asset == nil }
        retainedDelegates.append(RetainedDelegate(asset: asset, delegate: delegate))
        lock.unlock()
        return asset
    }
}
