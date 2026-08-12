# RESULT: 라운드6 Wave 3 — H-2w (릴리스 문서 최종화 + 데모 배경 오디오 검증 경로)

담당: Sonnet. worktree `/Users/jymac/Documents/GitHub/ABPlayerKit/.claude/worktrees/agent-af6586c88221dbc34`, 브랜치 `round6/docs`. 입력: `BRIEF-round6-h2w.md`. `Sources/` 아래 라이브러리 코드는 한 줄도 건드리지 않았다(§C.4로 재확인).

---

## 1. A — 문서 최종화: 실제로 무엇이 빠져 있었는가

CHANGELOG `## [Unreleased]`를 기준으로 README/DocC를 전부 대조했다. 결과는 브리프가 예상한 그대로였다: **PiP·배경정책·AirPlay·NowPlaying은 이미 정합했고, Controls·Metrics의 신규 노브가 대부분 빠져 있었다.**

### 1-1. 이미 정합해서 손대지 않은 것

- README `#### Background Policy`, `#### Picture in Picture`, `#### AirPlay` — 표, 전제조건, PiP가 명시 소유 경로(`init(player:...)`)에서만 지원된다는 한계까지 정확했다. 손대지 않음.
- README `### ABPlayerKitNowPlaying — Now Playing and Remote Commands` — 소유권 규칙(`.current`만 자격, last-eligible-wins, 원상복구)과 원격 명령 활성화 표까지 정확했다. 손대지 않음.
- `Sources/ABPlayerKit/ABPlayerKit.docc/BackgroundAndPictureInPicture.md` — PiP × 배경정책 매트릭스, 억제 범위, 배경-진입 레이스까지 이미 CHANGELOG 수준의 디테일이었다. 손대지 않음.
- `Sources/ABPlayerKit/ABPlayerKit.docc/ABPlayerKit.md` — PiP Topics 섹션(`ABPictureInPictureSession`/`ABPictureInPictureFailure`) 이미 존재. 손대지 않음.
- `Sources/ABPlayerKitNowPlaying/ABPlayerKitNowPlaying.docc/*.md` — Topics·소유권 설명 모두 정확. 손대지 않음.
- `Sources/ABPlayerKitMetrics/ABPlayerKitMetrics.docc/ABPlayerKitMetrics.md` — 놀랍게도 이건 이미 QoE 세션 전체(오픈/클로즈 이벤트, rebufferRatio, completionRatio, sourceURL 마스킹, non-exhaustive 규칙)를 다루고 있었고 Topics에 `ABSessionAnchor`/`ABBufferingInterval`/`ABFailureRecord`/`ABSessionSummary`/`ABQoESummary`/`ABLatencyDistribution`까지 이미 나열돼 있었다. 손대지 않음.
- Quick Start 재검증: README의 `ABVideoPlayerWithControls(url:)` 한 줄 예제를 `Sources/ABPlayerKitControls/SwiftUI/ABVideoPlayerWithControls.swift:101-113`의 실제 이니셜라이저(`url:videoGravity:autoplay:playerConfiguration:`)와 대조 — 정확히 일치. 변경 없음.
- 커버리지 배지(91.3%) — 브리프 지시대로 숫자는 건드리지 않았고, 배지/링크 자체를 바꾸지 않았으므로 살아있는 링크임은 기존 그대로다.

### 1-2. 실제로 빠져 있었고, 채운 것

