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
    private let observerRegistry = ABControlsObserverRegistry()
    private var playerObservationToken: ABObservationToken?
    private var periodicIntervalLease: ABPeriodicIntervalLease?
    private var isPlayingState = false
    private var currentPlaybackTime = ABPlaybackTime.zero
    private var visibilityMachine: ABControlsVisibilityMachine
    private var hideTask: Task<Void, Never>?
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

    var displayedPlayPauseImage: UIImage? { playPauseButton.image(for: .normal) }
    var displayedRateText: String? { rateButton.title(for: .normal) }
    var displayedElapsedText: String? { elapsedLabel.text }
    var displayedDurationText: String? { durationLabel.text }
    var controlsAreEnabled: Bool { playPauseButton.isEnabled }
    var isShowingPauseIcon: Bool { isPlayingState }
    var hasScheduledAutoHide: Bool { hideTask != nil }
    var controlsContentAlpha: CGFloat { rootStack.alpha }
    var controlsContentIsInteractive: Bool { rootStack.isUserInteractionEnabled }

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
        addSubview(rootStack)
        backgroundTapRecognizer.cancelsTouchesInView = false
        backgroundTapRecognizer.delegate = self
        addGestureRecognizer(backgroundTapRecognizer)
        NSLayoutConstraint.activate([
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
        seekBar.onScrubBegan = { [weak self] in self?.scrubBegan() }
        seekBar.onScrubChanged = { [weak self] progress in self?.scrubChanged(progress: progress) }
        seekBar.onScrubEnded = { [weak self] progress in self?.scrubEnded(progress: progress) }
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
        directionalLayoutMargins = style.contentInsets
        rootStack.spacing = style.seekBarBottomSpacing
        buttonStack.spacing = style.buttonSpacing
        seekBar.style = style
        elapsedLabel.textColor = style.timeLabelColor
        durationLabel.textColor = style.timeLabelColor
        elapsedLabel.font = style.timeLabelFont
        durationLabel.font = style.timeLabelFont
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
        setNeedsLayout()
    }

    private func applyConfiguration(previous: ABPlayerControlsConfiguration?) {
        seekBar.showsBufferedProgress = configuration.showsBufferedProgress
        seekBar.allowsTrackTapToSeek = configuration.allowsTrackTapToSeek
        elapsedLabel.isHidden = !configuration.showsTimeLabels
        durationLabel.isHidden = !configuration.showsTimeLabels || configuration.timeLabelLayout == .elapsedOnly
        skipBackwardButton.isHidden = !configuration.showsSkipButtons
        skipForwardButton.isHidden = !configuration.showsSkipButtons
        updateSkipIcons()
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

    private func updatePlaybackIcon() {
        playPauseButton.apply(icon: isPlayingState ? style.pauseIcon : style.playIcon, style: style)
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
        case .icon(let icon, _):
            rateButton.setTitle(nil, for: .normal)
            rateButton.apply(icon: icon, style: style)
        }
    }

    private func render(_ time: ABPlaybackTime) {
        currentPlaybackTime = time
        seekBar.progress = time.progress ?? 0
        seekBar.bufferedProgress = time.bufferedProgress ?? 0
        seekBar.isSeekEnabled = time.duration != nil && controlsAreEnabled
        elapsedLabel.text = ABTimeFormatter.string(from: time.currentTime)
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

    private func scrubBegan() {
        player?.beginScrubbing()
        handleVisibility(.scrubBegan)
        observerRegistry.broadcast(.scrubbingChanged(isScrubbing: true))
    }

    private func scrubChanged(progress: Double) {
        guard let duration = currentPlaybackTime.duration,
              let time = ABSeekBarGeometry.time(forProgress: progress, duration: duration) else { return }
        elapsedLabel.text = ABTimeFormatter.string(from: time)
        player?.scrub(to: time)
    }

    private func scrubEnded(progress: Double) {
        guard let player,
              let duration = currentPlaybackTime.duration,
              let time = ABSeekBarGeometry.time(forProgress: progress, duration: duration) else { return }
        Task { [weak self, weak player] in
            guard let self, let player, self.player === player else { return }
            await player.endScrubbing()
            self.handleVisibility(.scrubEnded)
            self.observerRegistry.broadcast(.scrubbingChanged(isScrubbing: false))
            self.observerRegistry.broadcast(.seekCommitted(to: time))
        }
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
            self.rootStack.alpha = visible ? 1 : 0
            self.rootStack.isUserInteractionEnabled = visible
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: style.visibilityAnimationDuration,
            animations: changes
        )
    }

    private func scheduleAutoHide(after delay: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, delay)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hideTask = nil
            self?.handleVisibility(.autoHideFired)
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
