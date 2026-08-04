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
    let durationLabel = UILabel()
    private let accessoryStack = UIStackView()
    private let buttonStack = UIStackView()
    private let bottomStack = UIStackView()
    private let rootStack = UIStackView()
    private let controlsBackgroundView = ABControlsBackgroundView()
    private let observerRegistry = ABControlsObserverRegistry()
    private var playerObservationToken: ABObservationToken?
    private var periodicIntervalLease: ABPeriodicIntervalLease?
    private weak var scrubbingPlayer: ABPlayer?
    private var isPlayingState = false
    private var currentPlaybackTime = ABPlaybackTime.zero
    private var visibilityMachine: ABControlsVisibilityMachine
    private var hideTask: Task<Void, Never>?
    var isVoiceOverRunningProvider: @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }
    var isReduceMotionEnabledProvider: @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled }
    private(set) var lastVisibilityAnimationDuration: TimeInterval?
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
    private var durationMinimumWidthConstraint: NSLayoutConstraint?
    private var equalTimeLabelWidthConstraint: NSLayoutConstraint?

    var displayedPlayPauseImage: UIImage? { playPauseButton.image(for: .normal) }
    var displayedRateText: String? { rateButton.title(for: .normal) }
    var displayedElapsedText: String? { elapsedLabel.text }
    var displayedDurationText: String? { durationLabel.text }
    var controlsAreEnabled: Bool { playPauseButton.isEnabled }
    var isShowingPauseIcon: Bool { isPlayingState }
    var hasScheduledAutoHide: Bool { hideTask != nil }
    var controlsContentAlpha: CGFloat { rootStack.alpha }
    var controlsContentIsInteractive: Bool { rootStack.isUserInteractionEnabled }
    var backgroundContentAlpha: CGFloat { controlsBackgroundView.alpha }
    var renderedBackgroundContentView: UIView? { controlsBackgroundView.renderedContentView }
    var renderedBackgroundGradientLayer: CAGradientLayer? { controlsBackgroundView.gradientLayer }
    private(set) var styleLayoutInvalidationCount = 0
    var hasFixedWidthTimeLabels: Bool { equalTimeLabelWidthConstraint?.isActive == true }
    var fixedTimeLabelMinimumWidth: CGFloat { elapsedMinimumWidthConstraint?.constant ?? 0 }

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
        rootStack.alpha = isControlsVisible ? 1 : 0
        rootStack.isUserInteractionEnabled = isControlsVisible
        controlsBackgroundView.alpha = rootStack.alpha
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

    deinit {
        hideTask?.cancel()
        playerObservationToken?.cancel()
    }

    private func buildViewHierarchy() {
        directionalLayoutMargins = style.contentInsets
        rootStack.axis = .vertical
        rootStack.spacing = style.seekBarBottomSpacing
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.spacing = style.buttonSpacing
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
        bottomStack.addArrangedSubview(buttonStack)
        bottomStack.addArrangedSubview(UIView())
        bottomStack.addArrangedSubview(rateButton)
        bottomStack.addArrangedSubview(accessoryStack)
        bottomStack.addArrangedSubview(durationLabel)

        rootStack.addArrangedSubview(seekBar)
        rootStack.addArrangedSubview(bottomStack)
        controlsBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        controlsBackgroundView.isUserInteractionEnabled = false
        addSubview(controlsBackgroundView)
        addSubview(rootStack)
        backgroundTapRecognizer.cancelsTouchesInView = false
        backgroundTapRecognizer.delegate = self
        addGestureRecognizer(backgroundTapRecognizer)
        NSLayoutConstraint.activate([
            controlsBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            controlsBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            rootStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            rootStack.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            seekBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
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
        durationMinimumWidthConstraint = durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        equalTimeLabelWidthConstraint = elapsedLabel.widthAnchor.constraint(equalTo: durationLabel.widthAnchor)
        for constraint in [
            elapsedMinimumWidthConstraint,
            durationMinimumWidthConstraint,
            equalTimeLabelWidthConstraint
        ].compactMap({ $0 }) {
            constraint.priority = .defaultHigh
        }
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
        resetTimeline()

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
        setControlsEnabled(player.grade == .current)
    }

    func handlePlayerEvent(_ event: ABPlayerEvent) {
        switch event {
        case .periodicTime(let time):
            render(time)
        case .timeControlStatusChanged(let status):
            isPlayingState = status == .playing
            updatePlaybackIcon()
            handleVisibility(.playbackStateChanged(isPlaying: isPlayingState))
        case .rateChanged(let rate):
            updateRate(rate)
        case .gradeChanged(_, let grade):
            setControlsEnabled(grade == .current)
            if grade != .current { resetTimeline() }
        case .itemDetached, .sourceChanged:
            resetTimeline()
        case .itemStatusChanged(.readyToPlay):
            if let player {
                render(player.playbackTime)
                setControlsEnabled(player.grade == .current)
            }
        case .itemStatusChanged(.unknown):
            break
        case .itemStatusChanged(.failed), .failed:
            setControlsEnabled(false)
        case .playedToEnd:
            isPlayingState = false
            updatePlaybackIcon()
            handleVisibility(.setVisible(true))
        case .seekCompleted(let time):
            guard player?.isScrubbing != true else { return }
            let snapshot = ABPlaybackTime(
                currentTime: time,
                duration: currentPlaybackTime.duration ?? player?.duration,
                bufferedUntil: currentPlaybackTime.bufferedUntil
            )
            render(snapshot)
        default:
            break
        }
    }

    private func applyStyle(previous: ABPlayerControlsStyle?) {
        let replacedBackground = controlsBackgroundView.apply(style.backgroundStyle)
        controlsBackgroundView.layer.cornerRadius = style.containerCornerRadius
        controlsBackgroundView.clipsToBounds = style.containerCornerRadius > 0
        directionalLayoutMargins = style.contentInsets
        rootStack.spacing = style.seekBarBottomSpacing
        buttonStack.spacing = style.buttonSpacing
        seekBar.style = style
        elapsedLabel.textColor = style.timeLabelColor
        durationLabel.textColor = style.timeLabelColor
        let scaledTimeFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: style.timeLabelFont)
        elapsedLabel.font = scaledTimeFont
        durationLabel.font = scaledTimeFont
        elapsedLabel.adjustsFontForContentSizeCategory = true
        durationLabel.adjustsFontForContentSizeCategory = true
        updateTimeLabelWidthConstraints(using: scaledTimeFont)
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
        updateRate(player?.rate ?? 1)
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
        durationLabel.isHidden = !configuration.showsTimeLabels || configuration.timeLabelLayout == .elapsedOnly
        skipBackwardButton.isHidden = !configuration.showsSkipButtons
        skipForwardButton.isHidden = !configuration.showsSkipButtons
        updateSkipIcons()
        updateRate(player?.rate ?? 1)
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
    }

    private func updateTimeLabelWidthConstraints(using font: UIFont) {
        let constraints = [
            elapsedMinimumWidthConstraint,
            durationMinimumWidthConstraint,
            equalTimeLabelWidthConstraint
        ].compactMap { $0 }
        NSLayoutConstraint.deactivate(constraints)
        guard style.usesFixedWidthTimeLabels else { return }
        let reference = "59:59" as NSString
        let width = ceil(reference.size(withAttributes: [.font: font]).width)
        elapsedMinimumWidthConstraint?.constant = width
        durationMinimumWidthConstraint?.constant = width
        NSLayoutConstraint.activate(constraints)
    }

    private func updatePlaybackIcon() {
        playPauseButton.apply(icon: isPlayingState ? style.pauseIcon : style.playIcon, style: style)
        playPauseButton.accessibilityLabel = ABControlsLocalization.string(
            isPlayingState ? "controls.pause" : "controls.play"
        )
    }

    private func updateSkipIcons() {
        let interval = configuration.skipInterval
        let supported = [5, 10, 15, 30, 45, 60, 75, 90]
        let integerInterval = Int(interval.rounded())
        let synchronized = configuration.synchronizesSkipIconWithInterval
            && interval == Double(integerInterval)
            && supported.contains(integerInterval)
        let backward = style.skipBackwardIcon
            ?? .system("gobackward.\(synchronized ? integerInterval : 10)")
        let forward = style.skipForwardIcon
            ?? .system("goforward.\(synchronized ? integerInterval : 10)")
        skipBackwardButton.apply(icon: backward, style: style)
        skipForwardButton.apply(icon: forward, style: style)
        skipBackwardButton.accessibilityLabel = ABControlsLocalization.string("controls.skipBackward")
        skipForwardButton.accessibilityLabel = ABControlsLocalization.string("controls.skipForward")
        if !configuration.showsSkipButtons {
            skipBackwardButton.isHidden = true
            skipForwardButton.isHidden = true
        }
    }

    private func updateRate(_ rate: Float) {
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
        }
        rateButton.accessibilityLabel = ABControlsLocalization.string("controls.rate")
        rateButton.accessibilityValue = ABControlsLocalization.format("controls.rateValue", value)
        rateButton.accessibilityTraits.insert(.button)
        configureRateInteraction(currentRate: rate)
    }

    private func render(_ time: ABPlaybackTime) {
        currentPlaybackTime = time
        seekBar.progress = time.progress ?? 0
        seekBar.bufferedProgress = time.bufferedProgress ?? 0
        seekBar.isSeekEnabled = time.duration != nil && controlsAreEnabled
        elapsedLabel.text = ABTimeFormatter.string(from: time.currentTime)
        seekBar.accessibilityLabel = ABControlsLocalization.string("controls.timeline")
        seekBar.accessibilityValue = accessibilityTimelineValue(for: time)
        switch configuration.timeLabelLayout {
        case .elapsedAndTotal:
            durationLabel.text = time.duration.map(ABTimeFormatter.string(from:)) ?? ABTimeFormatter.liveMarker
        case .elapsedAndRemaining:
            durationLabel.text = ABTimeFormatter.remainingString(
                current: CMTimeGetSeconds(time.currentTime),
                duration: time.duration.map(CMTimeGetSeconds)
            )
        case .elapsedOnly:
            durationLabel.text = nil
        }
    }

    private func resetTimeline() {
        currentPlaybackTime = .zero
        seekBar.progress = 0
        seekBar.bufferedProgress = 0
        seekBar.isSeekEnabled = false
        elapsedLabel.text = ABTimeFormatter.string(from: 0)
        durationLabel.text = ABTimeFormatter.liveMarker
        seekBar.accessibilityLabel = ABControlsLocalization.string("controls.timeline")
        seekBar.accessibilityValue = ABControlsLocalization.string("controls.live")
    }

    private func setControlsEnabled(_ enabled: Bool) {
        for control in [playPauseButton, skipBackwardButton, skipForwardButton, rateButton] {
            control.isEnabled = enabled
            control.tintColor = enabled ? style.tintColor : style.disabledTintColor
        }
        seekBar.isEnabled = enabled
        seekBar.isSeekEnabled = enabled && currentPlaybackTime.duration != nil
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlayingState = false
        } else {
            player.play()
            isPlayingState = true
        }
        updatePlaybackIcon()
        handleVisibility(.controlInteracted)
        observerRegistry.broadcast(.playPauseTapped(isPlayingAfterTap: isPlayingState))
    }

    private func skip(by interval: TimeInterval) {
        guard let player else { return }
        Task { await player.skip(by: interval) }
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
        let resolvedRate = ABPlaybackRate.clamped(rate)
        player?.setRate(resolvedRate)
        updateRate(resolvedRate)
        handleVisibility(.controlInteracted)
        observerRegistry.broadcast(.rateSelected(resolvedRate))
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
        elapsedLabel.text = ABTimeFormatter.string(from: time)
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
        guard direction != 0,
              let duration = currentPlaybackTime.duration else { return }
        let durationSeconds = CMTimeGetSeconds(duration)
        let currentSeconds = CMTimeGetSeconds(currentPlaybackTime.currentTime)
        guard durationSeconds.isFinite, durationSeconds > 0, currentSeconds.isFinite else { return }
        let delta = Double(direction) * configuration.skipInterval
        let targetSeconds = min(max(currentSeconds + delta, 0), durationSeconds)
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        render(ABPlaybackTime(
            currentTime: target,
            duration: duration,
            bufferedUntil: currentPlaybackTime.bufferedUntil
        ))
        if let player {
            Task { await player.skip(by: delta) }
        }
        handleVisibility(.controlInteracted)
        observerRegistry.broadcast(.seekCommitted(to: target))
    }

    private func accessibilityTimelineValue(for time: ABPlaybackTime) -> String {
        guard let duration = time.duration else {
            return ABControlsLocalization.string("controls.live")
        }
        let currentSeconds = CMTimeGetSeconds(time.currentTime)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard currentSeconds.isFinite, durationSeconds.isFinite else {
            return ABControlsLocalization.string("controls.live")
        }
        return ABControlsLocalization.format(
            "controls.timelineValue",
            ABControlsLocalization.spokenTime(currentSeconds),
            ABControlsLocalization.spokenTime(durationSeconds)
        )
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
            self.rootStack.alpha = alpha
            self.rootStack.isUserInteractionEnabled = visible
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
        var view = touch.view
        while let current = view, current !== self {
            if current is UIControl { return false }
            view = current.superview
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
