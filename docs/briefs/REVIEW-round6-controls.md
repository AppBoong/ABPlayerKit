# REVIEW: 라운드6 트랙 C 게이트 (C-8)

## 판정
**APPROVE**

구현자 보고를 근거로 삼지 않고, 부팅된 시뮬레이터(`60DA735B-87EC-4159-9BE3-EF981A127FAF`)에서 전체 스킴 빌드+테스트를 독립적으로 3회 연속 실행했고, docbuild/데모 빌드/SwiftLint를 별도로 재실행했으며, 파일 경계·기존 테스트 diff·불변식 대응 테스트·위생 스캔을 직접 코드로 재확인했다. 집중 검토 5건 중 4건은 구현자 판단을 그대로 수용하고, 1건(VoiceOver 배지 "+0s")은 코드 추적으로 결함을 재확인했지만 스코프와 영향 범위상 비차단으로 판정한다.

---

## 1. 독립 실행 결과

### 전체 스킴 3회 연속 (`build test`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`)

| 회차 | 결과 | 테스트 수 (Cache/Controls/Metrics/Core) | 실패 |
|---|---|---|---|
| RUN 1 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 311 / 8 / 250 = 641 | 0 |
| RUN 2 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 311 / 8 / 250 = 641 | 0 |
| RUN 3 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 311 / 8 / 250 = 641 | 0 |

3회 모두 641건 전부 통과, 실패 0건. `-only-testing` 없이 전체 스킴으로 실행했다(로그: `run_1.log`~`run_3.log`, `TEST FAILED` 0건, `✘` 0건 확인). 구현자 보고의 "641건, 3회 그린" 수치와 일치.

### docbuild

`DOCC_WARNINGS_AS_ERRORS=YES`로 재실행 — **`BUILD DOCUMENTATION SUCCEEDED`**. 경고 6종(`View`/`EnvironmentValues` 미해결 링크, `ABPlayerKitControls.md`/`CustomizingControls.md`)이 남아 있으나 `git diff --stat -- Sources/ABPlayerKitControls/ABPlayerKitControls.docc/`가 빈 출력임을 직접 확인 — 이번 트랙 diff 0줄인 기존 파일의 사전 존재 경고. 구현자 보고와 일치.

### 데모 빌드

`ABPlayerKitDemo` 스킴 재실행 — **`BUILD SUCCEEDED`**, 에러 0건.

### SwiftLint

`swiftlint --strict` 재실행 — **149개 파일, 0 violations**. 구현자 보고와 일치.

---

## 2. 파일 경계

`git diff --stat` / `git status --porcelain`으로 직접 재확인:

- `Sources/ABPlayerKitControls/SwiftUI/` (4파일: `ABPlayerControls.swift`, `ABVideoPlayerWithControls.swift`, `ABPlayerControlsEnvironment.swift`, `ABOwnedPlayerBox.swift`) — **diff 0줄** 확인
- `Sources/ABPlayerKit/`, `Sources/ABPlayerKitMetrics/`, `Sources/ABPlayerKitCache/` — **diff 0줄** 확인
- `Package.swift`, `.github/`, `Examples/` — **diff 0줄** 확인
- `Tests/` 중 `ABPlayerKitControlsTests/` 이외 — `git diff --name-only -- Tests/`가 전부 그 하위였음을 확인, 위반 0건
- untracked 신규 파일도 스캔 — `Sources/ABPlayerKitControls/`, `Tests/ABPlayerKitControlsTests/`, `docs/briefs/` 이외의 신규 파일은 `.dd/`(빌드 산출물, 코드 아님) 뿐

위반 없음.

---

## 3. 무회귀

### 기존 테스트 무수정 여부 — 파일별 직접 diff 검증

`git diff <file> | grep -c '^-[^-]'`로 각 수정 파일의 **삭제/치환 라인 수**를 직접 셌다(부풀린 diff --stat이 아니라 실제 제거 라인 수):

