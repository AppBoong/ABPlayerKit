# ROADMAP-round4 훅 census

`ABPlayerControlsView`의 internal(비-`public`, 비-`private`) 멤버 — 즉 프로덕션 코드에는 필요 없고 테스트 접근을 위해 접근 수준을 완화한 "테스트 훅" — 사용 횟수 census다. WP-A1에서 최초 측정(baseline), WP-A5에서 재측정(final)해 두 시점을 모두 이 문서에 남긴다.

측정 방법: `grep -rn '\b<식별자>\b' Tests Examples | grep -v ABPlayerControlsView.swift | wc -l` — 선언부 자체를 제외한 `Tests/`, `Examples/` 전체에서의 참조 횟수(테스트 파일 간 우발적 동명 식별자 충돌 가능성이 낮은 이름들이라 실사용 근사치로 채택).

## WP-A1 시점 (baseline, 2026-08-05, HEAD `0e44695`)

`ABPlayerControlsView.swift` 1109줄 기준. 실측 결과 아래 36개 internal 멤버(오버로드 2종 포함, 서로 다른 선언 37개)가 존재했다 — 로드맵 문서의 "31개" 추정치와 정확히 일치하지는 않으나(문서 자체가 "이전 시점 수치로 보인다"고 명시), 실제 코드베이스 기준 census는 아래와 같다. (최초 스캔에서 `private(set) var lastVisibilityAnimationDuration`/`lastPlayPauseBounceDuration` 2개가 누락되었다가 재검증에서 추가됨.)

### 삭제 대상 — 사용 0회

| 훅 | 종류 | 사용 횟수 | 처리 |
|---|---|---|---|
| `renderedBackgroundContentView` (구 :88) | 계산 접근자 | **0** | **WP-A1에서 삭제 완료** — `ABControlsBackgroundViewTests`는 `ABControlsBackgroundView.renderedContentView`를 직접 참조하므로 이 뷰 레벨 위임 접근자는 불필요했다 |

### 존치 — 사용 1회 이상 (구동 시임 / 배선 검증 / 계산 위임)

| 훅 | 종류 | 사용 횟수 | 분류 |
|---|---|---|---|
| `seekBar` | 저장 프로퍼티 | 66 | 구동 시임 |
| `rateButton` | 저장 프로퍼티 | 28 | 구동 시임 |
| `playPauseButton` | 저장 프로퍼티 | 24 | 구동 시임 |
| `handlePlayerEvent(_:)` | 메서드 | 23 | 구동 시임 |
| `skipBackwardButton` | 저장 프로퍼티 | 11 | 구동 시임 |
| `skipForwardButton` | 저장 프로퍼티 | 11 | 구동 시임 |
| `displayedElapsedText` | 계산 접근자 | 8 | 축소 대상(WP-A5) |
| `controlsAreEnabled` | 계산 접근자 | 7 | 축소 대상(WP-A5) |
| `handleVisibility(_:animated:)` | 메서드 | 6 | 구동 시임 |
| `renderedSeekBarFrame` | 계산 접근자 | 5 | 배선 검증 |
| `hasScheduledAutoHide` | 계산 접근자 | 5 | 구동 시임 보조 |
| `styleLayoutInvalidationCount` | 저장 프로퍼티(`private(set)`) | 5 | 구동 시임 보조 |
| `displayedRateText` | 계산 접근자 | 4 | 축소 대상(WP-A5) |
| `elapsedLabel` | 저장 프로퍼티 | 3 | 구동 시임 |
| `lastPlayPauseBounceDuration` | 저장 프로퍼티(`private(set)`) | 3 | 구동 시임 보조 |
| `controlsContentAlpha` | 계산 접근자 | 3 | 구동 시임 보조 |
| `displayedPlayPauseImage` | 계산 접근자 | 2 | 구동 시임 보조 |
| `isVoiceOverRunningProvider` | 저장 프로퍼티(주입 시임) | 2 | 구동 시임 |
| `isReduceMotionEnabledProvider` | 저장 프로퍼티(주입 시임) | 2 | 구동 시임 |
| `controlsContentIsInteractive` | 계산 접근자 | 2 | 구동 시임 보조 |
| `renderedBackgroundGradientLayer` | 계산 접근자 | 2 | 배선 검증 |
| `hasFixedWidthTimeLabels` | 계산 접근자 | 2 | 이관 후 삭제 대상(WP-A2 완료 후) |
| `renderedTransportControlsFrame` | 계산 접근자 | 2 | 배선 검증 |
| `renderedSeekBarVisibleTrackFrame` | 계산 접근자 | 2 | 배선 검증 |
| `renderedBottomRowFrame` | 계산 접근자 | 2 | 배선 검증 |
| `renderedTimeLabelFrame` | 계산 접근자 | 2 | 배선 검증 |
| `selectRate(_:)` | 메서드 | 2 | 구동 시임 |
| `simulateBackgroundTap()` | 메서드 | 2 | 구동 시임 |
| `isShowingPauseIcon` | 계산 접근자 | 1 | 이관 후 삭제 대상(WP-A2/A4 완료 후) |
| `backgroundContentAlpha` | 계산 접근자 | 1 | 이관 후 삭제 대상 |
| `fixedTimeLabelMinimumWidth` | 계산 접근자 | 1 | 이관 후 삭제 대상 |
| `lastVisibilityAnimationDuration` | 저장 프로퍼티(`private(set)`) | 1 | 이관 후 삭제 대상 |
| `renderedRateButtonFrame` | 계산 접근자 | 1 | 배선 검증 |
| `renderedRateButtonVisibleContentFrame` | 계산 접근자 | 1 | 배선 검증 |
| `scaledTimeLabelFont(for:)` / `scaledTimeLabelFont(for:compatibleWith:)` | 메서드(오버로드 2종) | 1 | **WP-A2에서 `ABControlsLayout`으로 이관 후 삭제 대상** |

