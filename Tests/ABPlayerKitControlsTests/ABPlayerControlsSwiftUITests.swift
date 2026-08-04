import ABPlayerKit
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("SwiftUI controls update only changed UIKit properties", .timeLimit(.minutes(1)))
@MainActor
struct ABPlayerControlsSwiftUITests {
    @Test("Given matching inputs, wrapper updates preserve player and style state")
    func unchangedInputsAreStable() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let wrapper = ABPlayerControls(player: player)
        let view = ABPlayerControlsView()
        let coordinator = wrapper.makeCoordinator()

        wrapper.update(view, coordinator: coordinator)
        let invalidations = view.styleLayoutInvalidationCount
        wrapper.update(view, coordinator: coordinator)

        #expect(view.player === player)
        #expect(view.styleLayoutInvalidationCount == invalidations)
    }

    @Test("Given changed style and configuration, wrapper applies both live")
    func changedInputsApply() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        var style = ABPlayerControlsStyle()
        style.playPauseButtonSize = CGSize(width: 50, height: 50)
        var configuration = ABPlayerControlsConfiguration()
        configuration.skipInterval = 15
        let wrapper = ABPlayerControls(
            player: player,
            style: style,
            configuration: configuration
        )
        let view = ABPlayerControlsView()

        wrapper.update(view, coordinator: wrapper.makeCoordinator())

        #expect(view.style == style)
        #expect(view.configuration == configuration)
        #expect(view.skipForwardButton.resolvedIcon == .system("goforward.15"))
    }

    @Test("Given an updated callback, the coordinator delivers events to the latest closure")
    func callbackUpdates() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        var firstEvents: [ABControlsEvent] = []
        var latestEvents: [ABControlsEvent] = []
        let first = ABPlayerControls(player: player) { firstEvents.append($0) }
        let second = ABPlayerControls(player: player) { latestEvents.append($0) }
        let coordinator = first.makeCoordinator()
        let view = ABPlayerControlsView()
        first.update(view, coordinator: coordinator)

        second.update(view, coordinator: coordinator)
        view.setControlsVisible(false, animated: false)

        #expect(firstEvents.isEmpty)
        #expect(latestEvents == [.visibilityChanged(isVisible: false)])
    }
}
