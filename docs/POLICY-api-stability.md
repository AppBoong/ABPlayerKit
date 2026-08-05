# API Stability Policy (0.x)

This project already documents non-exhaustive `enum` growth for `ABPlayerEvent`/`ABPlayerError` (README §Targets, CHANGELOG entries for each new case). This document extends that same practice to the rest of the public API surface for as long as the package stays at a `0.x` version, and records the concrete rules WP-B (`ROADMAP-round4.md`) followed when deprecating the array-based `accessoryViews:` initializers in favor of the `@ViewBuilder accessories:` ones (see `DESIGN-OPEN-QUESTIONS.md` Q6-A).

## Rules

| Rule | Content |
|---|---|
| Replacement APIs | Always added **additively** first. The old API is never removed in the same release that introduces its replacement. |
| Deprecation timing | `@available(*, deprecated, message:)` is added in the **same minor** release as the replacement API. `message` must name the replacement symbol and the version scheduled for removal. |
| Removal timing | Nothing is removed **before 1.0.0**. At least one minor release of overlap is guaranteed between deprecation and removal. |
| Patch releases | A patch release (`0.x.y`) never introduces a new deprecation. Deprecations land only in minor releases, alongside their replacement. |
| Adding `enum` cases | Existing convention continues — non-exhaustive declaration, `default` required, documented in both the type's doc comment and its DocC page. |
| Behavior changes | Even when a signature is unchanged, if the *observable output* changes, the CHANGELOG's `### Changed` (or `### Fixed`) entry must include a one-line **Migration** note. |

The last rule turns an actual incident from this project into a standing rule: WP12's `.custom` time-format contract change (round3 Phase4) landed under `### Fixed` in the CHANGELOG initially without a migration note (see `REVIEW-round3-final.md` N13) — a consumer relying on the old (buggy) combining behavior would have had no signal that their `.custom` formatter needed to change. The `[0.3.0]` CHANGELOG entry for that same fix now carries a **Migration notes** section as the pattern this rule requires going forward.

## Worked example: WP-B3's deprecation (round4)

- `ABPlayerControls.init(player:style:configuration:accessoryViews:onEvent:)` and `ABVideoPlayerWithControls.init(player:videoGravity:style:configuration:accessoryViews:)` were marked `@available(*, deprecated, message: "Use the @ViewBuilder \`accessories:\` initializer instead. Scheduled for removal in 1.0.0.")` in the same change that added the `@ViewBuilder accessories:` initializers (additive-first, satisfied in one commit rather than staged across two, since both landed together here).
- `ABPlayerControlsView.accessoryViews` (the underlying UIKit `[UIView]` property, not the SwiftUI initializer) was deliberately **not** deprecated — it remains the correct, first-class API for UIKit consumers, and deprecating it would have broken every existing UIKit call site and DocC reference for no reason tied to this change.
- The library's own internal call from `ABVideoPlayerWithControls` into `ABPlayerControls`'s array-based initializer was routed through a separate, non-deprecated `internal` initializer (`init(legacyPlayer:...)`) rather than the deprecated public one — calling a deprecated declaration from a *non-deprecated* context still warns under `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, and Swift has no per-call-site suppression attribute, so the only way to avoid the warning without disabling the CI gate is to not go through the deprecated symbol internally at all.

## Where this doesn't apply

This policy governs the `0.x` line specifically. Once the package reaches `1.0.0`, standard semver applies (breaking changes require a major version bump instead of a deprecate-then-remove cycle), and this document should be revisited.
