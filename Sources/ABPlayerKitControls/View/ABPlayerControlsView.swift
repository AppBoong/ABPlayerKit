@preconcurrency import AVFoundation
import ABPlayerKit
import UIKit

/// A UIKit playback-controls overlay backed by the core playback engine.
@MainActor
public final class ABPlayerControlsView: UIView, UIGestureRecognizerDelegate {
    public var player: ABPlayer? {
        didSet {
            guard player !== oldValue else { return }
            replacePlayer()
        }
    }

    public var style: ABPlayerControlsStyle {
        didSet { applyStyle(previous: oldValue) }
    }

    public var configuration: ABPlayerControlsConfiguration {
        didSet { applyConfiguration(previous: oldValue) }
    }

    public private(set) var isControlsVisible: Bool

    public var accessoryViews: [UIView] {
        get { accessoryStack.arrangedSubviews }
        set {
            for view in accessoryStack.arrangedSubviews {
                accessoryStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            for view in newValue {
                accessoryStack.addArrangedSubview(view)
            }
        }
    }

    let playPauseButton = ABControlButton(type: .custom)
    let skipBackwardButton = ABControlButton(type: .custom)
    let skipForwardButton = ABControlButton(type: .custom)
    let rateButton = ABControlButton(type: .custom)
    let seekBar = ABSeekBar()
    let elapsedLabel = UILabel()
    private let accessoryStack = UIStackView()
    private let buttonStack = UIStackView()
    private let bottomStack = UIStackView()
    private let rootStack = UIStackView()
    private let controlsContentView = UIView()
    private let controlsBackgroundView = ABControlsBackgroundView()
    private let observerRegistry = ABControlsObserverRegistry()
    private var playerObservationToken: ABObservationToken?
    private var periodicIntervalLease: ABPeriodicIntervalLease?
    private weak var scrubbingPlayer: ABPlayer?
    private var isPlayingState = false
    private var currentPlaybackTime = ABPlaybackTime.zero
    private var visibilityMachine: ABControlsVisibilityMachine
    private var presenter = ABControlsPresenter()
    private var hideTask: Task<Void, Never>?
    var isVoiceOverRunningProvider: @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }
    var isReduceMotionEnabledProvider: @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled }
    private(set) var lastVisibilityAnimationDuration: TimeInterval?
    /// The duration of the most recently triggered play/pause bounce, or `nil`
    /// if the last tap skipped it (Reduce Motion). Exposes the trigger path for tests.
    private(set) var lastPlayPauseBounceDuration: TimeInterval?
    private lazy var backgroundTapRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(backgroundTapped)
    )

    private var playWidthConstraint: NSLayoutConstraint?
    private var playHeightConstraint: NSLayoutConstraint?
    private var backwardWidthConstraint: NSLayoutConstraint?
    private var backwardHeightConstraint: NSLayoutConstraint?
    private var forwardWidthConstraint: NSLayoutConstraint?
    private var forwardHeightConstraint: NSLayoutConstraint?
    private var rateWidthConstraint: NSLayoutConstraint?
    private var rateHeightConstraint: NSLayoutConstraint?
    private var elapsedMinimumWidthConstraint: NSLayoutConstraint?

    var displayedPlayPauseImage: UIImage? { playPauseButton.image(for: .normal) }
    var displayedRateText: String? { rateButton.title(for: .normal) }
    var displayedElapsedText: String? { elapsedLabel.text }
    var controlsAreEnabled: Bool { playPauseButton.isEnabled }
    var isShowingPauseIcon: Bool { isPlayingState }
    var hasScheduledAutoHide: Bool { hideTask != nil }
    var controlsContentAlpha: CGFloat { controlsContentView.alpha }
    var controlsContentIsInteractive: Bool { controlsContentView.isUserInteractionEnabled }
    var backgroundContentAlpha: CGFloat { controlsBackgroundView.alpha }
    var renderedBackgroundGradientLayer: CAGradientLayer? { controlsBackgroundView.gradientLayer }
    private(set) var styleLayoutInvalidationCount = 0
    var hasFixedWidthTimeLabels: Bool { elapsedMinimumWidthConstraint?.isActive == true }
    var fixedTimeLabelMinimumWidth: CGFloat { elapsedMinimumWidthConstraint?.constant ?? 0 }
    var renderedTransportControlsFrame: CGRect { buttonStack.convert(buttonStack.bounds, to: self) }
    var renderedSeekBarFrame: CGRect { seekBar.convert(seekBar.bounds, to: self) }
    /// The seek bar's *drawn* track — smaller than `renderedSeekBarFrame`, which
    /// is the full 44pt touch-target row the track is centered inside.
    var renderedSeekBarVisibleTrackFrame: CGRect { seekBar.convert(seekBar.renderedTrackFrame, to: self) }
    var renderedBottomRowFrame: CGRect { bottomStack.convert(bottomStack.bounds, to: self) }
    var renderedTimeLabelFrame: CGRect { elapsedLabel.convert(elapsedLabel.bounds, to: self) }
    var renderedRateButtonFrame: CGRect { rateButton.convert(rateButton.bounds, to: self) }
    /// The rate button's *drawn* title/icon — smaller than `renderedRateButtonFrame`,
    /// which is the full 44pt-tall touch-target the content is centered inside.
    var renderedRateButtonVisibleContentFrame: CGRect {
        if let titleLabel = rateButton.titleLabel, !(titleLabel.text ?? "").isEmpty {
            return titleLabel.convert(titleLabel.bounds, to: self)
        }
        if let imageView = rateButton.imageView, imageView.image != nil {
            return imageView.convert(imageView.bounds, to: self)
        }
        return renderedRateButtonFrame
    }

    public init(
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init()
    ) {
        self.style = style
        self.configuration = configuration
        self.isControlsVisible = configuration.initialVisibility == .visible
        self.visibilityMachine = ABControlsVisibilityMachine(
            visibility: configuration.initialVisibility == .visible ? .visible : .hidden
        )
        super.init(frame: .zero)
        buildViewHierarchy()
        wireActions()
        applyStyle(previous: nil)
        applyConfiguration(previous: nil)
        resetTimeline()
        controlsContentView.alpha = isControlsVisible ? 1 : 0
        controlsContentView.isUserInteractionEnabled = isControlsVisible
        controlsBackgroundView.alpha = controlsContentView.alpha
    }

    required init?(coder: NSCoder) {
        self.style = .default
        self.configuration = .init()
        self.isControlsVisible = true
        self.visibilityMachine = ABControlsVisibilityMachine(visibility: .visible)
        super.init(coder: coder)
        buildViewHierarchy()
        wireActions()
        applyStyle(previous: nil)
        applyConfiguration(previous: nil)
        resetTimeline()
    }

    public func setControlsVisible(_ visible: Bool, animated: Bool = true) {
        handleVisibility(.setVisible(visible), animated: animated)
    }

    public func addObserver(
        _ handler: @escaping @MainActor @Sendable (ABControlsEvent) -> Void
    ) -> ABObservationToken {
        observerRegistry.add(handler)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled,
              !isHidden,
              alpha > 0.01 else {
            return nil
        }
        if controlsContentView.isUserInteractionEnabled,
           !controlsContentView.isHidden,
           controlsContentView.alpha > 0.01 {
            // Small, specific circular targets first; the full-width seek bar's
            // broad touch-target row is checked last. On short overlays the
            // bottom cluster's 44pt touch rows can vertically overlap the
            // centered transport row (see ABPlayerControlsLayoutTests) — when
            // they do, the more specific button must win, not the seek bar.
            // accessoryViews (consumer-injected, e.g. fullscreen/captions) sit
            // in that same bottom row and are just as overlapped, so they must
            // be checked before the seek bar too — otherwise the documented
            // "the more specific control always wins" promise (CustomizingControls.md)
            // is false for the one extension point consumers actually plug into.
            var priorityControls: [UIView] = [
                playPauseButton,
                skipForwardButton,
                skipBackwardButton,
                rateButton
            ]
            priorityControls.append(contentsOf: accessoryStack.arrangedSubviews)
            priorityControls.append(seekBar)
            for control in priorityControls {
                let controlPoint = control.convert(point, from: self)
                if let hitView = control.hitTest(controlPoint, with: event) {
                    return hitView
                }
            }
        }
        return super.hitTest(point, with: event)
    }

    deinit {
        hideTask?.cancel()
        playerObservationToken?.cancel()
    }

    /// `ABControlsLayout.rootStackSpacing` depends on `scaledTimeLabelFont`,
    /// which varies with the Dynamic Type trait — recomputed on `style`/`configuration`
    /// assignment, but the *system* content-size-category preference can also
    /// change underneath an unchanged style (Settings app, Slide Over split
    /// changes, or an accessibility size override) without either ever being
    /// reassigned. Without this, spacing keeps using whatever font size was
    /// current at the last style/configuration write, so the label can grow
    /// past the seek bar's track without the layout ever adjusting to it.
    ///
    /// Also re-applies the scaled font directly (matching `applyStyle`'s font
    /// block) rather than relying solely on `adjustsFontForContentSizeCategory`'s
    /// own automatic update — that mechanism updates the label's font on its
    /// own trait-change notification, which is a separate pass from this one
    /// and isn't guaranteed to run before layout reads `rootStack.spacing`,
    /// so this keeps the font and the spacing that depends on it in lockstep.
    private func registerForSpacingTraitChanges() {
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: ABPlayerControlsView, _: UITraitCollection) in
            let scaledTimeFont = view.layout.scaledTimeLabelFont
            view.elapsedLabel.font = scaledTimeFont
            view.updateTimeLabelWidthConstraints(using: scaledTimeFont)
            view.rootStack.spacing = view.layout.rootStackSpacing
        }
    }

    /// Fresh on every access — never cache this. `registerForSpacingTraitChanges`
    /// relies on a new `ABControlsLayout` picking up the current `traitCollection`
    /// on every Dynamic Type change; a stored `layout` would freeze at whatever
    /// trait was current when it was first computed and silently stop tracking
    /// accessibility size changes.
    private var layout: ABControlsLayout {
        ABControlsLayout(style: style, traitCollection: traitCollection)
    }

    private func buildViewHierarchy() {
        directionalLayoutMargins = style.contentInsets
        rootStack.axis = .vertical
        rootStack.spacing = layout.rootStackSpacing
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        registerForSpacingTraitChanges()

        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.spacing = style.buttonSpacing
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.addArrangedSubview(skipBackwardButton)
        buttonStack.addArrangedSubview(playPauseButton)
        buttonStack.addArrangedSubview(skipForwardButton)

        accessoryStack.axis = .horizontal
        accessoryStack.alignment = .center
        accessoryStack.spacing = 8

        bottomStack.axis = .horizontal
        bottomStack.alignment = .center
        bottomStack.spacing = 8
        bottomStack.addArrangedSubview(elapsedLabel)
        bottomStack.addArrangedSubview(UIView())
        bottomStack.addArrangedSubview(accessoryStack)
        bottomStack.addArrangedSubview(rateButton)

        // Seek bar first, compact row (time label + rate) below it — both share the
        // root stack's leading/trailing anchors, so they line up with the bar's edges.
        rootStack.addArrangedSubview(seekBar)
        rootStack.addArrangedSubview(bottomStack)
        controlsContentView.translatesAutoresizingMaskIntoConstraints = false
        controlsBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        controlsBackgroundView.isUserInteractionEnabled = false
        addSubview(controlsBackgroundView)
        addSubview(controlsContentView)
        controlsContentView.addSubview(buttonStack)
        controlsContentView.addSubview(rootStack)
        backgroundTapRecognizer.cancelsTouchesInView = false
        backgroundTapRecognizer.delegate = self
        addGestureRecognizer(backgroundTapRecognizer)
        NSLayoutConstraint.activate([
            controlsBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            controlsBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlsContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsContentView.topAnchor.constraint(equalTo: topAnchor),
            controlsContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonStack.centerXAnchor.constraint(equalTo: controlsContentView.centerXAnchor),
            buttonStack.centerYAnchor.constraint(equalTo: controlsContentView.centerYAnchor),
            rootStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            rootStack.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            seekBar.heightAnchor.constraint(equalToConstant: ABControlsLayout.seekBarTouchRowHeight)
        ])

        playWidthConstraint = playPauseButton.widthAnchor.constraint(equalToConstant: style.playPauseButtonSize.width)
        playHeightConstraint = playPauseButton.heightAnchor.constraint(equalToConstant: style.playPauseButtonSize.height)
        backwardWidthConstraint = skipBackwardButton.widthAnchor.constraint(equalToConstant: style.skipButtonSize.width)
        backwardHeightConstraint = skipBackwardButton.heightAnchor.constraint(equalToConstant: style.skipButtonSize.height)
        forwardWidthConstraint = skipForwardButton.widthAnchor.constraint(equalToConstant: style.skipButtonSize.width)
        forwardHeightConstraint = skipForwardButton.heightAnchor.constraint(equalToConstant: style.skipButtonSize.height)
        rateWidthConstraint = rateButton.widthAnchor.constraint(equalToConstant: style.rateButtonSize.width)
        rateHeightConstraint = rateButton.heightAnchor.constraint(equalToConstant: style.rateButtonSize.height)
        elapsedMinimumWidthConstraint = elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        elapsedMinimumWidthConstraint?.priority = .defaultHigh
        NSLayoutConstraint.activate([
            playWidthConstraint,
            playHeightConstraint,
            backwardWidthConstraint,
            backwardHeightConstraint,
            forwardWidthConstraint,
            forwardHeightConstraint,
            rateWidthConstraint,
            rateHeightConstraint
        ].compactMap { $0 })
    }

    private func wireActions() {
        playPauseButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)
        skipBackwardButton.addAction(UIAction { [weak self] _ in self?.skip(by: -(self?.configuration.skipInterval ?? 0)) }, for: .touchUpInside)
        skipForwardButton.addAction(UIAction { [weak self] _ in self?.skip(by: self?.configuration.skipInterval ?? 0) }, for: .touchUpInside)
        rateButton.addAction(UIAction { [weak self] _ in self?.rateButtonTapped() }, for: .touchUpInside)
        seekBar.onScrubBegan = { [weak self] in self?.scrubBegan() }
        seekBar.onScrubChanged = { [weak self] progress in self?.scrubChanged(progress: progress) }
        seekBar.onScrubEnded = { [weak self] progress in self?.scrubEnded(progress: progress) }
        seekBar.onAccessibilityAdjustment = { [weak self] direction in
            self?.adjustTimelineForAccessibility(direction: direction)
        }
    }

    private func replacePlayer() {
        handleVisibility(.detached, animated: false)
        playerObservationToken?.cancel()
        playerObservationToken = nil
        periodicIntervalLease?.restore()
        periodicIntervalLease = nil
        applyPresenterEffects(presenter.handle(.detached))

        guard let player else {
            setControlsEnabled(false)
            return
        }
        periodicIntervalLease = ABPeriodicIntervalLease(
            player: player,
            previousInterval: player.configuration.periodicTimeInterval
        )
        player.configuration.periodicTimeInterval = configuration.periodicTimeInterval
        playerObservationToken = player.addObserver { [weak self, weak player] event in
            guard let self, let player, self.player === player else { return }
            self.handlePlayerEvent(event)
        }
        isPlayingState = player.isPlaying
        _ = visibilityMachine.handle(.playbackStateChanged(isPlaying: isPlayingState))
        let initialVisibility: ABControlsVisibilityMachine.Visibility = configuration.initialVisibility == .visible
            ? .visible
            : .hidden
        applyVisibilityEffects(
            visibilityMachine.handle(.attached(initial: initialVisibility)),
            animated: false
        )
        currentPlaybackTime = player.playbackTime
        updatePlaybackIcon()
        updateRate(player.rate)
        render(currentPlaybackTime)
        // `.attached`'s effect only covers enablement (see its doc comment) —
        // seed the rest of the presenter's own tracked state here so it isn't
        // stale (still at this struct's init defaults) the first time
        // `togglePlayback`/`selectRate` read `presenter.isPlaying`/`.rate`
        // before any further `ABPlayerEvent` has arrived to update them.
        presenter.seed(isPlaying: player.isPlaying, rate: player.rate, currentPlaybackTime: currentPlaybackTime)
        applyPresenterEffects(presenter.handle(.attached(
            grade: player.grade,
            promotesToCurrentOnPlay: configuration.promotesToCurrentOnPlay
        )))
    }

    /// Interprets `ABControlsPresenter.Effect`s by calling this view's own
    /// existing UI-update methods — same pattern as `applyVisibilityEffects`
    /// for `ABControlsVisibilityMachine.Effect`.
    ///
    /// `targetPlayer` is only consulted for `.send` effects, and only the
    /// specific player instance the caller resolved *before* calling
    /// `presenter.handle(...)` — never re-read from `self.player` here. A
    /// synchronous reentrant call triggered mid-loop (e.g. `.promoteToCurrent`
    /// re-entering `handlePlayerEvent` via `.gradeChanged`) could otherwise
    /// observe a `self.player` a consumer swapped out from under this call,
    /// same reasoning as pinning `scrubbingPlayer` for a scrub session.
    private func applyPresenterEffects(
        _ effects: [ABControlsPresenter.Effect],
        player targetPlayer: ABPlayer? = nil
    ) {
        for effect in effects {
            switch effect {
            case .setPlaybackIcon(let isPlaying):
                isPlayingState = isPlaying
                updatePlaybackIcon()
            case .setRateTitle(let rate):
                updateRate(rate)
            case .renderTimeline(let time):
                render(time)
            case .resetTimeline:
                resetTimeline()
            case .setEnabled(let enabled, let allowsPromotionTap):
                setControlsEnabled(enabled, allowsPromotionTap: allowsPromotionTap)
            case .send(let command):
                sendPlayerCommand(command, to: targetPlayer)
            }
        }
    }

    private func sendPlayerCommand(_ command: ABControlsPresenter.PlayerCommand, to targetPlayer: ABPlayer?) {
        switch command {
        case .play:
            targetPlayer?.play()
        case .pause:
            targetPlayer?.pause()
        case .promoteToCurrent:
            targetPlayer?.promote(to: .current)
        case .skip(let interval):
            guard let targetPlayer else { return }
            Task { await targetPlayer.skip(by: interval) }
        case .setRate(let rate):
            targetPlayer?.setRate(rate)
        }
    }

    func handlePlayerEvent(_ event: ABPlayerEvent) {
        applyPresenterEffects(presenter.handle(.playerEvent(event)))
        switch event {
        case .timeControlStatusChanged(let status):
            handleVisibility(.playbackStateChanged(isPlaying: status == .playing))
        case .itemDetached, .sourceChanged:
            // The rest of this transition (`.resetTimeline`) already applied
            // above via the presenter — this needs a live `player.grade` read
            // the presenter deliberately doesn't have. See
            // `ABControlsPresenter`'s doc comment.
            setControlsEnabled(player?.grade == .current)
        case .itemStatusChanged(.readyToPlay):
            // Needs `player.playbackTime`/`player.grade` — the presenter
            // contributes nothing for this event. See its doc comment.
            if let player {
                render(player.playbackTime)
                presenter.syncPlaybackTime(player.playbackTime)
                setControlsEnabled(player.grade == .current)
            }
        case .playedToEnd:
            handleVisibility(.setVisible(true))
        case .seekCompleted(let time):
            // Needs `player?.isScrubbing`/`player?.duration` — the presenter
            // contributes nothing for this event. See its doc comment.
            guard player?.isScrubbing != true else { return }
            let snapshot = ABPlaybackTime(
                currentTime: time,
                duration: currentPlaybackTime.duration ?? player?.duration,
                bufferedUntil: currentPlaybackTime.bufferedUntil
            )
            render(snapshot)
            presenter.syncPlaybackTime(snapshot)
        default:
            break
        }
    }

    private func applyStyle(previous: ABPlayerControlsStyle?) {
        let replacedBackground = controlsBackgroundView.apply(style.backgroundStyle)
        controlsBackgroundView.layer.cornerRadius = style.containerCornerRadius
        controlsBackgroundView.clipsToBounds = style.containerCornerRadius > 0
        directionalLayoutMargins = style.contentInsets
        rootStack.spacing = layout.rootStackSpacing
        buttonStack.spacing = style.buttonSpacing
        seekBar.style = style
        elapsedLabel.textColor = style.timeLabelColor
        if previous == nil
            || style.timeLabelFont != previous?.timeLabelFont
            || style.usesFixedWidthTimeLabels != previous?.usesFixedWidthTimeLabels {
            let scaledTimeFont = layout.scaledTimeLabelFont
            elapsedLabel.font = scaledTimeFont
            elapsedLabel.adjustsFontForContentSizeCategory = true
            updateTimeLabelWidthConstraints(using: scaledTimeFont)
        }
        playWidthConstraint?.constant = style.playPauseButtonSize.width
        playHeightConstraint?.constant = style.playPauseButtonSize.height
        backwardWidthConstraint?.constant = style.skipButtonSize.width
        backwardHeightConstraint?.constant = style.skipButtonSize.height
        forwardWidthConstraint?.constant = style.skipButtonSize.width
        forwardHeightConstraint?.constant = style.skipButtonSize.height
        rateWidthConstraint?.constant = style.rateButtonSize.width
        rateHeightConstraint?.constant = style.rateButtonSize.height
        updatePlaybackIcon()
        updateSkipIcons()
        updateRate(player?.rate ?? 1, rebuildInteraction: false)
        guard let previous else { return }
        if style.iconsDiffer(from: previous) {
            for button in [playPauseButton, skipBackwardButton, skipForwardButton, rateButton] {
                button.invalidateIntrinsicContentSize()
            }
        }
        if replacedBackground || style.requiresControlsLayout(comparedTo: previous) {
            styleLayoutInvalidationCount += 1
            setNeedsLayout()
        }
    }

    private func applyConfiguration(previous: ABPlayerControlsConfiguration?) {
        seekBar.showsBufferedProgress = configuration.showsBufferedProgress
        seekBar.allowsTrackTapToSeek = configuration.allowsTrackTapToSeek
        elapsedLabel.isHidden = !configuration.showsTimeLabels
        skipBackwardButton.isHidden = !configuration.showsSkipButtons
        skipForwardButton.isHidden = !configuration.showsSkipButtons
        updateSkipIcons()
        // Only rebuild the rate menu (a real, visible UIMenu recreation — can
        // close one a user has open mid-interaction) when something that
        // actually changes its *contents* did. `configuration != previous`
        // firing (checked by the SwiftUI wrapper before assigning here) isn't
        // itself a reliable signal: a `.custom` TimeLabelFormat makes every
        // ABPlayerControlsConfiguration compare unequal to its own copy (see
        // TimeLabelFormat's Equatable conformance), so on every SwiftUI update
        // pass this method runs regardless of whether anything meaningful
        // changed. previous == nil (first call, from init) always rebuilds.
        let rateMenuContentsChanged = previous == nil
            || previous?.rateOptions != configuration.rateOptions
            || previous?.rateInteraction != configuration.rateInteraction
        updateRate(player?.rate ?? 1, rebuildInteraction: rateMenuContentsChanged)
        render(currentPlaybackTime)
        if previous?.periodicTimeInterval != configuration.periodicTimeInterval,
           let player,
           periodicIntervalLease != nil {
            player.configuration.periodicTimeInterval = configuration.periodicTimeInterval
        }
        if previous?.autoHideDelay != configuration.autoHideDelay
            || previous?.staysVisibleWhilePaused != configuration.staysVisibleWhilePaused {
            handleVisibility(.configurationChanged(
                autoHideDelay: configuration.autoHideDelay,
                staysVisibleWhilePaused: configuration.staysVisibleWhilePaused
            ))
        }
        backgroundTapRecognizer.isEnabled = configuration.handlesBackgroundTap
        // Re-derive play/pause's promotion-tap eligibility: promotesToCurrentOnPlay
        // itself may have just changed. Only when a player is actually attached —
        // otherwise this would force every control disabled on init (before
        // `player` is ever set), which changes their hit-testability, not just
        // their look, unlike every other pre-attachment default in this view.
        if let player {
            setControlsEnabled(player.grade == .current)
        }
    }

    private func updateTimeLabelWidthConstraints(using font: UIFont) {
        guard let elapsedMinimumWidthConstraint else { return }
        elapsedMinimumWidthConstraint.isActive = false
        guard style.usesFixedWidthTimeLabels else { return }
        elapsedMinimumWidthConstraint.constant = layout.timeLabelMinimumWidth(using: font)
        elapsedMinimumWidthConstraint.isActive = true
    }

    private func updatePlaybackIcon() {
        playPauseButton.apply(icon: isPlayingState ? style.pauseIcon : style.playIcon, style: style)
        playPauseButton.accessibilityLabel = ABControlsLocalization.string(
            isPlayingState ? "controls.pause" : "controls.play"
        )
    }

    /// Skip intervals with a matching `gobackward.N`/`goforward.N` SF Symbol.
    /// `skipInterval` is clamped to 5-second steps in 5...60, so this is exactly
    /// the subset of that range the system ships a numbered glyph for.
    private static let symbolSupportedSkipIntervals: Set<Int> = [5, 10, 15, 30, 45, 60]

    private enum SkipDirection {
        case backward, forward
        var baseSymbolName: String { self == .backward ? "gobackward" : "goforward" }
    }

    private func updateSkipIcons() {
        let backwardPlan = skipIconPlan(direction: .backward, explicitIcon: style.skipBackwardIcon)
        let forwardPlan = skipIconPlan(direction: .forward, explicitIcon: style.skipForwardIcon)
        skipBackwardButton.applySkip(icon: backwardPlan.icon, badgeNumber: backwardPlan.badgeNumber, style: style)
        skipForwardButton.applySkip(icon: forwardPlan.icon, badgeNumber: forwardPlan.badgeNumber, style: style)
        skipBackwardButton.accessibilityLabel = ABControlsLocalization.string("controls.skipBackward")
        skipForwardButton.accessibilityLabel = ABControlsLocalization.string("controls.skipForward")
        if !configuration.showsSkipButtons {
            skipBackwardButton.isHidden = true
            skipForwardButton.isHidden = true
        }
    }

    /// Resolves the icon (and, when no SF Symbol variant exists for the configured
    /// interval, the number to badge over a generic arrow) for one skip button.
    /// An explicit `style` icon always wins and is never badged.
    private func skipIconPlan(
        direction: SkipDirection,
        explicitIcon: ABControlIcon?
    ) -> (icon: ABControlIcon, badgeNumber: Int?) {
        if let explicitIcon {
            return (explicitIcon, nil)
        }
        guard configuration.synchronizesSkipIconWithInterval else {
            return (.system("\(direction.baseSymbolName).10"), nil)
        }
        let integerInterval = Int(configuration.skipInterval.rounded())
        if Self.symbolSupportedSkipIntervals.contains(integerInterval) {
            return (.system("\(direction.baseSymbolName).\(integerInterval)"), nil)
        }
        return (.system(direction.baseSymbolName), integerInterval)
    }

    private func updateRate(_ rate: Float, rebuildInteraction: Bool = true) {
        let value = String(format: "%g", rate)
        switch style.rateLabelStyle {
        case .text(let font, let format):
            rateButton.setImage(nil, for: .normal)
            rateButton.setTitle(String(format: format, value), for: .normal)
            rateButton.titleLabel?.font = font
            rateButton.setTitleColor(style.tintColor, for: .normal)
            rateButton.isHidden = configuration.rateInteraction == .hidden || configuration.rateOptions.isEmpty
        case .icon(let icon, let showsValueBadge):
            rateButton.setTitle(nil, for: .normal)
            rateButton.apply(icon: icon, style: style)
            if showsValueBadge {
                rateButton.setTitle(value, for: .normal)
            }
            rateButton.isHidden = configuration.rateInteraction == .hidden || configuration.rateOptions.isEmpty
        }
        rateButton.accessibilityLabel = ABControlsLocalization.string("controls.rate")
        rateButton.accessibilityValue = ABControlsLocalization.format("controls.rateValue", value)
        rateButton.accessibilityTraits.insert(.button)
        if rebuildInteraction {
            configureRateInteraction(currentRate: rate)
        }
    }

    private func render(_ time: ABPlaybackTime) {
        currentPlaybackTime = time
        seekBar.progress = time.progress ?? 0
        seekBar.bufferedProgress = time.bufferedProgress ?? 0
        seekBar.isSeekEnabled = time.duration != nil && controlsAreEnabled
        updateTimeLabels(currentTime: time.currentTime, duration: time.duration)
        seekBar.accessibilityLabel = ABControlsLocalization.string("controls.timeline")
        seekBar.accessibilityValue = timeLabelFormatter.accessibilityValue(
            elapsedSeconds: time.currentTime.isNumeric ? CMTimeGetSeconds(time.currentTime) : nil,
            durationSeconds: time.duration.flatMap { $0.isNumeric ? CMTimeGetSeconds($0) : nil }
        )
    }

    /// Fresh on every access — `configuration.timeFormat`/`timeLabelLayout` can
    /// change independently of a full `configuration` reassignment's identity,
    /// so this always reflects the current values rather than one captured at
    /// some earlier point.
    private var timeLabelFormatter: ABControlsTimeLabelFormatter {
        ABControlsTimeLabelFormatter(timeFormat: configuration.timeFormat, timeLabelLayout: configuration.timeLabelLayout)
    }

    private func updateTimeLabels(currentTime: CMTime, duration: CMTime?) {
        elapsedLabel.text = timeLabelFormatter.label(
            elapsedSeconds: currentTime.isNumeric ? CMTimeGetSeconds(currentTime) : nil,
            durationSeconds: duration.flatMap { $0.isNumeric ? CMTimeGetSeconds($0) : nil }
        )
    }

    private func resetTimeline() {
        currentPlaybackTime = .zero
        seekBar.progress = 0
        seekBar.bufferedProgress = 0
        seekBar.isSeekEnabled = false
        updateTimeLabels(currentTime: .zero, duration: nil)
        seekBar.accessibilityLabel = ABControlsLocalization.string("controls.timeline")
        seekBar.accessibilityValue = ABControlsLocalization.string("controls.live")
    }

    /// `true` when a play/pause tap should promote the player to `.current`
    /// (see `ABPlayerControlsConfiguration/promotesToCurrentOnPlay`) rather than
    /// do nothing. Requires an actual source to promote to — with none, there's
    /// nothing a promotion could play, so the button stays genuinely disabled.
    private var canPromoteToCurrentOnPlayTap: Bool {
        guard configuration.promotesToCurrentOnPlay, let player else { return false }
        return player.grade != .current && player.source != nil
    }

    /// - Parameter allowsPromotionTap: `false` forces the play/pause button to
    ///   the same disabled state as every other control (used when disabling
    ///   because of an actual failure, where a "play" tap has nothing to
    ///   promote into working order).
    private func setControlsEnabled(_ enabled: Bool, allowsPromotionTap: Bool = true) {
        let playPauseEnabled = enabled || (allowsPromotionTap && canPromoteToCurrentOnPlayTap)
        playPauseButton.isEnabled = playPauseEnabled
        playPauseButton.tintColor = playPauseEnabled ? style.tintColor : style.disabledTintColor
        for control in [skipBackwardButton, skipForwardButton, rateButton] {
            control.isEnabled = enabled
            control.tintColor = enabled ? style.tintColor : style.disabledTintColor
        }
        seekBar.isEnabled = enabled
        seekBar.isSeekEnabled = enabled && currentPlaybackTime.duration != nil
    }

    private func togglePlayback() {
        guard let player else { return }
        applyPresenterEffects(
            presenter.handle(.playPauseTapped(allowsPromotionTap: canPromoteToCurrentOnPlayTap)),
            player: player
        )
        isPlayingState = presenter.isPlaying
        updatePlaybackIcon()
        bouncePlayPauseButton()
        handleVisibility(.controlInteracted)
        observerRegistry.broadcast(.playPauseTapped(isPlayingAfterTap: isPlayingState))
    }

    private static let playPauseBounceKey = "abplayerkit.playPauseBounce"
    private static let playPauseBounceDuration: TimeInterval = 0.3

    /// Quick scale-up-then-down bounce (0.85 → 1.1 → 1.0) on tap, skipped when
    /// Reduce Motion is on (respecting ``ABPlayerControlsStyle/respectsReduceMotion``,
    /// as every other controls animation does).
    private func bouncePlayPauseButton() {
        playPauseButton.layer.removeAnimation(forKey: Self.playPauseBounceKey)
        guard !(style.respectsReduceMotion && isReduceMotionEnabledProvider()) else {
            lastPlayPauseBounceDuration = nil
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, 0.85, 1.1, 1.0]
        animation.keyTimes = [0, 0.28, 0.72, 1.0]
        animation.duration = Self.playPauseBounceDuration
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        playPauseButton.layer.add(animation, forKey: Self.playPauseBounceKey)
        lastPlayPauseBounceDuration = Self.playPauseBounceDuration
    }

    private func skip(by interval: TimeInterval) {
        guard let player else { return }
        applyPresenterEffects(presenter.handle(.skipTapped(interval)), player: player)
        handleVisibility(.controlInteracted)
        observerRegistry.broadcast(.skipTapped(by: interval))
    }

    private func configureRateInteraction(currentRate: Float) {
        switch configuration.rateInteraction {
        case .menu:
            rateButton.isHidden = configuration.rateOptions.isEmpty
            rateButton.showsMenuAsPrimaryAction = true
            rateButton.menu = UIMenu(children: configuration.rateOptions.map { [weak self] option in
                UIAction(
                    title: "\(String(format: "%g", option))×",
                    state: abs(option - currentRate) < 0.000_1 ? .on : .off
                ) { [weak self] _ in
                    self?.selectRate(option)
                }
            })
        case .cycle:
            rateButton.isHidden = configuration.rateOptions.isEmpty
            rateButton.showsMenuAsPrimaryAction = false
            rateButton.menu = nil
        case .hidden:
            rateButton.isHidden = true
            rateButton.showsMenuAsPrimaryAction = false
            rateButton.menu = nil
        }
    }

    private func rateButtonTapped() {
        guard configuration.rateInteraction == .cycle,
              !configuration.rateOptions.isEmpty else { return }
        let currentRate = player?.rate ?? 1
        let currentIndex = configuration.rateOptions.firstIndex {
            abs($0 - currentRate) < 0.000_1
        }
        let nextIndex = currentIndex.map { configuration.rateOptions.index(after: $0) } ?? 0
        let wrappedIndex = nextIndex == configuration.rateOptions.endIndex ? 0 : nextIndex
        selectRate(configuration.rateOptions[wrappedIndex])
    }

    func selectRate(_ rate: Float) {
        applyPresenterEffects(presenter.handle(.rateSelected(rate)), player: player)
        handleVisibility(.controlInteracted)
        observerRegistry.broadcast(.rateSelected(presenter.rate))
    }

    private func scrubBegan() {
        scrubbingPlayer = player
        scrubbingPlayer?.beginScrubbing()
        handleVisibility(.scrubBegan)
        observerRegistry.broadcast(.scrubbingChanged(isScrubbing: true))
    }

    private func scrubChanged(progress: Double) {
        guard let duration = currentPlaybackTime.duration,
              let time = ABSeekBarGeometry.time(forProgress: progress, duration: duration) else { return }
        updateTimeLabels(currentTime: time, duration: currentPlaybackTime.duration)
        scrubbingPlayer?.scrub(to: time)
    }

    private func scrubEnded(progress: Double) {
        let sessionPlayer = scrubbingPlayer ?? player
        scrubbingPlayer = nil
        let committedTime = ABSeekBarGeometry.time(
            forProgress: progress,
            duration: currentPlaybackTime.duration
        )
        Task { [weak self, weak sessionPlayer] in
            await sessionPlayer?.endScrubbing()
            guard let self else { return }
            let controlsStillRepresentSession = if let sessionPlayer {
                self.player === sessionPlayer
            } else {
                self.player == nil
            }
            if controlsStillRepresentSession {
                self.handleVisibility(.scrubEnded)
            }
            self.observerRegistry.broadcast(.scrubbingChanged(isScrubbing: false))
            if controlsStillRepresentSession, let committedTime {
                self.observerRegistry.broadcast(.seekCommitted(to: committedTime))
            }
        }
    }

    private func adjustTimelineForAccessibility(direction: Int) {
        let effects = presenter.handle(.accessibilityAdjusted(direction: direction, skipInterval: configuration.skipInterval))
        guard case .renderTimeline(let newTime)? = effects.first else { return }
        applyPresenterEffects(effects, player: player)
        handleVisibility(.controlInteracted)
        observerRegistry.broadcast(.seekCommitted(to: newTime.currentTime))
    }

    @objc private func backgroundTapped() {
        handleVisibility(.tapped)
    }

    func simulateBackgroundTap() {
        guard configuration.handlesBackgroundTap else { return }
        backgroundTapped()
    }

    func handleVisibility(
        _ input: ABControlsVisibilityMachine.Input,
        animated: Bool = true
    ) {
        applyVisibilityEffects(visibilityMachine.handle(input), animated: animated)
    }

    private func applyVisibilityEffects(
        _ effects: [ABControlsVisibilityMachine.Effect],
        animated: Bool
    ) {
        for effect in effects {
            switch effect {
            case .show:
                applyControlsVisibility(true, animated: animated)
            case .hide:
                applyControlsVisibility(false, animated: animated)
            case .scheduleAutoHide(let delay):
                scheduleAutoHide(after: delay)
            case .cancelAutoHide:
                hideTask?.cancel()
                hideTask = nil
            case .notifyVisibility(let visible):
                observerRegistry.broadcast(.visibilityChanged(isVisible: visible))
            }
        }
    }

    private func applyControlsVisibility(_ visible: Bool, animated: Bool) {
        isControlsVisible = visible
        let changes = {
            let alpha: CGFloat = visible ? 1 : 0
            self.controlsContentView.alpha = alpha
            self.controlsContentView.isUserInteractionEnabled = visible
            self.controlsBackgroundView.alpha = alpha
        }
        let duration = style.respectsReduceMotion && isReduceMotionEnabledProvider()
            ? 0
            : style.visibilityAnimationDuration
        lastVisibilityAnimationDuration = animated ? duration : 0
        guard animated, duration > 0 else {
            changes()
            return
        }
        UIView.animate(
            withDuration: duration,
            animations: changes
        )
    }

    private func scheduleAutoHide(after delay: TimeInterval) {
        hideTask?.cancel()
        guard !isVoiceOverRunningProvider() else {
            hideTask = nil
            return
        }
        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, delay)))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            guard !self.isVoiceOverRunningProvider() else { return }
            self.handleVisibility(.autoHideFired)
        }
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === backgroundTapRecognizer else { return true }
        return Self.backgroundTapShouldReceiveTouch(on: touch.view, upTo: self)
    }

    /// `true` unless `view` (or an ancestor strictly between it and `root`) is a
    /// `UIControl` — real button/seek-bar touches must never also recognize the
    /// whole-overlay background tap. Factored out of the delegate callback so it's
    /// testable without a real `UITouch` (UIKit gives no public initializer for one).
    static func backgroundTapShouldReceiveTouch(on view: UIView?, upTo root: UIView) -> Bool {
        var current = view
        while let node = current, node !== root {
            if node is UIControl { return false }
            current = node.superview
        }
        return true
    }
}

