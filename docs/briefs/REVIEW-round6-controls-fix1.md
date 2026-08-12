# REVIEW: 트랙 C fix1 델타 게이트

## 판정
**APPROVE**

원 게이트(`REVIEW-round6-controls.md`)의 비차단 지적 2건(VoiceOver 배지 델타, D-10 참고 데이터 미확보)에 대한 후속 작업을 델타 중심으로 직접 재검증했다. 자가 보고를 근거로 삼지 않고 부팅된 시뮬레이터에서 전체 스킴 3회를 독립 실행했고, 방금 트랙 G 게이트가 자가 보고("위생 재스캔 출력 없음")를 신뢰했다가 실제로는 `@unchecked Sendable` 1건이 남아 있어 차단됐다는 경고를 받아 이 트랙에서는 diff 기반 스캔과 전체 파일 raw 스캔을 **이중으로** 직접 실행해 재확인했다 — 0건.

---

## 1. 전체 스킴 3회 연속 (독립 재실행)

```
DEST='platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF'
xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  EXTRACT_APP_INTENTS_METADATA=NO build test
```

| 회차 | 결과 | 테스트 수 (Cache/Controls/Metrics/Core) | 실패 |
|---|---|---|---|
| RUN 1 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 322 / 8 / 250 = 652 | 0 |
| RUN 2 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 322 / 8 / 250 = 652 | 0 |
| RUN 3 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 322 / 8 / 250 = 652 | 0 |

3회 모두 652건 전부 통과(`TEST FAILED` 0건, `✘` 0건), `-only-testing` 없이 전체 스킴. 구현자 보고의 652건 수치와 일치. **원 게이트가 확인한 641건이 전부 살아 있고(Controls 311→322 = +11), 신규분만큼 늘었을 뿐 줄어들거나 실패한 것이 없다.**

- **docbuild**: `DOCC_WARNINGS_AS_ERRORS=YES`로 재실행 — `BUILD DOCUMENTATION SUCCEEDED`. 경고 6종은 원 게이트 때와 동일한 사전 존재 경고(`ABPlayerKitControls.docc/` diff 0줄, 이번에도 재확인)뿐, fix1발 신규 경고 없음.
- **데모 빌드**: `BUILD SUCCEEDED`, 에러 0건.
- **SwiftLint**: `swiftlint --strict` — **150개 파일**(원 게이트 149 + 신규 `ABPlayerControlsStyleSendableTests.swift` 1건), **0 violations**.

---

## 2. 위생 스캔 — 직접 실행, 이중 확인

**트랙 G의 경고를 그대로 받아들여 diff 기반과 전체 파일 raw 스캔을 모두 실행했다.**

```bash
git diff -U0 -- Sources Tests | grep '^+' | grep -nE '@unchecked Sendable|MainActor\.assumeIsolated|@available\(\*, deprecated'
# 0건 (exit 1)
grep -rn "@unchecked Sendable" Sources/ABPlayerKitControls/ Tests/ABPlayerKitControlsTests/
grep -rn "MainActor\.assumeIsolated" Sources/ABPlayerKitControls/ Tests/ABPlayerKitControlsTests/
```

raw 스캔에서 히트 4건이 나왔으나 **전부 `Observation/`·`SwiftUI/` 하위의 사전 존재 코드**(`ABControlsObserverRegistry.swift:6,19`, `ABPeriodicIntervalLease.swift:4`의 `@unchecked Sendable`, `ABPlayerControls.swift`의 주석 언급)였다. `git diff --stat -- Sources/ABPlayerKitControls/Observation/ Sources/ABPlayerKitControls/SwiftUI/`가 빈 출력임을 확인 — **이 트랙(원 라운드+fix1) 어느 쪽도 이 파일들을 건드리지 않았다.** fix1이 새로 추가한 `@unchecked Sendable`/`MainActor.assumeIsolated`는 **0건.**

