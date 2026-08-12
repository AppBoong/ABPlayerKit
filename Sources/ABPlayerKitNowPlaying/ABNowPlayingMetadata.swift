import Foundation

/// Consumer-known information about what's playing. The core `ABPlayerKit`
/// module knows only a source URL, never a title or artist, so this bridge
/// never infers metadata — the consumer always supplies it.
public struct ABNowPlayingMetadata: Sendable, Equatable {
    public enum MediaType: Sendable, Equatable {
        case video
        case audio
    }

    public var title: String
    public var artist: String?
    public var albumTitle: String?
    public var mediaType: MediaType
    /// Published as a live stream when `true`, or whenever the attached
    /// item's duration isn't finite regardless of this value.
    public var isLiveStream: Bool
    public var externalContentIdentifier: String?

    public init(
        title: String,
        artist: String? = nil,
        albumTitle: String? = nil,
        mediaType: MediaType = .video,
        isLiveStream: Bool = false,
        externalContentIdentifier: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.mediaType = mediaType
        self.isLiveStream = isLiveStream
        self.externalContentIdentifier = externalContentIdentifier
    }
}
