# REVIEW: 라운드6 최종 게이트 (v0.4.0 태깅 전)

- **일시**: 2026-08-13
- **대상 커밋**: `8793bb6` (Round 6 H-2w: finalize release docs and add the demo's background-audio path, #14)
- **기준선**: `995bb6d` (라운드6 착수 시점)
- **판정 기준**: `ROADMAP-round6.md` §7 완료 정의
- **작업 위치**: 격리 worktree `/Users/jymac/Documents/GitHub/ABPlayerKit/.claude/worktrees/agent-a350035f20903225c`, 브랜치 `worktree-agent-a350035f20903225c`
- **코드 수정 없음.** 이 문서 1개가 유일한 쓰기 작업이다.

이 게이트는 라운드6을 오케스트레이션하지 않았다. 각 트랙 게이트와 `RESULT-*`/`REVIEW-*` 문서는 **참고 입력이지 근거가 아니며**, 아래 §1의 모든 검증은 직접 실행했다.

---

## 1. 검증 방법과 원본 출력

### 1-1. 전체 스킴 3회 연속 (공유 시뮬레이터 `60DA735B-87EC-4159-9BE3-EF981A127FAF` 재사용, 신규 부팅 없음)

```
xcodebuild -scheme ABPlayerKit-Package \
  -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' test
```

원본 출력:

```
===== RUN 1 START Thu Aug 13 07:44:01 KST 2026 =====
RUN 1 xcodebuild exit=0
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
✔ Test run with 269 tests in 41 suites passed after 0.305 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.022 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.866 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.056 seconds.
✔ Test run with 72 tests in 8 suites passed after 0.105 seconds.
** TEST SUCCEEDED **
===== RUN 1 END Thu Aug 13 07:44:25 KST 2026 =====
===== RUN 2 START Thu Aug 13 07:44:25 KST 2026 =====
RUN 2 xcodebuild exit=0
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
✔ Test run with 269 tests in 41 suites passed after 0.278 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.014 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.527 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.048 seconds.
✔ Test run with 72 tests in 8 suites passed after 0.078 seconds.
** TEST SUCCEEDED **
===== RUN 2 END Thu Aug 13 07:44:31 KST 2026 =====
===== RUN 3 START Thu Aug 13 07:44:31 KST 2026 =====
RUN 3 xcodebuild exit=0
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
✔ Test run with 269 tests in 41 suites passed after 0.296 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.017 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.496 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.040 seconds.
✔ Test run with 72 tests in 8 suites passed after 0.078 seconds.
** TEST SUCCEEDED **
===== RUN 3 END Thu Aug 13 07:44:37 KST 2026 =====
```

- 합계 **269 + 31 + 322 + 49 + 72 = 743건**. 기대치와 정확히 일치.
- XCTest의 `Executed 0 tests` 줄은 예상대로 항상 0이며 판정에 쓰지 않았다. 집계는 swift-testing의 `Test run with N tests` 줄로만 했다.
- `-only-testing` 미사용. 3회 모두 전체 스킴.
- 라이브러리 코드 경고 0건 (`warning:` 히트 5건은 전부 `appintentsmetadataprocessor`의 AppIntents 미링크 안내로 소스와 무관).

### 1-2. 위생 스캔 2건

```
$ grep -rnE '(DESIGN|PLANNING|REVIEW|ROADMAP|HANDOFF)[^ ]*\.md|round ?[0-9]|Round ?[0-9]|Phase [0-9]|§[0-9]' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
exit=1

$ grep -rnE '(^|[^A-Za-z0-9])(MJ-[0-9]+|mn-[0-9]+|[NMC][0-9]+|WP[0-9]+(\.[0-9]+)?|Q[0-9]+(-[A-Z])?)([^A-Za-z0-9]|$)' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
exit=1
```

둘 다 출력 0줄 + `exit=1`. H-1w는 실제로 완료됐다.

추가로, **`docs/briefs/` 밖에서 `docs/briefs/`를 참조하는 파일이 0건**임을 확인했다 (`grep -rn 'docs/briefs' ... | grep -v '^./docs/briefs/'` → 히트 없음). H-3w가 `docs/briefs/`를 제거해도 깨지는 링크는 없다. 외부 문서 참조는 전부 `docs/DESIGN-*.md` / `docs/POLICY-api-stability.md`이며 이들은 존치 대상이다.

### 1-3. 데모 빌드 + 배경 모드 산출물 확인

```
$ xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj -scheme ABPlayerKitDemo \
    -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' -derivedDataPath /tmp/dd-final build
...
** BUILD SUCCEEDED **

$ plutil -extract UIBackgroundModes xml1 -o - "/tmp/dd-final/Build/Products/Debug-iphonesimulator/ABPlayerKitDemo.app/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
	<string>audio</string>
</array>
</plist>
exit=0
```

빌드된 `.app` 번들의 실제 `Info.plist`에 `UIBackgroundModes = [audio]`가 들어 있다. HANDOFF §3-3의 이월 항목("데모의 `UIBackgroundModes: audio`")은 **해소됐다**. `.continueAudioOnly`와 PiP의 기기 시연 전제조건 1번이 충족된다.

### 1-4. CI가 돌리는 나머지 잡을 로컬 재현

보고서를 믿지 않기 위해 CI의 다른 세 잡도 직접 돌렸다.

**ThreadSanitizer** (`.github/workflows/ci.yml`의 `thread-sanitizer` 잡과 동일한 인자 + `TEST_RUNNER_ABPLAYERKIT_WAIT_SCALE=6`):

```
tsan xcodebuild exit=0
✔ Test run with 269 tests in 41 suites passed after 0.798 seconds.
✔ Test run with 72 tests in 8 suites passed after 0.085 seconds.
** TEST SUCCEEDED **
```

`WARNING: ThreadSanitizer` / `data race` 히트 0건. `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 하에서 그린.

**데모 warnings-as-errors 빌드**:

```
demo werror exit=0
** BUILD SUCCEEDED **
```

**SwiftLint**:

```
Done linting! Found 0 violations, 0 serious in 181 files.
swiftlint exit=0
```

**DocC (`docbuild`, `DOCC_WARNINGS_AS_ERRORS=YES`)**:

```
docbuild exit=0
** BUILD DOCUMENTATION SUCCEEDED **
```

— 그러나 **DocC 경고 14건이 출력됐는데도 exit=0이다.** 이것이 §4-1 차단 결함 B2의 출발점이다.

### 1-5. README 예제 실제 컴파일 (눈으로 읽지 않았다)

README의 코드 예제를 눈으로 대조하는 대신, **전 예제를 그대로 옮긴 소비자 패키지를 만들어 실제로 컴파일했다.** 스크래치패드에 `ReadmeCheck` 패키지(iOS 17, Swift 6 언어 모드)를 만들고 이 worktree를 로컬 경로 의존성으로 링크한 뒤, README의 Quick Start·코어 단독·커스터마이징·playerConfiguration·직접 소유·UIKit·등급/프리로드·이벤트·오디오 세션·배경 정책 5케이스·PiP·AirPlay·자막 escape hatch·UIKit 컨트롤·SwiftUI 조합 — 총 16개 예제를 파일 하나에 담아 빌드했다.

```
$ xcodebuild -scheme ReadmeCheck -destination 'platform=iOS Simulator,id=60DA735B-...' build
** BUILD SUCCEEDED **
ReadmeExamples.swift:189:31: warning: 'mediaSelectionGroup(forMediaCharacteristic:)' was deprecated in iOS 16.0: Use loadMediaSelectionGroup(for:) instead
ReadmeExamples.swift:213:9: warning: 'init(player:videoGravity:style:configuration:accessoryViews:)' is deprecated: Use the @ViewBuilder `accessories:` initializer instead. Scheduled for removal in 1.0.0.
```

- **에러 0건** — README의 모든 예제는 실제로 컴파일된다. 특히 §7 기준 2의 URL 원라이너(`ABVideoPlayerWithControls(url:)`)는 인자 하나로 컴파일된다.
- 경고 2건이 나왔고, 그중 `:213`이 §4-1의 차단 결함 B4다. `:189`는 비차단(§4-2 N5).

### 1-6. 공개 API 제거 여부 (POLICY-api-stability의 additive-only 검증)

`995bb6d`의 전 `Sources/**.swift`에서 공개 선언을 추출해 HEAD와 차집합을 냈다.

```
=== public declarations present at 995bb6d but ABSENT at HEAD ===
public enum ABControlIcon: Equatable
public enum ABControlsBackgroundStyle: Equatable
public enum ABRateLabelStyle: Equatable
public enum ABTrackCornerRadius: Equatable
public struct ABPlayerControlsStyle: Equatable
public var duration: CMTime?
public var isPlaying: Bool
=== counts: base / head ===
     269
     417
```

7건 전부 **제거가 아니라 선언 문자열 변화**임을 개별 확인했다:
- 앞의 5건은 `: Equatable` → `: Sendable, Equatable` (D-10 해소, 순수 추가 conformance).
- `isPlaying`/`duration`은 `public var { get }` computed → `public private(set) var` stored (B-1 해소). 외부에서 보이는 계약은 read-only로 동일.

**실질적 공개 API 제거 0건.** 공개 선언 수 269 → 417.

---

## 2. ROADMAP §7 기준별 판정

| # | 기준 | 판정 | 근거 |
|---|---|---|---|
| 1 | 감사 ID 해소 (E-7·G-5 이월 허용) | **충족** | §3 표 |
| 2 | URL 원라이너 README 첫 예제 | **충족** | §1-5 컴파일 통과. README.md:88-97이 첫 코드 예제이고 `ABVideoPlayerWithControls(url:)` 한 줄이다 |
| 3 | 테스트 총량 증가 + 전 스위트 그린 + TSan 그린 + 커버리지 배지 | **충족** | `@Test` 406건(995bb6d) → 743건. 3회 연속 그린. TSan 로컬 그린. 배지 README.md:9 + `ci.yml:83-101,192-216` |
| 4-a | 소스에 내부 리뷰 ID 인용 0건 | **충족** | §1-2, 두 스캔 0줄 + exit=1 |
| 4-b | main에 `docs/briefs/` 부재 | **설계상 이 리뷰 이후 단계** | H-3w는 이 게이트 다음이며 오케스트레이터 직접 수행. 결함 아님. 선행 조건(외부 참조 0건)은 §1-2에서 확인 |
| 5 | FINAL-VERDICT: APPROVE | **미충족** | §4-1의 차단 결함 4건 |

기준 1~4는 전부 충족한다. **코드에서 발견된 기능적·정합성 결함은 0건이다.** 판정을 가르는 것은 전적으로 §4-1의 문서 결함이며, 그 이유는 §4-1 말미에 적었다.

---

## 3. 감사 ID 해소 상태

각 항목을 실코드에서 직접 확인했다. "해소"는 코드 근거를 눈으로 확인했다는 뜻이다.

### A. 코어 버그 — 8/8 해소

| ID | 상태 | 근거 |
|---|---|---|
| A-1 | 해소 | `setLooping`이 `actionAtItemEnd`를 전환하고, `ABLoopRestartTests`의 `loopedEndOfItemResumesPlayback`이 **실제 `isPlaying` 복귀**를 대기 단언한다. 감사가 지적한 "setLooping 호출 여부만 검증"이 실제 재생 재개 검증으로 대체됐다 |
| A-2 | 해소 | `ABBackgroundLifecycleEngineTests`: "Foreground resume under a managed audio session policy reactivates before target.play()" |
| A-3 | 해소 | `ABPlayer.swift:33/38` — `lastFailure`(종료성)와 `lastDiagnostic`(비종료성)이 분리됐고 `:301-302`에서 attach 시 둘 다 리셋. `lastError`는 `lastFailure?.kind`의 computed projection으로 하위호환 유지 |
| A-4 | 해소 | `ABFailureLifecycleTests` / `ABDetachOrderingTests` |
| A-5 | 해소 | `ABAVPlaybackTargetReadyWaitTests` + `ReadyWaitState`(`ABAVPlaybackTarget.swift:280`)의 continuation 설치 경합 처리 |
| A-6 | 해소 | `ABBackgroundLifecycleEngineTests`: "A capture at willResignActive survives isPlaying already reading false by didEnterBackground" + "A resign that never reaches didEnterBackground does not leave a stale capture" |
| A-7 | 해소 | `ABSeekUnificationTests` 7건. 특히 "A stale out-of-session scrub seek does not broadcast .seekCompleted after a source replacement"와 "Five rapid out-of-session scrub taps coalesce to fewer than five target seeks" |
| A-8 | 해소 | `ABDetachOrderingTests` |

### B. 코어 관찰성/이벤트 — 8/8 해소

| ID | 상태 | 근거 |
|---|---|---|
| B-1 | 해소 | `ABPlayer.swift:66/81/88` — `isPlaying`/`duration`/`isBuffering`이 `public private(set) var` 저장 프로퍼티 |
| B-2 | 해소 | `isBuffering` + `bufferingChanged` + `ABBufferingEvaluatorTests` |
| B-3 | 해소 | `ABPlayerFailure`(`ABPlayerError.swift:72-81`)가 `kind` + `origin: ABErrorOrigin?`을 캐리 |
| B-4 | 해소 | `ABObservabilityEventsTests`. 신규 이벤트 9종 확인 |
| B-5 | 해소 | `.playbackRejected` 페이로드 보강, `ABRejectedCall` |
| B-6 | 해소 | `ABAssetFactory.swift:21-26` — `AVURLAssetHTTPHeaderFieldsKey`로 실제 적용 |
| B-7 | 해소 | `grep -rn 'UIScreen' Sources/` → 히트 0건 |
| B-8 | 해소 | `ABAVPlaybackTarget.swift:142` `avPlayer?.defaultRate`, `ABPlaybackTuning.swift:21` `audioTimePitchAlgorithm` |

### C. SwiftUI 간편화 — 3/3 해소 (단, C-2·C-3의 **문서 전달**에 결함 — §4-1 B2·B3)

| ID | 상태 | 근거 |
|---|---|---|
| C-1 | 해소 | `ABVideoPlayer.init(url:)`, `ABVideoPlayerWithControls.init(url:)` 및 `source:`/`accessories:` 오버로드. §1-5 컴파일 통과 |
| C-2 | 코드 해소 / 문서 결함 | `EnvironmentValues.playerControlsStyle`·`playerControlsConfiguration` + `View` modifier 존재, `ABPlayerControlsEnvironmentTests`로 고정. 그러나 **모듈 DocC에서 이 API의 큐레이션 섹션이 통째로 누락**(§4-1 B2) |
| C-3 | 코드 해소 / 문서 결함 | README 첫 예제가 URL 원라이너이고 `kind:` 없음. 그러나 한국어 README가 이번 라운드 Controls 기능을 하나도 반영하지 않았다(§4-1 B3) |

### D. Controls UX — 11/11 해소

`D-1`~`D-11` 전부 실코드+테스트 확인. 대표 근거: `ABPlayerControlsBufferingTests`(D-2·D-3), `ABPlayerControlsSeekFeedbackTests`(D-1 잔여), `ABPlayerControlsDoubleTapTests`·`ABDoubleTapSeekZoneTests`(D-4), `ABPlayerControlsReplayTests`(D-5), `ABRateFormatterTests`(D-6), `ABPlayerControlsSlotTests`(D-7), `ABPlayerControlsStyleFacetsTests`(D-8), `ABControlsPresenterTests`(D-9), `ABPlayerControlsStyleSendableTests`(D-10), `controls.liveMarker` en=`LIVE`/ko=`실시간` + `accessibilityHint` 5개소(D-11).

D-11의 로케일 항목은 **번역 실재까지 확인**했다 — 키만 만들고 값이 영어 그대로인 흔한 함정이 아니다.

### E. Cache — E-1~E-6·E-8 해소, E-7 이월(허용)

| ID | 상태 | 근거 |
|---|---|---|
| E-1 | 해소 | `ABCacheRevalidationRegistry`(`ABCacheStore.swift:142`) + `If-Range`/`ETag`/`Last-Modified` + `Content-Range` 오프셋 방어 검증 |
| E-2 | 해소 | `defer` close |
| E-3 | 해소 | `ABMediaCacheTests`의 삭제-중-재생 시나리오 |
| E-4 | 해소 | fill 수명 동안 writer 핸들 유지 |
| E-5 | 해소 | `ABCacheStore.swift:1307-1309` — 제네릭 supertype이면 확장자 우선 |
| E-6 | 해소 | `ABCacheStore.swift:855, 1055` — 200 응답 경로의 상한 처리 |
| E-7 | **이월(허용)** | DocC `ABPlayerKitCache.md`에 LRU 제약이 문서화돼 있음을 확인 |
| E-8 | 해소 | `ABLoadingRequestServicerTests` — `ABLoadingRequesting` 심을 통한 contentInformation/데이터 경로 직접 테스트. 감사가 요구한 "가짜 loading request" 형태로 충족 |

### F. Metrics — 6/6 해소

`ABQoEAggregationTests`(F-1·F-2), `ABSessionAccumulatorTests`(F-1·F-3), `ABPlaybackStatistics.waited`(F-4), `ABAccessLogFolder`(F-5), `ABMetricsSink.swift:80/103` `writeFailureCount`/`public func flush()` + 로테이션(F-6). 데모 Metrics 탭 확장도 확인.

### G. 차별화 — G-1~G-4·G-6 해소, G-5 이월(허용)

| ID | 상태 | 근거 |
|---|---|---|
| G-1 | 해소 | `ABPictureInPictureSession`(248줄) + `ABPlayerView.pictureInPictureSession`. `AVPlayerLayer`는 여전히 비노출 |
| G-2 | 해소 | AirPlay 3노브 + `isExternalPlaybackActive`. `ABExternalPlaybackConfigurationTests` |
| G-3 | 코드 해소 / **문서 결함** | `ABPlayerKitNowPlaying` 타깃 존재, 31 테스트. 그러나 **리모트 커맨드 활성화 조건 문서가 실코드와 다르다**(§4-1 B1) |
| G-4 | 해소 | `ABBackgroundPolicy.swift:27` + `ABContinueAudioOnlyTests` + 데모 `UIBackgroundModes` |
| G-5 | **이월(허용)** | tvOS/visionOS 미착수 |
| G-6 | 해소 | README "Subtitles and Audio Tracks" — escape hatch 경로 + 3개 제약 명시. §1-5에서 컴파일 확인 |

### H. 위생 — H-1은 이 리뷰 다음 단계, H-2~H-6 해소

H-1(briefs 이전)은 설계상 이후 단계. H-2(리뷰 ID 인용) §1-2로 확인. H-3(커버리지 배지·TSan) §1-1·1-4. H-4(SwiftLint) §1-4. H-5(`ABTestSupport` 통합) `Tests/ABTestSupport/ABWaitUntil.swift` 1벌로 확인. H-6(레지스트리 통합) `Sources/ABPlayerKit/Observation/`에 `ABLayerAttachmentObserverRegistry` 부재 확인.

### 미해소 항목

**없다.** 이월 2건(E-7, G-5)은 §7이 명시적으로 허용한다. 릴리스를 차단하는 미해소 감사 ID는 없다.

---

## 4. 리포 전체 관점의 발견

### 4-1. 차단 (Blocking) — 4건, 전부 문서

먼저 분명히 해 둔다: **코드에서 기능적 결함을 하나도 찾지 못했다.** 3회 그린, TSan 그린, lint 그린, 데모 그린, README 전 예제 컴파일 통과, 공개 API 제거 0건, 신규 위험 패턴 없음. 아래 4건은 전부 문서 결함이다.

그럼에도 차단으로 판정하는 이유는 **라운드6의 명시된 제품 목표 4개 중 2번이 "README 사용법 완결"이고**, §7 기준 1이 C-2·C-3·G-3의 해소를 요구하며, 이 4건이 정확히 그 지점에서 소비자를 잘못된 길로 보내기 때문이다. 그리고 4건 모두 문서 전용 수정이라 **회귀 리스크가 0이고, 다음 단계인 H-3w도 문서 전용이라 일정 비용도 0이다.** 이는 HANDOFF §4-5가 정식화한 판단 기준("비차단이라도 일정 비용이 없고 원인이 특정돼 있으면 닫아라")에 그대로 해당한다.

---

#### B1. NowPlaying 리모트 커맨드 활성화 조건이 실코드와 다르다 — 문서대로 따르면 커맨드가 죽는다

**위치**: `README.md:595-596`, `README.ko.md:537-538`, `Sources/ABPlayerKitNowPlaying/ABPlayerKitNowPlaying.docc/RemoteCommands.md:19-21`

세 문서가 모두 이렇게 적는다:

| Command | Default | Activates when |
|---|---|---|
| Change Playback Rate | Off | `ABNowPlayingConfiguration.supportedPlaybackRates` is non-empty |
| Next / Previous Track | Off | A handler is installed via `setTrackNavigationHandlers(next:previous:for:)` |

실코드(`ABNowPlayingCenter.swift:220-230`)는 **조건이 두 개**다:

```swift
install(.changePlaybackRate, requested: commands.contains(.changePlaybackRate),
        enabled: commands.contains(.changePlaybackRate) && hasRates)
install(.nextTrack, requested: commands.contains(.nextTrack) && hasNext,
        enabled: commands.contains(.nextTrack) && hasNext)
install(.previousTrack, requested: commands.contains(.previousTrack) && hasPrevious, ...)
```

그리고 `ABRemoteCommandSet.default`(`ABRemoteCommandSet.swift:25-27`)는 이 세 커맨드를 **전부 제외**한다:

```swift
public static let `default`: ABRemoteCommandSet = [
    .play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePlaybackPosition
]
```

**재현 경로**: 문서를 그대로 따라

```swift
ABNowPlayingCenter.shared.attach(player, metadata: metadata)   // configuration 기본값
ABNowPlayingCenter.shared.setTrackNavigationHandlers(next: { ... }, previous: { ... }, for: player)
```

하면 `commands`가 `.default`이므로 `.nextTrack`이 포함되지 않아 **핸들러가 아예 설치되지 않는다**(`requested: false`). 잠금화면에 버튼이 나타나지 않고, 소비자에게는 어떤 단서도 없다. `supportedPlaybackRates`도 동일하다.

`ABNowPlayingConfiguration.commands`를 함께 설정해야 한다는 사실은 README.md·README.ko.md·`ABPlayerKitNowPlaying.md`·`RemoteCommands.md`의 **산문 어디에도 없다** — Topics 심볼 링크로만 등장한다. 근거를 아는 유일한 곳은 `ABRemoteCommandSet.default`의 소스 주석인데, 소비자가 그것을 먼저 읽을 이유가 없다.

이것은 감사 B-5가 "첫 사용 경험의 '왜 아무 일도 안 일어나지'"라고 지목한 실패 양식 그 자체이며, 하필 이번 라운드가 새로 만든 차별화 타깃(G-3)에서 발생한다.

**수정**: 세 표의 "Activates when" 칸에 `ABNowPlayingConfiguration.commands`에 해당 커맨드를 추가해야 한다는 조건을 병기하고, 산문에 한 문장 추가.

---

#### B2. DocC "SwiftUI Environment" 토픽 섹션이 산출물에서 통째로 사라졌다

**위치**: `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/ABPlayerKitControls.md:47-54`

작성된 원문:

```markdown
### SwiftUI Environment

Set a style or configuration once on an ancestor view to cover every player-controls view in its subtree — an explicit `style:`/`configuration:` initializer argument still overrides it locally.

- ``View/playerControlsStyle(_:)``
- ``View/playerControlsConfiguration(_:)``
- ``EnvironmentValues/playerControlsStyle``
- ``EnvironmentValues/playerControlsConfiguration``
```

네 링크가 전부 해석 실패한다. `docbuild` 원본 출력:

```
ABPlayerKitControls.md:51:5: warning: 'View' doesn't exist at '/ABPlayerKitControls'
ABPlayerKitControls.md:52:5: warning: 'View' doesn't exist at '/ABPlayerKitControls'
ABPlayerKitControls.md:53:5: warning: 'EnvironmentValues' doesn't exist at '/ABPlayerKitControls' Replace 'EnvironmentValues' with 'SwiftUI-Environment'
ABPlayerKitControls.md:54:5: warning: 'EnvironmentValues' doesn't exist at '/ABPlayerKitControls' Replace 'EnvironmentValues' with 'SwiftUI-Environment'
CustomizingControls.md:55:3: warning: 'View' doesn't exist at '/ABPlayerKitControls/CustomizingControls'
CustomizingControls.md:55:40: warning: 'View' doesn't exist at '/ABPlayerKitControls/CustomizingControls'
CustomizingControls.md:95:9: warning: 'ABPlayerKit' doesn't exist at '/ABPlayerKitControls/CustomizingControls'
```

경고로 끝나지 않는다. **빌드된 `.doccarchive`를 직접 열어 확인했다**:

```
$ python3 -c "... json.load(...abplayerkitcontrols.json)['topicSections'] ..."
SECTION: UIKit
SECTION: SwiftUI
SECTION: Appearance
SECTION: Behavior and Events
SECTION: Extended Modules
```

**"SwiftUI Environment" 섹션이 없다.** 네 항목이 모두 해석 실패하자 DocC가 섹션 자체를 버렸고, 설명 산문도 함께 사라졌다:

```
$ grep -c 'Set a style or configuration once' data/documentation/abplayerkitcontrols.json
0
```

즉 `ABPlayerKitControls` 모듈 랜딩 페이지에는 **`.playerControlsStyle(_:)`/`.playerControlsConfiguration(_:)`에 대한 언급이 한 글자도 없다.** 심볼 페이지 자체는 생성돼 있으나(`swiftuicore/view/playercontrolsstyle(_:).json`) 자동 생성된 "Extended Modules → SwiftUICore" 버킷을 통해서만 도달 가능하다. 감사 C-2가 "modifier/Environment API 전무"였고 이번 라운드의 답이 바로 이 API인데, 모듈 문서에서 그 답이 큐레이션 밖으로 밀려났다.

`CustomizingControls.md:95`의 `` ``ABPlayerKit/ABPlayer/isBuffering`` ``(크로스모듈 링크)도 해석 실패해 평문으로 렌더된다. 이 줄은 H-2w가 추가한 "Show Buffering and Seek Feedback" 절에 있다.

**부수 발견 (이것도 고쳐야 한다)**: `ci.yml:111`이 `DOCC_WARNINGS_AS_ERRORS=YES`를 넘기는데도 이 14건이 빌드를 실패시키지 않는다(§1-4 원본 출력에서 `docbuild exit=0`). **문서 게이트가 이 부류에 대해 무력하다.** 감사가 "강점"으로 꼽은 "DocC CI 강제"가 실제로는 이 종류의 파손을 잡지 못한다. 앞으로도 계속 못 잡는다.

**수정**: `View/` → `SwiftUICore/View/`, `EnvironmentValues/` → `SwiftUICore/EnvironmentValues/`. 검증은 재빌드 후 위 `topicSections` 덤프에 "SwiftUI Environment"가 나타나는지로 한다 — 경고 유무만으로는 안 된다.

---

#### B3. `README.ko.md`가 이번 라운드 Controls 기능을 **하나도** 반영하지 않았다

```
$ grep -c 'showsPlayPauseButton\|touchPassthrough\|doubleTapSeek\|rateLabelFormat\|timeLabelSeparator\|ABControlsSlot\|showsBufferingIndicator' README.md README.ko.md
README.md:12
README.ko.md:0
```

Controls 절 분량도 EN 80줄 / KO 50줄이다. 누락 범위는 `README.md:417-445` 전체 — `showsPlayPauseButton`/`showsSeekBar`, 버퍼링 인디케이터, `touchPassthrough`, `doubleTapSeek`·`providesHapticFeedback`, `rateLabelFormat`, `timeLabelSeparator`, 시크 피드백 배지, `ABControlsSlot`, 리플레이. Metrics의 QoE 세션 블록(`README.md:501-527`)도 마찬가지다.

한국어 README는 영어 README의 **첫 줄에서 링크**되는 대등한 문서다. PiP·AirPlay·배경 정책·NowPlaying 절은 정확히 번역돼 있어(§4-3에서 확인) 전체가 방치된 것이 아니라 **Controls·Metrics 두 절만 한 라운드 뒤처졌다.** v0.4.0의 핵심 산출물 절반이 이번 릴리스를 설명하지 못한 채 태깅된다.

H-2w의 범위가 "README/DocC/CHANGELOG 최종화"였으므로 이것은 그 WP의 미완이다.

---

#### B4. README의 SwiftUI Controls 예제가 deprecated 이니셜라이저를 호출한다

**위치**: `README.md:392-397`, `README.ko.md:392-396`

```swift
ABVideoPlayerWithControls(
    player: player,
    videoGravity: .resizeAspect
)
```

컴파일러가 직접 확인해 준다(§1-5):

```
ReadmeExamples.swift:213:9: warning: 'init(player:videoGravity:style:configuration:accessoryViews:)' is deprecated:
Use the @ViewBuilder `accessories:` initializer instead. Scheduled for removal in 1.0.0.
```

`accessories:`에 기본값이 없어 제네릭 오버로드가 선택될 수 없고, 인자 없는 호출은 `ABVideoPlayerWithControls.swift:43-50`의 deprecated 이니셜라이저로만 해석된다.

같은 README가 **270줄 뒤에서 정확히 이 함정을 경고한다**(`README.md:666`, CHANGELOG 0.3.0의 Deprecated 절도 동일). 그리고 같은 README의 다른 예제(`README.md:145`)와 `CustomizingControls.md:69`는 올바르게 `{}`를 붙인다. 즉 README가 자기 자신의 마이그레이션 안내를 위반하는 유일한 지점이다.

`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`를 쓰는 소비자(이 리포 자신이 CI에서 그렇게 한다)가 이 예제를 복사하면 빌드가 깨진다.

**수정**: `)` → `) {}` 두 파일 각 1곳.

---

### 4-2. 비차단 — 문서 정확성

같은 수정 사이클에서 함께 닫기를 권한다. 전부 문서 전용이다.

**N1. 시간 라벨 위치가 거꾸로 적혀 있다.**
`README.md:399`("sits directly above the seek bar"), `README.ko.md:399`("탐색 막대 바로 위 왼쪽에"), `ABPlayerKitControls.md:9`("immediately above the timeline's leading edge") — 셋 다 **위**라고 한다.
실코드는 **아래**다. `ABPlayerControlsView.swift:341-343`에 주석까지 달려 있다: "Seek bar first, compact row (time label + rate) below it". 고정 테스트도 아래를 단언한다 — `ABPlayerControlsViewTests.swift:517`: `#expect(timeLabel.minY >= visibleTrack.maxY, ...)`. 그리고 형제 문서 `CustomizingControls.md:18`은 **올바르게** "Directly below the seek bar's visible track"이라고 적는다.
`docs/BRIEF-bottombar.md:7`을 보면 아래로 옮긴 것이 의도된 변경이었고 세 문서만 갱신되지 않았다. 라운드6 유입은 아니지만 H-2w의 재검 대상이었다.

**N2. `CustomizingControls.md:126`의 더블탭 지연 설명이 뒤집혀 있다.**
"delays every single tap by the double-tap timeout — not just for consumers who opt in"이라고 적혀 있으나, `require(toFail:)` 간선은 `doubleTapSeek != .disabled`일 때만 설치된다(`ABPlayerControlsView.swift:1102-1128`). 옵트인하지 않은 소비자는 전혀 지연되지 않는다. `README.md:434`는 같은 사실을 올바르게 서술한다 — DocC 쪽만 반대로 적혀 있다.

**N3. `CustomizingControls.md:89`의 `.custom` 시간 포매터 설명이 부정확하다.**
"every label in a render pass (elapsed, total, remaining) receives the same `referenceDurationSeconds`"라고 하나, `.custom`에서는 포매터가 갱신당 **한 번** 호출되어 라벨 전체를 반환한다(`ABControlsTimeLabelFormatter.swift:39-44`). elapsed/total/remaining 개별 호출이 존재하지 않는다. 이 서술은 `.automatic`에만 해당한다.

**N4. `ABPlayerKitMetrics.md:13`의 "every v2 event carries both"가 과장이다.**
`ABFailureRecord.sessionStartedAt`은 `CFTimeInterval?`이고(`ABFailureRecord.swift:11`) 세션 밖 실패에서 `nil`이며(`ABPlaybackSessionAccumulator.swift:218`), JSONL 기록 시 키가 아예 생략된다(`ABMetricsSink.swift:282-284`). 서버 조인을 전제로 스키마를 읽는 소비자에게 실제로 영향이 있다.

**N5. README의 자막 escape hatch 예제가 iOS 16 deprecated API를 쓴다.**
`README.md`의 `item.asset.mediaSelectionGroup(forMediaCharacteristic:)`이 iOS 16에서 deprecated다(§1-5 컴파일 경고 `:189`). 이 패키지의 하한이 iOS 17이므로 권장 예제가 하한에서부터 경고를 낸다. G-6의 유일한 코드 예제라 눈에 띈다.

**N6. `BackgroundAndPictureInPicture.md:20`의 `.demoteToInstance` × PiP 근거가 반대다.**
"Unaffected (nothing to demote — PiP requires an item)"라고 하나, PiP가 활성이면 플레이어는 `.current`이고 아이템이 있으므로 demote할 대상이 **있다**. 실제로 건너뛰는 이유는 `ABBackgroundPolicyMachine.swift:45-52`의 일괄 억제 가드다. 게다가 `.ignore` 행과 같은 단어("Unaffected")를 써서, 이 행이 억제가 실제로 일하는 자리라는 점을 가린다. 표의 결론은 맞고 근거만 틀렸다.

**N7. `CustomizingControls.md:179`의 상대 링크 깊이가 하나 깊다.**
`../../../../docs/POLICY-api-stability.md` — `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/` 기준으로 리포 루트보다 한 단계 위를 가리킨다. `../../../docs/...`가 맞다.

**N8. `CustomizingControls.md:142-144`의 스니펫 변수명이 파일 내 다른 예제와 다르다.**
파일 전체가 `controls`를 쓰는데(10-11, 35, 48-49, 160행) 슬롯 예제만 `controlsView`다. 그 스니펫만 파일의 흐름 예제와 함께 컴파일되지 않는다.

**N9. 갱신되지 않은 소스 주석 1건.**
`Sources/ABPlayerKitControls/SwiftUI/ABPlayerControlsEnvironment.swift:5-8`이 "`ABPlayerControlsStyle`'s own presets (`.default`/`.minimal`/`.tinted`) are `@MainActor static let`"이라고 적는다. D-10 해소로 `@MainActor`가 제거됐고(CHANGELOG.md:40, `ABPlayerControlsStyle.swift:101-131`) 이제 평범한 `public static let`이다. H-1w의 스캔 정규식에 걸리지 않는 종류의 낡은 주석이다.

**N10. "`@unchecked Sendable`은 이 코드베이스에서 금지"라는 주석이 사실이 아니다.**
`Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift:201-203`이 `MainActor.assumeIsolated`를 "banned in this codebase for the same reason as `@unchecked Sendable`"이라고 서술한다. 실제로는 `Sources/`에 `@unchecked Sendable` 선언이 **25개** 있고 그중 4개는 공개 타입(`ABObservationToken`, `ABHLSPrefetcher`, `ABInMemoryMetricsSink`, `ABJSONLinesMetricsSink`)이다. 금지가 아니라 "정당화를 요구하는 관례"다. 주석이 리포의 실제 규약을 잘못 서술한다. (라운드4 커밋 `7e4ba47` 유입, 라운드6 유입 아님.)

### 4-3. 비차단 — 공개 API 일관성 (리포 전체를 하나로 봤을 때만 보이는 것)

**N11. 같은 제스처의 기본 건너뛰기 양이 표면마다 다르다.**
`ABPlayerControlsConfiguration.skipInterval` 기본 **10초**(`ABPlayerControlsConfiguration.swift:80`, 5초 스텝 5~60으로 클램프됨) / `ABNowPlayingConfiguration.skipInterval` 기본 **15초**(`ABNowPlayingConfiguration.swift:14`, 클램프 없음). 같은 사용자가 오버레이에서 10초, 잠금화면에서 15초를 건너뛴다. 15초는 `MPSkipIntervalCommand`의 플랫폼 관례라 의도일 수 있으나 **어디에도 그렇게 적혀 있지 않고**, 한쪽만 검증된다는 비대칭도 남는다. 라운드6 유입(NowPlaying 신규 타깃).

**N12. `ABControlsSlot`이 `CaseIterable`인데 non-exhaustive 표기가 없다.**
`Sources/ABPlayerKitControls/Model/ABControlsSlot.swift:3`. 이번 라운드가 새로 만든 열거형이고 **가장 자라기 쉬운 것**(슬롯 추가가 D-7의 자연스러운 후속)인데, `CaseIterable`이라 케이스가 추가되면 소비자의 `allCases`가 조용히 바뀐다. `ABPlayerEvent`/`ABPlayerError`/`ABBackgroundPolicy`/`ABMetricEvent` 4개는 non-exhaustive 주석을 갖는데 `ABControlsSlot`은 없다. 지금 표기해 두는 비용이 0이고 나중이 비싸다.

**N13. 두 간판 편의 이니셜라이저의 같은 인자 레이블이 다르다.**
`ABVideoPlayer.init(url:videoGravity:autoplay:configuration:)` vs `ABVideoPlayerWithControls.init(url:videoGravity:autoplay:playerConfiguration:)`. Controls 쪽은 `configuration`이 컨트롤 설정과 충돌해서 내린 합리적 결정으로 보이나, README가 두 API를 나란히 보여 주므로 호출부를 옮길 때 걸린다. 문서화되지 않았다.

**N14. `ABOwnedPlayerBox.releaseIfOwned()`에 프로덕션 호출자가 없다 — 테스트만 부른다.**

```
$ grep -rn 'releaseIfOwned' Sources/ Tests/
Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift:106:        coordinator.releaseIfOwned()   ← 호출 있음 (dismantleUIView)
Sources/ABPlayerKitControls/SwiftUI/ABOwnedPlayerBox.swift:53:    func releaseIfOwned() {   ← 정의만
Tests/ABPlayerKitControlsTests/ABOwnedPlayerBoxTests.swift:56,57,66,67           ← 테스트만
```

결과적으로 두 편의 경로의 해제 시맨틱이 다르다. `ABVideoPlayer(url:)`은 `dismantleUIView`에서 **동기** 해제하고, `ABVideoPlayerWithControls(url:)`은 `@State` 박스의 `deinit` → `Task { @MainActor }`로 **비동기** 해제만 한다. README는 두 경로를 같은 문장으로 설명한다("releases every playback resource when SwiftUI discards the view"). 실동작 차이는 main-actor 한 홉이라 실질 피해는 없지만, **커버리지 숫자에 속지 말라는 지적이 그대로 적용되는 지점**이다 — `ABOwnedPlayerBoxTests` 3건 중 2건이 프로덕션이 한 번도 밟지 않는 경로를 검증한다.

**N15. `Package.swift`가 `.macOS(.v13)`를 선언하지만 이 패키지는 macOS로 빌드되지 않는다.**

```
$ swift build --target ABPlayerKitNowPlaying
Sources/ABPlayerKit/Policy/ABApplicationStateObserver.swift:2:8: error: no such module 'UIKit'
```

`Sources/`에 `#if canImport(UIKit)` 가드가 **0건**이고, `ABPlayerKit`·`ABPlayerKitControls`·`ABPlayerKitNowPlaying`이 무조건 `import UIKit`한다. 5개 프로덕트 중 macOS에서 성립하는 것은 `ABPlayerKitMetrics`·`ABPlayerKitCache`뿐이다. SwiftPM은 이 선언을 믿고 macOS 소비자가 의존성을 추가하도록 허용한 뒤 컴파일에서 실패한다.

**라운드6 유입이 아니다**(기준선에도 있었다). G-5(tvOS/visionOS)가 이월된 것과 별개 문제 — 이월된 것은 "플랫폼 **추가**"이고 이것은 "선언은 있는데 성립하지 않는 플랫폼"이다. 다만 라운드6이 같은 제약을 공유하는 5번째 프로덕트를 추가했다. `.macOS(.v13)`를 지우는 것이 한 줄이고 정직하다.

**N16. `@unchecked Sendable` 신규 유입은 2건, 둘 다 기존 관례를 따른다.**
기준선 대비 신규는 `ABCacheRevalidationRegistry`(`ABCacheStore.swift:142`)와 `ABAVLoadingRequestAdapter`(`ABLoadingRequestServicer.swift:144`) 뿐이다. 전자는 `NSLock` 보호 + `ABCacheReaderRegistry`/`ABCacheProgressWaiterRegistry`와 동형이라는 근거 주석이 있고, 후자는 AVFoundation 직렬 콜백 큐에 갇힌 어댑터라는 근거가 있다. `Sources/`에 `nonisolated(unsafe)` 신규 유입 0건, `try!`/`fatalError` 0건, 강제 캐스트는 `ABPlayerView.swift:13`의 `layer as! AVPlayerLayer` 1건(`layerClass` 오버라이드로 보장, SwiftLint 예외 명시)뿐이다. **위험 패턴 유입 없음 — 결함 아님.**

### 4-4. 테스트가 실제로 무엇을 보장하는가

743이라는 숫자가 아니라 불변식이 실제로 고정됐는지를 봤다. 표본 검수 결과 **이 라운드의 테스트는 형태 검사가 아니라 불변식 고정이다.**

가장 설득력 있는 세 가지:

- **A-1(루프)**: 감사가 지적한 실패 양식은 "테스트가 `setLooping` 호출 여부만 본다"였다. 지금은 `ABLoopRestartTests`가 실제 `AVPlayerItem`을 붙이고 `.AVPlayerItemDidPlayToEndTime`을 실제로 포스트한 뒤 `waitUntil { target.isPlaying }`으로 **재생 재개 자체**를 기다린다. 대칭으로 비루프 케이스가 재개되지 **않음**도 검증한다. 감사가 지적한 그 갭이 정확히 메워졌다.
- **A-7(시크 통일)**: `ABSeekUnificationTests`가 "두 번의 skip이 live `currentTime`이 아니라 `pendingSeekTime`에 대해 누적된다", "소스 교체 후 stale `.seekCompleted`가 방송되지 않는다", "5회 연속 탭이 5회 미만의 타깃 seek으로 coalesce된다"를 각각 단언한다. 셋 다 관찰 가능한 결과에 대한 단언이지 호출 여부가 아니다.
- **A-2/A-6(배경 수명주기)**: "`willResignActive` 캡처가 `didEnterBackground` 시점에 `isPlaying`이 이미 false여도 살아남는다"와 "`didEnterBackground`에 도달하지 않은 resign이 stale 캡처를 남겨 포그라운드에서 강제 재개하지 않는다"를 **쌍으로** 고정한다. 후자는 수정이 만들어낼 수 있는 새 버그를 미리 막는 테스트이며, 이런 종류가 있다는 것이 이 테스트 스위트의 질을 말해 준다.

**커버리지 91.3%에 속지 않기 위한 확인**: 신규 표면에 대해 대응 테스트 파일이 실재하는지를 파일 단위로 대조했다 — `ABPictureInPictureSessionTests`, `ABContinueAudioOnlyTests`, `ABExternalPlaybackConfigurationTests`, `ABNowPlaying*Tests` 4종, `ABPlayerControlsBufferingTests`, `ABDoubleTapSeekZoneTests`, `ABPlayerControlsDoubleTapTests`, `ABPlayerControlsReplayTests`, `ABPlayerControlsSlotTests`, `ABPlayerControlsSeekFeedbackTests`, `ABPlayerControlsEnvironmentTests`, `ABSessionAccumulatorTests`, `ABQoEAggregationTests`, `ABOwnedPlayerBoxTests`, `ABVideoPlayerOwnershipTests`. **라운드6 신규 기능 중 대응 테스트가 없는 것을 찾지 못했다.**

유일하게 지적할 것은 N14(프로덕션이 밟지 않는 경로를 검증하는 테스트 2건)이며, 그마저 비차단이다.

### 4-5. 이월 항목의 표기 정직성 — 확인 결과 정직하다

- **PiP가 명시 소유 경로에서만 지원된다**는 한계는 세 곳 모두에 **숨기지 않고** 적혀 있다:
  - `README.md`: "**Picture in Picture is supported only on the explicit-ownership path** (`player:` initializers). The `url:`/`source:` convenience initializers release their owned player when the SwiftUI identity is discarded, which would cut PiP short — so they don't accept a `pictureInPicture:` parameter."
  - `README.ko.md:324`: 같은 내용을 굵게 표기.
  - `BackgroundAndPictureInPicture.md`의 "Scope" 절: "extending that path is tracked as future work, not implemented here."
  - 소스 주석까지 일치한다(`ABVideoPlayer.swift:24-27`).
  이유(왜 조합되지 않는가)까지 적혀 있어 흐리는 서술이 아니다. **결함 아님.**
- 시뮬레이터 PiP 미지원은 README 표와 DocC "Prerequisites" 양쪽에 `ABPictureInPictureSession.isSupported` — "usually `false` in the simulator"로 명시.
- E-7(LRU)은 `ABPlayerKitCache.md`에 제약으로 문서화.
- `.continueAudioOnly`의 3개 전제조건(누가 무엇을 설정하는지 포함)이 README 표로 명시되고, 미충족 시 `.pause`처럼 동작한다는 폴백까지 적혀 있다.
- `ABBackgroundPolicy` non-exhaustive는 README와 CHANGELOG 마이그레이션 노트 양쪽에 있다. (다만 `ABPlayerKit.docc/ABPlayerKit.md:23`은 `ABPlayerEvent`/`ABPlayerError`만 열거해 README와 어긋난다 — 사소, N-급.)

### 4-6. 검증 범위 밖 (확인하지 않았다 — 확인했다고 쓰지 않는다)

- **기기 전용 6항목** (PiP 실동작·배경 진입 순서·배경 오디오 지속·NowPlaying 잠금화면/리모트 커맨드·AirPlay 라우팅·PiP 중 플레이어 소멸). 시뮬레이터로 검증 불가. 이 중 잠금화면 리모트 커맨드는 §4-1 B1과 직접 맞물린다 — **기기 확인 시 `commands`를 명시 설정한 구성과 기본 구성 양쪽을 시험해 B1의 진단을 실증할 것.**
- **GitHub Actions 상의 CI 그린**. 로컬에서 CI의 4개 잡(test/docbuild/demo/lint/TSan)을 같은 인자로 재현했을 뿐, 실제 러너(macOS 15, 3코어, Xcode 16.4)에서의 결과는 확인하지 않았다. 특히 D-10의 `Sendable`화는 로컬 Xcode 26.2에서만 검증됐다.
- **커버리지 배지의 현재 값**. 배지 파이프라인(`ci.yml:62-101, 192-216`)의 존재와 README 참조는 확인했으나, `badges` 브랜치의 `coverage.json`을 가져오지는 않았다. 91.3%라는 값은 오케스트레이터 보고이며 이 게이트가 재현하지 않았다.
- **`ABPlayerKitNowPlayingTests`가 TSan 잡에 미포함**인 상태. CI 설정상 사실이나(`ci.yml:177-178`이 코어·캐시만), 이는 ROADMAP CI-2의 명시 범위("코어+캐시 테스트 타깃")와 일치하며 이월로 확정된 항목이다. 결함으로 세지 않는다.

---

## 5. 판정 (1차 게이트 — 이력으로 보존)

> 아래 §5는 **1차 게이트(`8793bb6` 기준)의 판정 원문**이다. 여기서 REQUEST-CHANGES가 나왔고 차단 결함 4건이 수정돼 `ebdf0d9`로 병합됐다. 무엇이 잡혔고 어떻게 닫혔는지가 이 문서의 값어치이므로 원문을 지우지 않는다. **현재 판정은 §6 재게이트를 보라.**

§7 기준 1~4는 전부 충족한다. 코드에는 기능적 결함이 없다 — 3회 그린, TSan 그린, lint 그린, README 전 예제 컴파일 통과, 공개 API 제거 0건, 위험 패턴 유입 없음, 신규 기능의 불변식이 실제로 테스트로 고정돼 있다. **라운드6의 엔지니어링 결과물 자체는 v0.4.0으로 나갈 수준이다.**

판정을 가르는 것은 문서다. 라운드6의 제품 목표 4개 중 2번은 "README 사용법 완결"이고, §7 기준 1은 C-2·C-3·G-3의 해소를 요구한다. 그 세 지점에서:

- 새로 만든 NowPlaying의 리모트 커맨드 활성화 조건이 세 문서 모두에서 실코드와 다르고, 문서대로 따르면 커맨드가 조용히 죽는다 (B1).
- 새로 만든 Environment modifier API가 자기 모듈 DocC 랜딩 페이지에서 통째로 사라졌고, 그것을 잡으라고 둔 CI 게이트가 무력하다 (B2).
- 한국어 README가 이번 라운드 Controls 기능을 **0건** 반영한다 (B3).
- README의 SwiftUI Controls 예제가 자기 README가 경고하는 deprecated 이니셜라이저를 호출한다 (B4).

4건 전부 문서 전용 수정이라 회귀 리스크가 0이고, 바로 다음 단계인 H-3w도 문서 전용이라 일정 비용이 사실상 0이다. HANDOFF §4-5가 정식화한 기준("비차단이라도 일정 비용이 없고 원인이 특정돼 있으면 닫아라")이 그대로 적용된다. 원인은 4건 모두 파일·행 단위로 특정돼 있고, 각각에 검증 방법을 적었다 — 특히 B2는 경고 유무가 아니라 `.doccarchive`의 `topicSections` 덤프로 확인해야 한다(경고는 이미 CI를 통과하고 있다).

수정 후 재게이트에 필요한 것은 (1) `docbuild` 후 `topicSections`에 "SwiftUI Environment" 등장 확인, (2) README 예제 재컴파일로 경고 0건 확인, (3) 한국어 README의 기능 키워드 grep 대조 — 세 가지이며 전부 §1에 명령이 있다. 전체 스킴 재실행은 코드 변경이 없다면 불필요하다.

*(1차 게이트 판정: REQUEST-CHANGES. 이하 §6이 현재 판정이다.)*

---

## 6. 재게이트 (1차 — `ebdf0d9` 기준, 이력으로 보존)

> §6은 **1차 재게이트의 판정 원문**이다. 여기서 차단 결함 4건의 종결을 확인했고 신규 차단 R1을 발견해 다시 REQUEST-CHANGES가 나왔다. R1은 `fc547a0`에서 닫혔다. **현재 판정은 §7 최종 재검증을 보라.**


- **기준 커밋**: `ebdf0d9` (Round 6: close the final gate's documentation findings, #15)
- worktree를 `origin/main`에 리베이스했고, 이 리뷰 문서 커밋은 그 위에 유지된다.

### 6-1. 재실행 범위의 판단 근거

먼저 "런타임 코드 변경 0줄"이라는 전제를 **보고가 아니라 diff로** 확인했다.

```
$ git diff --stat 8793bb6 ebdf0d9
 README.ko.md                                          |  91 ++++++-
 README.md                                             |  31 ++-
 Sources/ABPlayerKitCache/ABCacheStore.swift           |  10 +-
 .../ABPlayerKitControls.docc/ABPlayerKitControls.md   |  10 +-
 .../ABPlayerKitControls.docc/CustomizingControls.md   |   6 +-
 Sources/ABPlayerKitControls/Model/ABControlsSlot.swift |   6 +
 Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift | 10 +-
 .../ABPlayerKitNowPlaying.docc/RemoteCommands.md      |  39 ++-
 docs/briefs/RESULT-round6-docfix.md                   | 296 +++++++++++++++++++
 9 files changed, 454 insertions(+), 45 deletions(-)
```

`.swift` 파일이 **3개 바뀌었다** — 전제가 그대로는 성립하지 않는다. 셋의 diff를 전부 읽었고, **실행문 변경은 0줄이며 전부 주석·문서 주석뿐**임을 확인했다:

- `ABCacheStore.swift:255-263` — `@unchecked Sendable` "banned" 표현 정밀화(N10). 주석만.
- `ABPlayerControls.swift:199-206` — 같은 표현 정밀화(N10). 주석만. *(N10에서 나는 `ABPlayerControls.swift` 1곳만 지적했는데 같은 표현이 `ABCacheStore.swift`에도 있었고 양쪽 다 고쳐졌다.)*
- `ABControlsSlot.swift:1-11` — non-exhaustive 문서 주석 6줄 추가(N12). 선언 변경 없음.

따라서 **런타임 동작이 달라질 수 있는 경로가 없으므로 전체 스킴 3회와 TSan 재실행은 불필요**하다고 판단했다. 3회 반복 프로토콜은 런타임 동작의 flakiness를 드러내기 위한 장치인데 드러낼 런타임 변경 자체가 없다.

다만 주석 변경도 (a) 컴파일을 깨뜨릴 수 있고 (b) DocC 마크업을 깨뜨릴 수 있으며 (c) **위생 스캔의 대상이 정확히 `Sources/`의 주석**이므로, 아래는 전부 다시 돌렸다. 전체 스킴은 비용이 수십 초라 "불필요"와 "안 할 이유"는 다르다고 보아 **1회 확인 사살**로 실행했다.

### 6-2. 원본 출력

**DocC (`DOCC_WARNINGS_AS_ERRORS=YES`) — 경고 14건 → 2건**

```
docbuild exit=0
--- DocC warnings (was 14) ---
2
CustomizingControls.md:97:9: warning: 'ABPlayerKit' doesn't exist at '/ABPlayerKitControls/CustomizingControls'
CustomizingControls.md:97:9: warning: 'ABPlayerKit' doesn't exist at '/ABPlayerKitControls/CustomizingControls' (in target 'ABPlayerKitControls' from project 'ABPlayerKit')
** BUILD DOCUMENTATION SUCCEEDED **
```

**전체 스킴 1회**

```
test exit=0
✔ Test run with 269 tests in 41 suites passed after 0.252 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.015 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.821 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.056 seconds.
✔ Test run with 72 tests in 8 suites passed after 0.112 seconds.
** TEST SUCCEEDED **
```

743건 유지, 그린.

**SwiftLint**

```
Done linting! Found 0 violations, 0 serious in 181 files.
```

**위생 스캔 2건** (`Sources/`의 주석이 바뀌었으므로 반드시 재실행)

```
$ grep -rnE '(DESIGN|PLANNING|REVIEW|ROADMAP|HANDOFF)[^ ]*\.md|round ?[0-9]|Round ?[0-9]|Phase [0-9]|§[0-9]' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
exit=1

$ grep -rnE '(^|[^A-Za-z0-9])(MJ-[0-9]+|mn-[0-9]+|[NMC][0-9]+|WP[0-9]+(\.[0-9]+)?|Q[0-9]+(-[A-Z])?)([^A-Za-z0-9]|$)' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
exit=1
```

둘 다 0줄 + `exit=1` 유지. 새 주석이 인용을 재유입시키지 않았다.

### 6-3. 차단 결함 4건의 종결 여부 — 전부 직접 확인

| # | 결함 | 상태 | 내가 직접 본 근거 |
|---|---|---|---|
| B1 | NowPlaying 커맨드 활성화 표가 실코드와 다름 | **종결** | 아래 |
| B2 | DocC "SwiftUI Environment" 섹션 드롭 | **종결** | 아래 |
| B3 | 한국어 README가 라운드6 Controls 미반영 | **종결** | 아래 |
| B4 | README 예제가 deprecated 이니셜라이저 호출 | **종결** | 아래 |

**B1 — 종결.** 세 문서를 다시 읽고 `ABNowPlayingCenter.swift:220-230`의 게이팅 및 `ABRemoteCommandSet.swift:25-27`의 `.default`와 한 줄씩 대조했다. 표가 "In `.default`?" / "Also requires" 두 열로 재구성돼 **두 조건이 모두 드러난다**. `.default`의 구성원 열거가 실코드와 정확히 일치하고(`.play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePlaybackPosition`), 제외 3종이 명시된다. 산문에 "Supplying a rates list or a handler alone, without also expanding `commands`, leaves those three disabled with no runtime signal that anything is missing"가 추가돼, 내가 지적한 **무징후 실패**가 명시적으로 경고된다. `RemoteCommands.md`에는 `skipInterval` 15초 vs Controls 10초 차이(N11)까지 문단으로 들어갔다.

**B2 — 핵심 종결.** 경고 개수가 아니라 **빌드된 `.doccarchive`를 다시 열어** 확인했다(경고는 애초에 CI를 통과하므로 근거가 못 된다):

```
SECTION: UIKit                  | identifiers: 1
SECTION: SwiftUI                | identifiers: 2
SECTION: SwiftUI Environment    | identifiers: 4
      ABPlayerKitControls/SwiftUICore/View/playerControlsStyle(_:)
      ABPlayerKitControls/SwiftUICore/View/playerControlsConfiguration(_:)
      ABPlayerKitControls/SwiftUICore/EnvironmentValues/playerControlsStyle
      ABPlayerKitControls/SwiftUICore/EnvironmentValues/playerControlsConfiguration
SECTION: Appearance             | identifiers: 6
SECTION: Behavior and Events    | identifiers: 5
```

```
$ grep -c 'Set a style or configuration once' data/documentation/abplayerkitcontrols.json
1        (재게이트 전: 0)
```

섹션이 4개 식별자와 함께 복귀했고, 사라졌던 설명 산문도 복귀했으며, 자동 생성 `Extended Modules` 버킷은 큐레이션에 흡수돼 사라졌다. 근본 원인이 내 가설(`SwiftUI/` 한정)보다 정확했다 — 이 SDK에서 `View`/`EnvironmentValues`는 `SwiftUICore` 모듈에 있다.

**B3 — 종결.**

```
=== Controls 기능 키워드 (재게이트 전: EN 12 / KO 0) ===
README.ko.md:12
README.md:12
=== Metrics QoE 키워드 ===
README.ko.md:6
README.md:6
=== Controls 절 줄 수 (재게이트 전: EN 80 / KO 50) ===
80
80
```

**B4 — 종결.** 양쪽 README가 `) {}`로 바뀐 것을 읽었고, **컴파일러로 확증했다**: 현재 README와 동일하게 갱신한 하네스에서 해당 deprecation 경고가 사라졌다(§6-4 출력의 유일한 잔여 경고는 N5의 기존 항목뿐).

### 6-4. 새로 발견한 것 — 신규 차단 1건

**R1 (차단). 이번 수정이 새로 추가한 리모트 커맨드 스니펫이 컴파일되지 않는다.**

**위치**: `README.md:589-599`, `README.ko.md`(대응 블록), `Sources/ABPlayerKitNowPlaying/ABPlayerKitNowPlaying.docc/RemoteCommands.md:29-40` — 세 문서 모두 동일.

이 스니펫은 한 번도 컴파일된 적이 없는 신규 코드라, §1-5의 하네스에 그대로 옮겨 컴파일했다:

```
** BUILD FAILED **
ReadmeExamples.swift:249:24: error: value of type 'ABPlayer' has no member 'skipToNextEpisode'
ReadmeExamples.swift:250:28: error: value of type 'ABPlayer' has no member 'skipToPreviousEpisode'
```

문제 지점:

```swift
let token = ABNowPlayingCenter.shared.attach(player, metadata: metadata, configuration: configuration)
ABNowPlayingCenter.shared.setTrackNavigationHandlers(
    next: { player.skipToNextEpisode() },        // ← ABPlayer에 없는 멤버
    previous: { player.skipToPreviousEpisode() },// ← ABPlayer에 없는 멤버
    for: player
)
```

`player`는 같은 스니펫 안에서 `attach(player, ...)`와 `for: player`에 넘겨지므로 **명백히 `ABPlayer`**다. 소비자 앱의 플레이스홀더 메서드를 의도한 것으로 보이나, 하필 **라이브러리 자신의 타입 위에서** 호출돼 있어 독자는 이것이 플레이스홀더인지, 자기 버전이 낮은 것인지, 오타인지 구별할 수 없다. `ABPlayer`의 API를 뒤지게 된다.

두 호출을 주석 처리하자 나머지는 전부 통과했다 — 스니펫의 **핵심 내용(`commands = .default.union([...])`, `supportedPlaybackRates`)은 정확하고 컴파일된다.** 결함은 플레이스홀더 명명 하나뿐이다.

```
** BUILD SUCCEEDED **
ReadmeExamples.swift:189:31: warning: 'mediaSelectionGroup(forMediaCharacteristic:)' was deprecated in iOS 16.0  ← N5(기존, 비차단)
```

**차단으로 두는 이유**: 이 게이트가 라운드 내내 적용한 기준이 "README 예제는 실제로 컴파일된다"였고, B4는 예제가 **경고**를 낸다는 이유로 차단했다. 신규 예제의 **하드 컴파일 에러**는 같은 결함군의 더 무거운 사례이며, 문서 3개에 동시에 있다. 더 가벼운 것을 막고 더 무거운 것을 통과시키면 B4 판정이 자의적이 된다. 수정은 파일당 두 줄 — 예: `next: { episodes.advanceToNext() }`처럼 **소비자 소유임이 자명한 수신자**로 바꾸면 된다.

**비차단 잔여 2건** (같은 사이클에 함께 닫기를 권한다):

- **R2.** `CustomizingControls.md:97`의 `` ``ABPlayerKit/ABPlayer/isBuffering`` `` 크로스모듈 링크가 여전히 해석되지 않는다(잔여 DocC 경고 2건의 정체). **다만 B2와 달리 내용 손실은 없음을 아카이브에서 확인했다** — 해당 문단은 살아 있고(`grep -c 'spinner overlay'` → 1) 링크만 평문으로 렌더된다. 멀티타깃 SPM DocC에서 크로스타깃 심볼 링크는 결합 아카이브 없이는 원래 해석되지 않으므로, 링크를 고치기보다 평문 `ABPlayer.isBuffering`으로 바꾸는 것이 맞다.
- **R3.** `RemoteCommands.md:5`의 `## Overview`가 **빈 섹션**이 됐다 — 원래 그 아래 있던 문단이 새 `## The "no empty handlers" invariant` 절로 옮겨가면서 헤딩만 남았다. 재작성의 부산물이며 두 줄 삭제로 끝난다.

내가 §4-2/§4-3에서 올린 나머지 비차단 항목 중 N1(시간 레이블 위치), N11(`skipInterval` 기본값 차이), N12(`ABControlsSlot` non-exhaustive), N10(`@unchecked Sendable` "banned" 표현)은 이번에 함께 닫힌 것을 확인했다. N2~N9, N13~N15는 미처리이며 전부 비차단으로 유지된다.

### 6-5. 검증 범위 밖 (재게이트에서도 확인하지 않았다)

- **기기 전용 6항목** — 변함없이 사람의 확인이 필요하다. B1이 닫혔으므로 이제 문서를 신뢰하고 검증해도 된다. 잠금화면 리모트 커맨드 확인 시 `commands`를 확장한 구성과 기본 구성 양쪽을 시험하면 B1 수정의 실증이 된다.
- **GitHub Actions 상의 실제 CI 결과.** 로컬 재현일 뿐이다. 오케스트레이터가 알려온 TSan 1회 실패(data race 0건 + `ABWaitUntilTimedOut`, 정상 수 ms 테스트가 134초 소요된 러너 과부하, 재실행 1회로 통과, main 최근 4회 연속 그린)는 **이 PR의 런타임 코드 변경이 0줄임을 §6-1에서 직접 확인했으므로 인과관계가 성립할 수 없다.** 새 결함으로 세지 않는다. 다만 HANDOFF §4-6이 정리한 대로 `ABPLAYERKIT_WAIT_SCALE`은 "느림을 멈춤으로 오판"하는 문제를 완화했을 뿐 없애지 못했으므로, **러너 과부하에 견디는 대기 전략을 v0.5.0 이월 사항으로 기록**하기를 권한다.
- **커버리지 배지의 현재 값** — 재게이트에서도 `badges` 브랜치를 가져오지 않았다.

### 6-6. 재게이트 판정

차단 결함 4건은 **전부 종결됐고, 보고가 아니라 직접 실행으로 확인했다.** 특히 B2는 빌드 산출물에서, B4는 컴파일러로 확증했다. 수정 품질은 요구한 것보다 낫다 — B1은 내가 지적한 두 조건의 병기를 넘어 무징후 실패 자체를 경고 문장으로 명시했고, B2는 내 가설보다 정확한 근본 원인(`SwiftUICore`)을 짚었으며, 비차단 4건도 함께 닫혔다. `Sources/`의 변경은 실행문 0줄임을 diff로 확인했고 위생 스캔·테스트·lint·DocC 전부 그린이다.

**리포는 사실상 v0.4.0 준비가 끝났다.** 남은 것은 신규 결함 R1 하나이며, 세 문서에서 **파일당 두 줄**을 고치면 된다 — 스니펫의 실질 내용은 이미 정확하다.

R1을 차단으로 두는 것은 판정의 일관성 때문이지 리포의 상태에 대한 불신 때문이 아니다. 재재게이트에 필요한 것은 **§1-5 하네스에 세 문서의 스니펫을 옮겨 컴파일해 에러 0건을 확인하는 것 하나뿐**이다. 코드가 그대로라면 테스트·TSan·lint·DocC 재실행은 불필요하다.

*(1차 재게이트 판정: REQUEST-CHANGES. 이하 §7이 현재 판정이다.)*

---

## 7. 최종 재검증 (`fc547a0` 기준, 2026-08-13)

- **기준 커밋**: `fc547a0` (Round 6: make the remote-command snippet compile, and fix the recurring TSan timeout, #16)
- worktree를 `origin/main`에 리베이스했고 이 리뷰의 두 커밋이 그 위에 유지된다.

### 7-1. 변경 범위 (직접 확인)

```
$ git diff --stat ebdf0d9 fc547a0
 .gitignore                                              |  3 +++
 README.ko.md                                            |  6 ++++--
 README.md                                               |  7 +++++--
 .../ABPlayerKitControls.docc/CustomizingControls.md     |  2 +-
 .../ABPlayerKitNowPlaying.docc/RemoteCommands.md        |  9 +++++----
 Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift     |  4 ++--
 Tests/ABTestSupport/ABWaitUntil.swift                   | 17 +++++++++++++++++
 7 files changed, 37 insertions(+), 11 deletions(-)

$ git diff --name-only ebdf0d9 fc547a0 -- 'Sources/'
Sources/ABPlayerKitControls/ABPlayerKitControls.docc/CustomizingControls.md
Sources/ABPlayerKitNowPlaying/ABPlayerKitNowPlaying.docc/RemoteCommands.md
```

`Sources/`의 변경은 **DocC 마크다운 2개뿐이고 `.swift`는 0개** — 이번에는 제품 코드 0줄이 문자 그대로 성립한다. 반면 `Tests/`가 바뀌었으므로 **전체 스위트와 TSan은 반드시 재실행해야 한다**(§6-1에서 생략을 정당화했던 근거가 여기서는 성립하지 않는다).

### 7-2. 원본 출력

**DocC — 경고 14건 → 2건 → 0건**

```
docbuild exit=0
DocC warnings (was 14, then 2):
       0
** BUILD DOCUMENTATION SUCCEEDED **
```

**전체 스킴 2회** (`Tests/` 변경분 확인)

```
run 1 exit=0
✔ Test run with 269 tests in 41 suites passed after 0.309 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.016 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.900 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.054 seconds.
✔ Test run with 72 tests in 8 suites passed after 0.092 seconds.
** TEST SUCCEEDED **
run 2 exit=0
✔ Test run with 269 tests in 41 suites passed after 0.287 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.014 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.512 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.042 seconds.
✔ Test run with 72 tests in 8 suites passed after 0.079 seconds.
** TEST SUCCEEDED **
```

743건 유지.

**TSan** (변경이 겨냥한 잡, `TEST_RUNNER_ABPLAYERKIT_WAIT_SCALE=6`)

```
tsan exit=0
✔ Test run with 269 tests in 41 suites passed after 0.816 seconds.
✔ Test run with 72 tests in 8 suites passed after 0.118 seconds.
** TEST SUCCEEDED **
```

`WARNING: ThreadSanitizer` / `data race` / `ABWaitUntilTimedOut` 히트 0건.

**SwiftLint**

```
Done linting! Found 0 violations, 0 serious in 181 files.
```

**위생 스캔 2건** (`Sources/`의 `.md`가 바뀌었으므로 재실행)

```
exit=1
exit=1
```

둘 다 0줄 유지.

### 7-3. R1·R2·R3 종결 확인

**R1 — 종결. 컴파일러로 확증했다.** 세 문서의 현재 스니펫을 §1-5 하네스에 **그대로 옮겨** 빌드했다:

```
** BUILD SUCCEEDED **
ReadmeExamples.swift:189:31: warning: 'mediaSelectionGroup(forMediaCharacteristic:)' was deprecated in iOS 16.0  ← N5(기존, 비차단)
```

에러 0건. 유일한 진단은 N5(기존 비차단 항목)뿐이다. 이 하네스가 결함을 실제로 잡는다는 것은 1차 재게이트에서 **같은 하네스가 정확히 그 두 에러를 냈다**는 사실로 이미 입증돼 있다.

수정 방식도 좋다. 플레이스홀더 수신자를 없애는 대신 클로저 본문을 주석으로 비운 것은, 컴파일을 통과시키면서 **"이 라이브러리에는 큐 개념이 없고 그 자리는 소비자의 것"이라는 사실 자체를 문서가 말하게** 한다. 원래 결함의 근본 원인(라이브러리 타입 위에서 존재하지 않는 메서드를 부른 것)이 제거됐다.

**R2 — 종결.** `CustomizingControls.md:97`이 `` `ABPlayer.isBuffering` `` 평문 코드 표기로 바뀌었다. 이것이 DocC 경고를 0건으로 만든 마지막 한 건이다. 멀티타깃 SPM에서 크로스타깃 심볼 링크는 원래 해석되지 않으므로, 링크를 고치는 대신 평문화한 것이 옳은 선택이다.

**R3 — 종결.** `RemoteCommands.md`의 빈 `## Overview`가 제거돼 문서가 곧바로 `## The "no empty handlers" invariant`로 들어간다.

### 7-4. TSan 수정에 대한 판단 (요청받은 항목)

**결론: 설계·적용·제외 판단 모두 옳다. 다만 적용 범위에 빈 곳이 하나 남아 있다.**

**(a) `abScaledTimeout`의 설계 — 옳다.** `waitUntil`과 **같은 `deadlineScale`을 재사용**하므로 조절 노브가 하나로 유지된다. 환경변수가 없으면 `deadlineScale == 1`이므로 로컬·일반 CI 실행의 동작은 문자 그대로 불변이고, 배수가 걸리는 것은 TSan 잡뿐이다. 무엇보다 **언제 스케일하고 언제 하지 말아야 하는지의 규칙이 문서로 적혔다** — "성공 경로가 이겨야 하는 상한만. 취소돼야 할 작업을 대신하는 의도적 장시간 sleep은 스케일하지 말 것." 이 규칙이 글로 남은 것이 이 변경의 가장 큰 값어치다. PR #11이 진단은 옳고 범위만 좁았던 이유가 바로 이 규칙이 암묵지였기 때문이다.

**(b) 두 곳에 적용한 것 — 옳다.** `ABCacheStoreTests.swift:1082`와 `:1570`은 `withTaskGroup`의 두 갈래 중 하나가 자고 일어나 `.timedOut`을 반환하는 **경주형 타임아웃**이다. 이것은 성공 경로가 이겨야 하는 상한이 맞고, `waitUntil`을 거치지 않아 `ABPLAYERKIT_WAIT_SCALE`이 닿지 않던 것도 사실이다. 그리고 `:1570`이 속한 테스트가 **`@Test("Removing all cached media while a load is stalled on a fill lets that load finish via passthrough instead of failing")`(1523행)** — 보고된 실패 테스트와 정확히 일치한다. 진단이 실제 실패 지점을 짚었음을 코드 위치로 확인했다.

진단력 손실은 있으나 수용 가능하다: TSan 잡에서만 실제 교착 감지가 2초 → 12초로 늦어진다. 대안은 느린 러너를 **제품 실패로 오보**하는 것이고, HANDOFF §4-6이 정리했듯 오보는 "그린 나올 때까지 재실행"을 학습시켜 진짜 실패까지 무디게 만든다. 10초 늦은 참 양성이 거짓 양성보다 낫다.

**(c) 30초 sleep을 제외한 판단 — 옳다. 방어 가능한 정도가 아니라 필요한 조치다.** 해당 테스트를 직접 읽었다(`ABAVPlaybackTargetReadyWaitTests.swift:152-175`, `installTimeoutTaskCancelsWhenAlreadyResolved`):

```swift
let task = Task {
    try? await Task.sleep(for: .seconds(30))
    guard !Task.isCancelled else { return }
    await ranFlag.markRan()
}
state.installTimeoutTask(task)
_ = await task.value          // ← 성공 경로는 "즉시 반환"이다
#expect(await ranFlag.ran == false)
```

여기서 30초는 **성공 상한이 아니라 실패 상한**이다. 제품이 동기 취소에 성공하면 `await task.value`가 곧바로 돌아오고 30초는 아예 소비되지 않는다. 취소에 실패해야만 30초가 흐른다. 즉 이 값은 "회귀가 발생했을 때 얼마나 빨리 알 수 있는가"를 정하며, 스케일하면 회귀 감지만 느려진다.

그리고 이 경우엔 단순히 느려지는 정도가 아니다. 이 스위트의 선언은 `@Suite(..., .timeLimit(.minutes(3)))`이고, **30초 × 6 = 180초 = 정확히 그 제한값**이다. 스케일했다면 취소 회귀가 깔끔한 `#expect` 실패 대신 스위트 레벨 타임아웃으로 바뀌었을 것이다 — 실패 지점을 가리키지 못하는, 엄격히 더 나쁜 진단이다. 게다가 이 파일은 `ABPlayerKitTests`에 속해 **TSan 잡이 실제로 돌리는 대상**이므로 가상의 판단이 아니라 실제 선택이었다. 제외가 맞다.

**(d) 적용 범위 — 한 곳 빠졌다 (아래 7-5).** `Tests/` 전체에서 `Task.sleep`을 전수 조사했다:

| 위치 | 성격 | 스케일 | 판정 |
|---|---|---|---|
| `ABCacheStoreTests.swift:1082` | 경주형 타임아웃 | 적용 | 옳음 |
| `ABCacheStoreTests.swift:1570` | 경주형 타임아웃 | 적용 | 옳음 |
| `ABCacheStoreTests.swift:1982` | 폴링 간격(5ms) | 미적용 | 옳음 — 폴링 **간격**은 스케일 대상이 아니다 |
| `ABAVPlaybackTargetReadyWaitTests.swift:163` | 취소돼야 할 작업(30s) | 미적용 | 옳음 (위 (c)) |
| `ABPlayerControlsAutoHideTests.swift:54` | 부정 단언용 대기(30ms) | 미적용 | 옳음 — 취소된 sleep이 발화하지 **않음**을 보이는 대기이고, Controls는 TSan 잡 대상도 아니다 |
| `ABWaitUntil.swift:62` | 폴링 간격(5ms) | 미적용 | 옳음 |

`Task.sleep` 기준으로는 빠짐이 없다. **그러나 마감시한이 `Task.sleep`으로만 표현되는 것은 아니다** — 7-5를 보라.

### 7-5. 새로 발견한 것 — 비차단 1건

**F1 (비차단). `waitUntilHandleCount`의 5초 마감시한이 스케일되지 않는다 — 같은 결함군이 같은 파일에 남아 있다.**

**위치**: `Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift:1957-1963`

```swift
private func waitUntilHandleCount(
    _ store: ABCacheStore,
    equals expected: Int,
    deadline: Duration = .seconds(5),          // ← 스케일되지 않는 맨 마감시한
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    ...
        if clock.now - start >= deadline {
            Issue.record("fillHandleCount() did not reach \(expected) in time ...")
            throw ABWaitUntilTimedOut()
```

이것은 공유 `waitUntil`이 actor 격리 `async` 술어를 못 받아서 이 파일이 자체 구현한 **손수 만든 대기 헬퍼**다. 성격은 방금 고친 두 곳과 정확히 같다 — 성공 경로가 이겨야 하는 상한인데 `waitUntil`을 거치지 않아 `ABPLAYERKIT_WAIT_SCALE`이 닿지 않는다. 실패했을 때 던지는 것도 **`ABWaitUntilTimedOut`** 으로, 지금까지 보고된 플레이크 신호와 같은 문자열이다.

호출부 3곳 전부 마감시한을 명시하지 않아 맨 5초를 쓴다:

```
1452:        try await waitUntilHandleCount(store, equals: 1)
1457:        try await waitUntilHandleCount(store, equals: 0)
1513:        try await waitUntilHandleCount(store, equals: 1)
```

이들이 속한 테스트는 방금 고친 테스트의 **바로 이웃**이고 구조도 같다 — `@Test("A truncate-and-refill fill holds its writer handle open for the whole lifetime and closes it exactly once on completion")`(1425행)과 `@Test("removeAll while a fill is in flight closes its writer handle")`(1481행). 같은 `ABPlayerKitCacheTests` 타깃, 즉 **TSan 잡이 실제로 돌리는 대상**이며, 동일한 fill/removeAll 동시성 경로를 기다린다. 다음 플레이크의 가장 유력한 후보다.

**차단하지 않는 이유**: 출하되는 산출물이 아니라 테스트 전용이고, 지금 TSan은 실제로 그린이다(§7-2). §7 기준 3의 "TSan 그린"은 오늘 충족된다. 이 게이트가 지금까지 차단으로 삼은 기준은 일관되게 **"출하물(라이브러리 + 그 문서)에 틀린 것이 들어 있는가"** 였고(B1~B4, R1 전부 그랬다), 여기에는 해당하지 않는다.

**그럼에도 태깅 전에 닫기를 권한다.** 수정은 기본값 한 줄(`deadline: Duration = abScaledTimeout(.seconds(5))`)이고, 이것을 남겨 두면 "진단은 옳은데 범위가 좁다"는 같은 실수가 **세 번째로** 반복된다 — PR #11(`waitUntil`만), PR #16(`Task.sleep`만), 그리고 다음은 손수 만든 마감시한. 규칙이 이미 `abScaledTimeout`의 문서 주석에 적혔으므로, 규칙을 적용할 자리를 하나 더 찾는 일일 뿐이다.

### 7-6. `.gitignore` 변경 — 타당하다

```
$ git ls-files '.claude/'
(출력 없음 — 추적 중인 파일 없음)

$ git check-ignore -v .claude/worktrees/agent-a350035f20903225c
.gitignore:13:.claude/worktrees/	.claude/worktrees/agent-a350035f20903225c
```

`.claude/` 아래 추적 중인 파일이 없으므로 기존 파일을 추적에서 떨어뜨리는 부작용이 없고, 규칙이 실제로 매칭됨을 확인했다. 범위도 `.claude/worktrees/`로 좁아 `.claude/settings.json` 같은 설정 파일은 나중에 추적할 수 있다. embedded repository 스테이징 사고를 막는 올바른 최소 변경이다.

### 7-7. 검증 범위 밖 / 이후 단계

- **기기 전용 6항목** — 여전히 사람의 확인이 필요하다. B1이 닫혔으므로 이제 문서를 신뢰하고 검증해도 되며, 잠금화면 리모트 커맨드는 `commands`를 확장한 구성과 기본 구성 양쪽을 시험하면 B1 수정의 실증이 된다.
- **GitHub Actions 상의 실제 CI 결과** — 로컬 재현일 뿐이다.
- **커버리지 배지의 현재 값** — `badges` 브랜치를 가져오지 않았다. 배지 파이프라인의 존재와 README 참조만 확인했다.
- **`docs/briefs/` 부재(H-3w)** — 설계상 이 리뷰 **이후** 단계이며 오케스트레이터가 직접 수행한다. 결함이 아니다. 선행 조건인 "`docs/briefs/` 밖에서의 참조 0건"은 §1-2에서 확인했다.
- **v0.5.0 이월 권고**: (1) F1의 손수 만든 마감시한 스케일, (2) `Tests/`에 남은 라운드 이력 인용 — 예: `ABPlayerControlsAutoHideTests.swift:52`의 `round3 Phase1+2 review m6`. §7 기준 4와 H-1w의 범위는 명시적으로 `Sources/`였으므로 **결함이 아니지만**, `docs/briefs/`가 아카이브되면 이 인용도 참조 불명이 된다. (3) `Package.swift`의 `.macOS(.v13)` 선언 정리(§4-3 N15). (4) §4-2의 미처리 비차단 문서 항목 N2~N9, §4-3의 N13·N14.

### 7-8. 최종 판정

세 차례에 걸쳐 제기한 차단 결함은 **B1·B2·B3·B4·R1 다섯 건이며 전부 종결됐고, 종결 여부를 매번 보고가 아니라 직접 실행으로 확인했다** — B2는 빌드된 `.doccarchive`에서, B4와 R1은 컴파일러로.

§7 완료 정의 대조:

| # | 기준 | 판정 |
|---|---|---|
| 1 | 감사 ID 해소 (E-7·G-5 이월 허용) | 충족 (§3) |
| 2 | URL 원라이너 README 첫 예제 | 충족 — 컴파일 확인 |
| 3 | 테스트 총량 증가 + 전 스위트 그린 + TSan 그린 + 커버리지 배지 | 충족 — 406 → 743, 2회 그린, TSan 그린, 배지 존재 |
| 4-a | 소스에 내부 리뷰 ID 인용 0건 | 충족 — 두 스캔 0줄 + exit=1 |
| 4-b | main에 `docs/briefs/` 부재 | 이 리뷰 이후 단계 (H-3w) |
| 5 | 최종 게이트 APPROVE | **충족** |

부수적으로, 1차 게이트가 지적한 **CI 문서 게이트의 거짓 그린**은 실질적으로 무해해졌다 — DocC 경고가 14건에서 **0건**이 됐으므로 현재 내용에 한해 게이트의 무력함이 드러날 표면이 없다. (`DOCC_WARNINGS_AS_ERRORS`가 이 부류를 승격시키지 못한다는 사실 자체는 그대로이므로, 향후 DocC 파손은 여전히 `topicSections` 덤프 같은 산출물 확인으로만 잡힌다는 점은 기억해 둘 것.)

남은 비차단 항목(F1, §4-2·§4-3의 미처리분)은 어느 것도 출하물의 정확성에 영향을 주지 않는다. F1은 태깅 전에 닫으면 좋고, 닫지 않아도 릴리스를 막지 않는다.

**v0.4.0 태깅에 대한 공학적 장애물은 없다.** 남은 것은 H-3w(사용자 결정)와 기기 수동 확인 6항목(사용자 수행)뿐이다.

FINAL-VERDICT: APPROVE
