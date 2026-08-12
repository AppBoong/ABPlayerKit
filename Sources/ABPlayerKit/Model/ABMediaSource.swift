import Foundation

/// Identifies a piece of media to play. Value type — safe to compare, hash, and
/// pass across actor boundaries.
public struct ABMediaSource: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case hls
        case progressive
    }

    public let url: URL
    public let kind: Kind
    /// Applied by `ABDefaultAssetFactory` to the asset's initial request via
    /// `AVURLAssetHTTPHeaderFieldsKey` — a real but undocumented
    /// `AVFoundation` option, not guaranteed to reach HLS sub-requests
    /// (segments, keys, alternate renditions). `ABPlayerKitCache`'s
    /// resource loader is the supported path when headers must reach every
    /// HLS sub-request.
    public var httpHeaders: [String: String]

    /// - Parameters:
    ///   - url: The remote or local media URL.
    ///   - kind: Explicit kind. When `nil`, inferred from the URL's extension:
    ///     `.m3u8` → `.hls`, anything else → `.progressive`.
    ///   - httpHeaders: HTTP headers retained with the source and applied to
    ///     the asset's initial request by `ABDefaultAssetFactory`. HLS
    ///     sub-requests need `ABPlayerKitCache`'s resource loader instead.
    public init(url: URL, kind: Kind? = nil, httpHeaders: [String: String] = [:]) {
        self.url = url
        self.kind = kind ?? Self.inferredKind(for: url)
        self.httpHeaders = httpHeaders
    }

    private static func inferredKind(for url: URL) -> Kind {
        url.pathExtension.lowercased() == "m3u8" ? .hls : .progressive
    }
}
