import UIKit

@MainActor
final class ABControlButton: UIButton {
    private(set) var resolvedIcon: ABControlIcon?
    /// The number composited onto `resolvedIcon` when no SF Symbol variant exists
    /// for the configured skip interval (e.g. `gobackward.20`). `nil` when the
    /// button renders a plain icon.
    private(set) var resolvedSkipBadgeNumber: Int?
    /// The image `resolvedIcon` last resolved to, independent of whether it's
    /// currently being shown — `isGlyphSuppressed` needs this to restore the
    /// glyph without recomputing it (SF Symbol lookup, badge compositing).
    private var resolvedImage: UIImage?

    /// Hides the glyph without touching `isHidden`/`alpha` — both of those
    /// remove the button from `UIView.hitTest`, which a buffering stall must
    /// not do (the button stays tappable to pause). Only the button this
    /// view suppresses during buffering ever sets this.
    var isGlyphSuppressed = false {
        didSet {
            guard isGlyphSuppressed != oldValue else { return }
            applyGlyphVisibility()
        }
    }

    private var highlightedAlpha: CGFloat = 0.5

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? highlightedAlpha : 1 }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let horizontalExpansion = max(0, (44 - bounds.width) / 2)
        let verticalExpansion = max(0, (44 - bounds.height) / 2)
        return bounds.insetBy(dx: -horizontalExpansion, dy: -verticalExpansion).contains(point)
    }

    func apply(icon: ABControlIcon, style: ABPlayerControlsStyle) {
        resolvedSkipBadgeNumber = nil
        applyBaseIcon(icon, style: style)
    }

    /// Applies a skip-button icon, optionally compositing `badgeNumber` over it when
    /// no SF Symbol exists for the configured interval (e.g. `gobackward.20`).
    func applySkip(icon: ABControlIcon, badgeNumber: Int?, style: ABPlayerControlsStyle) {
        resolvedSkipBadgeNumber = badgeNumber
        guard let badgeNumber, case .system(let name) = icon else {
            applyBaseIcon(icon, style: style)
            return
        }
        resolvedIcon = icon
        highlightedAlpha = min(max(style.buttonHighlightedAlpha, 0), 1)
        resolvedImage = Self.badgedSymbolImage(named: name, number: badgeNumber, style: style)
        applyGlyphVisibility()
        tintColor = style.tintColor
        accessibilityTraits.insert(.button)
        invalidateIntrinsicContentSize()
    }

    private func applyBaseIcon(_ icon: ABControlIcon, style: ABPlayerControlsStyle) {
        resolvedIcon = icon
        highlightedAlpha = min(max(style.buttonHighlightedAlpha, 0), 1)
        switch icon {
        case .system(let name):
            let configuration = UIImage.SymbolConfiguration(
                pointSize: style.iconPointSize,
                weight: style.iconWeight
            )
            resolvedImage = UIImage(systemName: name, withConfiguration: configuration)?
                .withRenderingMode(style.iconRenderingMode)
        case .image(let image):
            resolvedImage = image.withRenderingMode(style.iconRenderingMode)
            imageView?.contentMode = .scaleAspectFit
        case .none:
            resolvedImage = nil
        }
        applyGlyphVisibility()
        tintColor = style.tintColor
        accessibilityTraits.insert(.button)
        invalidateIntrinsicContentSize()
    }

    /// The single point that reconciles `resolvedImage` with what's actually
    /// drawn — called after every icon resolution and every
    /// `isGlyphSuppressed` change, so the two can never disagree.
    private func applyGlyphVisibility() {
        setImage(isGlyphSuppressed ? nil : resolvedImage, for: .normal)
        isHidden = resolvedImage == nil && !isGlyphSuppressed
    }

    /// Draws `number` centered over the symbol as a template image (alpha channel
    /// only), mimicking the built-in `gobackward.N`/`goforward.N` glyphs for
    /// intervals none of them cover. Staying template-rendered lets the button's
    /// `tintColor` (including the disabled-state color) recolor it live, the same
    /// as every other icon on this button.
    private static func badgedSymbolImage(named name: String, number: Int, style: ABPlayerControlsStyle) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: style.iconPointSize, weight: style.iconWeight)
        guard let base = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        let opaqueBase = base.withTintColor(.black, renderingMode: .alwaysOriginal)
        let renderer = UIGraphicsImageRenderer(size: opaqueBase.size)
        let composed = renderer.image { _ in
            opaqueBase.draw(in: CGRect(origin: .zero, size: opaqueBase.size))
            let fontSize = opaqueBase.size.height * 0.36
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let text = "\(number)" as NSString
            let textSize = text.size(withAttributes: attributes)
            let origin = CGPoint(
                x: (opaqueBase.size.width - textSize.width) / 2,
                y: (opaqueBase.size.height - textSize.height) / 2 + opaqueBase.size.height * 0.05
            )
            text.draw(at: origin, withAttributes: attributes)
        }
        return composed.withRenderingMode(.alwaysTemplate)
    }
}
