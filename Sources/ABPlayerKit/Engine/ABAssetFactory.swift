@preconcurrency import AVFoundation

/// The single seam between core and the Cache target (Phase 3): swapping the
/// factory lets a cache intercept asset creation without the core knowing
/// caching exists.
public protocol ABAssetFactory: Sendable {
    func makeAsset(for source: ABMediaSource) -> AVURLAsset
}

public struct ABDefaultAssetFactory: ABAssetFactory, Sendable {
    public init() {}

    public func makeAsset(for source: ABMediaSource) -> AVURLAsset {
        var options: [String: Any] = [:]
        if !source.httpHeaders.isEmpty {
            // "AVURLAssetHTTPHeaderFieldsKey" is AVFoundation's documented
            // options-dictionary key for custom HTTP headers. It's declared
            // as a plain `NSString * const` in the Objective-C headers and
            // never got a Swift-visible symbol, so referencing it by its
            // literal string (rather than a private/undocumented header
            // field trick) is the official, documented path.
            options["AVURLAssetHTTPHeaderFieldsKey"] = source.httpHeaders
        }
        return AVURLAsset(url: source.url, options: options)
    }
}