**baseline 합계**: 37개 선언(오버로드 포함) · 36개 고유 식별자 · 사용 0회 1개(`renderedBackgroundContentView`, WP-A1에서 삭제) · 뷰 인스턴스 없이 도는 컨트롤 테스트 비율은 WP-A5에서 별도 측정.

## WP-A5 시점 (final, WP-A2~A4b 완료 후 재측정)

### 실제로 삭제된 훅 — 1개

| 훅 | 근거 |
|---|---|
| `scaledTimeLabelFont(for:)` / `scaledTimeLabelFont(for:compatibleWith:)` | 재census 결과 뷰 쪽 사용 0회 확인(유일한 호출부였던 `ABPlayerControlsViewTests.dynamicTypeScalingIsReal`을 `ABControlsLayout(style:traitCollection:).scaledTimeLabelFont` 직접 호출로 이관). 두 오버로드 전부 삭제. |

### baseline에서 "이관 후 삭제 대상"으로 표시됐으나 — 재census 결과 존치

WP-A1 시점엔 아직 실제 추출이 끝나지 않아 "이 로직이 순수 타입으로 옮겨가면 이 훅도 지울 수 있을 것"이라는 **예측**으로 분류됐다. WP-A2~A4b를 실제로 마친 뒤 재측정한 결과, 아래 5개는 예측과 달리 **삭제하면 안 되는 것으로 판명**됐다 — 전부 "새로 만든 순수 타입이 이미 검증하는 로직"이 아니라 "그 로직이 실제 UIKit 객체(제약조건, 아이콘 상태, 배경 뷰 알파, 애니메이션 duration)에 올바르게 반영됐는지"를 확인하는 **배선 검증**이었기 때문이다 — WP-A2 설계 원칙이 이미 명시한 "순수 테스트가 이것을 대체하지 못한다"가 그대로 적용된다.