**README `### ABPlayerKitControls`** — 완전히 없던 문단을 추가:
- 리플레이-프롬-스타트(끝에서 play 탭 시 0으로 시크 후 재생)
- `showsPlayPauseButton`/`showsSeekBar`
- 버퍼링 인디케이터(`showsBufferingIndicator`, `bufferingIndicatorColor`) — 스피너가 재생/일시정지 글리프 위에 뜨고 버튼은 계속 hit-test 가능하다는 설명 포함
- `touchPassthrough`(`ABControlsTouchPassthrough`: `.never`/`.whenControlsHidden`/`.always`)
- `doubleTapSeek`(`ABDoubleTapSeek`: `.disabled`/`.edges(edgeWidthFraction:)`) + `providesHapticFeedback`
- `rateLabelFormat`(`.automatic`/`.custom`), `timeLabelSeparator`
- 시크 피드백 배지(`seekFeedbackTextColor`/`seekFeedbackBackgroundColor`/`seekFeedbackFont`)
- `ABControlsSlot`(`.topTrailing`/`.transportTrailing`/`.bottomTrailing`)와 `accessoryViews(in:)`/`setAccessoryViews(_:in:)`

**README `### ABPlayerKitMetrics`** — QoE 섹션 전체가 없었다(기존 내용은 v1 TTFF 예제뿐). 새로 추가:
- QoE 세션 개요(`endSession(for:)`/`snapshot(for:)`, 세션 오픈/클로즈 이벤트)
- `rebufferRatio`/`completionRatio`/`sourceURL` 마스킹 설명
- 신규 타입 목록(`ABSessionAnchor`/`ABBufferingInterval`/`ABFailureRecord`/`ABSessionSummary`/`ABQoESummary`/`ABLatencyDistribution`) 및 `ABPlaybackStatistics.waited`
- `ABMetricEvent` non-exhaustive 및 4신규 케이스
- 확장된 `ABAccessSnapshot` 필드, `ABClock.wallClockEpoch`
- `ABJSONLinesMetricsSink`의 `flush()` public화, 로테이션(`maxFileSizeBytes`/`maxRotatedFiles`), `writeFailureCount`/`lastWriteErrorDescription`

**`Sources/ABPlayerKitControls/ABPlayerKitControls.docc/ABPlayerKitControls.md`** — Topics에 `ABControlsSlot`/`ABControlsTouchPassthrough`/`ABDoubleTapSeek` 누락돼 있어 추가. Overview에 버퍼링/시크배지/슬롯 한 줄 요약 추가.

**`Sources/ABPlayerKitControls/ABPlayerKitControls.docc/CustomizingControls.md`** — 새 섹션 6개 추가: "Show Buffering and Seek Feedback", "Hide Individual Controls", "Configure Touch Passthrough and Double-Tap Seek", "Format the Rate Label and Time Separator", "Place Accessory Views at Additional Slots" (+ 리플레이 한 줄).

### 1-3. 확인만 하고 편집하지 않기로 판단한 것 (마이그레이션 노트 커버리지)

브리프가 지목한 4개 항목 중 CHANGELOG `### Migration notes`에 **명시적으로** 있는 것은 2개뿐이다:
- `ABMetricEvent` 4케이스 추가 — 있음.
- Style `Sendable`화에 따른 `@MainActor` 제거 — 있음.

나머지 2개는 `### Changed` 절에는 있지만 `### Migration notes`에 별도 항목이 없다:
- `style:`/`configuration:`의 `Optional`화 — `### Changed`에서 "Source-compatible: every existing call site ... keeps compiling"이라고 명시.
- `ABVideoPlayer.Coordinator` 타입 변경 — `### Changed`에서 "Only affects code that references `ABVideoPlayer.Coordinator` by name directly, which no consumer in this repository does"라고 명시.

**판단**: 이 둘은 CHANGELOG 저자가 "Migration notes"를 "실제로 뭔가 해야 하는 변경"으로 좁게 스코프하고, 완전히 소스 호환인 두 항목은 `### Changed`에 호환성 문구를 인라인으로 붙이는 것으로 대신한 것으로 보인다 — 실수라기보다 의도된 편집 판단일 가능성이 높다. 브리프가 "CHANGELOG는 이미 완비돼 있으니 기준으로 쓰라"고 명시했고, 이 작업 범위가 README/DocC/(필요 시)CHANGELOG인데 CHANGELOG 자체의 구조적 판단을 뒤집는 것은 범위 밖이라 판단해 **CHANGELOG는 건드리지 않았다.** 게이트가 이 판단에 동의하지 않으면 두 항목을 `### Migration notes`로 옮기는 건 CHANGELOG 한 파일의 사소한 편집이라 후속 라운드에서 쉽게 되돌릴 수 있다.

