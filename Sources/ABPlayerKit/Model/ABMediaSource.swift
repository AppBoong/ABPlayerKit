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
    public var httpHeaders: [String: String]

    /// - Parameter kind: Explicit kind. When `nil`, inferred from the URL's
    ///   extension: `.m3u8` → `.hls`, anything else → `.progressive`.
    public init(url: URL, kind: Kind? = nil, httpHeaders: [String: String] = [:]) {
        self.url = url
        self.kind = kind ?? Self.inferredKind(for: url)
        self.httpHeaders = httpHeaders
    }

    private static func inferredKind(for url: URL) -> Kind {
        url.pathExtension.lowercased() == "m3u8" ? .hls : .progressive
    }
}
