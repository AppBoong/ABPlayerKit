import ABPlayerKit
import SwiftUI

/// A SwiftUI wrapper around ``ABPlayerControlsView``.
@MainActor
public struct ABPlayerControls: UIViewRepresentable {
    private let player: ABPlayer
    private let style: ABPlayerControlsStyle
    private let configuration: ABPlayerControlsConfiguration
    private let accessoryViews: [UIView]
    private let accessoriesContent: (() -> AnyView)?
    private let onEvent: (@MainActor (ABControlsEvent) -> Void)?

    @available(*, deprecated, message: "Use the @ViewBuilder `accessories:` initializer instead. Scheduled for removal in 1.0.0.")
    public init(
        player: ABPlayer,
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init(),
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

    /// Not deprecated — the array-based designated initializer's actual
    /// implementation, kept separate (and separately labeled, since Swift
    /// can't overload two initializers by attributes/access level alone) so
    /// `ABVideoPlayerWithControls`'s own legacy `accessoryViews:` bridge can
    /// reach it without tripping a "reference to deprecated declaration"
    /// warning under `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` (see
    /// ROADMAP-round4.md WP-B3's "CI 함정" note — that warning fires at any
    /// *non-deprecated* call site, and `ABVideoPlayerWithControls.body`'s
    /// `some View` computed property can't itself be marked deprecated
    /// without also suppressing warnings for its unrelated, non-deprecated
    /// accessories path).
    init(
        legacyPlayer player: ABPlayer,
        style: ABPlayerControlsStyle,
        configuration: ABPlayerControlsConfiguration,
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

    /// SwiftUI accessory overlay content, hosted via `ABAccessoryHostingBox`
    /// (see `DESIGN-OPEN-QUESTIONS.md` Q6-A). `accessories` is the last
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
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init(),
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
        let view = ABPlayerControlsView(style: style, configuration: configuration)
        update(view, coordinator: context.coordinator)
        return view
    }

    public func updateUIView(_ uiView: ABPlayerControlsView, context: Context) {
        update(uiView, coordinator: context.coordinator)
    }

    func update(_ view: ABPlayerControlsView, coordinator: Coordinator) {
        if view.player !== player {
            view.player = player
        }
        if view.style != style {
            view.style = style
        }
        if view.configuration != configuration {
            view.configuration = configuration
        }
        if let accessoriesContent {
            let box = coordinator.accessoryBox(makingIfNeeded: accessoriesContent)
            box.update { accessoriesContent() }
            if view.accessoryViews != [box.view] {
                view.accessoryViews = [box.view]
            }
            if view.window != nil {
                box.attach(to: view)
            }
        } else if view.accessoryViews != accessoryViews {
            view.accessoryViews = accessoryViews
        }
        coordinator.onEvent = onEvent
        coordinator.observe(view)
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

        isolated deinit {
            observationToken?.cancel()
            accessoryBox?.detach()
        }
    }
}
