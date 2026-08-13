# RESULT: 라운드6 최종 게이트 REQUEST-CHANGES 닫기 (문서 전용)

담당: Sonnet. worktree `/Users/jymac/Documents/GitHub/ABPlayerKit/.claude/worktrees/agent-a2322795a1d04f844`, 브랜치 `round6/docfix`. 입력: `BRIEF-round6-docfix.md`. `Sources/**/*.swift`의 로직은 한 줄도 바꾸지 않았다 — 손댄 세 `.swift` 파일(`ABCacheStore.swift`, `ABControlsSlot.swift`, `ABPlayerControls.swift`)은 전부 주석/doc-comment만 바뀐 diff다(§6-5 원본 출력으로 하단에서 재확인).

베이스: `origin/main` = `8793bb6`(H-2w). 브랜치 생성 시점에 이미 `origin/main`과 동일했으므로 `git fetch && git rebase origin/main`은 no-op("Current branch round6/docfix is up to date.")이었다.

---

## 1. [차단] Now Playing 리모트 커맨드 표 — 두 조건 모두 명시

**대상과 커밋**: `README.md`(`f94f105`), `README.ko.md`(`f674ee5`), `RemoteCommands.md`(`e0fc96e`).

세 파일 모두 표를 "In `.default`? / Also requires"(또는 한국어 대응) 두 열로 재구성하고, 표 위에 "두 조건이 모두 필요하다"는 산문과 실제로 동작하는 예제(`commands = .default.union([.nextTrack, .previousTrack, .changePlaybackRate])` + `setTrackNavigationHandlers` + `supportedPlaybackRates`)를 추가했다. `ABRemoteCommandSet.default`가 `.changePlaybackRate`/`.nextTrack`/`.previousTrack`를 제외한다는 사실도 산문에 명시했다.

`RemoteCommands.md`는 추가로 "## Enabling commands beyond the default" 절을 신설해 표 바로 아래에 같은 예제를 배치했다.

**재현 검증**: 이 수정 전 문서를 그대로 따라 `ABNowPlayingConfiguration(skipInterval: 15)`(commands는 `.default`인 채)에 `setTrackNavigationHandlers`만 호출하면, `ABNowPlayingCenter.installCommands(for:)`(`ABNowPlayingCenter.swift:225-230`)가 `commands.contains(.nextTrack)`을 만족하지 못해 핸들러가 설치되지 않는다는 것을 코드로 재확인했다. 수정된 문서는 이 함정을 코드와 함께 명시한다.

## 2. [차단] DocC "SwiftUI Environment" 토픽 섹션 — 실제 원인은 링크 미해석

**대상과 커밋**: `ABPlayerKitControls.md` + `CustomizingControls.md`(`0240f19`).

**근본 원인을 직접 특정했다** — 브리프가 예상한 "익스텐션 심볼이라 DocC가 자동으로 Extended Modules로 보낸다"는 정성적 설명을 넘어, 베이스라인 `docbuild` 로그에서 정확한 원인을 찾았다:

```
CustomizingControls.md:55:3: warning: 'View' doesn't exist at '/ABPlayerKitControls/CustomizingControls'
ABPlayerKitControls.md:51:5: warning: 'View' doesn't exist at '/ABPlayerKitControls'
ABPlayerKitControls.md:53:5: warning: 'EnvironmentValues' doesn't exist at '/ABPlayerKitControls' Replace 'EnvironmentValues' with 'SwiftUI-Environment'
```

이 SDK(Xcode 26.2 / iOS 26.2 시뮬레이터)에서는 `View`/`EnvironmentValues`가 `SwiftUI`가 아니라 `SwiftUICore` 모듈에 속한다. Topics 링크가 `` ``View/playerControlsStyle(_:)`` ``처럼 모듈 프리픽스 없이 쓰여 있어 DocC가 이를 **ABPlayerKitControls 자신의 심볼**로 해석하려다 실패했고(경고는 발생하지만 `DOCC_WARNINGS_AS_ERRORS`가 잡는 범주가 아니라 빌드는 성공), 링크가 실패한 Topics 섹션 전체가 조용히 드롭됐다 — 그 결과 심볼 자체는 (자동 큐레이션으로) "Extended Modules → SwiftUICore" 아래에 살아 있지만 모듈 랜딩 페이지의 커스텀 섹션에서는 사라진 것이다.

