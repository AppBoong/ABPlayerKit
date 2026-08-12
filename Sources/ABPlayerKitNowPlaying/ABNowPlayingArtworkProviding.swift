import UIKit

/// Resolves a participant's Now Playing artwork.
///
/// `MPMediaItemArtwork`'s `requestHandler` is called synchronously, at
/// arbitrary sizes, on arbitrary threads. This protocol's job stops at
/// resolving the original image exactly once, asynchronously — the bridge
/// resizes from that cached original synchronously whenever the system
/// asks for a specific size.
@MainActor
public protocol ABNowPlayingArtworkProviding: AnyObject {
    /// Returning `nil` (or the task being cancelled) means "no artwork" —
    /// the bridge omits the artwork key entirely rather than inventing a
    /// placeholder image on the consumer's behalf.
    func artwork(for metadata: ABNowPlayingMetadata) async -> UIImage?
}

/// A ready-made provider for a consumer that already holds a single image.
@MainActor
public final class ABStaticArtworkProvider: ABNowPlayingArtworkProviding {
    private let image: UIImage?

    public init(image: UIImage?) {
        self.image = image
    }

    public func artwork(for metadata: ABNowPlayingMetadata) async -> UIImage? {
        image
    }
}