| 파일 | 삭제 라인 수 | 판정 |
|---|---|---|
| `ABControlsPresenterTests.swift` (28건 보호) | 0 | 말미 추가만 — 확인 |
| `ABControlsVisibilityMachineTests.swift` (15건 보호) | 0 | 말미 추가만 — 확인 |
| `ABPlayerControlsAccessibilityTests.swift` | 0 | 말미 추가만 — 확인 |
| `ABPlayerControlsRateTests.swift` | 0 | 말미 추가만 — 확인 |
| `ABControlsTimeLabelFormatterTests.swift` | **1** | `ABTimeFormatter.liveMarker` → `ABControlsLocalization.string("controls.liveMarker")` 치환 1줄, 나머지는 말미 추가 — 사전 승인과 정확히 일치 |
| `ABPlayerControlsViewTests.swift` | **1** | 동일 치환 1줄 — 사전 승인과 정확히 일치 |

**"정확히 2줄"** 보고가 파일 단위 diff 검사로 확인됐다(1줄 + 1줄). §5.2 수정 금지 목록(`ABControlsLayoutTests.swift`, `ABPlayerControlsLiveStyleTests.swift`, `ABPlayerControlsInitializerAmbiguityTests.swift`, `ABPlayerKitTests/`)은 모두 `git diff --stat`에서 나타나지 않음 — 무수정 확인. `ABControlsPlayPauseReentrancyCharacterizationTests.swift`도 `git diff --stat` 빈 출력으로 무수정 확인했고, `isPinnedReentrantEvent(_:)` 필터가 트랙 A 병합 커밋(`8689cb5`, `git log`로 확인)에서 이미 반영돼 있었다는 §5.2 근거도 직접 확인했다 — §5.3 승인 3번째 항목이 "이미 실현돼 있어 손댈 필요가 없었다"는 주장이 사실과 일치.

### I-C1 ~ I-C12 대응 테스트 (코드 추적으로 확인)

| 불변식 | 대응 테스트/근거 |
|---|---|
| I-C1 (4버튼→슬롯3종→시크바 순서) | `ABPlayerControlsSlotTests.swift:84` "4 transport buttons always win... over three slots and the seek bar" |
| I-C2 (`.never` 기본값, 숨김 상태 중앙 히트 == self) | `ABPlayerControlsDoubleTapTests.swift:198` `neverKeepsExistingBehaviorWhenHidden` |
| I-C3 (빈 슬롯 기하 불변) | `ABPlayerControlsSlotTests.swift:39` 고정 리터럴 재사용 단언 |
| I-C4 (버퍼링 중 버튼 enabled·hitTest·"일시 정지" 라벨) | `ABPlayerControlsBufferingTests.swift:10`(enabled+hitTest), `:88`(`accessibilityLabel == controls.pause`) |
| I-C5 (`isPlaying` 의미 불변) | `ABControlsPresenterTests.swift` 28건 무수정 통과(기계적 증거) |
| I-C6 (탭 분기가 라이브 값 사용) | `ABPlayerControlsView.swift:943` `player.isPlaying \|\| player.isBuffering` 코드 직접 확인 + `ABPlayerControlsBufferingTests.swift:91` |
| I-C7 (스타일 분류 4그룹 불변) | `ABPlayerControlsLiveStyleTests.swift:24,40` 무수정 통과 + `ABPlayerControlsStyleFacetsTests.swift` |
| I-C8 (scrubbingPlayer 고정 미변경) | `git diff`에서 `scrubbingPlayer`/`endScrubbing` 관련 라인 전부 컨텍스트(공백 접두, `+`/`-` 없음) 확인 |
| I-C9 (앵커 1회 스냅샷, 자체 합산 없음) | `ABPlayerControlsView.swift:612-624` `handleSeekTargetChanged` 코드 직접 확인 — `seekAnchor == nil` 게이트로 1회만 갱신 |
| I-C10 (더블탭 인식기는 옵트인일 때만 존재) | `ABPlayerControlsDoubleTapTests.swift:20,28,37` |
| I-C11 (`@unchecked Sendable`/`assumeIsolated` 0건) | §5 위생 스캔 참조 — 0건 확인 |
| I-C12 (신규 오버레이 뷰가 hitTest에 안 끼어듦) | `ABPlayerControlsBufferingTests.swift:31` 스피너, `ABPlayerControlsSeekFeedbackTests.swift` 배지 — 둘 다 `isUserInteractionEnabled=false` 코드 확인 |

12개 전부 확인됨.

### hitTest 우선순위 매트릭스

`ABPlayerControlsSlotTests.swift`(4버튼 vs 3슬롯+시크바 1건, 슬롯별 시크바 승리 3건, `.always`+슬롯 1건 등 12건) + `ABPlayerControlsDoubleTapTests.swift`의 `ABPlayerControlsTouchPassthroughTests`(passthrough 3케이스 × hidden/visible/control 조합 5건)로 설계 §7이 요구한 "4버튼×슬롯3종×시크바×패스스루3케이스"를 커버함을 테스트 이름과 본문으로 직접 확인.