**고침**: 링크를 `` ``SwiftUICore/View/playerControlsStyle(_:)`` `` 형태로 모듈 한정. `ABPlayerKitControls.md`의 Topics 링크 4개와 `CustomizingControls.md` 산문의 링크 2개를 모두 고쳤다.

**빌드 산출물로 직접 검증** — §6-3 참고. 고치기 전(베이스라인)에는 `topicSections`에 "SwiftUI Environment"가 없고 "Extended Modules"가 있었다; 고친 뒤에는 "SwiftUI Environment"가 4개 identifier와 함께 나타나고 "Extended Modules"는 사라졌다.

## 3. [차단] README.ko.md 라운드6 내용 이식

**대상과 커밋**: `README.ko.md`(`f674ee5`).

Controls 절(`showsPlayPauseButton`/`showsSeekBar`, 버퍼링 인디케이터, `touchPassthrough`, `doubleTapSeek`+`providesHapticFeedback`, `rateLabelFormat`, `timeLabelSeparator`, 시크 피드백 배지, `ABControlsSlot`)과 Metrics의 QoE Sessions 절(`endSession`/`snapshot`, `rebufferRatio`/`completionRatio`/`sourceURL` 마스킹, 신규 타입 6종, `ABMetricEvent` non-exhaustive, `ABAccessSnapshot` 확장 필드, `ABJSONLinesMetricsSink` 로테이션) 전체를 기존 KO 파일의 문체·구조에 맞춰 새로 작성해 삽입했다. 기계 번역이 아니라 절 순서와 문단 구조를 EN과 1:1로 맞췄다.

**키워드 카운트 재확인**(브리프 §3 표 대비):

| 키워드 | EN | KO (수정 전) | KO (수정 후) |
|---|---:|---:|---:|
| `touchPassthrough` | 2 | 0 | 2 |
| `doubleTapSeek` | 2 | 0 | 2 |
| `showsBufferingIndicator` | 2 | 0 | 2 |
| `ABControlsSlot` | 1 | 0 | 1 |
| `seekFeedback` | 1 | 0 | 1 |
| `rateLabelFormat` | 2 | 0 | 2 |
| `timeLabelSeparator` | 2 | 0 | 2 |
| `endSession` | 2 | 0 | 2 |
| `snapshot` | 3* | 0 | 2 |
| `ABSessionSummary` | 5 | 0 | 5 |

\* EN의 `snapshot` 3건 중 1건은 라운드6과 무관한 오디오 세션 문단(`README.md:261`)에 있고, 그 대응 KO 문장은 원래부터 "스냅샷"(한글)으로 번역되어 있어 영단어 `snapshot`으로는 안 잡힌다 — 라운드6 관련 2건(코드 예제 + 산문)은 정확히 일치한다.

**주의**: 브리프가 "같은 파일을 두 번 만지지 말라"고 지시한 대로, 1번(Now Playing 표)과 4번(deprecated 이니셜라이저) 수정도 이 파일 안에서 함께 처리했다(같은 커밋 `f674ee5`).

## 4. [차단] deprecated 이니셜라이저 예제

**대상과 커밋**: `README.md`(`f94f105`), `README.ko.md`(`f674ee5`).

390~397행 부근(SwiftUI 컴포지션 예제)에 후행 클로저 `{}`를 추가해 `ABVideoPlayerWithControls(player:videoGravity:accessories:)`(비-deprecated)로 가도록 고쳤다. 전체 README에서 같은 형태(`player:`를 받는 `ABPlayerControls`/`ABVideoPlayerWithControls` 호출)를 모두 검색해 다른 인스턴스가 없음을 확인했다(§6-2 근거 참고) — 145행의 형제 예제는 이미 `{}`를 갖고 있었다.

**컴파일로 증명** — §6-2 참고.

## 5. 비차단 정확성 수정

### 5-1. 시간 레이블 위치 — **코드로 직접 확인**: "below"가 맞다

`Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift:342-343`를 읽었다:

```swift
rootStack.addArrangedSubview(seekBar)
rootStack.addArrangedSubview(bottomStack)   // elapsedLabel이 여기 포함됨
```

