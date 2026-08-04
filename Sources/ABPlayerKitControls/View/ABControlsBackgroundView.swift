import UIKit

@MainActor
final class ABControlsBackgroundView: UIView {
    private(set) var renderedContentView: UIView?
    private(set) var gradientLayer: CAGradientLayer?
    private var currentStyle: ABControlsBackgroundStyle?

    @discardableResult
    func apply(_ style: ABControlsBackgroundStyle) -> Bool {
        if let currentStyle, Self.hasSameKind(currentStyle, style) {
            update(style)
            self.currentStyle = style
            return false
        }

        renderedContentView?.removeFromSuperview()
        renderedContentView = nil
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
        backgroundColor = .clear

        switch style {
        case .none:
            break
        case .color(let color):
            backgroundColor = color
        case .gradient(let top, let bottom):
            let gradient = CAGradientLayer()
            gradient.colors = [top.cgColor, bottom.cgColor]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
            layer.addSublayer(gradient)
            gradientLayer = gradient
        case .blur(let effectStyle):
            let effectView = UIVisualEffectView(effect: UIBlurEffect(style: effectStyle))
            effectView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(effectView)
            NSLayoutConstraint.activate([
                effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                effectView.topAnchor.constraint(equalTo: topAnchor),
                effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            renderedContentView = effectView
        }
        currentStyle = style
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
    }

    private func update(_ style: ABControlsBackgroundStyle) {
        switch style {
        case .none:
            break
        case .color(let color):
            backgroundColor = color
        case .gradient(let top, let bottom):
            gradientLayer?.colors = [top.cgColor, bottom.cgColor]
        case .blur(let effectStyle):
            (renderedContentView as? UIVisualEffectView)?.effect = UIBlurEffect(style: effectStyle)
        }
    }

    private static func hasSameKind(
        _ lhs: ABControlsBackgroundStyle,
        _ rhs: ABControlsBackgroundStyle
    ) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none), (.color, .color), (.gradient, .gradient), (.blur, .blur):
            true
        default:
            false
        }
    }
}