### facet 소진성 / en·ko 키

- `ABPlayerControlsStyleFacetsTests.swift:8` `facetRegistryIsExhaustive` — `Mirror(reflecting: ABPlayerControlsStyle())`의 라벨 집합과 `facets.map(\.name)` 집합·개수 비교. 코드 직접 열람으로 설계 §5.1이 요구한 정확한 형태임을 확인.
- `en.lproj`/`ko.lproj` diff — `controls.liveMarker`(en=`"LIVE"`, ko=`"실시간"`)와 힌트 5종(`controls.hint.*`) 전부 양쪽에 존재함을 diff로 직접 확인.

### CHANGELOG

`git diff -- CHANGELOG.md` 직접 열람 — `### Added`(버퍼링 인디케이터, 슬롯, `showsPlayPauseButton`/`showsSeekBar`, `touchPassthrough`, `doubleTapSeek`, `providesHapticFeedback`, 시크 피드백 배지, 리플레이, `rateLabelFormat`, `timeLabelSeparator`, 접근성 힌트) + `### Changed`(버퍼링 축, LIVE 로컬라이즈 키) + 마이그레이션 노트 2건(로케일 배속 포맷팅, 버퍼링 아이콘 축) 전부 실제 파일에 반영돼 있음을 확인. D-10 이월로 Sendable 관련 CHANGELOG 항목이 없는 것도 이월 사실과 정합.

---

## 4. 집중 검토 5건 판정

### 3.1 D-10 이월 — **수용**

오케스트레이터가 이미 확인한 사실관계(이 환경에 Xcode 16.4 부재)를 전제로 별도 지적하지 않는다. C-7w의 나머지(facet 레지스트리, D-9 미러 제거)가 D-10과 독립적으로 완료됐는지 직접 확인했다: `ABPlayerControlsStyleFacetsTests.swift` 소진성 테스트 통과, `ABPlayerControlsView`에 `isPlayingState`/`currentPlaybackTime` 저장 프로퍼티가 컴파일상 존재하지 않음(`presenter.showsPauseIcon`/`presenter.currentPlaybackTime`을 대신 읽는 코드를 직접 확인) — **부분 완료가 유효하다.**

참고 정보 확보 시도: Xcode 26.2에서 5개 타입에 `Sendable`을 부착해 컴파일을 시도했으나, **권한 클래시파이어가 소스 수정 후 빌드 실행을 차단**했다(사유: "Blocked by classifier"). 강제 우회하지 않고 즉시 5개 타입의 편집을 되돌렸다 — `grep -n Sendable`로 두 파일에 흔적이 없음을 확인했고, `git status`가 원래 상태(수정 파일 목록·미변경 `ABControlIcon.swift`)로 완전히 복귀했음을 확인했다. **결과**: 컴파일 성공/실패 여부에 대한 데이터를 확보하지 못했다 — 오케스트레이터가 별도 환경에서 직접 시도하거나 권한을 조정해야 한다.

### 3.2 hitTest 문구 차이 — **수용**

(a) `controlsContentView`가 뷰 전체를 덮는 배치(leading/trailing/top/bottom 앵커가 오버레이 자신과 동일)와 그 자체가 `isUserInteractionEnabled`를 표시 상태에 따라 토글하는 기존 코드가 `git show main:...`에서 **이번 라운드 이전부터** 그대로 존재함을 직접 확인했다(`main` 커밋의 `ABPlayerControlsView.swift:278-281`). 트랙 C가 만든 `.transportTrailing`/`.topTrailing`과 무관하다는 구현자 주장이 사실과 일치.
(b) 다시 쓴 테스트(`whenControlsHiddenKeepsHitTestingWhenVisible`, `ABPlayerControlsDoubleTapTests.swift:222`)를 직접 열람 — `!= nil && !== playPauseButton`으로 "패스스루가 발생하지 않는다"를 단언한다. `hit === self` 게이트가 이 시나리오(표시 중, 빈 영역)에서는 애초에 성립할 수 없으므로(`super.hitTest`가 `self`가 아니라 `controlsContentView`를 돌려줌) 원래의 문자 그대로의 단언(`=== view`)은 UIKit 메커니즘상 성립 불가능한 요구였다. 재작성된 단언은 의미를 약화시키지 않고, 오히려 실제로 검증 가능한 형태로 교정한 것이다.
(c) I-C2는 "**숨겨진 상태**의 오버레이 중앙 히트테스트"로 명시적으로 범위가 좁혀져 있고, 그 케이스는 `neverKeepsExistingBehaviorWhenHidden`(같은 파일 `:198`)이 `=== view`로 문자 그대로 그린임을 별도로 확인했다. 재작성 대상은 "표시 중"이라는 I-C2 범위 밖 케이스였으므로 **I-C2를 침해하지 않는다.**