private extension ABPlayerControlsStyle {
    func iconsDiffer(from previous: Self) -> Bool {
        playIcon != previous.playIcon
            || pauseIcon != previous.pauseIcon
            || skipBackwardIcon != previous.skipBackwardIcon
            || skipForwardIcon != previous.skipForwardIcon
            || iconPointSize != previous.iconPointSize
            || iconWeight != previous.iconWeight
            || iconRenderingMode != previous.iconRenderingMode
            || rateLabelStyle != previous.rateLabelStyle
    }

    func requiresControlsLayout(comparedTo previous: Self) -> Bool {
        playPauseButtonSize != previous.playPauseButtonSize
            || skipButtonSize != previous.skipButtonSize
            || buttonSpacing != previous.buttonSpacing
            || timeLabelFont != previous.timeLabelFont
            || usesFixedWidthTimeLabels != previous.usesFixedWidthTimeLabels
            || trackHeight != previous.trackHeight
            || trackHeightWhileScrubbing != previous.trackHeightWhileScrubbing
            || trackCornerRadius != previous.trackCornerRadius
            || seekBarHorizontalInset != previous.seekBarHorizontalInset
            || thumbSize != previous.thumbSize
            || thumbSizeWhileScrubbing != previous.thumbSizeWhileScrubbing
            || thumbBorderWidth != previous.thumbBorderWidth
            || thumbCornerRadius != previous.thumbCornerRadius
            || thumbShadowRadius != previous.thumbShadowRadius
            || thumbImage != previous.thumbImage
            || isThumbHidden != previous.isThumbHidden
            || rateButtonSize != previous.rateButtonSize
            || contentInsets != previous.contentInsets
            || containerCornerRadius != previous.containerCornerRadius
            || seekBarBottomSpacing != previous.seekBarBottomSpacing
    }
}
