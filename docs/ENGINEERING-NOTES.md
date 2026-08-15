# Engineering Notes

Three defects that an otherwise-green automated suite did not catch, what the tests
were measuring instead, and what changed as a result.

When the first of them was found, ABPlayerKit had **743 tests at ~91% line coverage**
(752 by the time v0.4.0 shipped), a Swift 6 language-mode build with warnings as
errors, a ThreadSanitizer job, and a DocC build gated on warnings. All of it was
green. Two of the three defects below were found by a person holding an iPhone; the
third was only reachable because the first one had been fixed.

The interesting part is not that bugs existed. It is that in each case the suite
already contained a test aimed at the behavior in question, which passed — because it
measured the wrong dimension, on the wrong object, or the wrong quantity.

- [The shape of the gap](#the-shape-of-the-gap)
- [1. A background-audio policy that was dead on hardware](#1-a-background-audio-policy-that-was-dead-on-hardware)
- [2. A pause that came back to life](#2-a-pause-that-came-back-to-life)
- [3. One pixel of layout jitter](#3-one-pixel-of-layout-jitter)
- [What changed in how this project tests](#what-changed-in-how-this-project-tests)
- [The numbers](#the-numbers)

---

## The shape of the gap

For a library that wraps `AVPlayer`, a large class of behavior is defined by what iOS
does in response to what you did, and *when* you did it. The iOS Simulator has no
Picture in Picture, no lock screen, no AirPlay receiver, and no background audio
assertion. So automated verification of the playback-policy layer reaches exactly
three things: the **policy reducer** (given this event and this policy, which
actions?), the **binding lifetime** (does the observer install and tear down?), and
**configuration passthrough** (does the value reach `AVPlayerItem`?).

It does not reach whether the feature works.

This was known before the round, not after it. The design document's risk register
carried the entry that later came due, written while the feature was still being
designed:

> | 10-9 | `.continueAudioOnly`가 레이어 detach만으로 실제 배경 오디오를 이어 가는가 | **플랫폼 기법에 근거한 설계 판단, 리포 코드로는 검증 불가** | §6.2의 3조건을 갖춘 데모에서 **기기 수동 확인**. 실패하면 §6.5의 "비디오 트랙 비활성화" 대안을 재검토 |
>
> *("Does `.continueAudioOnly` actually sustain background audio through layer detach
> alone? — A design judgment based on a platform technique; **not verifiable from
> repo code**. Mitigation: **manual device verification** in a demo satisfying the
> three preconditions. If it fails, revisit the §6.5 'disable the video track'
> alternative.")*
> — `DESIGN-round6-nowplaying.md:977`, a maintainer-facing design record no longer
> carried in the tree. Verify with
> `git show v0.4.0:docs/briefs/DESIGN-round6-nowplaying.md | sed -n '977p'`

That entry is why [`docs/CHECKLIST-device-verification.md`](CHECKLIST-device-verification.md)
exists: a six-item manual procedure, run by a person on real hardware before a tag.
The paragraph explaining why it exists states the claim it defends:

> CI가 전부 그린인 것과 기기에서 기능이 살아 있는 것은 **별개의 주장**이며, 이 목록은 그 간극을 메우는 유일한 수단이다.
>
> *("CI being all green and the feature being alive on the device are **separate
> claims**, and this list is the only means of closing that gap.")*
> — `docs/CHECKLIST-device-verification.md:5`

Item 3 of that checklist failed on its first run.

---

## 1. A background-audio policy that was dead on hardware

**Commit [`390cf09`](https://github.com/AppBoong/ABPlayerKit/commit/390cf09) · found on device · 743 tests green**

`ABBackgroundPolicy.continueAudioOnly` was a headline feature of v0.4.0. On a real
iPhone it did nothing. Backgrounding the app silenced playback and returning to the
foreground resumed it — which is precisely the documented fallback for *unmet
preconditions*, so the failure disguised itself as correct behavior.

### The mechanism

Keeping audio alive in the background requires clearing `AVPlayerLayer.player`
**while the app is still handling `didEnterBackgroundNotification`**. iOS decides
whether to grant the process a continuous-playback audio assertion at that moment,
and an attached video layer in a backgrounded app means AVFoundation stops the player
first.

The lifecycle observer registered a block-form notification handler:

```swift
// Sources/ABPlayerKit/Policy/ABApplicationStateObserver.swift @ 390cf09^
tokens.append(
    center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
    ) { _ in
        Task { @MainActor in onBackground() }
    }
)
```

Everything downstream of `onBackground()` is synchronous. Four hops, in order:

1. the policy machine returns `[.setLayerAttachment(false)]` for this policy — and
   notably no `.pause`;
2. the engine's `setLayerAttachmentEnabled(false)` flips its own flag;
3. it broadcasts to the layer-attachment observer registry;
4. `ABPlayerView` responds by setting `playerLayer.player = nil`.

All four were displaced by the single `Task {}` at the top. `post(name:)` returned
with nothing done; AVFoundation stopped the still-attached player; nothing was
playing when iOS evaluated the assertion; the process was suspended a few seconds
later.

`willResignActive` had the same requirement for an unrelated reason: its only job is
`wasPlayingBeforeBackground = target.isPlaying`, and one turn later decode teardown
has already falsified that value.

### Why 743 green tests said nothing

There was a test for this. It was the first test in the file named after the feature:

```swift
// Tests/ABPlayerKitTests/ABContinueAudioOnlyTests.swift @ 390cf09^
@Test("Background entry under .continueAudioOnly detaches the layer without pausing")
func backgroundEntryDetachesLayerOnly() async {
    …
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    await Task.yield()
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    await Task.yield()

    #expect(player.isPlaying)
    #expect(!player.isLayerAttachmentEnabled)
    #expect(!target.calls.contains(.pause))
}
```

Post, yield, assert the end state. **The yields absorb the exact hop the defect lived
in.** All five tests in that file have the same shape, and all five pass against the
broken code — verified by reverting the observer to its pre-fix version, keeping the
post-fix tests, and running the suite.

This was not something nobody had noticed. A sibling suite documented the hop
*explicitly*, as an inert implementation detail to be worked around:

```swift
// Tests/ABPlayerKitTests/ABPlayerEngineTests.swift @ 390cf09^
// `ABApplicationStateObserver` registers with `queue: .main` and
// wraps its callback in its own `Task { @MainActor in ... }`, so the
// actual `onBackground()` call is one more main-actor turn away
// from this synchronous `post(name:)` — a single `Task.yield()`
// deterministically hands the actor over long enough for both hops
// to run before this test resumes (round3 Phase1+2 review m6).
await Task.yield()
```

The comment names the exact defect mechanism, three rounds before the defect
surfaced, and treats it as a scheduling nuisance. It was written in response to a
review finding, so it passed through review on the way in. The five yields in
`ABContinueAudioOnlyTests` carry no such comment, but they have the same shape and
the same effect.

### The view-level test that existed, and still could not see it

A natural conclusion at this point would be "nothing tested the thing iOS actually
reads." That is not true, and the truth is more useful. `ABPlayerViewLifecycleTests`
did bind a real `ABPlayerView` and assert on `AVPlayerLayer.player` across a
background transition:

```swift
// Tests/ABPlayerKitTests/ABPlayerEngineTests.swift @ 390cf09^
@Test("pauseAndDetachLayer detaches in background and reattaches in foreground")
func backgroundPolicyDetachesAndReattachesLayer() async throws {
    …
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    try await waitUntil { (view.layer as? AVPlayerLayer)?.player == nil }
    #expect((view.layer as? AVPlayerLayer)?.player == nil)
    …
}
```

Two things about it. It covers `.pauseAndDetachLayer`, not `.continueAudioOnly`. And
it reaches its assertion through `try await waitUntil { … }` — **a poll, which is the
same shape as the yields one level up.** It proves the detach *happens* and is by
construction incapable of noticing *when*.

Under `.pauseAndDetachLayer` that is the correct test: the policy pauses as well, so
the timing carries no weight. Under `.continueAudioOnly` the timing *is* the feature.
The same assertion, on the same object, was right in one place and blind in the
other — which is why "do we have coverage of X?" is the wrong question to ask a suite.

### The fix

Selector-based registration, so handlers run synchronously inside the notification's
own dispatch:

```swift
// Sources/ABPlayerKit/Policy/ABApplicationStateObserver.swift @ main
final class ABApplicationStateObserver: NSObject {
    …
    init(…) {
        …
        super.init()
        center.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        …
    }

    @objc private func applicationDidEnterBackground() {
        onBackground()
    }
    …
}
```

Not every observer moved. `ABAudioInterruptionObserver` deliberately keeps the
closure form, because `AVAudioSession` posts off the main thread and a main-actor
`@objc` thunk carries a runtime executor check that would trap — in release builds,
not just debug.

### The test that pins it now

The new test's design decision is the *absence* of `async`:

```swift
/// Deliberately non-`async`, with no `Task.yield()` between the post and
/// the expectations — the assertion *is* that the detach already happened
/// by the time `post(name:)` returned.
@Test("The layer detaches inside the background notification's own dispatch, not a turn later")
func backgroundEntryDetachesLayerSynchronously() {
    …
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

    #expect(!player.isLayerAttachmentEnabled)
    #expect(player.isPlaying)
    #expect(!target.calls.contains(.pause))
}
```

A non-`async` `@MainActor` test body cannot suspend, so nothing a `Task {}` enqueues
can run before the expectations. The oracle is *"had it already happened when
`post(name:)` returned?"* — which is the question iOS asks.

A companion test binds an `ABPlayerView` and asserts `layer?.player == nil` under the
same conditions, with no poll — closing the gap the `waitUntil` version left open.
Both new tests fail against the reverted observer; the five original tests still pass
against it.

### A project constraint that pointed the wrong way

The first attempt at this fix used `MainActor.assumeIsolated`. CI rejected it — this
repository bans that API in `CONTRIBUTING.md` and enforces the ban with a custom
SwiftLint rule at `error` severity:

```
error: No MainActor.assumeIsolated Violation: CONTRIBUTING.md prohibits
MainActor.assumeIsolated; keep call sites provably non-isolation-assuming
(await the actor instead). (no_main_actor_assume_isolated)
```

The rule's suggested remedy — *"await the actor instead"* — **is the exact deferral
that caused the defect.** The constraint and the requirement were only jointly
satisfiable by removing the need for an isolation assumption at all, which selector
registration does: the `@objc` thunk for a main-actor-isolated method carries its own
runtime executor check, so posting from a background thread traps loudly instead of
racing silently. The assumption does not disappear; it moves somewhere it is enforced
rather than asserted.

---

## 2. A pause that came back to life

**Commit [`d484ea3`](https://github.com/AppBoong/ABPlayerKit/commit/d484ea3) · found in review, on a path the previous fix had just made executable · 745 tests green**

Provenance first, since it matters: this one was **not** found on the device. It was
a review finding, titled as such. The device checklist's item 4 does cover the
lock-screen pause path, but its results were only filled in after this fix landed —
there is no record of that item being run while the defect was live.

What makes it belong here is that it was *unreachable* until the previous fix
shipped. `.continueAudioOnly` is the only policy that leaves playback running in the
background, so it is the only one where a user can pause it there. Fixing defect 1
opened a code path that had never been executable, and the defect sitting in it had
been invisible for exactly that reason.

### The mechanism

Three sites, none of which the fix changed:

1. `willResignActive` emits `.capturePlaying` for `.pause`, `.pauseAndDetachLayer`,
   **and** `.continueAudioOnly`.
2. `.capturePlaying` sets `wasPlayingBeforeBackground = target.isPlaying`.
3. On `willEnterForeground`, `.resumePlay` is appended when
   `grade == .current && wasPlayingBeforeBackground` — gated on **nothing else**.

Under both other capturing policies the library itself pauses before backgrounding,
so nothing could contradict the capture and the flag was effectively unfalsifiable.
Under `.continueAudioOnly`, a user pausing from the lock screen went through the
public `ABPlayer.pause()`, which cleared `desiresPlayback` but left the capture set —
and `willEnterForeground` then overrode the user's explicit intent.

The fix is one line, plus ten of comment naming the callers that must *not* be
affected (the policy machine's own pause and the interruption handlers reach
`target.pause()` directly, bypassing the public method):

```swift
// Sources/ABPlayerKit/Engine/ABPlayer.swift:409
wasPlayingBeforeBackground = false
```

### Why the tests missed it

The state machine was well covered — parameterized over grade and prior state, across
the three policies that capture:

```swift
// Tests/ABPlayerKitTests/ABBackgroundPolicyMachineTests.swift @ d484ea3^
@Test("willEnterForeground resumes play only when .current and wasPlayingBeforeBackground, …",
      arguments: [(ABPlaybackGrade.current, true), (.current, false),
                  (.preloaded, true), (.instanceOnly, false)])
func willEnterForegroundResumesConditionally(grade: ABPlaybackGrade, wasPlaying: Bool) {
    for policy in [ABBackgroundPolicy.pause, .pauseAndDetachLayer, .continueAudioOnly] {
        let actions = machine.actions(
            for: .willEnterForeground,
            policy: policy,
            grade: grade,
            wasPlayingBeforeBackground: wasPlaying,
            hasCapturedGrade: false
        )
        …
```

(A *grade* here is how much of the AVFoundation stack a player currently holds —
`.released` → `.instanceOnly` → `.preloaded` → `.current` — and only `.current` may
play.)

The reducer's behavior was always correct. `wasPlayingBeforeBackground` is a **test
parameter, handed straight to a pure function.** A pure-reducer test can never ask
whether the engine keeps the reducer's inputs truthful — and that is where the defect
was.

The nearest engine-level test was aimed at the right concept and missed for a
different reason. It is named *"A resign that never reaches didEnterBackground does
not leave a stale capture that force-resumes on foreground"* — but it manufactures
the stale capture by **never starting playback** (so the flag is `false` from the
outset) rather than by contradicting a `true` one, and it uses `backgroundPolicy:
.pause`, the one policy family where a mid-background user pause is structurally
impossible. All three tests in that file used `.pause`.

**The lesson: the suite tested the state machine thoroughly and the state machine's
inputs not at all.** Covering a pure function across its input space proves the
function; it says nothing about the impure code that feeds it.

The regression test added with the fix ships alongside a *control* case asserting that
`.pause` policy's own background-pause-then-resume is unchanged. Verified by reverting
only the `pause()` change: the regression test fails, the control passes.

---

## 3. One pixel of layout jitter

**Commit [`14670be`](https://github.com/AppBoong/ABPlayerKit/commit/14670be) · found on device · 747 tests green**

`ABPlayerView` reports its pixel size to the engine on every layout pass so the engine
can cap decode resolution to what is actually on screen. On device, the reported size
alternated between two values one pixel apart — `1164×655` and `1165×655`. Legal host
behavior, and nothing a library can prevent.

The guard against re-applying on every pass was exact equality:

```swift
// Sources/ABPlayerKit/Engine/ABPlayer.swift @ 14670be^
/// Re-applies tuning only when the size actually changed, so repeated
/// identical layout passes don't loop.
func reportDisplaySize(_ size: CGSize) {
    guard displaySize != size else { return }
    …
    if target.applyTuning(resolvedTuning(for: role)) {
        broadcast(.tuningApplied(role, tuning(for: role)))
    }
}
```

So every alternation re-resolved the cap to a value one pixel different, re-applied
it, and broadcast `.tuningApplied`. A consumer re-rendering on that event moved the
view's frame, which produced the next layout pass, which produced the next broadcast.
The two drove each other at display refresh rate indefinitely — **1826 re-applies in
20 seconds on an iPhone Air** (≈91/s), with `AVPlayer`'s `timeControlStatus` KVO
re-firing in lockstep, because every apply writes
`automaticallyWaitsToMinimizeStalling`. The UI was unusable.

Note what closes this loop: it runs *through the consumer*. Nothing inside the library
observes it, which is why no amount of unit-testing the library in isolation had a
chance.

### Why the tests missed it: a specification error, not a coverage gap

The suite had a test for the loop. It was named for it:

```swift
// Tests/ABPlayerKitTests/ABDisplaySizeTuningTests.swift @ 14670be^
@Test("Reporting the same display size twice does not re-apply tuning (loop guard)")
func repeatedIdenticalDisplaySizeDoesNotReapply() {
    …
    player.reportDisplaySize(cellSize)
    let applyTuningCallCountAfterFirst = …

    player.reportDisplaySize(cellSize)

    let applyTuningCallCountAfterSecond = …
    #expect(applyTuningCallCountAfterSecond == applyTuningCallCountAfterFirst)
}
```

It reports the *same* `cellSize` twice. It verifies the `!=` guard's stated contract
and nothing beyond it. It has no notion of a size that *changes* without *meaning*
anything.

Trace it back and the test is not where the mistake was made. The design document
specified the guard in one sentence:

> 값이 실제로 바뀐 경우에만 재적용해 루프를 막는다.
>
> *("Re-apply only when the value actually changed, to block the loop.")*
> — `DESIGN-round6-core.md:504`, a maintainer-facing design record no longer carried
> in the tree. Verify with
> `git show v0.4.0:docs/briefs/DESIGN-round6-core.md | sed -n '504p'`

The implementation is a faithful, literal realization of that sentence. The test is a
faithful, literal test of that implementation. The doc comment restates the sentence
back. **Every layer agreed with every other layer, and every layer was wrong the same
way** — none of them modeled the fact that on real hardware a view's size *changes*
between passes without *meaning* anything. Internal consistency is not a correctness
argument; it is a shared assumption propagating unchallenged.

That design line was never corrected. The document carrying it has since been
retired from the tree, which means this page is now the only place the mistake is
written down — so it is worth being explicit: the sentence is wrong, and it was
wrong in a way that three layers of faithful implementation could not detect.

### The fix, and what it does not promise

Two guards: the size must move at least one macroblock (16 px) in one dimension,
measured against the *stored* size so sub-threshold jitter cannot accumulate into a
drift; and the resolved tuning that would actually reach `AVPlayerItem` must differ.
Both live in the engine rather than the view, because that is where the loop closes
and every future reporter then inherits the robustness.

The direct reproduction drives 200 alternations — 400 reports — and asserts that the
fixed code adds **zero** applies and **zero** broadcasts. Against the reverted code
every single report re-applies and broadcasts: 400 of each, a 1:1 amplification of
pure layout noise into work.

Four more tests accompany it: rotation still re-caps; a view growing one pixel at a
time re-caps exactly once, when it clears the tolerance; `.zero` transitions always
count; and a tuning carrying no display-size sentinel is never re-applied on a resize
(that one exercises the second guard independently of the 16-pixel threshold). Two of
the four pass against *both* versions, which is what makes them guard rails against
overcorrection rather than restatements of the fix.

The review pass on this commit removed two overclaims from its own first draft. The
changelog had said genuine resizes "re-cap exactly as before"; they do not — a resize
smaller than 16 px now leaves the cap where it was, and a feed cell is exactly where
that is plausible. The doc comment had said the guards "keep this from closing a
feedback loop"; they raise its threshold. **Measured, the loop reopens at an
oscillation amplitude of 16 pixels.** The observed one was a single pixel, so the
defect is genuinely fixed, but the structural possibility is not removed and cannot
be — the library does not control what a consumer does with an event.

---

## What changed in how this project tests

Five rules, each paid for by one of the above.

**1. When timing is the contract, assert the timing.** A test that yields — or polls —
before asserting measures the end state and nothing else. Where synchrony is
load-bearing, the test body is deliberately non-`async`, so the runtime cannot hand
the actor over and the assertion becomes *"this already happened."*

**2. The same assertion can be right in one place and blind in another.** The
view-level test asserting on `AVPlayerLayer.player` was correct for
`.pauseAndDetachLayer` and useless for `.continueAudioOnly`, because only one of those
policies makes the timing load-bearing. Coverage of an object says nothing until you
ask what property of it the platform actually depends on.

**3. A pure-reducer test cannot check who maintains its inputs.** Parameterizing a
reducer over its input space proves the reducer. The defect will be in the impure code
that decides what to pass it — which needs its own tests, at the level where that
decision is made.

**4. For a continuous physical quantity, "changed" is not "meaningfully changed."**
Exact equality is the right guard for an identity and the wrong one for a measurement.
Pixel sizes, timestamps, and byte offsets that come from a layout engine, a clock, or
a network all arrive with noise on them.

**5. Manual verification is a test, and it needs the same rigor as one.** Item 3 was
reported as failing twice for reasons that turned out to be procedural — a tester on
the Device tab, which lacks the controls the item requires, and leftover audio from
the previous item that was indistinguishable from this item's own pass criterion —
and a third demo defect muddied the signal further: the demo inherited the library's
`.unmanaged` audio-session default, so the Ring/Silent switch silenced it, and sound
appeared only on the one path that switched the session to `.playback`. Each produced
a hardening: explicit tab names, an explicit precondition to stop the prior item's
session, and a demo that takes a `.playback` session at startup. **Telling "the
feature is broken" from "the procedure is broken" was the expensive part of this
round.** An ambiguous manual checklist behaves much like a flaky test, and is debugged
the same way.

---

## The numbers

Test counts are `@Test` declarations across the five test targets — which is also what
swift-testing's run summary reports, since a parameterized test counts once there
rather than once per case. Cross-checked against the CI log for each run.

| Tree | Tests | State |
|---|---:|---|
| `390cf09^` | **743** | `.continueAudioOnly` dead on device. Suite green. |
| `390cf09` | 745 | Fixed. Two new tests, both failing against the reverted observer. |
| `d484ea3^` | **745** | Explicit-pause resurrection live, unreachable before `390cf09`. |
| `d484ea3` | 747 | Fixed, plus a control case pinning `.pause` policy's own resume. |
| `14670be^` | **747** | Tuning loop live on device at ~91 re-applies/s. Suite green. |
| `14670be` | **752** | Fixed. Five new tests, two of them guard rails. |
| v0.4.0 shipped | **752** | 91.1% line coverage. |

CI is four jobs: `build-and-test` (Xcode 16.4, warnings as errors, DocC warnings as
errors), `lint` (`swiftlint --strict`), `thread-sanitizer`, and a coverage job. All
four were green at each point above, with one exception worth stating rather than
rounding away: `14670be`'s own push run on `main` was **cancelled** 50 seconds in,
because the next commit landed 15 seconds later and the workflow sets
`concurrency: cancel-in-progress`. Its PR head ran green with all 752, and so did
`9087d2a`, the next commit on `main`, whose test tree is identical.

For the manual procedure these notes keep referring to, see
[`CHECKLIST-device-verification.md`](CHECKLIST-device-verification.md) — six items,
the automated coverage boundary stated for each, and the recorded results for v0.4.0
(iPhone Air, iOS 26.5).