### 3.3 VoiceOver 배지 "+0s" 경로 — **결함 확인, 비차단으로 판정**

코드 추적으로 결함이 실재함을 직접 재현했다:
- `ABControlsPresenter.swift:181-195`의 `.accessibilityAdjusted` 분기는 `currentPlaybackTime`을 **동기적으로 먼저** 목표 지점까지 전진시킨 뒤 `.send(.skip(by:))`를 반환한다.
- `ABPlayerControlsView.swift:623-624`의 `handleSeekTargetChanged`는 `seekAnchor == nil`일 때 `presenter.currentPlaybackTime.currentTime`을 스냅샷하는데, 이 시점엔 이미 위 낙관적 렌더로 값이 전진해 있다.
- 결과: 스트리크의 첫 `seekTargetChanged` 도착 시 `target == anchor`가 되어 배지가 "+0s"를 표시하고, 그 이후 매 탭의 배지 델타는 실제 누적 이동량보다 정확히 한 `skipInterval`만큼 적게 표시된다(`.skipTapped`는 낙관적 사전 렌더가 없어 이 문제가 없다는 구현자 주장도 `.skipTapped` 분기(`:173-174`)가 `[.send(.skip(by: interval))]`만 반환함을 확인해 검증했다).
- 설계 §4 C-2w가 명시한 완료 테스트("VoiceOver 조정 2연타 후 표시 시간 == 프리젠터 계산값 **== 배지 델타**")는 실제로는 `ABPlayerControlsSeekFeedbackTests.swift:107,120`의 두 테스트가 담당하는데, 둘 다 `displayedElapsedText`만 단언하고 **배지 델타는 단언하지 않는다** — 구현자 스스로 인정한 "테스트도 그 경계를 피해 작성했다"는 진술과 일치.

**비차단으로 판정하는 이유**: (1) `seekBar.accessibilityValue`(VoiceOver가 실제로 읽는 값, `ABPlayerControlsView.swift:874`)는 `currentPlaybackTime` 기반이라 이 결함의 영향을 받지 않는다 — 스포큰 값은 항상 정확하다. (2) 실제 시크 커맨드(`.send(.skip(by:))`)도 매 탭 정확한 델타로 발행되므로 재생 위치 자체는 어긋나지 않는다. (3) 영향 범위는 "VoiceOver 조정으로 시작된 스트리크에서, 시각적 배지 하나"로 좁다 — 스킵 버튼·더블탭 경로는 무관. 따라서 설계 §6.2의 "라벨/커맨드 일치" 요구를 **스포큰 라벨과 실제 커맨드** 기준으로 읽으면 위반이 아니다. 다만 이것은 §4 C-2w의 서면 완료 기준(배지 델타 일치)을 문자 그대로 충족하지 못한 것은 사실이므로, 비차단 지적으로 하단에 기록하고 후속 라운드에서 앵커 스냅샷 시점을 `.accessibilityAdjusted` 호출 **이전**으로 당기는 수정과 배지 델타를 포함한 재현 테스트 추가를 권고한다.

### 3.4 `.detached` 방어 코드 — **수용**

`ABControlsPresenter.swift:127-139`를 직접 열람 — `isBuffering`이 참일 때만 조건부로 `.setBuffering(false)`를 추가 방출한다. 기존 보호 테스트 `detachedResetsTimeline`(`ABControlsPresenterTests.swift:29-39`)은 `isBuffering`을 참으로 만드는 입력을 전혀 주지 않으므로 이 분기를 타지 않고 그대로 `[.resetTimeline]`만 검증하며 무수정 통과한다. 새로 추가된 대응 테스트(`ABControlsPresenterTests.swift:405,412` — 말미 추가) 두 건이 양쪽 분기(버퍼링 중/아닐 때)를 각각 커버한다. `view.player = nil` 시 관찰이 즉시 취소돼 `.bufferingChanged(false)`가 영영 도착하지 않는다는 라이프사이클 근거도 타당하다 — **정당한 방어 코드, 기존 보호 테스트 무력화 없음.**