`rootStack`은 `.vertical` 축(`line 305`)이고 `seekBar`가 `bottomStack`(시간 레이블 포함)보다 먼저 추가되므로, 시간 레이블은 seek bar **아래**에 온다. `CustomizingControls.md:18`("Directly below the seek bar's visible track")이 맞고, README.md/README.ko.md/`ABPlayerKitControls.md`의 "above"가 틀렸다 — **게이트 판정과 내가 코드에서 직접 읽은 결과가 일치한다.** 세 곳 모두 "below"로 고쳤다(`f94f105`, `f674ee5`, `0240f19`).

### 5-2. `skipInterval` 기본값 불일치 — **코드로 직접 확인**

- `Sources/ABPlayerKitControls/Model/ABPlayerControlsConfiguration.swift:80`: `public var skipInterval: TimeInterval = 10`
- `Sources/ABPlayerKitNowPlaying/ABNowPlayingConfiguration.swift:14`: `skipInterval: TimeInterval = 15`

두 기본값이 실제로 다르고(10 vs 15), 코드에 공유/동기화 메커니즘은 없다 — 완전히 독립된 두 설정이다. `CustomizingControls.md`(`0240f19`)와 `RemoteCommands.md`(`e0fc96e`)에 각각 한 줄씩, 서로를 상호 참조하는 형태로 명시했다.

### 5-3. `ABControlsSlot` non-exhaustive 주의

기존 관례(`ABPlayerEvent`/`ABBackgroundPolicy`/`ABMetricEvent`)와 같은 문구로 doc-comment를 추가했다(`00c7a27`). 다만 이 타입은 `CaseIterable`이라는 점에서 관례와 완전히 같지는 않다 — `allCases`는 향후 케이스 추가에도 소스 호환(케이스가 자동으로 추가됨)이지만, 소비자의 exhaustive `switch`는 여전히 깨질 수 있다는 점을 doc-comment에 한 문장 덧붙여 구분했다. **판단이 갈릴 수 있는 지점**: `CaseIterable`과 "non-exhaustive" 관례가 정확히 같은 의미는 아니므로, 이 조합이 리포 관례상 적절한지는 게이트의 재확인을 요청한다.

### 5-4. `@unchecked Sendable` "banned" 표현 정밀화

`ABCacheStore.swift:258` 및 `ABPlayerControls.swift:202`의 "banned in this codebase" 문구를, "이 특정 캡처의 액터 격리 진단을 침묵시키는 용도로는 쓰지 않는다"는 의미로 좁히고 "그 외 락으로 보호되는 29건은 다른, 증명 가능한 패턴"이라는 문장을 추가했다(`b5531bf`). 주석만 변경, 로직 변경 없음.

**판단이 갈릴 수 있는 지점**: 두 파일 모두 §5-4 대상으로 명시적으로 지목됐지만, 이는 Swift 파일 2개를 건드리는 것이라 브리프의 "§5의 주석 1건만 예외"라는 문구와 "1건"의 해석이 문자 그대로 파일 1개인지, 항목 1건(§5-4)인지 모호했다. §5-4 자체가 "두 지점"이라고 명시했으므로 항목 단위로 해석해 두 파일 모두 고쳤다. 5-3(`ABControlsSlot.swift`)도 별도 Swift 파일에 doc-comment를 추가했는데, 이는 §5-3이 명시적으로 "판단하고 추가하라"고 지시한 항목이라 별개의 허용된 편집으로 간주했다 — 결과적으로 Swift 파일 3개가 바뀌었지만 전부 주석/doc-comment이며 로직은 0줄 변경이다(§6-5로 재확인).

---

## 6. 검증 원본 출력

### 6-1. 전체 스킴 3회 연속 (동일 부팅된 시뮬레이터 재사용, `-only-testing` 미사용)

```
$ xcodebuild -scheme ABPlayerKit-Package -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' test
```

**Run 1** (EXIT=0):
```
✔ Test run with 72 tests in 8 suites passed after 0.101 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.842 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.052 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.016 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.297 seconds.
** TEST SUCCEEDED **
```
합계: 72+322+49+31+269 = **743**.