| 훅 | 사용 횟수 | 실제로 검증하는 것 | 대체 불가능한 이유 |
|---|---|---|---|
| `hasFixedWidthTimeLabels` | 2 | `elapsedMinimumWidthConstraint.isActive`가 `style.usesFixedWidthTimeLabels`를 따라 실제로 켜지고 꺼지는지(`ABPlayerControlsLiveStyleTests`) | `ABControlsLayout.timeLabelMinimumWidth(using:)`는 폭 **값**만 계산한다 — 제약조건이 실제로 활성화되는지는 `updateTimeLabelWidthConstraints`(뷰 전용 로직)의 몫 |
| `fixedTimeLabelMinimumWidth` | 1 | 위와 같은 테스트에서 활성화된 제약조건의 실제 `constant` 값 | 위와 동일 |
| `isShowingPauseIcon` | 3 (WP-A4b에서 작성한 재진입 characterization 테스트 2개 포함) | `ABControlsPresenter.Effect.setPlaybackIcon`이 뷰의 `isPlayingState`/아이콘 갱신으로 실제 반영되는지 | `ABControlsPresenterTests`는 `presenter.isPlaying`(순수 상태)만 검증한다 — 그 값이 실제 뷰 프로퍼티·아이콘 이미지로 배선됐는지는 별개 사실이고, 이 훅이 바로 그 배선 자체를 검증한다 |
| `backgroundContentAlpha` | 1 | `controlsBackgroundView.alpha`가 가시성 상태를 따르는지(`ABControlsBackgroundViewTests`) | 라운드4 추출 대상(Layout/TimeLabelFormatter/Presenter) 어느 것과도 무관 — `ABControlsVisibilityMachine`(기존 순수 타입) 관련 배선이며애초에 이번 라운드가 건드리지 않는 영역이다 |
| `lastVisibilityAnimationDuration` | 1 | Reduce Motion 시 애니메이션 duration이 실제로 0이 되는지(`ABPlayerControlsAccessibilityTests`) | 위와 동일 — visibility 관련, 라운드4 추출과 무관 |

**결론**: baseline 문서의 "이관 후 삭제 대상" 5개 표시는 실제 추출 전 예측이었고, 정확하지 않았다. R-A5("훅을 과하게 지워 커버리지 상실... 삭제 전 census 재실행 필수")가 예방하려던 바로 그 상황이며, 재census가 정확히 그 안전장치로 작동해 5개 모두 존치로 정정됐다.

### "축소 대상"(displayedElapsedText/displayedRateText/controlsAreEnabled) — 미착수

`displayedElapsedText`(8회) 중 다수가 `.automatic`/`.fixedHours`/`.custom` 포맷 조합을 검증하는데, 그 순수 로직은 이제 `ABControlsTimeLabelFormatterTests`(15개)에 이미 중복 커버되어 있다 — 이 테스트들을 "레이블 텍스트가 실제로 갱신되는지" 확인하는 1~2개의 배선 테스트로 축소하는 작업은 정확도상 안전하지만(각 케이스를 하나씩 재분류해야 함), 라운드4 예산 안에서 우선순위가 낮다고 판단해 **미착수**로 남긴다. `displayedRateText`/`controlsAreEnabled`도 동일 사유. 이 세 훅 모두 삭제 대상이 아니라 "순수 테스트로 커버리지를 옮긴 뒤에도 남겨도 되는 여분"이므로, 미착수가 회귀나 커버리지 손실을 일으키지 않는다.

### 뷰 인스턴스 없이 도는 컨트롤 테스트 비율

`ABPlayerControlsView(...)`를 전혀 생성하지 않는 테스트 파일만 집계한 **보수적** 하한값(일부 혼합 파일의 개별 view-free 테스트는 포함하지 않음):

| 파일 | 테스트 수 |
|---|---|
| `ABControlButtonTests` | 6 |
| `ABControlsLayoutTests` (신규, WP-A2) | 8 |
| `ABControlsTimeLabelFormatterTests` (신규, WP-A3) | 15 |
| `ABControlsPresenterTests` (신규, WP-A4a+b) | 27 |
| `ABControlsVisibilityMachineTests` (기존) | 15 |
| `ABPlayerControlsConfigurationTests` | 2 |
| `ABPlayerControlsStyleTests` | 3 |
| `ABPlayerKitControlsLinkTests` | 1 |
| `ABSeekBarTests` | 6 |
| `ABVideoPlayerWithControlsTests` | 3 |
| **합계** | **86 / 165** (Controls 전체 테스트 수, WP-A1 시점 110 → WP-A5 시점 165) |

목표 "27 → 70+"를 상회(86, 하한값 기준). 신규 순수 타입 테스트만으로 50개(8+15+27)가 늘었다.
