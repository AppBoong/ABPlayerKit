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
    /// Stored for forward compatibility but not applied by the Phase 2 core.
    /// Header support arrives through the Cache target's resource loader in
    /// Phase 3.
    public var httpHeaders: [String: String]

    /// - Parameters:
    ///   - url: The remote or local media URL.
    ///   - kind: Explicit kind. When `nil`, inferred from the URL's extension:
    ///     `.m3u8` → `.hls`, anything else → `.progressive`.
    ///   - httpHeaders: HTTP headers retained with the source and applied by
    ///     supporting asset factories such as `ABPlayerKitCache`.
    public init(url: URL, kind: Kind? = nil, httpHeaders: [String: String] = [:]) {
        self.url = url
        self.kind = kind ?? Self.inferredKind(for: url)
        self.httpHeaders = httpHeaders
    }

    private static func inferredKind(for url: URL) -> Kind {
        url.pathExtension.lowercased() == "m3u8" ? .hls : .progressive
    }
}
