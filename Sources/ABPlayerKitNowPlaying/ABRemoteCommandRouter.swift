import Foundation

/// The commands `ABNowPlayingCenter`'s bridge routes to concrete `ABPlayer`
/// calls, with the payload already extracted from whichever
/// `MPRemoteCommandEvent` subclass triggered it.
enum ABRemoteCommandIntent: Equatable {
    case play
    case pause
    case togglePlayPause
    case skip(TimeInterval)
    case seek(seconds: Double)
    case setRate(Float)
    case nextTrack
    case previousTrack
}

/// `MPRemoteCommandHandlerStatus` reduced to this library's own vocabulary
/// — `ABNowPlayingSurface`'s production implementation maps this back to
/// the real status the system expects.
enum ABRemoteCommandOutcome: Equatable {
    case perform(ABRemoteCommandIntent)
    /// Maps to `.noActionableNowPlayingItem` — nobody currently owns Now
    /// Playing.
    case rejectNoOwner
    /// Maps to `.commandFailed` — a position command arrived but the
    /// current item's duration isn't finite.
    case rejectNotSeekable
    /// Maps to `.commandFailed` — a track-navigation command arrived with
    /// no handler installed for it (shouldn't normally be reachable, since
    /// this library never enables such a command with no handler behind it
    /// in the first place — but the router still resolves the case
    /// explicitly rather than assuming the precondition holds).
    case rejectNoHandler
}

/// `MPRemoteCommandEvent` has no public initializer, so this router — not
/// a direct `MPRemoteCommandCenter` integration test — is the only way to
/// exhaustively verify command routing.
struct ABRemoteCommandRouter {
    func outcome(
        for intent: ABRemoteCommandIntent,
        ownerExists: Bool,
        isSeekable: Bool,
        hasTrackHandlers: (next: Bool, previous: Bool)
    ) -> ABRemoteCommandOutcome {
        guard ownerExists else { return .rejectNoOwner }
        switch intent {
        case .play, .pause, .togglePlayPause, .skip, .setRate:
            return .perform(intent)
        case .seek:
            return isSeekable ? .perform(intent) : .rejectNotSeekable
        case .nextTrack:
            return hasTrackHandlers.next ? .perform(intent) : .rejectNoHandler
        case .previousTrack:
            return hasTrackHandlers.previous ? .perform(intent) : .rejectNoHandler
        }
    }
}

/// The nine remote commands this bridge manages — a stable key independent
/// of `MediaPlayer`'s `MPRemoteCommand` subclasses, so the reducers above
/// can be tested without linking `MediaPlayer`.
enum ABRemoteCommandKey: CaseIterable, Equatable {
    case play
    case pause
    case togglePlayPause
    case skipForward
    case skipBackward
    case changePlaybackPosition
    case changePlaybackRate
    case nextTrack
    case previousTrack
}
