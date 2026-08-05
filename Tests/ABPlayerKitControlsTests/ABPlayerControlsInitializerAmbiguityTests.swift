import ABPlayerKit
import SwiftUI
import Testing
import UIKit
@testable import ABPlayerKitControls

/// WP-B2 (ROADMAP-round4.md): compile-only proof that adding the additive
/// `@ViewBuilder accessories:` initializer alongside the existing
/// `accessoryViews: [UIView]` one didn't introduce call-site ambiguity —
/// the most common failure mode when adding an overload. If any of the four
/// shapes below stopped compiling, this file itself would fail to build.
@Suite("ABPlayerControls/ABVideoPlayerWithControls initializer overloads resolve without ambiguity", .timeLimit(.minutes(1)))
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
}