### 1-4. 범위 밖: README.ko.md

브리프 A-1/A-2 어디에도 `README.ko.md` 동기화가 명시되지 않아 손대지 않았다. 영어 README만 갱신했으므로 두 언어가 지금 어긋나 있다 — 필요하면 별도 트랙으로 처리해야 한다.

---

## 2. B — 데모 배경 오디오 검증 경로

### 2-1. `UIBackgroundModes` 선언 — 브리프 원안이 이 툴체인에서 작동하지 않음을 발견하고 수정

브리프 지시대로 처음에는 `project.pbxproj`의 Debug/Release 양쪽에 `INFOPLIST_KEY_UIBackgroundModes = audio;`만 추가했다. **§C.3 검증에서 이 방식이 이 Xcode(26.2, SwiftBuild/XCBuild 둘 다)에서 조용히 무시된다는 것을 발견했다:**

- 빌드 후 `plutil -extract UIBackgroundModes ... Info.plist`가 "No value at that key path"로 실패.
- 근거: `GENERATE_INFOPLIST_FILE=YES`가 합성하는 `INFOPLIST_KEY_*` 키는 **큐레이션된 고정 목록**뿐이다. 두 빌드 시스템(`SwiftBuild.framework`/`XCBuild.framework`)의 `CoreBuildSystem.xcspec`을 직접 grep한 결과 `INFOPLIST_KEY_UIBackgroundModes`는 그 목록에 **없다.** Apple 자신의 Xcode 프로젝트 템플릿(`iOS App Base.xctemplate/TemplateInfo.plist`)도 `UIBackgroundModes`만은 `INFOPLIST_KEY_`가 아니라 실제 `Info.plist` 파일에 직접 XML로 써 넣는 방식을 쓴다 — 같은 한계를 Apple도 우회하고 있다는 독립적 증거.

**수정**: `Examples/ABPlayerKitDemo/ABPlayerKitDemo/Info.plist`를 새로 만들어 `UIBackgroundModes = [audio]`만 담고, Debug·Release 양쪽에 `INFOPLIST_FILE = ABPlayerKitDemo/Info.plist`를 `GENERATE_INFOPLIST_FILE = YES`와 **나란히** 설정했다. 이 조합은 파일의 키와 합성된 키를 병합한다 — 실제로 빌드해 `CFBundleDisplayName`/`UIApplicationSceneManifest`/`UILaunchScreen`이 전부 그대로 합성되면서 `UIBackgroundModes`도 함께 들어가는 것을 확인했다(§3.3). 쓸모없어진 `INFOPLIST_KEY_UIBackgroundModes = audio;` 줄은 양쪽에서 제거했다. `Sources/`는 건드리지 않았다 — 전부 `Examples/` 범위 안.

### 2-2. `PlaybackScreen`의 배경 정책 선택 컨트롤

`DemoModel.swift`에 `DemoTuningPreset`과 나란히 `DemoBackgroundPolicy`(`.pause`/`.continueAudioOnly`, `CaseIterable`/`Identifiable`)를 추가하고, `setLooping`/`setTuning`과 동일한 "`player.configuration` 읽기 → 로컬 복사본 수정 → 다시 쓰기" 패턴으로 `setBackgroundPolicy(_:)`를 추가했다.

