@preconcurrency import AVFoundation
import ABPlayerKit
import MediaPlayer
import UIKit

/// A single participant's bookkeeping. `player` is `weak` — this bridge
/// never extends an `ABPlayer`'s lifetime.
private struct ABNowPlayingParticipant {
    weak var player: ABPlayer?
    var metadata: ABNowPlayingMetadata
    var configuration: ABNowPlayingConfiguration
    var artworkProvider: (any ABNowPlayingArtworkProviding)?
    var nextHandler: (@MainActor () -> Void)?
    var previousHandler: (@MainActor () -> Void)?
    let subscriptionToken: ABObservationToken
    var artworkGeneration = 0
    var artworkTask: Task<Void, Never>?
    var resolvedArtwork: MPMediaItemArtwork?
}

/// The process-wide bridge to `MPNowPlayingInfoCenter`/
/// `MPRemoteCommandCenter`. Participants opt in with ``attach(_:metadata:configuration:artwork:)``;
/// until the first one does, this type never reads or writes either
/// singleton, and its only publish trigger is a discrete player-state
/// transition — periodic playback ticks never republish on their own.
///
/// Ownership is exclusive and LIFO (`ABNowPlayingOwnership`): only a
/// participant whose player is `.current` may own the surface, and the
/// most recently eligible participant wins. This mirrors
/// `ABAudioSessionCoordinator`'s snapshot/restore shape but, unlike that
/// refcounted coordinator, only ever has one active owner at a time.
@MainActor
public final class ABNowPlayingCenter {
    /// The process-wide single owner of this resource.
    public static let shared = ABNowPlayingCenter(surface: ABMediaPlayerNowPlayingSurface())

    /// The player currently owning the Now Playing surface, or `nil` if no
    /// eligible participant exists. Reading this also reconciles any
    /// participant whose player has since deallocated — the only signal
    /// available for that transition, since `ABPlayer` broadcasts nothing
    /// from `deinit`.
    public var owner: ABPlayerID? {
        reconcileDeallocatedParticipants()
        return ownership.owner
    }

    private let surface: any ABNowPlayingSurface
    private let router = ABRemoteCommandRouter()
    private var ownership = ABNowPlayingOwnership()
    private var participants: [ABPlayerID: ABNowPlayingParticipant] = [:]
    private var snapshotTaken = false
    private var snapshotInfo: [String: Any]?
    private var snapshotCommandEnablement: [ABRemoteCommandKey: Bool] = [:]

    init(surface: any ABNowPlayingSurface) {
        self.surface = surface
    }

    /// Registers a participant. Ownership only actually transfers once
    /// `player.grade == .current` — registering a `.preloaded` feed cell is
    /// harmless and takes no effect on the surface until it's promoted.
    ///
    /// Dropping the returned token (or letting it deinit) detaches
    /// immediately — this is not `@discardableResult`.
    public func attach(
        _ player: ABPlayer,
        metadata: ABNowPlayingMetadata,
        configuration: ABNowPlayingConfiguration = ABNowPlayingConfiguration(),
        artwork: (any ABNowPlayingArtworkProviding)? = nil
    ) -> ABObservationToken {
        reconcileDeallocatedParticipants()
        let id = player.id
        let subscriptionToken = player.addObserver { [weak self] event in
            self?.handle(event, for: id)
        }
        participants[id] = ABNowPlayingParticipant(
            player: player,
            metadata: metadata,
            configuration: configuration,
            artworkProvider: artwork,
            subscriptionToken: subscriptionToken
        )
        apply(ownership.register(id, isEligible: player.grade == .current))
        return ABObservationToken { [weak self] in
            self?.detach(id)
        }
    }

    /// Updates a participant's metadata. Republishes (and re-resolves
    /// artwork) immediately if it currently owns the surface; otherwise the
    /// new value simply takes effect the next time it acquires ownership.
    public func update(_ metadata: ABNowPlayingMetadata, for player: ABPlayer) {
        let id = player.id
        guard participants[id] != nil else { return }
        participants[id]?.metadata = metadata
        guard ownership.owner == id else { return }
        refreshArtwork(for: id)
        publish(for: id)
    }

