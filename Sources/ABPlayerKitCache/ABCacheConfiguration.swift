import Foundation

public struct ABCacheConfiguration: Sendable, Equatable {
    public var directory: URL
    public var maximumDiskSize: Int64
    public var maximumEntrySize: Int64
    /// How far ahead of the cache's linear fill prefix a requested offset
    /// may sit before `ABCacheStore.load` gives up waiting for the fill to
    /// catch up and serves the request via a direct network passthrough
    /// instead. Bounds worst-case time-to-first-byte for a distant seek
    /// against a non-faststart file to roughly one network round trip
    /// instead of "however long the linear fill takes to reach that byte"
    /// (round3 Phase4 WP11; sparse-range caching itself remains out of
    /// scope — this is a latency fallback, not a cache strategy change).
    ///
    /// Values `<= 0` mean *every* request passes through directly —
    /// `resolvedRange.lowerBound - currentPrefixEnd >= threshold` is then
    /// always true, including at offset 0 against an empty prefix. This is
    /// the inverse of what "0" might intuitively suggest ("always serve
    /// from cache"), so pass a positive value unless a fully
    /// cache-disabled passthrough mode is actually what's wanted
    /// (round4 review N10).
    public var passthroughGapThreshold: Int64

    public init(
        directory: URL? = nil,
        maximumDiskSize: Int64 = 512 * 1_024 * 1_024,
        maximumEntrySize: Int64 = 64 * 1_024 * 1_024,
        passthroughGapThreshold: Int64 = 2 * 1_024 * 1_024
    ) {
        self.directory = directory ?? Self.makeDefaultDirectory()
        self.maximumDiskSize = maximumDiskSize
        self.maximumEntrySize = maximumEntrySize
        self.passthroughGapThreshold = passthroughGapThreshold
    }

    private static func makeDefaultDirectory() -> URL {
        let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return cachesDirectory.appendingPathComponent("ABPlayerKitCache", isDirectory: true)
    }
}