**Run 2** (EXIT=0):
```
✔ Test run with 72 tests in 8 suites passed after 0.078 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.505 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.055 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.016 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.268 seconds.
** TEST SUCCEEDED **
```

**Run 3** (EXIT=0):
```
✔ Test run with 72 tests in 8 suites passed after 0.081 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.502 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.057 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.032 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.286 seconds.
** TEST SUCCEEDED **
```

세 번 모두 swift-testing 집계 줄(`Test run with N tests`) 기준 743건, exit code 0. (`Executed 0 tests, with 0 failures` 줄은 XCTest 브리지의 항상-0 표시이며 무시했다.)

### 6-2. README 예제 실제 컴파일 (4번 수정의 증명)

이 worktree(`/Users/jymac/Documents/GitHub/ABPlayerKit/.claude/worktrees/agent-a2322795a1d04f844`, 브랜치 `round6/docfix`)를 `path:` 의존성으로 링크하는 스크래치 소비자 패키지를 새로 만들었다(`/private/tmp/.../scratchpad/ReadmeCheck2`) — 게이트의 원래 리뷰 worktree(`agent-a350035f20903225c`)를 참조하던 기존 스크래치 패키지는 존재했지만 그 worktree를 가리켰으므로, 내 worktree를 가리키는 새 패키지를 만들어 README.md의 16개 예제(전체) 전사본으로 검증했다.

```
$ xcodebuild build -scheme ReadmeCheck2 -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' -derivedDataPath /tmp/dd-readmecheck2-final
EXIT=0
```

경고 검색 결과 (수정된 형태 — 후행 클로저 있음):
```
$ grep -n "warning:" ...log | grep ReadmeExamples
.../ReadmeExamples.swift:191:31: warning: 'mediaSelectionGroup(forMediaCharacteristic:)' was deprecated in iOS 16.0: Use loadMediaSelectionGroup(for:) instead
```
(이 경고는 README의 "Subtitles and Audio Tracks" 예제가 그대로 쓰는 Apple `AVFoundation` API 자체의 사전 존재 deprecation이고, 우리 라이브러리의 `ABVideoPlayerWithControls`와 무관하다 — 라운드6 이전부터 있던 것이며 브리프 범위 밖이다.) **`Use the @ViewBuilder` 문구(우리 라이브러리의 deprecated 이니셜라이저 경고)는 로그 전체에 0건.**

**음성 대조군(negative control)**: 같은 예제를 수정 전 형태(후행 클로저 없이)로 되돌려 같은 빌드를 재실행하면:
```
.../ReadmeExamples.swift:217:9: warning: 'init(player:videoGravity:style:configuration:accessoryViews:)' is deprecated: Use the @ViewBuilder `accessories:` initializer instead. Scheduled for removal in 1.0.0.
```
이 경고가 정확히 그 호출 지점(수정 전 217행)에서 재현됨을 확인한 뒤, 수정된 형태로 복원하고 다시 빌드해 경고가 사라짐을 재확인했다(위 최종 로그). 이는 이 컴파일 검증 방법론 자체가 그 결함을 실제로 잡아낸다는 것의 증거다.

### 6-3. DocC 아카이브 — SwiftUI Environment 토픽 섹션 (2번 수정의 증명, 핵심)

**베이스라인(수정 전, 별도 클린 derivedData)**:
```
$ xcodebuild docbuild -scheme ABPlayerKit-Package -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' -derivedDataPath /tmp/dd-docfix-baseline
EXIT=0
$ python3 -c "... topicSections ..."
- UIKit | identifiers: 1
- SwiftUI | identifiers: 2
- Appearance | identifiers: 6
- Behavior and Events | identifiers: 5
- Extended Modules | identifiers: 1
```
("SwiftUI Environment" 없음 — 브리프가 보고한 정확한 증상을 그대로 재현했다.)

