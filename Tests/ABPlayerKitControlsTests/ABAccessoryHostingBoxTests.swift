import ABTestSupport
import SwiftUI
import Testing
import UIKit
@testable import ABPlayerKitControls

@Suite("ABAccessoryHostingBox owns a UIHostingController safely, handling every Q6 failure mode explicitly", .timeLimit(abScaledMinutes(3)))
@MainActor
struct ABAccessoryHostingBoxTests {
    @Test("Given a box, its view stays addable and retained once inserted into a hierarchy")
    func viewStaysAddableAndRetained() {
        let box = ABAccessoryHostingBox { Text("Accessory") }
        let container = UIView()

        container.addSubview(box.view)

        #expect(box.view.superview === container)
        #expect(container.subviews.contains(box.view))
    }

    @Test("Given an update to larger content, the hosted view's intrinsic content size grows to match")
    func updateChangesRenderedContent() {
        let box = ABAccessoryHostingBox { Color.clear.frame(width: 10, height: 10) }
        box.view.layoutIfNeeded()
        let smallSize = box.view.intrinsicContentSize

        box.update { Color.clear.frame(width: 300, height: 300) }
        box.view.layoutIfNeeded()
        let largeSize = box.view.intrinsicContentSize

        #expect(largeSize.width > smallSize.width)
        #expect(largeSize.height > smallSize.height)
    }

    @Test("Given a view controller in the responder chain, attach adopts it as a child and detach releases it")
    func attachAdoptsParentAndDetachReleasesIt() {
        let box = ABAccessoryHostingBox { Text("Accessory") }
        let rootViewController = UIViewController()
        let searchOrigin = UIView()
        rootViewController.view.addSubview(searchOrigin)
        searchOrigin.addSubview(box.view)

        box.attach(to: searchOrigin)

        #expect(box.isAttachedToParent)
        #expect(rootViewController.children.count == 1)

        box.detach()

        #expect(!box.isAttachedToParent)
        #expect(rootViewController.children.isEmpty)
        // Standard child-VC teardown order (round4 review mn-6): the view
        // comes out of its superview too, not just the addChild relationship.
        #expect(box.view.superview == nil)
    }

    @Test("Given the box's view is added to a real window-backed hierarchy through the ordinary first-display path — no explicit attach(to:) call — it attaches itself automatically once it actually reaches a window")
    func attachFiresAutomaticallyOnOrdinaryFirstDisplay() {
        // Reproduces MJ-2's exact repro shape: a static accessory (no
        // content updates, so nothing re-triggers a SwiftUI update pass)
        // inserted into a view controller's hierarchy *before* that
        // hierarchy is windowed — mirroring `makeUIView` building the view
        // tree first and the window attaching only afterward.
        let box = ABAccessoryHostingBox { Text("Accessory") }
        let rootViewController = UIViewController()
        rootViewController.view.addSubview(box.view)
        #expect(!box.isAttachedToParent, "must not attach before a window exists")

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = rootViewController
        window.isHidden = false
        defer { window.isHidden = true }

        #expect(box.isAttachedToParent)
        #expect(rootViewController.children.count == 1)
    }

    @Test("Given a hosting box, its view background is transparent so it never paints an opaque rectangle over the overlay")
    func backgroundIsTransparent() {
        let box = ABAccessoryHostingBox { Text("Accessory") }

        #expect(box.view.backgroundColor == .clear)
    }

    @Test("Given non-empty SwiftUI content, the hosted view's intrinsic content size is non-zero")
    func intrinsicContentSizeIsNonZero() {
        let box = ABAccessoryHostingBox {
            Text("Accessory").padding()
        }
        box.view.layoutIfNeeded()

        let size = box.view.intrinsicContentSize
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    @Test("Given no view controller anywhere in the responder chain, attach neither crashes nor marks itself attached")
    func attachWithoutParentDoesNotCrash() {
        let box = ABAccessoryHostingBox { Text("Accessory") }
        let orphanContainer = UIView()
        orphanContainer.addSubview(box.view)

        box.attach(to: orphanContainer)

        #expect(!box.isAttachedToParent)
    }
}
