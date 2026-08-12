import ABPlayerKit
import SwiftUI

/// A SwiftUI wrapper around ``ABPlayerControlsView``.
@MainActor
public struct ABPlayerControls: UIViewRepresentable {
    private let player: ABPlayer
    /// `nil` means "unspecified" — resolved against
    /// `EnvironmentValues.playerControlsStyle` and finally
    /// `ABPlayerControlsStyle.default` in `resolveStyle(environment:)`.
    private let style: ABPlayerControlsStyle?
    /// `nil` means "unspecified" — resolved the same way as `style`, via
    /// `resolveConfiguration(environment:)`.
    private let configuration: ABPlayerControlsConfiguration?
    private let accessoryViews: [UIView]
    private let accessoriesContent: (() -> AnyView)?
    private let onEvent: (@MainActor (ABControlsEvent) -> Void)?

    @available(*, deprecated, message: "Use the @ViewBuilder `accessories:` initializer instead. Scheduled for removal in 1.0.0.")
    public init(
        player: ABPlayer,
        style: ABPlayerControlsStyle? = nil,
        configuration: ABPlayerControlsConfiguration? = nil,
        accessoryViews: [UIView] = [],
        onEvent: (@MainActor (ABControlsEvent) -> Void)? = nil
    ) {
        self.init(
            legacyPlayer: player,
            style: style,
            configuration: configuration,
            accessoryViews: accessoryViews,
            onEvent: onEvent
        )
    }

    /// The array-based designated initializer's actual implementation, kept
    /// separate (and separately labeled, since Swift can't overload two
    /// initializers by attributes/access level alone) so
    /// `ABVideoPlayerWithControls`'s own legacy `accessoryViews:` bridge can
    /// reach it without tripping a "reference to deprecated declaration"
    /// warning under `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`: that warning
    /// fires at any *non-deprecated* call site, and
    /// `ABVideoPlayerWithControls.body`'s `some View` computed property
    /// can't itself be marked deprecated without also suppressing warnings
    /// for its unrelated, non-deprecated accessories path.
    ///
    /// Deprecated too, not just the public initializer
    /// above — this is still the array-based, legacy shape, and leaving
    /// this one bare would let future *internal* code adopt it silently,
    /// with no nudge toward `accessories:`. `ABVideoPlayerWithControls`'s
    /// one legitimate call site wraps this in its own deprecated bridge
    /// (`legacyControlsView`) rather than calling it directly, for the same
    /// "deprecated calling deprecated doesn't warn" reason this
    /// initializer itself exists.
    @available(*, deprecated, message: "Internal bridge for the deprecated accessoryViews: initializer above — not part of the public API.")
    init(
        legacyPlayer player: ABPlayer,
        style: ABPlayerControlsStyle?,
        configuration: ABPlayerControlsConfiguration?,
        accessoryViews: [UIView],
        onEvent: (@MainActor (ABControlsEvent) -> Void)?
    ) {
        self.player = player
        self.style = style
        self.configuration = configuration
        self.accessoryViews = accessoryViews
        self.accessoriesContent = nil
        self.onEvent = onEvent
    }

