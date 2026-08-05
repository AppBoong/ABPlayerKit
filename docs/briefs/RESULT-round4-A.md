# RESULT: 라운드4 (A) — `ABPlayerControlsView` 분해

`docs/briefs/ROADMAP-round4.md`의 (A) 파트, WP-A1~WP-A5를 순서대로 구현한 결과다. (B) 파트(accessoryViews SwiftUI API 정리)는 지시에 따라 손대지 않았다.

**전제 조건 처리**: 착수 전 베이스라인 전체 테스트가 `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:422`의 Swift 6 격리 오류(`describe(errorLogEvent:)`가 nonisolated 컨텍스트에서 MainActor 메서드를 호출)로 실패하는 것을 발견했다. Controls 밖 파일 수정 금지 지시에 따라 직접 고치지 않고 사용자에게 보고했고, 사용자가 커밋 `0e44695`(`fix: make error log formatter nonisolated for Swift 6 strict concurrency`)로 해결한 뒤 그 HEAD에서 작업을 시작했다.

각 WP는 독립적으로 `xcodebuild -scheme ABPlayerKit-Package -destination "platform=iOS Simulator,id=<부팅된 시뮬레이터>" SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build test`로 검증했다(새 시뮬레이터 부팅 없이 기존 부팅된 `iPhone Air` 사용). 매 WP 종료 시점에 전체 4개 테스트 번들(ABPlayerKitTests/ABPlayerKitControlsTests/ABPlayerKitCacheTests/ABPlayerKitMetricsTests) 전부 `** TEST SUCCEEDED **`, 경고 0을 확인했다.

## 전체 결과 요약

| 시점 | 전체 테스트(4번들 합) | Controls 테스트 | `ABPlayerControlsView.swift` |
|---|---|---|---|
| 착수 전(베이스라인) | 330 | 110 | 1109줄 |
| WP-A1 이후 | 330 | 110 | 1109줄(dead hook 1개 삭제, 순변화 없음) |
| WP-A2 이후 | 338 | 118 | 1021줄 |
| WP-A3 이후 | 353 | 133 | 944줄 |
| WP-A4a 이후 | 368 | 148 | 962줄 |
| WP-A4b 이후 | 385 | 165 | 979줄 |
| **WP-A5(최종)** | **385** | **165** | **957줄** |

신규 프로덕션 파일 3개: `Layout/ABControlsLayout.swift`(123줄), `Model/ABControlsTimeLabelFormatter.swift`(109줄), `StateMachine/ABControlsPresenter.swift`(211줄) — 합계 443줄.

`ABPlayerControlsView.swift` **1109 → 957줄(−152줄, −13.7%)**. 로드맵이 예측한 "~620줄(−44%)"에는 못 미친다 — 아래 WP-A4b 절에 이유를 적었다(scrub 관련 3개 메서드를 의도적으로 이관하지 않았고, 재진입 안전성을 위해 `sendPlayerCommand`/`applyPresenterEffects`에 `targetPlayer` 파라미터를 명시적으로 꿰뚫는 코드가 추가됐다). 대신 목표는 "한 파일의 복잡도"와 "뷰 인스턴스 없이 도는 테스트 비율"이며 후자는 크게 초과 달성했다(아래 WP-A5 참조).

## WP-A1 — 죽은 훅 제거 + 훅 예산 기준선

- `renderedBackgroundContentView`(사용 0회 확인) 삭제.
- 나머지 훅 전수 census를 `docs/briefs/ROADMAP-round4-hook-census.md`에 기록. 최초 스캔에서 `lastVisibilityAnimationDuration`/`lastPlayPauseBounceDuration`(둘 다 `private(set) var`) 2개를 누락했다가 재검증에서 추가 — 최종 baseline은 37개 선언(오버로드 포함) · 36개 고유 식별자.
- 로드맵이 인용한 "31개" 추정치와 실측이 정확히 일치하지 않음을 문서에 명시(로드맵 자체가 "이전 시점 수치로 보인다"고 인정한 부분).

## WP-A2 — `ABControlsLayout` 추출

