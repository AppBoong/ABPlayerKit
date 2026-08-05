import ABPlayerKit
import Foundation
import Testing
@testable import ABPlayerKitControls

/// WP-A4b precondition (ROADMAP-round4.md): before converting
/// `togglePlayback`/etc. to route through `ABControlsPresenter.Effect`, pin
/// the exact interleaving a play/pause tap produces today. `player.promote(to:)`
/// broadcasts `.gradeChanged` synchronously (`ABObserverRegistry.broadcast`
/// iterates handlers directly, no dispatch hop — see
/// `Sources/ABPlayerKit/Observation/ABObserverRegistry.swift`), which
/// re-enters `ABPlayerControlsView.handlePlayerEvent` *before*
/// `togglePlayback` calls `player.play()`. (`player.play()`/`pause()`
/// themselves do *not* synchronously re-enter — the `timeControlStatus` KVO
/// forwards through `Task { @MainActor in ... }` in `ABAVPlaybackTarget`,
/// so that event always arrives on a later run-loop turn, never inside this
/// same call stack.) This test must pass unchanged before and after WP-A4b.
@Suite("A play tap's reentrant event ordering is pinned before WP-A4b touches togglePlayback", .timeLimit(.minutes(3)))
@MainActor
struct ABControlsPlayPauseReentrancyCharacterizationTests {
    /// Tracks just the event *kind* (case name), not full payloads — some
    /// reentrant events along the promote path (`.preloadCancelled`,
    /// `.tuningApplied`) carry values (tuning parameters) irrelevant to the
    /// ordering this test pins; only `.gradeChanged`'s payload matters here,
    /// since that's the one this WP's design reasons about explicitly.
    private enum RecordedEvent: Equatable, CustomStringConvertible {
        case player(String)
        case controls(ABControlsEvent)

        var description: String {
            switch self {
            case .player(let kind): "player(\(kind))"
            case .controls(let event): "controls(\(event))"
            }
        }

        static func kind(of event: ABPlayerEvent) -> String {
            switch event {
            case .gradeChanged(let from, let to): "gradeChanged(from: \(from), to: \(to))"
            default: "\(event)".split(separator: "(").first.map(String.init) ?? "\(event)"
            }
        }
    }

    @Test("Given a source at a lower grade with default promotion, a play tap promotes (reentering .gradeChanged before play() runs), then plays, then bounces/broadcasts")
    func playTapReentrantSequence() {
        let source = ABMediaSource(url: URL(string: "https://example.com/reentrancy.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .preloaded)
        let view = ABPlayerControlsView()
        view.player = player

        var recorded: [RecordedEvent] = []
        let playerToken = player.addObserver { event in recorded.append(.player(RecordedEvent.kind(of: event))) }
        let controlsToken = view.addObserver { event in recorded.append(.controls(event)) }
        defer {
            playerToken.cancel()
            controlsToken.cancel()
        }

        view.playPauseButton.sendActions(for: .touchUpInside)

        #expect(recorded == [
            .player("preloadCancelled"),
            .player("tuningApplied"),
            .player(RecordedEvent.kind(of: .gradeChanged(from: .preloaded, to: .current))),
            .controls(.playPauseTapped(isPlayingAfterTap: true))
        ])
        #expect(player.grade == .current)
        #expect(player.isPlaying)
        #expect(view.isShowingPauseIcon)
    }

    @Test("Given an already-current, playing source, a pause tap produces no reentrant player event — only the controls broadcast — since pause()'s timeControlStatus KVO forwards asynchronously")
    func pauseTapProducesNoSynchronousReentrantPlayerEvent() {
        let source = ABMediaSource(url: URL(string: "https://example.com/reentrancy-pause.mp4")!)
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        player.set(source: source, grade: .current)
        player.play()
        let view = ABPlayerControlsView()
        view.player = player
        view.handlePlayerEvent(.timeControlStatusChanged(.playing))

        var recorded: [RecordedEvent] = []
        let playerToken = player.addObserver { event in recorded.append(.player(RecordedEvent.kind(of: event))) }
        let controlsToken = view.addObserver { event in recorded.append(.controls(event)) }
        defer {
            playerToken.cancel()
            controlsToken.cancel()
        }

        view.playPauseButton.sendActions(for: .touchUpInside)

        #expect(recorded == [.controls(.playPauseTapped(isPlayingAfterTap: false))])
        #expect(!view.isShowingPauseIcon)
    }
}