**`audioSessionPolicy` 처리** (브리프가 특히 지목한 부분): 데모는 어디에서도 `audioSessionPolicy`를 설정한 적이 없어 기본값 `.unmanaged`로 남아 있었다(`grep -rn audioSessionPolicy Examples/`가 이번 작업 전 0건이었음을 확인). `.continueAudioOnly`는 `audioSessionPolicy != .unmanaged`가 아니면 조용히 `.pause`처럼 동작하므로, `setBackgroundPolicy(.continueAudioOnly)`를 선택하면 **`audioSessionPolicy`가 여전히 `.unmanaged`일 때만** `.playback(mixWithOthers: false)`로 함께 전환하도록 했다:

```swift
func setBackgroundPolicy(_ preset: DemoBackgroundPolicy) {
    guard preset != selectedBackgroundPolicy else { return }
    selectedBackgroundPolicy = preset
    var configuration = player.configuration
    configuration.backgroundPolicy = preset.policy
    if preset == .continueAudioOnly, configuration.audioSessionPolicy == .unmanaged {
        configuration.audioSessionPolicy = .playback(mixWithOthers: false)
    }
    player.configuration = configuration
}
```

`.pause`로 되돌려도 `audioSessionPolicy`는 그대로 둔다(되돌릴 근거——사용자가 다른 이유로 managed로 바꿨을 수도 있음——가 없어 건드리지 않는 쪽을 택했다). `ABBackgroundPolicy`는 non-exhaustive이므로, `player.configuration.backgroundPolicy`를 픽커 선택지로 되읽는 `DemoBackgroundPolicy.init(_ policy: ABBackgroundPolicy)`에 `default: self = .pause`가 있는 `switch`를 넣었다(`DemoModel.init`에서 `player.configuration.backgroundPolicy`로부터 초기 선택값을 읽어오는 데 실제로 사용한다 — 죽은 코드 아님).

`PlaybackScreen.swift`의 기존 `GroupBox("Live configuration")` 안, 튜닝 피커 아래에 `Picker("Background policy", selection: backgroundPolicyBinding)`와 조건을 설명하는 한 줄(배경 모드 선언 + 관리형 오디오 세션이 함께 필요하다는 취지, 실기기에서 백그라운드로 보내 확인하라는 안내)을 추가했다. `backgroundPolicyBinding`은 기존 `tuningBinding`과 동일한 get/set 패턴.

### 2-3. 검증 범위의 한계 (정직하게 남김)

배경 오디오 실동작 자체는 시뮬레이터에서 확인할 수 없다. 확인한 것은: (a) 빌드된 앱 번들의 `Info.plist`에 `UIBackgroundModes = [audio]`가 실제로 들어간다(§3.3), (b) 픽커가 `player.configuration.backgroundPolicy`/`audioSessionPolicy`에 실제로 반영된다(코드 리뷰 수준 — Debug/Release 양쪽 빌드 성공으로 컴파일 정합성은 확인했지만 런타임 UI 조작은 자동화하지 않았다). 실기기에서 앱을 백그라운드로 보내 오디오가 계속 재생되는지는 사용자가 확인해야 한다.

---

## 3. §C 검증 — 원본 출력

최종 커밋: `d4c8cb504c6f6e3ad0daa9284b447b9708a90ca8` (브랜치 `round6/docs`, `git fetch origin && git rebase origin/main` 완료 — `origin/main`이 시작점과 동일해 리베이스는 fast-forward 없이 그대로 "Current branch round6/docs is up to date."). 시뮬레이터 `60DA735B-87EC-4159-9BE3-EF981A127FAF`(iPhone 17 Pro Max, iOS 26.2, Booted) 재사용, 새로 부팅하지 않음.

### 3.1 전체 스킴 3회 연속 (최종 커밋에서 재실행)

```
$ xcodebuild -scheme ABPlayerKit-Package -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' test
```

**Run 1** — `EXIT_CODE=0`
```
✔ Test run with 72 tests in 8 suites passed after 0.095 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.855 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.077 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.019 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.312 seconds.
** TEST SUCCEEDED **
```