- Characterization 절차: `rootStackSpacing(for:)`를 임시로 `private → internal`로 승격해 실제 프로덕션 코드를 통해 리터럴 값을 캡처(수작업 재구현이 아닌 실측치 — `.default`/`.minimal` × base/AX3/XS 조합, 예: `.default` 스타일 rootStackSpacing = `-27.96142578125`). 이 값들을 이동 전/후 모두 통과하는 pinned 테스트로 고정.
- `seekBarTouchRowHeight`(static), `rootStackSpacing`, `bottomRowVisibleContentSlack`, `rateButtonBottomRowSlack`, `frameTopToInkTop`(doc 주석의 튜닝 이력 포함 원문 그대로), `timeLabelMinimumWidth(using:)`를 `ABControlsLayout`으로 순수 이동. 상수·수식 변경 없음.
- 뷰는 `private var layout: ABControlsLayout { ABControlsLayout(style: style, traitCollection: traitCollection) }`을 호출 시점마다 새로 생성(저장 프로퍼티로 캐시 금지 — R-A2 회귀 방지).
- `scaledTimeLabelFont(for:)`/`(for:compatibleWith:)`는 기존 테스트 호출부 1곳(`dynamicTypeScalingIsReal`) 때문에 이 시점엔 뷰에 얇은 delegating wrapper로 남김 — WP-A5에서 삭제(아래 참조).
- 신규 테스트 `ABControlsLayoutTests.swift` 8개: pinned 리터럴 2개, Dynamic Type pointSize pinned 6-way, `frameTopToInkTop` 클램프 경계, `.text`/`.icon` rate label 분기, AX 사이즈에서 rowHeight가 rateButton을 넘어서는 경우, `timeLabelMinimumWidth` 단조성, `seekBarTouchRowHeight` 상수.

## WP-A3 — `ABControlsTimeLabelFormatter` 추출

- `updateTimeLabels`/`formattedTime`/`fixedHoursString`/`timePlaceholder`/`accessibilityTimelineValue`의 문자열 조립 로직을 `label(elapsedSeconds:durationSeconds:)`/`accessibilityValue(elapsedSeconds:durationSeconds:)`로 이동. `CMTime` 의존성은 뷰가 호출부에서 `currentTime.isNumeric ? CMTimeGetSeconds(currentTime) : nil` 삼항 연산으로 미리 해소해 넘긴다(로드맵이 제시한 최종 형태와 동일).
- **N14 해소**: `.custom`을 `label(...)` 진입점에서 한 번만 분기하도록 만들어, 기존 `formattedTime`이 갖고 있던 도달 불가능한 `.custom` 분기를 제거했다. 완전히 제거할 수 없는 부분(`formattedTime`은 여전히 `TimeLabelFormat`의 3-케이스 스위치를 다뤄야 함)은 `assertionFailure` + 빈 문자열 폴백으로 명시적 불변조건으로 전환(침묵하는 죽은 코드 → 문서화되고 방어된 불변조건).
- stale 주석 정정(`referenceDuration`이 `.automatic`/`.custom` 둘 다에 전달된다던 주석 → `.automatic`만).
- 신규 테스트 `ABControlsTimeLabelFormatterTests.swift` 15개: `.automatic`/`.fixedHours`/`.custom` × `.elapsedOnly`/`.elapsedAndTotal`/`.elapsedAndRemaining`, `.custom`이 `timeLabelLayout` 조합을 무시하는 계약 테스트, live(`duration == nil`) 플레이스홀더, 비유한 elapsed 플레이스홀더, 음수 remaining 클램프, accessibilityValue의 독립성(어떤 `timeFormat`이든 무관).

## WP-A4a — `ABControlsPresenter` 상태 매핑 방향

- `ABControlsPresenter`(순수 값 타입, `Input`/`Effect`/`handle(_:) -> [Effect]`, `ABControlsVisibilityMachine`과 동일한 형태) 신설.
- **로드맵에 없던 발견**: `handlePlayerEvent`의 일부 분기(`itemDetached`, `sourceChanged`, `itemStatusChanged(.readyToPlay)`, `seekCompleted`)는 라이브 `player.grade`/`player.playbackTime`/`player.isScrubbing`/`player.duration`을 읽는다 — "프레젠터는 ABPlayer를 보유하지 않는다"는 설계 원칙과 정면으로 충돌한다. 이 4개 분기는 프레젠터가 순수하게 기여할 수 있는 부분만(`itemDetached`/`sourceChanged`의 `.resetTimeline`) 내주고, 나머지는 뷰에 그대로 남겨 프레젠터 effect 적용 **직후, 같은 순서로** 실행한다. `ABControlsPresenter.swift`의 타입 doc 주석에 이 경계를 명시했다.
- `replacePlayer()`의 `resetTimeline()`/`setControlsEnabled(player.grade == .current)` 호출을 `presenter.handle(.detached)`/`.attached(grade:promotesToCurrentOnPlay:)` 경유로 교체.
- 신규 테스트 `ABControlsPresenterTests.swift` 15개(상태 매핑 방향).

