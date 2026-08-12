import MediaPlayer
import UIKit

/// The seam between `ABNowPlayingCenter` and the real
/// `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` singletons — the same
/// role `ABPlaybackTarget` plays for `ABPlayer`. `MediaPlayer` is imported
/// only in this file; everything else in this target compiles without it,
/// which is what makes the ownership/publishing logic testable without a
/// real Now Playing surface.
@MainActor
protocol ABNowPlayingSurface: AnyObject {
    func snapshotInfo() -> [String: Any]?
    func setInfo(_ info: [String: Any]?)
    func snapshotCommandEnablement() -> [ABRemoteCommandKey: Bool]
    func setCommand(
        _ key: ABRemoteCommandKey,
        enabled: Bool,
        handler: (@MainActor (ABRemoteCommandIntent) -> ABRemoteCommandOutcome)?
    )
    func restoreCommandEnablement(_ snapshot: [ABRemoteCommandKey: Bool])
    func setSkipInterval(_ interval: TimeInterval)
    func setSupportedPlaybackRates(_ rates: [Float])
}

extension ABNowPlayingInfo {
    /// The dictionary `MPNowPlayingInfoCenter.nowPlayingInfo` expects.
    /// `MediaPlayer`-dependent, so it lives here rather than alongside
    /// ``ABNowPlayingInfo`` itself.
    func dictionary(artwork: MPMediaItemArtwork?) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: defaultRate,
            MPNowPlayingInfoPropertyIsLiveStream: isLiveStream,
            MPNowPlayingInfoPropertyMediaType: mediaType == .video
                ? MPNowPlayingInfoMediaType.video.rawValue
                : MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if let albumTitle { info[MPMediaItemPropertyAlbumTitle] = albumTitle }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let externalContentIdentifier { info[MPNowPlayingInfoPropertyExternalContentIdentifier] = externalContentIdentifier }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        return info
    }
}

/// The production `ABNowPlayingSurface` — the only conformer that actually
/// touches `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`.
@MainActor
final class ABMediaPlayerNowPlayingSurface: ABNowPlayingSurface {
    private let infoCenter: MPNowPlayingInfoCenter
    private let commandCenter: MPRemoteCommandCenter
    private var installedTargets: [ABRemoteCommandKey: Any] = [:]

    init(
        infoCenter: MPNowPlayingInfoCenter = .default(),
        commandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.infoCenter = infoCenter
        self.commandCenter = commandCenter
    }

    func snapshotInfo() -> [String: Any]? {
        infoCenter.nowPlayingInfo
    }

    func setInfo(_ info: [String: Any]?) {
        infoCenter.nowPlayingInfo = info
    }

    func snapshotCommandEnablement() -> [ABRemoteCommandKey: Bool] {
        var snapshot: [ABRemoteCommandKey: Bool] = [:]
        for key in ABRemoteCommandKey.allCases {
            snapshot[key] = command(for: key).isEnabled
        }
        return snapshot
    }

    func setCommand(
        _ key: ABRemoteCommandKey,
        enabled: Bool,
        handler: (@MainActor (ABRemoteCommandIntent) -> ABRemoteCommandOutcome)?
    ) {
        let command = command(for: key)
        removeInstalledTarget(for: key, from: command)
        command.isEnabled = enabled
        guard let handler else { return }
        let target = command.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            let intent = self.intent(for: key, event: event)
            return self.status(for: handler(intent))
        }
        installedTargets[key] = target
    }

    func restoreCommandEnablement(_ snapshot: [ABRemoteCommandKey: Bool]) {
        for key in ABRemoteCommandKey.allCases {
            let command = command(for: key)
            removeInstalledTarget(for: key, from: command)
            command.isEnabled = snapshot[key] ?? false
        }
    }

    func setSkipInterval(_ interval: TimeInterval) {
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: interval)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: interval)]
    }

    func setSupportedPlaybackRates(_ rates: [Float]) {
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = rates.map { NSNumber(value: $0) }
    }

    private func removeInstalledTarget(for key: ABRemoteCommandKey, from command: MPRemoteCommand) {
        guard let existingTarget = installedTargets[key] else { return }
        command.removeTarget(existingTarget)
        installedTargets[key] = nil
    }

    private func command(for key: ABRemoteCommandKey) -> MPRemoteCommand {
        switch key {
        case .play: commandCenter.playCommand
        case .pause: commandCenter.pauseCommand
        case .togglePlayPause: commandCenter.togglePlayPauseCommand
        case .skipForward: commandCenter.skipForwardCommand
        case .skipBackward: commandCenter.skipBackwardCommand
        case .changePlaybackPosition: commandCenter.changePlaybackPositionCommand
        case .changePlaybackRate: commandCenter.changePlaybackRateCommand
        case .nextTrack: commandCenter.nextTrackCommand
        case .previousTrack: commandCenter.previousTrackCommand
        }
    }

    private func intent(for key: ABRemoteCommandKey, event: MPRemoteCommandEvent) -> ABRemoteCommandIntent {
        switch key {
        case .play: .play
        case .pause: .pause
        case .togglePlayPause: .togglePlayPause
        case .skipForward: .skip((event as? MPSkipIntervalCommandEvent)?.interval ?? 0)
        case .skipBackward: .skip(-((event as? MPSkipIntervalCommandEvent)?.interval ?? 0))
        case .changePlaybackPosition: .seek(seconds: (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0)
        case .changePlaybackRate: .setRate(Float((event as? MPChangePlaybackRateCommandEvent)?.playbackRate ?? 1))
        case .nextTrack: .nextTrack
        case .previousTrack: .previousTrack
        }
    }

    private func status(for outcome: ABRemoteCommandOutcome) -> MPRemoteCommandHandlerStatus {
        switch outcome {
        case .perform: .success
        case .rejectNoOwner: .noActionableNowPlayingItem
        case .rejectNotSeekable, .rejectNoHandler: .commandFailed
        }
    }
}
