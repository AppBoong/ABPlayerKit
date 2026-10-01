import ABPlayerKit
import ABTestSupport
import SwiftUI
import Testing
import UIKit
@testable import ABPlayerKitControls

/// WP-B2 (ROADMAP-round4.md): compile-only proof that adding the additive
/// `@ViewBuilder accessories:` initializer alongside the existing
/// `accessoryViews: [UIView]` one didn't introduce call-site ambiguity —
/// the most common failure mode when adding an overload. If any of the four
/// shapes below stopped compiling, this file itself would fail to build.
@Suite("ABPlayerControls/ABVideoPlayerWithControls initializer overloads resolve without ambiguity", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPlayerControlsInitializerAmbiguityTests {
    @available(*, deprecated, message: "Intentionally exercises the deprecated accessoryViews: initializer to prove it still compiles.")
    @Test("Given the legacy [UIView]-array initializer, it still compiles and resolves")
    func legacyArrayInitializerCompiles() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let accessory = UIView()

        let controls = ABPlayerControls(player: player, accessoryViews: [accessory])
        let videoWithControls = ABVideoPlayerWithControls(player: player, accessoryViews: [accessory])

        _ = controls
        _ = videoWithControls
    }

    @Test("Given the new trailing-closure accessories initializer, it compiles and resolves")
    func trailingClosureAccessoriesInitializerCompiles() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))

        let controls = ABPlayerControls(player: player) {
            Text("Accessory")
        }
        let videoWithControls = ABVideoPlayerWithControls(player: player) {
            Text("Accessory")
        }

        _ = controls
        _ = videoWithControls
    }

    @Test("Given onEvent followed by a trailing-closure accessories, both resolve to their own parameters without ambiguity")
    func onEventFollowedByTrailingClosureAccessoriesCompiles() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))

        let controls = ABPlayerControls(player: player, onEvent: { _ in }) {
            Text("Accessory")
        }

        _ = controls
    }

    // Deliberately *not* marked deprecated: CI builds with
    // SWIFT_TREAT_WARNINGS_AS_ERRORS=YES, so if any bare call below resolved
    // to a deprecated initializer, this file would stop compiling.
    @Test("Given every parameter left at its default, a call with no closure resolves to the current initializer, not the deprecated array one")
    func bareCallsResolveToCurrentInitializers() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))

        let controls = ABPlayerControls(player: player)
        let controlsWithEvent = ABPlayerControls(player: player, onEvent: { _ in })
        let videoWithControls = ABVideoPlayerWithControls(player: player)
        let videoWithGravity = ABVideoPlayerWithControls(player: player, videoGravity: .resizeAspect, style: .minimal)
        // The 0.3.0 migration spelling keeps compiling, still to the current initializer.
        let emptyClosure = ABVideoPlayerWithControls(player: player) {}

        _ = controls
        _ = controlsWithEvent
        _ = videoWithControls
        _ = videoWithGravity
        _ = emptyClosure
    }

    @Test("Given the new url: initializers, the bare form, a trailing-closure accessories form, an explicit playerConfiguration:, and a modifier chain all compile and resolve without ambiguity")
    func urlInitializerShapesCompile() {
        let url = URL(string: "https://example.com/ambiguity-test.mp4")!

        let basic = ABVideoPlayerWithControls(url: url)
        let trailingClosure = ABVideoPlayerWithControls(url: url) {
            Text("Accessory")
        }
        var configuration = ABPlayerConfiguration()
        configuration.isMuted = true
        let withPlayerConfiguration = ABVideoPlayerWithControls(url: url, playerConfiguration: configuration)
        let withModifierChain = ABVideoPlayerWithControls(url: url)
            .playerControlsStyle(.minimal)
            .playerControlsConfiguration(ABPlayerControlsConfiguration())

        _ = basic
        _ = trailingClosure
        _ = withPlayerConfiguration
        _ = withModifierChain
    }
}
