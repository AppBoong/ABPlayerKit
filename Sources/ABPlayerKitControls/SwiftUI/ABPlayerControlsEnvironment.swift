import SwiftUI

private struct ABPlayerControlsStyleKey: EnvironmentKey {
    // Computed, not a stored `static let` — `ABPlayerControlsStyle`'s own
    // presets (`.default`/`.minimal`/`.tinted`) are `@MainActor static let`,
    // so a stored default referencing one of them would mix a nonisolated
    // static storage requirement with MainActor-isolated content. Returning
    // the sentinel `nil` directly sidesteps that entirely.
    static var defaultValue: ABPlayerControlsStyle? { nil }
}

private struct ABPlayerControlsConfigurationKey: EnvironmentKey {
    static var defaultValue: ABPlayerControlsConfiguration? { nil }
}

extension EnvironmentValues {
    /// The style an ancestor view set with `.playerControlsStyle(_:)`.
    /// `nil` means "unspecified" — resolution order is an initializer's own
    /// `style:` argument, then this value, then `ABPlayerControlsStyle.default`.
    public var playerControlsStyle: ABPlayerControlsStyle? {
        get { self[ABPlayerControlsStyleKey.self] }
        set { self[ABPlayerControlsStyleKey.self] = newValue }
    }

    /// The configuration an ancestor view set with
    /// `.playerControlsConfiguration(_:)`. `nil` means "unspecified" —
    /// resolution order is an initializer's own `configuration:` argument,
    /// then this value, then `ABPlayerControlsConfiguration()`.
    public var playerControlsConfiguration: ABPlayerControlsConfiguration? {
        get { self[ABPlayerControlsConfigurationKey.self] }
        set { self[ABPlayerControlsConfigurationKey.self] = newValue }
    }
}

extension View {
    /// Sets the controls style for every player-controls view in this
    /// view's subtree that doesn't specify its own `style:` initializer
    /// argument — an explicit argument always wins over this modifier.
    public func playerControlsStyle(_ style: ABPlayerControlsStyle) -> some View {
        environment(\.playerControlsStyle, style)
    }

    /// Sets the controls configuration for every player-controls view in
    /// this view's subtree that doesn't specify its own `configuration:`
    /// initializer argument — an explicit argument always wins over this
    /// modifier.
    public func playerControlsConfiguration(_ configuration: ABPlayerControlsConfiguration) -> some View {
        environment(\.playerControlsConfiguration, configuration)
    }
}