리뷰 ID 인용 패턴(`git diff -U0 | grep '^+' | grep -nE '...'`)도 재실행 — 0건. untracked 신규 파일(`ABPlayerControlsStyleSendableTests.swift`)도 같은 패턴으로 개별 스캔 — 0건.

---

## 3. I-C9 침해 여부

`ABPlayerControlsView.swift`의 `adjustTimelineForAccessibility(direction:)`(:1067-1090)와 `handleSeekTargetChanged(_:)`(:612-637)를 직접 열람했다.

- **진입점이 둘로 늘었지만 `seekAnchor: CMTime?` 프로퍼티 하나를 공유**하고, 양쪽 모두 `if seekAnchor == nil { seekAnchor = ... }` 게이트로만 대입한다. 뷰가 `@MainActor`(UIKit 메인 스레드) 격리이므로 두 진입점이 동시에 실행될 수 없어 경합 없이 "스트리크당 정확히 1회"가 유지된다.
- **`adjustTimelineForAccessibility`의 `previousTime` 캡처는 `presenter.handle(.accessibilityAdjusted(...))` 호출 이전**, 즉 프리젠터의 낙관적 렌더가 `currentPlaybackTime`을 전진시키기 전의 값이다. 가드(`guard case .renderTimeline(let newTime)? = effects.first else { return }`)가 실패하면(조정이 실제로 일어나지 않음) `seekAnchor`를 절대 건드리지 않으므로 무효 스냅샷으로 오염될 여지가 없다.
- **배지 델타 계산 자체는 손대지 않았다** — 여전히 `CMTimeGetSeconds(target) - CMTimeGetSeconds(seekAnchor ?? target)`이고 `target`은 오직 코어가 방송하는 `seekTargetChanged`(= `pendingSeekTime`)에서만 온다. `previousTime`/`seekAnchor`는 "지금 아는 마지막 위치"를 한 번 읽어두는 스냅샷일 뿐, Controls가 스스로 델타를 더해 나가는 누적기가 아니다.

직접 수치를 대입해 검증했다: `currentTime=100s`, `skipInterval=10s` 기준 — **수정 전** 코드라면 1차 `seekTargetChanged(110)` 도착 시 앵커가 이미 전진된 110으로 스냅샷돼 델타 0("+0s"), 2차 `seekTargetChanged(120)`에서 델타 10("+10s"). **수정 후** 코드는 `adjustTimelineForAccessibility` 호출 시점에 `previousTime=100`을 먼저 캡처해 `seekAnchor=100`으로 고정하므로, 1차 델타 10("+10s"), 2차 델타 20("+20s")이 된다 — 신규 테스트(`voiceOverStreakBadgeDeltaMatchesRealCumulativeMove`)의 단언과 정확히 일치한다. **I-C9 침해 없음, 진입점 확장은 안전하다.**

---

## 4. 스킵 버튼·더블탭 경로 무회귀 + 신규 배지 델타 테스트의 실효성

- `.skipTapped` 프리젠터 케이스(`ABControlsPresenter.swift:173-174`)는 `[.send(.skip(by: interval))]`만 반환하고 `currentPlaybackTime`을 전혀 건드리지 않는다 — `adjustTimelineForAccessibility`는 VoiceOver 전용 메서드이므로 스킵 버튼·더블탭 경로는 이 변경의 코드 경로 자체를 지나지 않는다. 코드 추적으로 회귀 가능성 자체가 없음을 확인했다.
- 신규 테스트 3건(`voiceOverStreakBadgeDeltaMatchesRealCumulativeMove`, `voiceOverStreakBadgeNeverShowsZeroForARealMove`, `mixedStreakSharesTheSameAnchorAcrossConsumers`) + 기존 1건 강화(`seekTargetConfirmationAfterAccessibilityAdjustmentAgreesOnTheFinalValue`에 `seekFeedbackText == "+10s"` 단언 추가)를 `ABPlayerControlsSeekFeedbackTests.swift`에서 직접 열람 — 수치를 손으로 대입해 위 §3에서 검증한 대로 **실제로 수정 전 버그(+0s→+10s)와 수정 후 정상값(+10s→+20s)을 구분하는 진짜 회귀 테스트**임을 확인했다(우연히 통과하는 테스트가 아니다).
- 스킵 버튼·더블탭 경로에 배지 델타를 단언하는 테스트가 원래 없었다는 브리프의 지적도 사실이었고, fix1이 실제 UIKit 액션 경로로 추가했다:
  - `ABPlayerControlsViewTests.swift:765` `skipButtonTapFeedsTheSharedBadgeMechanismCorrectly` — `view.skipForwardButton.sendActions(for: .touchUpInside)` 실경로.
  - `ABPlayerControlsDoubleTapTests.swift:81` `doubleTapFeedsTheSharedBadgeMechanismCorrectly` — `view.handleDoubleTap(at:)` 실경로.
