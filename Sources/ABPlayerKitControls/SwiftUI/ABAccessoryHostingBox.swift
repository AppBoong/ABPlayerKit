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
/// 4. Parent `UIViewController` attachment — `attach(to:)` walks the
///    responder chain from the view the caller supplies (call once that view
///    has a non-nil `window`, so the chain is actually connected) and, if a
///    `UIViewController` is found, performs the full `addChild` →
///    `didMove(toParent:)` handshake `detach()` reverses.
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
    private(set) var isAttachedToParent = false

    var view: UIView { controller.view }

    init<Content: View>(@ViewBuilder content: () -> Content) {
        controller = UIHostingController(rootView: AnyView(content()))
        controller.sizingOptions = [.intrinsicContentSize]
        controller.view.backgroundColor = .clear
        controller.view.translatesAutoresizingMaskIntoConstraints = false
    }

    func update<Content: View>(@ViewBuilder content: () -> Content) {
        controller.rootView = AnyView(content())
    }

    /// Walks `parentSearchOrigin`'s responder chain for the nearest
    /// `UIViewController` and, if found, adopts `controller` as its child.
    /// A no-op if already attached, or if no `UIViewController` is found
    /// (see item 5 above) — safe to call repeatedly, e.g. on every SwiftUI
    /// update pass, until it succeeds.
    func attach(to parentSearchOrigin: UIView) {
        guard !isAttachedToParent else { return }
        guard let parent = Self.nearestViewController(from: parentSearchOrigin) else { return }
        parent.addChild(controller)
        controller.didMove(toParent: parent)
        isAttachedToParent = true
    }

    /// Reverses `attach(to:)`. A no-op if never attached.
    func detach() {
        guard isAttachedToParent else { return }
        controller.willMove(toParent: nil)
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
