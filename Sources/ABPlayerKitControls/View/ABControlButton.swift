import UIKit

@MainActor
final class ABControlButton: UIButton {
    private(set) var resolvedIcon: ABControlIcon?

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
        resolvedIcon = icon
        highlightedAlpha = min(max(style.buttonHighlightedAlpha, 0), 1)
        switch icon {
        case .system(let name):
            let configuration = UIImage.SymbolConfiguration(
                pointSize: style.iconPointSize,
                weight: style.iconWeight
            )
            let image = UIImage(systemName: name, withConfiguration: configuration)?
                .withRenderingMode(style.iconRenderingMode)
            setImage(image, for: .normal)
            isHidden = image == nil
        case .image(let image):
            setImage(image.withRenderingMode(style.iconRenderingMode), for: .normal)
            imageView?.contentMode = .scaleAspectFit
            isHidden = false
        case .none:
            setImage(nil, for: .normal)
            isHidden = true
        }
        tintColor = style.tintColor
        accessibilityTraits.insert(.button)
        invalidateIntrinsicContentSize()
    }
}
