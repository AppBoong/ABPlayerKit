import Foundation

public struct ABCacheConfiguration: Sendable, Equatable {
    public var directory: URL
    public var maximumDiskSize: Int64
    public var maximumEntrySize: Int64

    public init(
        directory: URL? = nil,
        maximumDiskSize: Int64 = 512 * 1_024 * 1_024,
        maximumEntrySize: Int64 = 64 * 1_024 * 1_024
    ) {
        self.directory = directory ?? Self.defaultDirectory
        self.maximumDiskSize = maximumDiskSize
        self.maximumEntrySize = maximumEntrySize
    }

    private static var defaultDirectory: URL {
        let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return cachesDirectory.appendingPathComponent("ABPlayerKitCache", isDirectory: true)
    }
}
