import SwiftUI
import UIKit

/// Owns a `UIHostingController<AnyView>` so a SwiftUI accessory view can sit
/// inside `ABPlayerControlsView.accessoryViews` (a plain `[UIView]`) without
/// that API knowing anything about SwiftUI (see `DESIGN-OPEN-QUESTIONS.md`
/// Q6-A — this type is the mitigation Q6-A commits to for the hosting risk
/// Q6 originally flagged).
///
/// Every failure mode Q6 raised is handled explicitly here, not silently:
/// 1. `sizingOptions = [.intrinsicContentSize]` — without it, the
///    `UIStackView` this view sits in has no way to size it and it collapses
///    to 0×0.
/// 2. `view.backgroundColor = .clear` — `UIHostingController` defaults to an
///    opaque system background, which would paint a rectangle over the
///    overlay it's meant to sit transparently inside.
/// 3. `translatesAutoresizingMaskIntoConstraints = false`, matching every
///    other view `ABPlayerControlsView` lays out with Auto Layout.
/// 4. Parent `UIViewController` attachment — `view` is a thin
///    `ABAccessoryHostingContainerView` wrapping `controller.view`,
///    specifically so it can override `didMoveToWindow` (a `UIHostingController`'s
///    own `view` is a private SwiftUI type and can't be subclassed to add
///    that hook). The moment `view` actually lands in a window — the real
///    first-display signal, not merely being inserted into
///    `accessoryViews`, which can happen before the whole controls view is
///    itself windowed — the container walks its own responder chain for the
///    nearest `UIViewController` and, if found, performs the full
///    `addChild` → `didMove(toParent:)` handshake `detach()` reverses.
///    (round4 review MJ-2: an earlier version triggered this only from
///    `ABPlayerControls.update(_:coordinator:)`, which runs once at
///    `makeUIView` time — before the view has any window — and is never
///    guaranteed to run again afterward for static accessory content, so
///    attachment silently never happened on the ordinary first-display
///    path. Self-observing `didMoveToWindow` fixes this at the source
///    instead of depending on a caller's update cadence.)
/// 5. **If no parent is found**, this box's `view` still lays out and
///    renders — it's already a plain `UIView` in the hierarchy — but
///    safe-area propagation, `UIViewController` appearance callbacks, and
///    trait inheritance into the hosted SwiftUI content are not guaranteed.
///    This is Q6's original risk, deliberately left visible rather than
///    hidden: `attach(to:)` just returns without attaching, and callers that
///    need the guarantee should ensure their view sits inside a real
///    `UIViewController`'s hierarchy.
/// 6. `update(content:)` reassigns `controller.rootView` on every call —
///    SwiftUI diffs internally, so the `[UIView]`-era `!=` guard some
///    callers used to avoid unnecessary rebuilds doesn't need reproducing
///    here.
@MainActor
final class ABAccessoryHostingBox {
    private let controller: UIHostingController<AnyView>
    private let container = ABAccessoryHostingContainerView()
    private(set) var isAttachedToParent = false

    var view: UIView { container }

    init<Content: View>(@ViewBuilder content: () -> Content) {
        controller = UIHostingController(rootView: AnyView(content()))
        controller.sizingOptions = [.intrinsicContentSize]
        controller.view.backgroundColor = .clear
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false
        container.install(hostedView: controller.view)
        container.onDidMoveToWindow = { [weak self] in
            guard let self else { return }
            attach(to: container)
        }
    }

    func update<Content: View>(@ViewBuilder content: () -> Content) {
        controller.rootView = AnyView(content())
        container.invalidateIntrinsicContentSize()
    }

    /// Walks `parentSearchOrigin`'s responder chain for the nearest
    /// `UIViewController` and, if found, adopts `controller` as its child.
    /// A no-op if already attached, or if no `UIViewController` is found
    /// (see item 5 above). Called automatically once `view` reaches a
    /// window (item 4) — exposed publicly too, so a caller with a more
    /// specific origin in mind (or a reason to retry explicitly) still can.
    func attach(to parentSearchOrigin: UIView) {
        guard !isAttachedToParent else { return }
        guard let parent = Self.nearestViewController(from: parentSearchOrigin) else { return }
        parent.addChild(controller)
        controller.didMove(toParent: parent)
        isAttachedToParent = true
    }

    /// Reverses `attach(to:)` in the standard child-view-controller order
    /// (`willMove(toParent:)` → remove the view from its superview →
    /// `removeFromParent()`). A no-op if never attached.
    func detach() {
        guard isAttachedToParent else { return }
        controller.willMove(toParent: nil)
        container.removeFromSuperview()
        controller.removeFromParent()
        isAttachedToParent = false
    }

    private static func nearestViewController(from view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

/// Thin container solely so `ABAccessoryHostingBox` can observe
/// `didMoveToWindow` — `UIHostingController.view`'s concrete type is a
/// private SwiftUI implementation detail and can't be subclassed for this.
/// Forwards its intrinsic content size from the hosted view, pinned to fill
/// this container exactly, so it sizes identically to hosting `controller.view`
/// directly would have.
private final class ABAccessoryHostingContainerView: UIView {
    var onDidMoveToWindow: (() -> Void)?
    private weak var hostedView: UIView?

    func install(hostedView: UIView) {
        self.hostedView = hostedView
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override var intrinsicContentSize: CGSize {
        hostedView?.intrinsicContentSize ?? super.intrinsicContentSize
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        onDidMoveToWindow?()
    }
}
