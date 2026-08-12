/// Which lock-screen/Control Center remote commands `ABNowPlayingCenter`
/// should activate for a participant.
public struct ABRemoteCommandSet: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let play = ABRemoteCommandSet(rawValue: 1 << 0)
    public static let pause = ABRemoteCommandSet(rawValue: 1 << 1)
    public static let togglePlayPause = ABRemoteCommandSet(rawValue: 1 << 2)
    public static let skipForward = ABRemoteCommandSet(rawValue: 1 << 3)
    public static let skipBackward = ABRemoteCommandSet(rawValue: 1 << 4)
    public static let changePlaybackPosition = ABRemoteCommandSet(rawValue: 1 << 5)
    public static let changePlaybackRate = ABRemoteCommandSet(rawValue: 1 << 6)
    public static let nextTrack = ABRemoteCommandSet(rawValue: 1 << 7)
    public static let previousTrack = ABRemoteCommandSet(rawValue: 1 << 8)

    /// The six commands with an action that always exists at this
    /// library's public surface. `nextTrack`/`previousTrack` are excluded —
    /// this library has no queue concept — and `changePlaybackRate` is
    /// excluded since it's only meaningful once a supported-rates list is
    /// also configured.
    public static let `default`: ABRemoteCommandSet = [
        .play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePlaybackPosition
    ]
}
