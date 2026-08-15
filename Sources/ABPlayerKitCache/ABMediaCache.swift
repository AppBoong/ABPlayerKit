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

    /// The cache's size as the index accounts for it — the sum of every
    /// entry's recorded length, partial fills included.
    ///
    /// Not a measurement of the directory, so it can drift from the real
    /// on-disk footprint. Measure the directory itself if that exact number
    /// is what matters.
    public func totalSize() async -> Int64 {
        await store.totalSize()
    }

    /// How many eviction passes finished still over
    /// ``ABCacheConfiguration/maximumDiskSize``.
    ///
    /// Not a count of evicted entries. It rises when everything left is
    /// pinned by an active reader or an in-flight fill, so a persistently
    /// non-zero value means the working set genuinely does not fit rather
    /// than that eviction is broken. ``removeAll()`` resets it to zero.
    public func evictionShortfallCount() async -> Int {
        await store.evictionShortfallCount()
    }

    /// Deletes the cached entry for `source`.
    ///
    /// Errors are swallowed — a failed delete is indistinguishable from a
    /// successful one here. A read already in flight for this key is not
    /// failed: it continues over the network for the rest of that read. The
    /// invalidation is also store-wide rather than per-key, so removing one
    /// source can push an unrelated concurrently-filling source through the
    /// network for one read.
    public func remove(_ source: ABMediaSource) async {
        try? await store.remove(source)
    }

    /// Deletes every cached entry and resets
    /// ``evictionShortfallCount()``.
    ///
    /// Errors are swallowed, and reads already in flight keep going over the
    /// network rather than failing — same delete semantics as
    /// ``remove(_:)``.
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