- 이 두 파일의 diff/untracked 상태를 확인해 **기존 테스트 함수는 삭제·수정 없이 신규 함수만 삽입**됐음을 검증했다: `ABPlayerControlsViewTests.swift`는 원 게이트 때와 동일하게 삭제 라인 1줄(승인된 liveMarker 치환)뿐이고, `ABPlayerControlsDoubleTapTests.swift`는 원 게이트가 기록한 18개 `@Test` 이름이 전부 그대로 남아 있고 신규 1개(`doubleTapFeedsTheSharedBadgeMechanismCorrectly`)만 삽입됐다.

---

## 5. Sendable 부착 스크루티니

`git diff -- Sources/ABPlayerKitControls/Model/ABPlayerControlsStyle.swift`와 `ABControlIcon.swift`를 직접 열람 — 5개 타입(`ABPlayerControlsStyle`, `ABControlIcon`, `ABControlsBackgroundStyle`, `ABTrackCornerRadius`, `ABRateLabelStyle`) 전부 `Sendable` 컨포먼스 추가뿐이고 **`@unchecked`는 어디에도 없다**(§2 위생 스캔과 별개로 이 두 파일만 다시 확인). 프리셋 3종(`default`/`minimal`/`tinted`)의 `@MainActor` 제거도 diff로 확인했다.