**Run 2** — `EXIT_CODE=0`
```
✔ Test run with 72 tests in 8 suites passed after 0.081 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.529 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.047 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.018 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.286 seconds.
** TEST SUCCEEDED **
```

**Run 3** — `EXIT_CODE=0`
```
✔ Test run with 72 tests in 8 suites passed after 0.076 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.543 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.041 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.018 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.310 seconds.
** TEST SUCCEEDED **
```

합계 매 회 72+322+49+31+269 = **743** (Cache 72 / Controls 322 / Metrics 49 / NowPlaying 31 / Core 269) — 브리프 기대치와 정확히 일치. (참고: rebase 직후, 코드 변경 전에도 동일 스킴을 3회 돌려 동일한 결과를 얻었다 — 이 표는 최종 커밋에서의 재확인 실행이다.)

### 3.2 데모 빌드 (CI와 동일한 커맨드라인)

CI(`​.github/workflows/ci.yml:117-119`)는 `-project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj -scheme ABPlayerKitDemo`로 빌드한다. 저장소 루트에서 `-project` 없이 `-scheme ABPlayerKitDemo`만 주면 루트의 SwiftPM 패키지가 만드는 암묵적 워크스페이스가 잡혀 "does not contain a scheme named ABPlayerKitDemo" 오류가 난다 — 이건 이번 변경과 무관한, 브리프 §C.2 커맨드 문면 자체의 누락(`-project` 미기재)이며 CI 설정 파일로 교차 확인했다.

```
$ xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj \
    -scheme ABPlayerKitDemo \
    -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' \
    -derivedDataPath /tmp/round6-docs-verify/DerivedDataCI \
    build
EXIT_CODE=0
...
** BUILD SUCCEEDED **
```

Debug/Release 양쪽 구성 모두 개별적으로도 재빌드해 확인했다(둘 다 `BUILD SUCCEEDED`, 둘 다 `Info.plist`에 `UIBackgroundModes` 포함 — Release 쪽 원본 출력은 §3.3 아래 참고용으로 남긴다).

### 3.3 `UIBackgroundModes`가 실제 산출물에 들어갔는지

```
$ plutil -extract UIBackgroundModes xml1 -o - \
    "/tmp/round6-docs-verify/DerivedDataCI/Build/Products/Debug-iphonesimulator/ABPlayerKitDemo.app/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
	<string>audio</string>
</array>
</plist>
EXIT_CODE=0
```

Release 구성(별도 `-derivedDataPath`)에서도 동일:
```
$ plutil -extract UIBackgroundModes xml1 -o - \
    ".../DerivedDataRelease/Build/Products/Release-iphonesimulator/ABPlayerKitDemo.app/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
	<string>audio</string>
</array>
</plist>
```

(최초 시도 — `INFOPLIST_KEY_UIBackgroundModes = audio;`만 있었을 때 — 는 `No value at that key path or invalid key path: UIBackgroundModes` / `EXIT_CODE=1`이었다. §2.1에 원인과 수정을 기록했다. 최종 커밋에서는 위처럼 성공한다.)

### 3.4 `Sources/` 위생 재스캔 (최종 커밋에서)

```
$ grep -rnE '(DESIGN|PLANNING|REVIEW|ROADMAP|HANDOFF)[^ ]*\.md|round ?[0-9]|Round ?[0-9]|Phase [0-9]|§[0-9]' --include='*.swift' --include='*.md' Sources/
(no output)
exit=1

$ grep -rnE '(^|[^A-Za-z0-9])(MJ-[0-9]+|mn-[0-9]+|[NMC][0-9]+|WP[0-9]+(\.[0-9]+)?|Q[0-9]+(-[A-Z])?)([^A-Za-z0-9]|$)' --include='*.swift' --include='*.md' Sources/
(no output)
exit=1
```