## WP-A4b — `ABControlsPresenter` 명령 방출 방향 (⚠️ 최대 리스크)

### 필수 선행 조사: 실제 재진입 지점 규명

로드맵의 예시("togglePlayback → player.play() → .timeControlStatusChanged → 아이콘 갱신")를 그대로 믿지 않고 소스를 직접 추적했다:

- `ABObserverRegistry.broadcast`(`Sources/ABPlayerKit/Observation/ABObserverRegistry.swift:57`)는 핸들러를 **동기적으로** 순회 호출한다.
- `ABAVPlaybackTarget`의 `timeControlStatus` KVO 핸들러(`Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:433-444`)는 실제 이벤트 전달을 `Task { @MainActor in self?.onEvent?(...) }`로 감싼다 — **항상 다음 런루프 턴에 도착**하며 동기 재진입이 아니다.
- 반면 `ABPlayer.promote(to:)` → `set(source:grade:)`는 `.gradeChanged`를 **동기적으로** broadcast한다(`Sources/ABPlayerKit/Engine/ABPlayer.swift:253`).

결론: `play()`/`pause()` 자체는 동기 재진입하지 않고, **`promote(to: .current)`만** `.gradeChanged`를 통해 동기 재진입한다. 로드맵의 예시는 부정확했다. 이 결론을 `ABControlsPlayPauseReentrancyCharacterizationTests.swift`(2개 테스트, 실제 `ABPlayer` + 실제 관찰자로 이벤트 시퀀스를 배열로 캡처)로 코드 변경 **전**에 고정했고, WP-A4b 완료 후 동일 테스트가 바이트 단위로 동일한 시퀀스를 재현함을 확인했다.

### 구현

- `togglePlayback`/`skip(by:)`/`selectRate(_:)`/`adjustTimelineForAccessibility(direction:)`를 `presenter.handle(...)` 경유로 전환. `PlayerCommand`(`.play`/`.pause`/`.promoteToCurrent`/`.skip(by:)`/`.setRate(_:)`)를 `Effect.send`로 감싸고, 뷰의 `applyPresenterEffects(_:player:)`가 `sendPlayerCommand(_:to:)`로 해석한다.
- **재진입 안전성**: `sendPlayerCommand`는 `self.player`를 다시 읽지 않고, 호출부가 `guard let player`로 고정한 참조를 명시적으로 전달받는다(`scrubbingPlayer` 고정과 동일한 이유 — 동기 재진입 중 `self.player`가 바뀌는 이론적 경우에도 안전).
- **로드맵 시그니처에서 의도적으로 벗어난 부분**(모두 근거 있음, `ABControlsPresenter.swift` doc 주석에 기록):
  - `Input.playPauseTapped`에 `allowsPromotionTap: Bool`을, `Input.accessibilityAdjusted`에 `skipInterval: TimeInterval`을 추가 — 둘 다 라이브 `configuration`/`player.source` 의존값이라 프레젠터가 자체 보유할 수 없다.
  - `Effect.emit`/`.bouncePlayPause`와 `PlayerCommand.seek`/`.beginScrubbing`/`.scrub`/`.endScrubbing`은 제공하지 않는다 — 실사용처가 없어(broadcast/bounce는 뷰가 직접 호출) 죽은 케이스가 됐을 것이다.
  - **scrubBegan/scrubChanged/scrubEnded는 이관하지 않았다.** 스크럽 명령은 `self.player`가 아니라 스크럽 시작 시점에 스냅샷한 `scrubbingPlayer`를 대상으로 해야 한다(기존 테스트 "Given a source swap during scrubbing, the session ends and no stale seek issues"가 보장하는 불변조건) — player를 보유하지 않는 `Effect`/`PlayerCommand` 쌍으로는 "지금 player가 아니라 그때 그 player"를 표현할 방법이 없다. 진행 계산에 쓰이는 `ABSeekBarGeometry.time(forProgress:duration:)`는 이미 독립적으로 순수하고 별도 테스트(`ABPresentationLogicTests`)가 있어, 주변 오케스트레이션을 그대로 둬도 잃는 것이 없다고 판단했다.
