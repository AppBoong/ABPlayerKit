import ABPlayerKit
import SwiftUI
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("SwiftUI controls update only changed UIKit properties", .timeLimit(.minutes(3)))
@MainActor
struct ABPlayerControlsSwiftUITests {
    @Test("Given matching inputs, wrapper updates preserve player and style state")
    func unchangedInputsAreStable() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let wrapper = ABPlayerControls(player: player) {}
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
        ) {}
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
        let first = ABPlayerControls(player: player, onEvent: { firstEvents.append($0) }) {}
        let second = ABPlayerControls(player: player, onEvent: { latestEvents.append($0) }) {}
        let coordinator = first.makeCoordinator()
        let view = ABPlayerControlsView()
        first.update(view, coordinator: coordinator)

        second.update(view, coordinator: coordinator)
        view.setControlsVisible(false, animated: false)

        #expect(firstEvents.isEmpty)
        #expect(latestEvents == [.visibilityChanged(isVisible: false)])
    }

    @Test("Given SwiftUI accessories content, the wrapper hosts it as a single accessory view")
    func accessoriesContentIsHosted() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let wrapper = ABPlayerControls(player: player) {
            Text("Accessory")
        }
        let view = ABPlayerControlsView()

        wrapper.update(view, coordinator: wrapper.makeCoordinator())

        #expect(view.accessoryViews.count == 1)
    }

    @Test("Given EmptyView accessories (the default, no trailing closure), no accessory view is hosted")
    func emptyViewAccessoriesHostsNothing() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let wrapper = ABPlayerControls(player: player) {}
        let view = ABPlayerControlsView()

        wrapper.update(view, coordinator: wrapper.makeCoordinator())

        #expect(view.accessoryViews.isEmpty)
    }

    @Test("Given accessories content updated across two wrapper values sharing a coordinator, the same hosted view instance is reused rather than rebuilt")
    func accessoriesUpdateReusesTheSameHostedView() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let first = ABPlayerControls(player: player) { Text("One") }
        let second = ABPlayerControls(player: player) { Text("Two") }
        let coordinator = first.makeCoordinator()
        let view = ABPlayerControlsView()
        first.update(view, coordinator: coordinator)
        let hostedView = view.accessoryViews.first

        second.update(view, coordinator: coordinator)

        #expect(view.accessoryViews.first === hostedView)
    }

    @Test("Given SwiftUI accessories mounted through a real window — the ordinary first-display path, not a manual update(_:coordinator:) call — the hosted accessory attaches to a parent view controller (round4 review MJ-2 integration coverage)")
    func accessoriesAttachToParentOnRealWindowDisplay() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let rootView = ABPlayerControls(player: player) {
            Text("Accessory")
        }
        let hostingController = UIHostingController(rootView: rootView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        window.rootViewController = hostingController
        window.isHidden = false
        defer { window.isHidden = true }
        hostingController.view.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        #expect(hostingController.children.count == 1, "the accessory hosting box's controller should have self-attached as a child once its view reached the window")
    }
}