**수정 후, 리베이스된 브랜치에서 브리프 §6-3의 정확한 명령으로 재실행**:
```
$ rm -rf /tmp/dd-docfix
$ xcodebuild docbuild -scheme ABPlayerKit-Package \
  -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' \
  -derivedDataPath /tmp/dd-docfix
EXIT=0
** BUILD DOCUMENTATION SUCCEEDED **

$ ARCH=$(find /tmp/dd-docfix -name 'ABPlayerKitControls.doccarchive' | head -1)
$ python3 -c "
import json
d=json.load(open('$ARCH/data/documentation/abplayerkitcontrols.json'))
for s in d.get('topicSections',[]):
    print('-', s.get('title'), '| identifiers:', len(s.get('identifiers',[])))
"
- UIKit | identifiers: 1
- SwiftUI | identifiers: 2
- SwiftUI Environment | identifiers: 4
- Appearance | identifiers: 6
- Behavior and Events | identifiers: 5
```

"SwiftUI Environment"가 4개 identifier로 나타나고 "Extended Modules"는 사라졌다. identifier 4개를 개별 확인:
```
doc://.../ABPlayerKitControls/SwiftUICore/View/playerControlsStyle(_:)
doc://.../ABPlayerKitControls/SwiftUICore/View/playerControlsConfiguration(_:)
doc://.../ABPlayerKitControls/SwiftUICore/EnvironmentValues/playerControlsStyle
doc://.../ABPlayerKitControls/SwiftUICore/EnvironmentValues/playerControlsConfiguration
```
4개 모디파이어/환경값 전부 정확히 커리이션됐다. "경고 없음"이 아니라 **빌드된 아카이브의 JSON을 직접 파싱**해 증명했다.

### 6-4. 위생 스캔

```
$ grep -rnE '(DESIGN|PLANNING|REVIEW|ROADMAP|HANDOFF)[^ ]*\.md|round ?[0-9]|Round ?[0-9]|Phase [0-9]|§[0-9]' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
exit=1
$ grep -rnE '(^|[^A-Za-z0-9])(MJ-[0-9]+|mn-[0-9]+|[NMC][0-9]+|WP[0-9]+(\.[0-9]+)?|Q[0-9]+(-[A-Z])?)([^A-Za-z0-9]|$)' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
exit=1
```
둘 다 0줄 + `exit=1`. (루트 `README.md`의 `[Q1 설계 결정]` 링크는 `Sources/` 밖이라 이 스캔 범위에 들지 않는다 — 기존부터 있던 것이고 브리프 범위 밖이다.)

### 6-5. 코드 무변경 증명

```
$ git diff origin/main --name-only -- 'Sources/**/*.swift'
Sources/ABPlayerKitCache/ABCacheStore.swift
Sources/ABPlayerKitControls/Model/ABControlsSlot.swift
Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift
```

세 파일 모두 diff 전체가 주석/doc-comment 텍스트 변경이며, 코드 라인(선언·로직·시그니처)은 0줄 변경이다:

```diff
--- a/Sources/ABPlayerKitCache/ABCacheStore.swift
+++ b/Sources/ABPlayerKitCache/ABCacheStore.swift
@@ -255,10 +255,12 @@ actor ABCacheStore {
         /// closure, which — being `@Sendable` — can't capture this
         /// non-`Sendable` class instance itself without either an
         /// actor-isolation data-race diagnostic or `@unchecked Sendable`
-        /// (banned in this codebase: it would silence the compiler's
-        /// actor-isolation diagnostic instead of proving the capture safe,
-        /// the same reason `MainActor.assumeIsolated` is banned as a
-        /// compile-error workaround). A plain `UUID` is trivially
+        /// (not used here to silence this specific captured-actor-isolation
+        /// diagnostic — that would suppress the compiler's check instead of
+        /// proving the capture safe, the same reason `MainActor.assumeIsolated`
+        /// is avoided as a compile-error workaround; this codebase does use
+        /// `@unchecked Sendable` elsewhere for lock-protected types, a
+        /// different, provably-safe pattern). A plain `UUID` is trivially
         /// `Sendable` and serves the identity comparison just as well.
         let id = UUID()
         var task: Task<RemoteMetadata, Error>!
--- a/Sources/ABPlayerKitControls/Model/ABControlsSlot.swift
+++ b/Sources/ABPlayerKitControls/Model/ABControlsSlot.swift
@@ -1,5 +1,11 @@
 /// A position within the controls overlay where consumer-provided accessory
 /// views can be placed — see ``ABPlayerControlsView/accessoryViews(in:)``.
+///
+/// Treat this enum as non-exhaustive, the same convention documented on
+/// `ABPlayerEvent`: minor releases may add cases, so switches outside this
+/// package should include a `default` branch. `CaseIterable`'s `allCases`
+/// stays source-compatible either way — a future case is simply appended to
+/// it — but an exhaustive `switch` is not.
 public enum ABControlsSlot: Sendable, Hashable, CaseIterable {
     /// The overlay's top trailing corner.
     case topTrailing
--- a/Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift
+++ b/Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift
@@ -199,11 +199,11 @@ public struct ABPlayerControls: UIViewRepresentable {
             // declares `6.0` — bumping the floor is a
             // bigger, separate decision than this one cleanup, so this hops
             // to the MainActor asynchronously instead. `MainActor.assumeIsolated`
-            // is not an option either — banned in this codebase for the same
-            // reason as `@unchecked Sendable`: `deinit` genuinely isn't
-            // statically known to already be on the MainActor here, so
-            // *assuming* it would be exactly the kind of unchecked escape
-            // hatch that ban exists to prevent.
+            // is not an option either — avoided here for the same reason
+            // `@unchecked Sendable` isn't used to silence a captured-actor-isolation
+            // diagnostic: `deinit` genuinely isn't statically known to already
+            // be on the MainActor here, so *assuming* it would be exactly the
+            // kind of unchecked escape hatch that convention exists to prevent.
             // The async detach still runs promptly (the next MainActor
             // turn) and is safe to run after this instance is already
             // gone — it only touches `accessoryBox`, captured by value.
```