- **발견한 staleness 격차와 수정**: `.attached`의 effect는 `setEnabled`만 다룬다 — `isPlaying`/`rate`/`currentPlaybackTime`은 방금 붙은(이미 재생 중일 수 있는) 플레이어로부터 시딩되지 않은 채 구조체 초기값(`false`/`1`/`.zero`)으로 남는다. 이 상태로 `togglePlayback`이 `presenter.isPlaying`을 기준으로 분기했다면 이미 재생 중인 플레이어에 다시 `.play()`를 보내는 오류가 났을 것이다. `ABControlsPresenter.seed(isPlaying:rate:currentPlaybackTime:)`를 추가해 `replacePlayer()`에서 `.attached` 처리 직전에 호출하도록 수정. 같은 이유로 `itemStatusChanged(.readyToPlay)`/`seekCompleted`(뷰가 직접 처리하는 두 분기)가 `render(...)`를 호출한 뒤 `presenter.syncPlaybackTime(...)`도 함께 호출해, 그 직후 `adjustTimelineForAccessibility`가 프레젠터의 stale한 `currentPlaybackTime`으로 잘못된 목표 시각을 계산하지 않도록 했다.
- 신규 테스트: `ABControlsPresenterTests.swift`에 12개 추가(playPauseTapped 3, skipTapped 1, rateSelected 2, accessibilityAdjusted 4, seed 1), `ABPlayerControlsViewTests.swift`에 `ABPlayerControlsSkipWiringTests` suite 3개(스킵 버튼 탭이 실제로 옵저버 브로드캐스트에 도달하는지 — 기존에 없던 배선 검증 공백을 메움).

## WP-A5 — 훅 예산 정산

- census 재실행 결과, `scaledTimeLabelFont(for:)`/`(for:compatibleWith:)`(WP-A2에서 얇은 wrapper로 남겨뒀던 것)의 뷰 쪽 사용이 0회로 확인됨 — 유일한 호출부(`dynamicTypeScalingIsReal`)를 `ABControlsLayout(style:traitCollection:).scaledTimeLabelFont` 직접 호출로 이관하고, 두 오버로드를 뷰에서 완전히 삭제.
- **baseline 문서가 "이관 후 삭제 대상"으로 표시한 나머지 5개(`hasFixedWidthTimeLabels`, `fixedTimeLabelMinimumWidth`, `isShowingPauseIcon`, `backgroundContentAlpha`, `lastVisibilityAnimationDuration`)는 재census 결과 존치로 정정했다.** 전부 "순수 타입이 이미 검증하는 로직"이 아니라 "그 로직이 실제 UIKit 객체(제약조건 활성화, 아이콘 상태, 배경 알파, 애니메이션 duration)에 올바르게 반영됐는지"를 확인하는 배선 검증이었다 — WP-A2 설계 원칙이 이미 경고한 "순수 테스트가 이것을 대체하지 못한다"가 그대로 적용됐고, R-A5("삭제 전 census 재실행 필수")가 정확히 이 상황을 막기 위한 것이었다. 근거는 `docs/briefs/ROADMAP-round4-hook-census.md`의 WP-A5 절에 훅별로 기록.
- `displayedElapsedText`/`displayedRateText`/`controlsAreEnabled`의 "축소 대상"(8→2 등)은 낮은 우선순위로 판단해 미착수 — 삭제 대상이 아니라 여분 커버리지이므로 미착수가 회귀나 손실을 일으키지 않는다.
- **뷰 인스턴스 없이 도는 컨트롤 테스트**: `ABPlayerControlsView(...)`를 전혀 생성하지 않는 파일만 집계한 보수적 하한값 기준 **27 → 86**(목표 "70+" 상회). 신규 순수 타입 테스트만으로 50개(Layout 8 + TimeLabelFormatter 15 + Presenter 27)가 늘었다.

## 완료 정의 체크리스트 (로드맵 대비)

- [x] 전 WP에서 `xcodebuild test ... SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 통과, 경고 0
- [x] characterization 테스트 2종(레이아웃 수치, 재진입 순서)이 해당 이동보다 먼저 작성·통과
- [x] `docs/briefs/ROADMAP-round4-hook-census.md`가 WP-A1과 WP-A5 시점 수치를 모두 담음
- [ ] WP당 독립 커밋 — **커밋 금지** 지시에 따라 커밋하지 않음(사용자 확인 후 별도 진행 필요)
- (B) 트랙 관련 항목(B-0 게이트, `POLICY-api-stability.md` 등)은 이번 라운드 스코프 밖 — 손대지 않음
