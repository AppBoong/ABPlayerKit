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
            // Official AVFoundation options key — not the unofficial
            // `AVURLAssetOptionsKeyHTTPHeaderFields`-style strings some code
            // uses.
            options[AVURLAssetHTTPHeaderFieldsKey] = source.httpHeaders
        }
        return AVURLAsset(url: source.url, options: options)
    }
}
