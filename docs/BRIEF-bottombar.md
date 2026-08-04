# Controls Bottom-Bar Rework (user feedback round 2)

Implementation brief. Repo: ABPlayerKit (this directory). Current HEAD: `ecfd779`.

## Requirements (exact)

1. **Layout** — the seek bar spans the full overlay width with EQUAL horizontal padding on both sides. The time label moves BELOW the seek bar at the bottom-LEFT; the rate button moves BELOW the seek bar at the bottom-RIGHT — both use the SAME horizontal padding as the seek bar edges. The vertical gap between seek bar and the row below must be tight (the previous gap between time label and seek bar was far too large — make the whole bottom cluster compact).
2. **Time format customization** — expose time-label formatting in `ABPlayerControlsConfiguration`: enum with `automatic` (mm:ss under 1 hour, HH:mm:ss otherwise), `fixedHours` (current HH:mm:ss/HH:mm:ss behavior), and `custom((TimeInterval, TimeInterval?) -> String)`. Extend `ABTimeFormatter` accordingly with tests.
3. **Rate default** — a fresh controls view over a fresh player always shows `1×`.
4. **Skip interval** — `skipInterval` customizable in 5-second steps from 5 to 60 (clamp invalid values; document the rule). The NUMBER RENDERED INSIDE the skip button icons must reflect the configured interval: use the matching SF Symbol (`gobackward.N`/`goforward.N`) when it exists, otherwise render the number over a generic arrow icon; must still work with custom icons via style.
5. **Play/pause bounce** — tapping play/pause runs a quick scale-up-then-down spring bounce on the button (~0.85→1.1→1.0, <0.35s), skipped when Reduce Motion is on.

## Quality gates
- Unit tests for: formatter cases, skip clamping, new bottom-cluster layout geometry, rate default. Animation itself excluded from unit scope but its trigger path testable.
- Zero compiler warnings, full package suite green:
  `xcodebuild -scheme ABPlayerKit-Package -destination 'id=65CDD0F3-DEE7-4132-B823-E86003329F5E' test`
- English Conventional Commits, one logical change per commit. No push, no tag.

## Simulator rule (STRICT)
Do NOT boot or create any simulator. Use ONLY the already-booted Orca-attached iPhone Air, UDID `65CDD0F3-DEE7-4132-B823-E86003329F5E`:
- build demo: `xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj -scheme ABPlayerKitDemo -destination 'id=65CDD0F3-DEE7-4132-B823-E86003329F5E' build`
- install/launch/screenshot via `xcrun simctl ... 65CDD0F3-DEE7-4132-B823-E86003329F5E ...` (bundle id `com.appboong.ABPlayerKitDemo`)
- drive touches with `orca emulator tap x y --json` / `orca emulator gesture ...` (already attached to this device; coordinates normalized 0–1)

## Visual verification checklist (screenshots required)
- Compact bottom cluster; full-width seek bar with equal side padding
- Time label bottom-left BELOW the bar; `1×` bottom-right BELOW the bar
- Skip buttons show the configured number (test with a non-default like 5 or 30 via the demo)
- Bounce on play/pause tap

## Done signal
Append `BOTTOMBAR-DONE` plus the commit list to `IMPL-v0.2-RESULT.md`.
