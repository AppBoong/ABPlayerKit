import ABPlayerKit
import ABTestSupport
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("Controls support menu, cycle, and hidden rate interactions", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABPlayerControlsRateTests {
    @Test("Given menu interaction, every configured rate appears in the menu")
    func menuContainsConfiguredRates() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateOptions = [0.5, 1, 1.5]
        configuration.rateInteraction = .menu

        let view = ABPlayerControlsView(configuration: configuration)

        #expect(view.rateButton.menu?.children.count == 3)
        #expect(view.rateButton.showsMenuAsPrimaryAction)
        #expect(!view.rateButton.isHidden)
    }

    @Test("Given cycle interaction, each tap selects the next rate and wraps")
    func cycleAdvancesAndWraps() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateOptions = [1, 1.5, 2]
        configuration.rateInteraction = .cycle
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView(configuration: configuration)
        view.player = player

        view.rateButton.sendActions(for: .touchUpInside)
        #expect(player.rate == 1.5)
        view.rateButton.sendActions(for: .touchUpInside)
        #expect(player.rate == 2)
        view.rateButton.sendActions(for: .touchUpInside)
        #expect(player.rate == 1)
    }

    @Test("Given a selected rate, player, label, and observer event agree")
    func selectionSynchronizesOutputs() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = player
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.selectRate(1.5)

        #expect(player.rate == 1.5)
        #expect(view.displayedRateText == "1.5×")
        #expect(events.contains(.rateSelected(1.5)))
    }

    @Test("Given an out-of-range option, selection emits the clamped rate")
    func selectionClampsInvalidRate() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = player
        var events: [ABControlsEvent] = []
        let token = view.addObserver { events.append($0) }
        defer { token.cancel() }

        view.selectRate(99)

        #expect(player.rate == ABPlaybackRate.allowedRange.upperBound)
        #expect(events.contains(.rateSelected(ABPlaybackRate.allowedRange.upperBound)))
    }

    @Test("Given hidden interaction or no options, the rate button is hidden")
    func hiddenModesHideButton() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateInteraction = .hidden
        let view = ABPlayerControlsView(configuration: configuration)
        #expect(view.rateButton.isHidden)

        configuration.rateInteraction = .menu
        configuration.rateOptions = []
        view.configuration = configuration
        #expect(view.rateButton.isHidden)
    }

    @Test("Given live rate configuration changes, button visibility and menu options rebuild")
    func configurationChangesRebuildInteraction() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateInteraction = .hidden
        let view = ABPlayerControlsView(configuration: configuration)

        configuration.rateInteraction = .menu
        configuration.rateOptions = [1, 2]
        view.configuration = configuration

        #expect(!view.rateButton.isHidden)
        #expect(view.rateButton.showsMenuAsPrimaryAction)
        #expect(view.rateButton.menu?.children.count == 2)
    }

    @Test("Given a custom time format, the configuration never compares equal to a copy of itself")
    func customTimeFormatConfigurationNeverComparesEqual() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.timeFormat = .custom { seconds, _ in "\(seconds)" }
        let copy = configuration

        // Documents the known, deliberate limitation of TimeLabelFormat's
        // Equatable conformance (closures aren't comparable) — this is the
        // premise `repeatedCustomTimeFormatUpdatesDoNotRebuildTheRateMenu`
        // guards against staying broken: SwiftUI's ABPlayerControls reassigns
        // `configuration` whenever `!=` its previous value, so this being
        // true means that guard is permanently open for `.custom` users.
        #expect(configuration != copy)
    }

    @Test("Given repeated configuration reassignments with a custom time format, the rate menu is not rebuilt")
    func repeatedCustomTimeFormatUpdatesDoNotRebuildTheRateMenu() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.timeFormat = .custom { seconds, _ in "\(seconds)" }
        let view = ABPlayerControlsView(configuration: configuration)
        let firstMenu = view.rateButton.menu

        // Simulates what ABPlayerControls.updateUIView does on every SwiftUI
        // render pass: since `.custom` values never compare equal (see the
        // test above), its `!=` guard never blocks this reassignment, even
        // though nothing about the configuration actually changed.
        for _ in 0..<5 {
            view.configuration = configuration
        }

        #expect(view.rateButton.menu === firstMenu, "reassigning an unchanged .custom configuration must not recreate the UIMenu — doing so could close one a user has open mid-interaction")
    }

    @Test("Given a hidden rate interaction and an icon label, a style change keeps the button hidden")
    func hiddenIconRateStaysHiddenAfterStyleChange() {
        var style = ABPlayerControlsStyle()
        style.rateLabelStyle = .icon(.system("speedometer"), showsValueBadge: false)
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateInteraction = .hidden
        let view = ABPlayerControlsView(style: style, configuration: configuration)
        #expect(view.rateButton.isHidden)

        var changedStyle = style
        changedStyle.tintColor = .systemPink
        view.style = changedStyle

        #expect(view.rateButton.isHidden)
    }

    @Test("Given empty rate options and an icon label, a style change keeps the button hidden")
    func emptyIconRateOptionsStayHiddenAfterStyleChange() {
        var style = ABPlayerControlsStyle()
        style.rateLabelStyle = .icon(.system("speedometer"), showsValueBadge: false)
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateInteraction = .menu
        configuration.rateOptions = []
        let view = ABPlayerControlsView(style: style, configuration: configuration)
        #expect(view.rateButton.isHidden)

        var changedStyle = style
        changedStyle.tintColor = .systemPink
        view.style = changedStyle

        #expect(view.rateButton.isHidden)
    }

    @Test("Given the default rateLabelFormat, the button title uses a locale-aware, .text-template-wrapped value")
    func automaticRateLabelFormatWrapsTheTextTemplate() {
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView()
        view.player = player

        view.selectRate(1.5)

        #expect(view.displayedRateText == "1.5×")
    }

    @Test("Given a custom rateLabelFormat, its return value is used verbatim as the whole button title — the rateLabelStyle .text template does not wrap it")
    func customRateLabelFormatBypassesTheTextTemplate() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateLabelFormat = .custom { rate in "\(rate)x-speed" }
        let player = ABPlayer(configuration: ABPlayerConfiguration(backgroundPolicy: .ignore))
        let view = ABPlayerControlsView(configuration: configuration)
        view.player = player

        view.selectRate(1.5)

        #expect(view.displayedRateText == "1.5x-speed")
    }

    @Test("Given a custom rateLabelFormat, the configuration never compares equal to a copy of itself — the same closure-identity limitation as TimeLabelFormat.custom")
    func customRateLabelFormatConfigurationNeverComparesEqual() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateLabelFormat = .custom { "\($0)" }
        let copy = configuration

        #expect(configuration != copy)
    }

    @Test("Given repeated configuration reassignments with a custom rateLabelFormat, the rate menu is not rebuilt — rateLabelFormat is deliberately excluded from the rebuild gate")
    func repeatedCustomRateLabelFormatUpdatesDoNotRebuildTheRateMenu() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateLabelFormat = .custom { "\($0)" }
        let view = ABPlayerControlsView(configuration: configuration)
        let firstMenu = view.rateButton.menu

        for _ in 0..<5 {
            view.configuration = configuration
        }

        #expect(view.rateButton.menu === firstMenu)
    }

    @Test("Every rate menu item's title matches the button's own title format for that same rate — the menu no longer hardcodes a bare \"×\" independent of rateLabelStyle")
    func menuItemTitlesMatchTheButtonsOwnFormatPath() {
        var configuration = ABPlayerControlsConfiguration()
        configuration.rateOptions = [0.5, 1, 1.5, 2]
        configuration.rateInteraction = .menu
        let view = ABPlayerControlsView(configuration: configuration)

        let titles = view.rateButton.menu?.children.compactMap { ($0 as? UIAction)?.title }

        #expect(titles == ["0.5×", "1×", "1.5×", "2×"])
    }
}
