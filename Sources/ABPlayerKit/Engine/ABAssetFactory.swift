@preconcurrency import AVFoundation

/// The single seam between core and the Cache target: swapping the
/// factory lets a cache intercept asset creation without the core knowing
/// caching exists.
public protocol ABAssetFactory: Sendable {
    func makeAsset(for source: ABMediaSource) -> AVURLAsset
}

public struct ABDefaultAssetFactory: ABAssetFactory, Sendable {
    public init() {}

    /// Applies `source.httpHeaders` via `AVURLAssetHTTPHeaderFieldsKey`
    /// when non-empty. This is a documented-by-convention `AVFoundation`
    /// key, not a formally documented public API, and it only covers the
    /// asset's *initial* request — HLS sub-requests (segments, keys,
    /// alternate renditions) aren't guaranteed to carry it. `ABPlayerKitCache`'s
    /// resource loader is the supported path for headers that must reach
    /// every HLS sub-request.
    public func makeAsset(for source: ABMediaSource) -> AVURLAsset {
        guard !source.httpHeaders.isEmpty else {
            return AVURLAsset(url: source.url)
        }
        return AVURLAsset(
            url: source.url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": source.httpHeaders]
        )
    }
}
