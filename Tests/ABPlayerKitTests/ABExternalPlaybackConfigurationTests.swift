import Foundation
import Testing
@testable import ABPlayerKit
@preconcurrency import AVFoundation

/// Coverage for the three AirPlay (`AVPlayer` external-playback) knobs:
/// they reach the target at player creation and on every later
/// configuration change, and `ABPlayerConfiguration`'s hand-written `==`
/// actually compares them (a field easy to add and forget to also add to
/// equality).
@Suite("AirPlay knobs reach the playback target and participate in ABPlayerConfiguration equality")
@MainActor
struct ABExternalPlaybackConfigurationTests {
    private let source = ABMediaSource(url: URL(string: "https://example.com/a.mp4")!)

    @Test("The three external-playback knobs are applied when the player is created")
    func knobsAppliedAtPlayerCreation() {
        let target = ABFakePlaybackTarget()
        var configuration = ABPlayerConfiguration()
        configuration.allowsExternalPlayback = false
        configuration.usesExternalPlaybackWhileExternalScreenIsActive = true
        configuration.externalPlaybackVideoGravity = .resizeAspectFill
        let player = ABPlayer(configuration: configuration, target: target)

        player.set(source: source, grade: .instanceOnly)

        #expect(target.appliedExternalPlaybackSettings == ABExternalPlaybackSettings(
            allowsExternalPlayback: false,
            usesExternalPlaybackWhileExternalScreenIsActive: true,
            externalPlaybackVideoGravity: .resizeAspectFill
        ))
    }

    @Test("Changing any of the three knobs re-applies all three to the target")
    func knobsReappliedOnConfigurationChange() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(), target: target)
        player.set(source: source, grade: .instanceOnly)
        let callsBeforeChange = target.calls.count

        var configuration = player.configuration
        configuration.allowsExternalPlayback = false
        player.configuration = configuration

        #expect(target.calls.count == callsBeforeChange + 1)
        #expect(target.appliedExternalPlaybackSettings == ABExternalPlaybackSettings(
            allowsExternalPlayback: false,
            usesExternalPlaybackWhileExternalScreenIsActive: false,
            externalPlaybackVideoGravity: .resizeAspect
        ))
    }

    @Test("An unrelated configuration change does not re-apply external playback settings")
    func unrelatedChangeDoesNotReapplyKnobs() {
        let target = ABFakePlaybackTarget()
        let player = ABPlayer(configuration: ABPlayerConfiguration(), target: target)
        player.set(source: source, grade: .instanceOnly)
        let callsBeforeChange = target.calls.count

        var configuration = player.configuration
        configuration.isMuted = true
        player.configuration = configuration

        let applyExternalPlaybackCalls = target.calls[callsBeforeChange...].filter {
            if case .applyExternalPlayback = $0 { return true }
            return false
        }
        #expect(applyExternalPlaybackCalls.isEmpty)
    }

    @Test("ABPlayerConfiguration equality reflects all three external-playback knobs")
    func configurationEqualityReflectsExternalPlaybackKnobs() {
        let base = ABPlayerConfiguration()

        var differsInAllows = base
        differsInAllows.allowsExternalPlayback = false
        #expect(differsInAllows != base)

        var differsInUsesWhileActive = base
        differsInUsesWhileActive.usesExternalPlaybackWhileExternalScreenIsActive = true
        #expect(differsInUsesWhileActive != base)

        var differsInGravity = base
        differsInGravity.externalPlaybackVideoGravity = .resizeAspectFill
        #expect(differsInGravity != base)
    }

    @Test("ABPlayerConfiguration defaults match AVPlayer's own defaults (no behavior change)")
    func defaultsMatchAVPlayerDefaults() {
        let configuration = ABPlayerConfiguration()
        #expect(configuration.allowsExternalPlayback == true)
        #expect(configuration.usesExternalPlaybackWhileExternalScreenIsActive == false)
        #expect(configuration.externalPlaybackVideoGravity == .resizeAspect)
    }

    @Test("A freshly-created AVPlayer's own externalPlaybackVideoGravity default is what ABPlayerConfiguration's default follows")
    func avPlayerOwnDefaultMatchesTheChosenDefault() {
        let freshPlayer = AVPlayer()
        #expect(freshPlayer.externalPlaybackVideoGravity == .resizeAspect)
    }
}