---

## 7. 판단이 갈린 지점 요약

1. **§5-1 시간 레이블 위치**: 코드(`ABPlayerControlsView.swift:342-343`, `rootStack`이 `.vertical`이고 `seekBar`가 `bottomStack`보다 먼저 추가됨)로 직접 확인한 결과 게이트 판정("below"가 맞다)과 일치했다. README.md/README.ko.md의 "above"뿐 아니라, 브리프가 언급하지 않은 `ABPlayerKitControls.md` 랜딩 페이지에도 같은 오류가 있어 함께 고쳤다.
2. **§5-3 `ABControlsSlot`**: `CaseIterable`이라는 점이 기존 non-exhaustive 관례(`ABPlayerEvent` 등, 전부 비-`CaseIterable`)와 정확히 같지 않다. `allCases`는 소스 호환이 유지되지만 exhaustive `switch`는 아니라는 구분을 doc-comment에 넣었다 — 이 표현이 적절한지 재확인 요청.
3. **§5-4 "주석 1건" 해석**: 브리프의 "§5의 주석 1건만 예외"를 "파일 1개"가 아니라 "§5의 항목(§5-4) 1건"으로 해석해 지시된 두 파일(`ABCacheStore.swift`, `ABPlayerControls.swift`)을 모두 고쳤다. §5-3의 `ABControlsSlot.swift` doc-comment 추가는 별도 항목(§5-3)이 명시적으로 요청한 것이라 별개로 허용된다고 판단했다. 결과적으로 Swift 파일 3개가 바뀌었으나 전부 주석/doc-comment이고 로직 변경은 0줄이다.
4. **§2 원인 규명**: 브리프는 "익스텐션 심볼이라 DocC가 Extended Modules로 보낸다"는 정성적 가설을 제시했지만, 실제로는 **모듈 프리픽스 없는 Topics 링크가 이 SDK에서 `SwiftUICore`로 이전된 `View`/`EnvironmentValues`를 찾지 못해 해석 실패했고, 그 결과 섹션 전체가 드롭된 것**이었다(경고 로그로 직접 확인). 고침 방법은 브리프가 제시한 선택지 중 "링크 표기를 DocC가 해석 가능한 형태로 바꾸기"에 해당하지만, 실제 근본 원인은 더 구체적이었다.
5. **CHANGELOG.md:188** ("above the timeline")도 같은 문구를 담고 있음을 발견했지만, 이는 `[0.2.0]` 릴리스의 과거 이력 기술이라 손대지 않았다(살아있는 문서가 아니라 시점 기록이므로 소급 수정은 범위 밖으로 판단) — 게이트가 원하면 별도로 처리 가능.
