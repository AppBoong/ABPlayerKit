import UIKit

/// The transient "+20s"/"-10s" badge for cumulative skip/double-tap/VoiceOver
/// seeks. A pure renderer — the delta it displays is computed by the caller
/// from `pendingSeekTime`; this view never accumulates anything itself.
@MainActor
final class ABSeekFeedbackView: UIView {
    private let label = UILabel()
    private(set) var isVisible = false
    private(set) var lastAnimationDuration: TimeInterval?

    var text: String? { label.text }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = false
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    func apply(_ style: ABPlayerControlsStyle) {
        label.textColor = style.seekFeedbackTextColor
        label.font = style.seekFeedbackFont
        backgroundColor = style.seekFeedbackBackgroundColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func show(deltaSeconds: Double, animated: Bool, reduceMotion: Bool, duration: TimeInterval) {
        label.text = Self.formattedDelta(deltaSeconds)
        isVisible = true
        setAlpha(1, animated: animated, reduceMotion: reduceMotion, duration: duration)
    }

    func dismiss(animated: Bool, reduceMotion: Bool, duration: TimeInterval) {
        guard isVisible else { return }
        isVisible = false
        setAlpha(0, animated: animated, reduceMotion: reduceMotion, duration: duration)
    }

    private func setAlpha(_ value: CGFloat, animated: Bool, reduceMotion: Bool, duration: TimeInterval) {
        let effectiveDuration = reduceMotion ? 0 : duration
        lastAnimationDuration = animated ? effectiveDuration : 0
        guard animated, effectiveDuration > 0 else {
            alpha = value
            return
        }
        UIView.animate(withDuration: effectiveDuration) { [self] in alpha = value }
    }

    private static func formattedDelta(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        let sign = rounded >= 0 ? "+" : "-"
        return "\(sign)\(abs(rounded))s"
    }
}