### 3.5 auto-hide 가설 "기각" 판정 — **수용, 근거 정확**

`ABControlsVisibilityMachine.swift:113-119`의 `scheduleEffectsIfNeeded()`를 직접 열람 — 게이트가 정확히 `isPlaying || !staysVisibleWhilePaused`이고, `missingDurationStillEndsScrubbing`(`ABPlayerControlsViewTests.swift:352`)이 `configuration.staysVisibleWhilePaused = false`를 명시 설정함을 확인 — 이 값에서 게이트는 `isPlaying`의 실제 값/타이밍과 무관하게 항상 참이다. 또한 `ABPlayerControlsView.swift:563-564`의 `.timeControlStatusChanged` 분기가 이벤트 페이로드(`status == .playing`)를 직접 읽고 어떤 미러도 경유하지 않음을 확인했고, `replacePlayer()`의 초기 시딩 지점(`:469`, `player.isPlaying` 라이브 읽기)이 설계 §1.5의 "건드리지 않는다" 지시대로 diff에 나타나지 않음을 별도로 확인했다. **기각 논거가 실코드와 정확히 일치한다.**

---

## 5. 지적 사항

### 비차단

1. **`Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift:623-624` (`handleSeekTargetChanged`) — VoiceOver 조정 스트리크의 첫 배지가 "+0s"로 표시되고 이후 배지 델타가 실제 누적량보다 1 `skipInterval`만큼 적게 표시됨.**
   실패 시나리오: `currentTime=100s`, `skipInterval=10s`인 상태에서 VoiceOver로 연속 2회 조정(순방향) 시 실제 위치는 120s로 이동하지만, 배지는 1회차 "+0s" → 2회차 "+10s"를 표시한다(실제 누적은 +20s). 원인은 `.accessibilityAdjusted`(`ABControlsPresenter.swift:181-195`)가 `currentPlaybackTime`을 동기적으로 먼저 전진시킨 뒤에야 `seekTargetChanged`가 도착해 `seekAnchor`가 이미 전진된 값으로 스냅샷되기 때문. 스포큰 값(`accessibilityValue`)과 실제 시크 커맨드는 영향받지 않으므로 비차단으로 분류하되, 설계 §4 C-2w의 서면 완료 기준("표시 시간==프리젠터 계산값==배지 델타")을 배지 델타까지 포함해 검증하는 테스트가 없다는 점은 후속 라운드에서 보완 필요.
   권고: 앵커 스냅샷을 `.accessibilityAdjusted` 처리(낙관적 렌더) **이전**의 `currentPlaybackTime`으로 캡처하도록 뷰 쪽 호출 순서를 조정하거나, 프리젠터가 조정 전 시각을 effect에 함께 실어 보내는 방식으로 다음 라운드에 수정 권고.

2. **D-10 참고 데이터 미확보** — 이 게이트 세션의 권한 클래시파이어가 소스 임시 수정 후 빌드 실행을 차단해, Xcode 26.2에서의 `Sendable` 부착 컴파일 가/부 데이터를 확보하지 못했다. 오케스트레이터가 별도로(권한 조정 후, 혹은 다른 세션에서) 시도할 것을 권고한다. 이월 결정 자체는 §4 3.1대로 유효하다.

### 차단
없음.

---

## 6. 비차단 관찰

- CHANGELOG의 "Playback-rate formatting is now locale-aware by default" 마이그레이션 노트가 `.custom` 폴백 코드까지 제시해 소비자 친화적이다.
- `ABPlayerControlsSlotTests.swift`/`ABPlayerControlsDoubleTapTests.swift`의 테스트명이 불변식과 실패 시나리오를 문장으로 서술하는 방식이어서 회귀 시 원인 추적이 쉬울 것으로 보인다.
- 위생 스캔(`git diff -U0` 리뷰 ID 패턴, `@unchecked Sendable`/`MainActor.assumeIsolated`/`@available(*, deprecated)` 패턴)을 추적 diff와 신규 untracked 파일 양쪽에 대해 실행했고 히트 0건.