- 신규 `ABPlayerControlsStyleSendableTests.swift`(6건: 5개 타입 각각 + 프리셋 3종 통합 1건)를 직접 열람 — `Task.detached` 경계를 넘기는 실제 컴파일 증명 테스트로, 설계 §4 C-7w가 요구한 정확한 형태다. 3회 전체 스킴 그린이 이 파일의 컴파일 성공(`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 포함)을 이미 증명한다.
- `SwiftUI/` 4파일에서 `ABPlayerControlsStyle.default/.minimal/.tinted`를 실제 코드로 참조하는지 재확인 — 주석 언급 2건뿐, 실제 코드 참조 없음. 격리 제거로 인한 신규 경고가 이쪽으로 튈 여지가 없음을 확인.
- CHANGELOG diff 직접 열람 — `### Changed`에 Sendable/프리셋 격리 항목, `### Fixed`에 배지 델타 버그 항목, 마이그레이션 노트에 `@MainActor` 제거 안내가 모두 실제 파일에 반영돼 있다. 브리프 지시(§요구사항 5)대로 "26.2에서는 컴파일됨, 16.4는 CI가 판정"이라는 톤을 유지했는지 `RESULT`에서 확인 — 유지됨(§2, "이것은 필요조건일 뿐 확정이 아니다... 16.4에서의 최종 판정은 PR CI가 낸다").

---

## 6. 파일 경계 재확인

`git diff --stat` / `git status --porcelain` 직접 재실행:

- `Sources/ABPlayerKitControls/SwiftUI/` 4파일 — **diff 0줄**
- `Sources/ABPlayerKit/`, `Sources/ABPlayerKitMetrics/`, `Sources/ABPlayerKitCache/`, `Package.swift`, `.github/`, `Examples/` — **diff 0줄**
- `Tests/` 중 `ABPlayerKitControlsTests/` 이외 — **diff 0줄**
- untracked 신규 파일 — `Sources/ABPlayerKitControls/`, `Tests/ABPlayerKitControlsTests/`, `docs/briefs/` 이외 없음(`.dd/` 제외)

위반 없음.

---

## 7. 작업 1/작업 2 파일 분리 검증

CI가 D-10을 거부할 경우 작업 2만 들어낼 수 있는지 직접 파일 단위로 대조했다:

| | 작업 1 (배지 델타) | 작업 2 (Sendable) |
|---|---|---|
| 수정 소스 | `View/ABPlayerControlsView.swift`(`adjustTimelineForAccessibility` 1개 함수) | `Model/ABControlIcon.swift`, `Model/ABPlayerControlsStyle.swift`(시그니처 라인만) |
| 수정 테스트 | `ABPlayerControlsSeekFeedbackTests.swift`, `ABPlayerControlsViewTests.swift`, `ABPlayerControlsDoubleTapTests.swift` | (신규) `ABPlayerControlsStyleSendableTests.swift` |
| CHANGELOG | `### Fixed` 배지 델타 항목 | `### Changed` Sendable 항목 + 마이그레이션 노트 |

`grep -iE "seekAnchor|adjustTimeline"`을 `ABPlayerControlsStyle.swift`(작업 2 파일)에 돌려 작업 1의 개념이 섞여 있지 않음을 확인했고(히트 0건 — badge 관련 doc-comment 3줄은 **원 라운드**에서 이미 추가된 스타일 프로퍼티 주석으로, fix1과 무관함을 원 게이트 리뷰와 대조해 확인), `grep -iE "Sendable"`을 `ABPlayerControlsView.swift`(작업 1 파일)에 돌려 작업 2의 개념이 섞여 있지 않음을 확인했다(히트 0건). **두 작업은 실제로 파일 단위로 완전히 분리돼 있다** — CI가 D-10을 거부하면 `ABControlIcon.swift`/`ABPlayerControlsStyle.swift`의 `Sendable`/`@MainActor` 줄만 되돌리고 `ABPlayerControlsStyleSendableTests.swift`를 삭제하면 되며, 작업 1은 전혀 영향받지 않는다.

---

## 8. 지적 사항

없음(차단·비차단 모두).

원 게이트의 비차단 2건은 다음과 같이 해소됐다:
1. **VoiceOver 배지 델타** — 고쳤고, 코드 추적과 수치 대입으로 수정이 정확함을 검증했다. 종결.
2. **D-10 참고 데이터** — Xcode 26.2 컴파일이 실제로 통과함을 이번엔 fix1 구현자가 직접 실행해 확보했고(이 게이트도 3회 전체 스킴 그린으로 재확인), Xcode 16.4 최종 판정은 설계된 대로 PR CI로 넘긴다. 브리프의 "고치지 못하면 이월 사유를 남긴다"가 아니라 "일단 붙이고 CI가 거부하면 되돌린다"는 새 전략이 §7에서 확인한 대로 실제로 안전하게(파일 분리) 구현돼 있다. 종결.

## 9. 비차단 관찰

- `voiceOverStreakBadgeDeltaMatchesRealCumulativeMove`의 테스트명과 인라인 주석이 "이 값이 왜 이래야 하는지"(수정 전 버그 재현 경로)를 정확히 서술하고 있어, 향후 이 앵커 로직을 다시 건드릴 사람에게 회귀 방지 문서 역할을 겸한다.
- `ABPlayerControlsStyleSendableTests.swift`의 스위트 설명("컴파일이 곧 증명")이 테스트 존재 이유를 명확히 밝혀 불필요한 `#expect` 남발 없이 최소한으로 구성돼 있다.
