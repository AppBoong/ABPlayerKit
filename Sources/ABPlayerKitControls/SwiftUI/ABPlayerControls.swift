import ABPlayerKit
import SwiftUI

/// A SwiftUI wrapper around ``ABPlayerControlsView``.
@MainActor
public struct ABPlayerControls: UIViewRepresentable {
    private let player: ABPlayer
    private let style: ABPlayerControlsStyle
    private let configuration: ABPlayerControlsConfiguration
    private let accessoryViews: [UIView]
    private let onEvent: (@MainActor (ABControlsEvent) -> Void)?

    public init(
        player: ABPlayer,
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init(),
        accessoryViews: [UIView] = [],
        onEvent: (@MainActor (ABControlsEvent) -> Void)? = nil
    ) {
        self.player = player
        self.style = style
        self.configuration = configuration
        self.accessoryViews = accessoryViews
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
        if view.accessoryViews != accessoryViews {
            view.accessoryViews = accessoryViews
        }
        coordinator.onEvent = onEvent
        coordinator.attach(to: view)
    }

    @MainActor
    public final class Coordinator {
        var onEvent: (@MainActor (ABControlsEvent) -> Void)?
        private weak var observedView: ABPlayerControlsView?
        private var observationToken: ABObservationToken?

        init(onEvent: (@MainActor (ABControlsEvent) -> Void)?) {
            self.onEvent = onEvent
        }

        func attach(to view: ABPlayerControlsView) {
            guard observedView !== view else { return }
            observationToken?.cancel()
            observedView = view
            observationToken = view.addObserver { [weak self] event in
                self?.onEvent?(event)
            }
        }

        deinit {
            observationToken?.cancel()
        }
    }
}