    /// Installs the consumer action `nextTrack`/`previousTrack` need.
    /// Leaving a handler `nil` keeps that command disabled even if
    /// `configuration.commands` includes it — an enabled command always
    /// has a real action behind it.
    public func setTrackNavigationHandlers(
        next: (@MainActor () -> Void)?,
        previous: (@MainActor () -> Void)?,
        for player: ABPlayer
    ) {
        let id = player.id
        guard participants[id] != nil else { return }
        participants[id]?.nextHandler = next
        participants[id]?.previousHandler = previous
        guard ownership.owner == id else { return }
        installCommands(for: id)
    }

    // MARK: - Ownership effects

    private func apply(_ effect: ABNowPlayingOwnership.Effect) {
        switch effect {
        case .acquire(let id): acquireOwnership(for: id)
        case .relinquishAll: relinquishAll()
        case .none: break
        }
    }

    private func acquireOwnership(for id: ABPlayerID) {
        guard let participant = participants[id], participant.player != nil else { return }
        if !snapshotTaken {
            snapshotTaken = true
            snapshotInfo = surface.snapshotInfo()
            snapshotCommandEnablement = surface.snapshotCommandEnablement()
        }
        surface.setSkipInterval(participant.configuration.skipInterval)
        surface.setSupportedPlaybackRates(participant.configuration.supportedPlaybackRates.map(ABPlaybackRate.clamped))
        installCommands(for: id)
        refreshArtwork(for: id)
        publish(for: id)
    }

    private func relinquishAll() {
        guard snapshotTaken else { return }
        surface.setInfo(snapshotInfo)
        surface.restoreCommandEnablement(snapshotCommandEnablement)
        snapshotTaken = false
        snapshotInfo = nil
        snapshotCommandEnablement = [:]
    }

    // MARK: - Player events

    private func handle(_ event: ABPlayerEvent, for id: ABPlayerID) {
        switch event {
        case .gradeChanged(_, let to):
            apply(ownership.setEligible(id, to == .current))
        case .durationAvailable, .itemAttached:
            // `changePlaybackPosition`'s enablement depends on duration
            // finiteness, which isn't necessarily settled yet at the
            // moment ownership is first acquired (`ABPlayer.duration`
            // refreshes only at the end of `set(source:grade:)`, after the
            // `.gradeChanged` broadcast that triggers acquisition) — so
            // this re-evaluates it whenever duration becomes known or the
            // item changes.
            guard ownership.owner == id else { return }
            installCommands(for: id)
            publish(for: id)
        case .itemDetached:
            guard ownership.owner == id else { return }
            installCommands(for: id)
        case .timeControlStatusChanged, .bufferingChanged, .rateChanged, .seekCompleted, .playedToEnd:
            guard ownership.owner == id else { return }
            publish(for: id)
        case .scrubbingChanged(let isScrubbing):
            guard !isScrubbing, ownership.owner == id else { return }
            publish(for: id)
        default:
            break
        }
    }

    // MARK: - Publishing

    private func publish(for id: ABPlayerID) {
        guard let participant = participants[id], let player = participant.player else { return }
        let info = ABNowPlayingInfoBuilder().info(metadata: participant.metadata, snapshot: snapshot(for: player))
        surface.setInfo(info.dictionary(artwork: participant.resolvedArtwork))
    }

    private func snapshot(for player: ABPlayer) -> ABNowPlayingPlayerSnapshot {
        ABNowPlayingPlayerSnapshot(
            currentTimeSeconds: player.currentTime.isNumeric ? CMTimeGetSeconds(player.currentTime) : 0,
            durationSeconds: player.duration.flatMap { $0.isNumeric ? CMTimeGetSeconds($0) : nil },
            isPlaying: player.isPlaying,
            isBuffering: player.isBuffering,
            rate: player.rate
        )
    }

    // MARK: - Remote commands

    private func installCommands(for id: ABPlayerID) {
        guard let participant = participants[id], let player = participant.player else { return }
        let commands = participant.configuration.commands
        let isSeekable = Self.isSeekable(duration: player.duration)
        let hasNext = participant.nextHandler != nil
        let hasPrevious = participant.previousHandler != nil
        let hasRates = !participant.configuration.supportedPlaybackRates.isEmpty

        install(.play, requested: commands.contains(.play), enabled: commands.contains(.play))
        install(.pause, requested: commands.contains(.pause), enabled: commands.contains(.pause))
        install(.togglePlayPause, requested: commands.contains(.togglePlayPause), enabled: commands.contains(.togglePlayPause))
        install(.skipForward, requested: commands.contains(.skipForward), enabled: commands.contains(.skipForward))
        install(.skipBackward, requested: commands.contains(.skipBackward), enabled: commands.contains(.skipBackward))
        install(
            .changePlaybackPosition,
            requested: commands.contains(.changePlaybackPosition),
            enabled: commands.contains(.changePlaybackPosition) && isSeekable
        )
        install(
            .changePlaybackRate,
            requested: commands.contains(.changePlaybackRate),
            enabled: commands.contains(.changePlaybackRate) && hasRates
        )
        install(.nextTrack, requested: commands.contains(.nextTrack) && hasNext, enabled: commands.contains(.nextTrack) && hasNext)
        install(
            .previousTrack,
            requested: commands.contains(.previousTrack) && hasPrevious,
            enabled: commands.contains(.previousTrack) && hasPrevious
        )
    }

