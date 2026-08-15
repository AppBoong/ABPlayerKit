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

    @available(*, deprecated, message: "Intentionally exercises the deprecated accessoryViews: initializer's all-defaults call shape.")
    @Test("Given every parameter left at its default, both the legacy array form and the new accessories form still resolve without ambiguity")
    func allDefaultsCompileForBothOverloads() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))

        // Legacy overload, no trailing closure — resolves via `accessoryViews: [UIView] = []`.
        let legacyDefaults = ABPlayerControls(player: player)
        // New overload, `EmptyView` — resolves via `@ViewBuilder accessories:`, skips hosting entirely.
        let accessoriesDefaults = ABPlayerControls(player: player) {}

        _ = legacyDefaults
        _ = accessoriesDefaults
    }

    @available(*, deprecated, message: "Intentionally exercises ABVideoPlayerWithControls's deprecated accessoryViews: initializer's all-defaults call shape (round4 review mn-3).")
    @Test("Given ABVideoPlayerWithControls with every parameter left at its default, the bare call resolves to the legacy (deprecated) initializer, and an empty trailing closure resolves to the new one — the exact pair CHANGELOG/README document as the migration for consumers who don't use accessories at all")
    func videoPlayerWithControlsAllDefaultsCompileForBothOverloads() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))

        // Legacy overload, no trailing closure — this is the call every
        // pre-existing `ABVideoPlayerWithControls(player:)` consumer already
        // has, and it now warns (round4 review mn-3) since it resolves here,
        // to `accessoryViews: [UIView] = []`, not to the new initializer.
        let legacyDefaults = ABVideoPlayerWithControls(player: player)
        // The documented migration for those consumers: an empty trailing
        // closure routes to the new, non-deprecated initializer instead.
        let accessoriesDefaults = ABVideoPlayerWithControls(player: player) {}

        _ = legacyDefaults
        _ = accessoriesDefaults
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
