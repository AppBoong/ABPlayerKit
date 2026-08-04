# ABPlayerKit v0.2 Design Brief — Engine Enhancements + Controls Layer

## Context
ABPlayerKit v0.1.0 is released (github.com/AppBoong/ABPlayerKit). The view layer is chrome-less: `ABPlayerView`/`ABVideoPlayer` render only. A consumer demo (ABKitsDemo) showed the gaps: no playback-rate public API, no periodic time events (demo had to poll with TimelineView), no skip convenience, and no controls UI at all.

## Scope for v0.2 (ABPlayerKit only — ABShortsKit comes later)

### 1. Engine reinforcement
- `setRate(_:)` public API + rate change event. Decide interaction with play()/pause() (does play() restore last rate?), preroll, and grade transitions.
- `skip(by: TimeInterval)` convenience (forward/backward, clamped to duration/zero).
- Periodic time observation: an opt-in periodic time event with configurable interval, delivered through the existing observer system (`ABPlayerEvent`), designed so a seekbar can be driven without polling. Consider buffered-range (loadedTimeRanges) exposure for a buffer bar.
- Scrubbing support: design a seek API suitable for seekbar dragging (coalescing/debounced seeks, `seek(to:precise:)` or begin/endScrubbing semantics) so rapid slider movements don't queue stale seeks.

### 2. Controls layer (new)
A ready-made controls overlay, UIKit core + SwiftUI wrapper, following existing library conventions:
- Play/pause button
- Skip backward/forward buttons with configurable interval (default 10s)
- Playback rate control (e.g. menu/cycle: 0.5×, 1×, 1.25×, 1.5×, 2×; configurable list)
- Seekbar: current progress, (optionally buffered progress), draggable thumb, elapsed/total time labels
- Auto-hide behavior (tap to show, hide after configurable delay, stay visible while scrubbing)

### 3. Customization (user requirement — must-have)
External consumers must be able to customize at minimum:
- Icons: play, pause, skip-forward, skip-backward, (rate label style) — default SF Symbols, overridable with custom images
- Seekbar track background color (뒷편색) and progress color (앞편색)
- Thumb (pointer) size and color
- General tint/text colors
Design this as a value-type style/theme configuration (e.g. `ABPlayerControlsStyle`) consistent with the library's existing config-struct pattern. Consider which properties need live update (style change after creation).

## Constraints (follow existing project conventions — see docs/PLANNING.md, docs/DESIGN-ABPlayerKit.md)
- iOS 17+, Swift 6 language mode, zero warnings
- Observer + ABObservationToken pattern (no delegate/AsyncStream for new events)
- Init injection + config structs; protocols only at test seams
- MainActor discipline: no `MainActor.assumeIsolated`; timestamp capture rules as in TTFF design
- Scenario-based `@Suite` tests for all new engine logic; controls logic testable (state machine for auto-hide/scrubbing extracted as pure type if feasible)
- DocC + README (en/ko) updates; English Conventional Commits; semver v0.2.0
- Public API additions must be additive (no breaking changes to v0.1 API)

## Deliverable
Write the full design to `docs/DESIGN-v0.2-CONTROLS.md`:
- Public API sketch (signatures) for engine additions and controls layer
- File/target layout (does controls live in ABPlayerKit or a new ABPlayerKitControls target? Recommend one with rationale)
- Event flow diagrams for scrubbing and auto-hide
- Style/theme struct full property list with defaults
- Test plan (scenario list per suite)
- Implementation task breakdown for Codex (ordered commits)
- Open questions section: anything requiring user decision, clearly listed with options and a recommendation

When complete, write `docs/DESIGN-v0.2-VERDICT.md` containing the single line `DESIGN-COMPLETE` plus a 5-line summary.
