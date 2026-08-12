import ABPlayerKit
import SwiftUI
import Testing
@testable import ABPlayerKitControls

/// Coverage for the `.playerControlsStyle(_:)`/`.playerControlsConfiguration(_:)`
/// resolution order: an initializer argument beats the Environment value,
/// which beats the type default. Exercised through
/// `update(_:coordinator:environment:)` directly, without a real SwiftUI
/// host — the same pattern `ABPlayerControlsSwiftUITests` already uses for
/// non-environment update coverage.
@Suite("ABPlayerControls resolves style/configuration from initializer argument, then Environment, then the type default", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerControlsEnvironmentTests {
    private func player() -> ABPlayer {
        ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
    }

    @Test("Given only an initializer argument, it wins with no environment value present")
    func styleArgumentOnly() {
        let wrapper = ABPlayerControls(player: player(), style: .minimal) {}
        let view = ABPlayerControlsView()

        wrapper.update(view, coordinator: wrapper.makeCoordinator(), environment: EnvironmentValues())

        #expect(view.style == .minimal)
    }

    @Test("Given only an environment value, it applies with no initializer argument present")
    func styleEnvironmentOnly() {
        let wrapper = ABPlayerControls(player: player()) {}
        let view = ABPlayerControlsView()
        var environment = EnvironmentValues()
        environment.playerControlsStyle = .tinted

        wrapper.update(view, coordinator: wrapper.makeCoordinator(), environment: environment)

        #expect(view.style == .tinted)
    }

    @Test("Given both an initializer argument and an environment value, the initializer argument wins")
    func styleArgumentWinsOverEnvironment() {
        let wrapper = ABPlayerControls(player: player(), style: .minimal) {}
        let view = ABPlayerControlsView()
        var environment = EnvironmentValues()
        environment.playerControlsStyle = .tinted

        wrapper.update(view, coordinator: wrapper.makeCoordinator(), environment: environment)

        #expect(view.style == .minimal)
    }

    @Test("Given neither an initializer argument nor an environment value, the type default applies")
    func styleFallsBackToDefault() {
        let wrapper = ABPlayerControls(player: player()) {}
        let view = ABPlayerControlsView()

        wrapper.update(view, coordinator: wrapper.makeCoordinator(), environment: EnvironmentValues())

        #expect(view.style == .default)
    }

    @Test("Given only an initializer argument, configuration resolution matches the style matrix")
    func configurationArgumentOnly() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.skipInterval = 15
        let wrapper = ABPlayerControls(player: player(), configuration: configuration) {}
        let view = ABPlayerControlsView()

        wrapper.update(view, coordinator: wrapper.makeCoordinator(), environment: EnvironmentValues())

        #expect(view.configuration.skipInterval == 15)
    }

    @Test("Given only an environment value, configuration applies with no initializer argument present")
    func configurationEnvironmentOnly() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.skipInterval = 30
        let wrapper = ABPlayerControls(player: player()) {}
        let view = ABPlayerControlsView()
        var environment = EnvironmentValues()
        environment.playerControlsConfiguration = configuration

        wrapper.update(view, coordinator: wrapper.makeCoordinator(), environment: environment)

        #expect(view.configuration.skipInterval == 30)
    }

    @Test("Given both, the initializer argument wins for configuration too")
    func configurationArgumentWinsOverEnvironment() {
        var argumentConfiguration = ABPlayerControlsConfiguration()
        argumentConfiguration.skipInterval = 15
        var environmentConfiguration = ABPlayerControlsConfiguration()
        environmentConfiguration.skipInterval = 30
        let wrapper = ABPlayerControls(player: player(), configuration: argumentConfiguration) {}
        let view = ABPlayerControlsView()
        var environment = EnvironmentValues()
        environment.playerControlsConfiguration = environmentConfiguration

        wrapper.update(view, coordinator: wrapper.makeCoordinator(), environment: environment)

        #expect(view.configuration.skipInterval == 15)
    }

    @Test("Given neither, configuration falls back to ABPlayerControlsConfiguration()'s default skipInterval")
    func configurationFallsBackToDefault() {
        let wrapper = ABPlayerControls(player: player()) {}
        let view = ABPlayerControlsView()

        wrapper.update(view, coordinator: wrapper.makeCoordinator(), environment: EnvironmentValues())

        #expect(view.configuration.skipInterval == ABPlayerControlsConfiguration().skipInterval)
    }
}