둘 다 0줄 + `exit=1` — H-1w가 만든 상태를 되살리지 않았다. DocC 편집(`Sources/ABPlayerKitControls/ABPlayerKitControls.docc/*.md`)이 이 스캔 범위 안이라는 점을 감안해 편집 직후에도 한 번, 최종 커밋에서 다시 한 번 확인했다.

---

## 4. 소스와의 불일치 — 발견한 것 없음

문서화 전 모든 신규 API의 시그니처를 소스에서 직접 확인했다(`ABPlayerControlsConfiguration.swift`, `ABControlsSlot.swift`, `ABPlayerControlsView.swift`, `ABPlayerControlsStyle*.swift`, `ABMetricsRecorder.swift`, `ABMetricEvent.swift`, `ABPlaybackStatistics.swift`, `ABLatencyDistribution.swift`, `ABMetricsSink.swift`, `ABClock.swift`, `ABBackgroundPolicy.swift`, `ABAudioSessionPolicy.swift`, `ABPlayerConfiguration.swift`). CHANGELOG 서술과 실제 소스 사이에 불일치는 없었다. §1-3에 적은 마이그레이션 노트 커버리지 건은 "불일치"가 아니라 CHANGELOG의 편집 스코프 판단이라 별도로 분리해 적었다.

Xcode 툴체인 자체에 대한 발견(`INFOPLIST_KEY_UIBackgroundModes`가 이 버전에서 합성되지 않는다는 것)은 라이브러리 코드나 CHANGELOG의 문제가 아니라 브리프 B-2(a)의 구체적 구현 지시가 이 환경에서 작동하지 않았던 것이라, §2.1에 적은 대로 `Examples/` 범위 안에서 직접 고쳤다(라이브러리 코드 변경 금지 규칙과 무관).

---

## 5. 브리프를 벗어난 변경

- `Examples/ABPlayerKitDemo/ABPlayerKitDemo/Info.plist`(신규 파일)와 `project.pbxproj`의 `INFOPLIST_FILE` 설정 — 브리프 B-2(a)가 지시한 `INFOPLIST_KEY_UIBackgroundModes` 한 줄 추가만으로는 목표(§C.3 검증)를 달성할 수 없어서 한 것이므로, 정신적으로는 브리프 범위 안이지만 브리프가 적은 정확한 구현 방법과는 다르다. §2.1·§3.3에 근거를 남겼다.
- 그 외에는 브리프에 적힌 범위(README/DocC/Examples) 밖의 파일을 건드리지 않았다.

---

## 6. 판단이 어려웠던 지점

1. **마이그레이션 노트 2건을 CHANGELOG로 옮길지** — §1-3에 적은 대로, 옮기지 않기로 했다. 저장소 상태를 CHANGELOG 저자의 의도적 판단으로 해석했지만 확신은 아니다.
2. **`INFOPLIST_KEY_UIBackgroundModes`가 작동하지 않는다는 발견을 어떻게 처리할지** — "라이브러리 코드는 고치지 말고 보고하라"는 브리프 문구가 이 경우에는 적용되지 않는다고 판단했다(이건 `Examples/`의 빌드 설정이지 `Sources/`가 아니다). 대신 실제로 작동하는 방식으로 고치고 원인을 상세히 남겼다 — 브리프의 검증 게이트(§C.3)가 "필수"였고 우회할 방법이 없었기 때문이다.
3. **`.pause`로 되돌릴 때 `audioSessionPolicy`를 원상복구할지** — 하지 않기로 했다(§2.2 근거). 검증자가 "Continue audio only를 껐는데 오디오 세션이 여전히 managed"인 것을 이상하게 여길 수도 있어 이 판단이 맞는지는 확신이 덜하다.
4. **README.ko.md를 갱신할지** — 브리프 범위 밖으로 판단하고 건드리지 않았다(§1-4). 두 언어 README가 지금 어긋나 있다는 점은 명시해 둔다.