    /// SwiftUI accessory overlay content, hosted via `ABAccessoryHostingBox`.
    /// `accessories` is the last
    /// parameter so a trailing closure reads naturally; `onEvent` sits right
    /// before it specifically to avoid trailing-closure ambiguity between the
    /// two `(@MainActor (...) -> Void)`-shaped parameters.
    ///
    /// `Accessories == EmptyView` (the default, unadorned call) skips
    /// creating a hosting controller entirely — there is nothing to host,
    /// and standing one up anyway would be a pure cost with no observable
    /// benefit.
    public init<Accessories: View>(
        player: ABPlayer,
        style: ABPlayerControlsStyle? = nil,
        configuration: ABPlayerControlsConfiguration? = nil,
        onEvent: (@MainActor (ABControlsEvent) -> Void)? = nil,
        @ViewBuilder accessories: @escaping () -> Accessories
    ) {
        self.player = player
        self.style = style
        self.configuration = configuration
        self.accessoryViews = []
        self.accessoriesContent = Accessories.self == EmptyView.self ? nil : { AnyView(accessories()) }
        self.onEvent = onEvent
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    public func makeUIView(context: Context) -> ABPlayerControlsView {
        let view = ABPlayerControlsView(
            style: resolveStyle(environment: context.environment),
            configuration: resolveConfiguration(environment: context.environment)
        )
        update(view, coordinator: context.coordinator, environment: context.environment)
        return view
    }

    public func updateUIView(_ uiView: ABPlayerControlsView, context: Context) {
        update(uiView, coordinator: context.coordinator, environment: context.environment)
    }

    func update(_ view: ABPlayerControlsView, coordinator: Coordinator, environment: EnvironmentValues = EnvironmentValues()) {
        let resolvedStyle = resolveStyle(environment: environment)
        let resolvedConfiguration = resolveConfiguration(environment: environment)
        if view.player !== player {
            view.player = player
        }
        if view.style != resolvedStyle {
            view.style = resolvedStyle
        }
        if view.configuration != resolvedConfiguration {
            view.configuration = resolvedConfiguration
        }
        if let accessoriesContent {
            let box = coordinator.accessoryBox(makingIfNeeded: accessoriesContent)
            box.update { accessoriesContent() }
            if view.accessoryViews != [box.view] {
                view.accessoryViews = [box.view]
            }
            // No explicit attach() call here — `box.view` observes its own
            // `didMoveToWindow` and attaches itself the moment it actually
            // lands in a window (see `ABAccessoryHostingBox`'s doc comment).
            // `update(_:coordinator:)` running before
            // that happens (e.g. right after `makeUIView`, before this view
            // has any window) no longer matters.
        } else if view.accessoryViews != accessoryViews {
            view.accessoryViews = accessoryViews
        }
        coordinator.onEvent = onEvent
        coordinator.observe(view)
    }

    /// An explicit `style:` initializer argument always wins over the
    /// `.playerControlsStyle(_:)` environment value — a local, explicit
    /// declaration is more specific than an ambient one, the same
    /// convention SwiftUI itself follows (e.g. `.font` on a `Text` versus
    /// an inherited font).
    private func resolveStyle(environment: EnvironmentValues) -> ABPlayerControlsStyle {
        style ?? environment.playerControlsStyle ?? .default
    }

    private func resolveConfiguration(environment: EnvironmentValues) -> ABPlayerControlsConfiguration {
        configuration ?? environment.playerControlsConfiguration ?? .init()
    }

    @MainActor
    public final class Coordinator {
        var onEvent: (@MainActor (ABControlsEvent) -> Void)?
        private weak var observedView: ABPlayerControlsView?
        private var observationToken: ABObservationToken?
        private var accessoryBox: ABAccessoryHostingBox?

        init(onEvent: (@MainActor (ABControlsEvent) -> Void)?) {
            self.onEvent = onEvent
        }

        func observe(_ view: ABPlayerControlsView) {
            guard observedView !== view else { return }
            observationToken?.cancel()
            observedView = view
            observationToken = view.addObserver { [weak self] event in
                self?.onEvent?(event)
            }
        }

        /// Lazily creates and retains the accessory hosting box for the
        /// lifetime of this coordinator, so it survives across
        /// `ABPlayerControls` value-struct reconstructions between SwiftUI
        /// update passes.
        func accessoryBox<Content: View>(makingIfNeeded content: @escaping () -> Content) -> ABAccessoryHostingBox {
            if let accessoryBox {
                return accessoryBox
            }
            let box = ABAccessoryHostingBox(content: content)
            accessoryBox = box
            return box
        }

        deinit {
            observationToken?.cancel()
            // `accessoryBox?.detach()` can't run directly here: `deinit` on
            // an ordinary (non-isolated) class isn't guaranteed to run on
            // the MainActor even though this class itself is
            // `@MainActor`-isolated, so calling `detach()` (MainActor-isolated)
            // synchronously would be a data-race risk the compiler correctly
            // rejects. `isolated deinit` (SE-0371) would fix this cleanly,
            // but it needs `swift-tools-version: 6.1`+ and this package
            // declares `6.0` — bumping the floor is a
            // bigger, separate decision than this one cleanup, so this hops
            // to the MainActor asynchronously instead. `MainActor.assumeIsolated`
            // is not an option either — avoided here for the same reason
            // `@unchecked Sendable` isn't used to silence a captured-actor-isolation
            // diagnostic: `deinit` genuinely isn't statically known to already
            // be on the MainActor here, so *assuming* it would be exactly the
            // kind of unchecked escape hatch that convention exists to prevent.
            // The async detach still runs promptly (the next MainActor
            // turn) and is safe to run after this instance is already
            // gone — it only touches `accessoryBox`, captured by value.
            if let accessoryBox {
                Task { @MainActor in
                    accessoryBox.detach()
                }
            }
        }
    }
}