    /// `requested` gates whether a handler is installed at all — a command
    /// with no possible action never gets a live target, even disabled;
    /// `enabled` is the surface's `isEnabled` value.
    private func install(_ key: ABRemoteCommandKey, requested: Bool, enabled: Bool) {
        surface.setCommand(key, enabled: enabled, handler: requested ? makeHandler(for: key) : nil)
    }

    private func makeHandler(for key: ABRemoteCommandKey) -> @MainActor (ABRemoteCommandIntent) -> ABRemoteCommandOutcome {
        { [weak self] intent in
            guard let self else { return .rejectNoOwner }
            let ownerID = self.ownership.owner
            let participant = ownerID.flatMap { self.participants[$0] }
            let player = participant?.player
            let outcome = self.router.outcome(
                for: intent,
                ownerExists: player != nil,
                isSeekable: Self.isSeekable(duration: player?.duration),
                hasTrackHandlers: (
                    next: participant?.nextHandler != nil,
                    previous: participant?.previousHandler != nil
                )
            )
            if case .perform(let performedIntent) = outcome, let player, let participant {
                self.perform(performedIntent, on: player, participant: participant)
            }
            return outcome
        }
    }

    private func perform(_ intent: ABRemoteCommandIntent, on player: ABPlayer, participant: ABNowPlayingParticipant) {
        switch intent {
        case .play: player.play()
        case .pause: player.pause()
        case .togglePlayPause:
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
        case .skip(let interval): Task { await player.skip(by: interval) }
        case .seek(let seconds): Task { await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
        case .setRate(let rate): player.setRate(rate)
        case .nextTrack: participant.nextHandler?()
        case .previousTrack: participant.previousHandler?()
        }
    }

    private static func isSeekable(duration: CMTime?) -> Bool {
        guard let duration, duration.isNumeric else { return false }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0
    }

    // MARK: - Artwork

    private func refreshArtwork(for id: ABPlayerID) {
        participants[id]?.artworkTask?.cancel()
        participants[id]?.artworkGeneration += 1
        let generation = participants[id]?.artworkGeneration ?? 0
        participants[id]?.resolvedArtwork = nil
        guard let participant = participants[id], let provider = participant.artworkProvider else { return }
        let metadata = participant.metadata
        participants[id]?.artworkTask = Task { [weak self] in
            let image = await provider.artwork(for: metadata)
            guard !Task.isCancelled else { return }
            self?.artworkResolved(image, generation: generation, for: id)
        }
    }

    private func artworkResolved(_ image: UIImage?, generation: Int, for id: ABPlayerID) {
        guard let participant = participants[id], participant.artworkGeneration == generation else { return }
        participants[id]?.resolvedArtwork = image.map { resolvedImage in
            MPMediaItemArtwork(boundsSize: resolvedImage.size) { requestedSize in
                Self.resized(image: resolvedImage, to: requestedSize)
            }
        }
        guard ownership.owner == id else { return }
        publish(for: id)
    }

    /// Runs inside `MPMediaItemArtwork`'s `requestHandler` — synchronous,
    /// called at arbitrary sizes on arbitrary threads. No I/O, no `await`,
    /// no lock waits: only a resize of the already-cached original.
    private static func resized(image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Lifecycle

    private func detach(_ id: ABPlayerID) {
        guard let participant = participants[id] else { return }
        participants[id] = nil
        participant.subscriptionToken.cancel()
        participant.artworkTask?.cancel()
        apply(ownership.unregister(id))
    }

    private func reconcileDeallocatedParticipants() {
        let deadIDs = participants.compactMap { key, value in value.player == nil ? key : nil }
        for id in deadIDs {
            detach(id)
        }
    }
}
