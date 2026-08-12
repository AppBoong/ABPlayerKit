# RESULT: 트랙 C fix1

## 1. 작업 1 — VoiceOver 배지 델타

**고쳤다.**

### 택한 접근

게이트가 권고한 두 옵션 중 "뷰 쪽 호출 순서 조정"을 택했다. `ABPlayerControlsView.adjustTimelineForAccessibility(direction:)`에서, `presenter.handle(.accessibilityAdjusted(...))`를 호출해 프리젠터가 `currentPlaybackTime`을 동기적으로 전진시키기 **이전에** `presenter.currentPlaybackTime.currentTime`을 로컬 변수(`previousTime`)로 먼저 읽어둔다. 호출 후 `effects.first`가 실제로 `.renderTimeline`임을 확인한(= 조정이 진짜로 일어났음을 확인한) 다음에만, 그리고 `seekAnchor == nil`일 때만(스트리크당 1회) 이 `previousTime`을 `seekAnchor`에 대입한다.

```swift
private func adjustTimelineForAccessibility(direction: Int) {
    let previousTime = presenter.currentPlaybackTime.currentTime
    let effects = presenter.handle(.accessibilityAdjusted(direction: direction, skipInterval: configuration.skipInterval))
    guard case .renderTimeline(let newTime)? = effects.first else { return }
    if seekAnchor == nil {
        seekAnchor = previousTime
    }
    applyPresenterEffects(effects, player: player)
    ...
}
```

가드 실패(방향 0, duration 없음 등)로 조정이 실제로 일어나지 않은 호출은 `effects.first`가 `.renderTimeline`이 아니므로 `previousTime`을 읽어둔 것 자체는 버려지고 `seekAnchor`를 절대 오염시키지 않는다.

### I-C9를 어떻게 지켰는지

- **앵커는 여전히 스트리크당 정확히 1회만 스냅샷된다.** `seekAnchor == nil`일 때만 대입하는 게이트는 그대로다 — 이번 변경은 그 게이트를 통과하는 시점을 `handleSeekTargetChanged`(코어의 비동기 확인 도착 시) 하나에서, `handleSeekTargetChanged` **또는** `adjustTimelineForAccessibility`(사용자 탭 시점, 동기) 둘 중 먼저 도달하는 쪽으로 넓힌 것뿐이다. 두 진입점이 같은 `seekAnchor` 저장 프로퍼티 하나를 공유하고 같은 "nil일 때만" 조건을 지키므로, 어느 경로로 스트리크가 시작되든 앵커는 여전히 정확히 1개다.
- **Controls는 여전히 자체 누적기를 두지 않는다.** 배지 델타 계산(`CMTimeGetSeconds(target) - CMTimeGetSeconds(seekAnchor)`)은 손대지 않았다 — `target`은 여전히 코어가 방송하는 `pendingSeekTime`(즉 `seekTargetChanged`의 payload)에서만 온다. 이번 수정은 오직 **앵커를 어느 시점의 값으로 캡처하느냐**만 바꿨을 뿐, 배지 값 자체를 Controls가 스스로 더하고 있지 않다 — `previousTime`도 그냥 "지금 알고 있는 마지막 위치"를 한 번 읽은 것이지 누적기가 아니다.

### 추가한 테스트

`ABPlayerControlsSeekFeedbackTests.swift`에 3건 추가(+ 기존 1건 강화):
- `voiceOverStreakBadgeDeltaMatchesRealCumulativeMove`: 게이트가 제시한 정확한 실패 시나리오 재현 — `currentTime=100s`, `skipInterval=10s`, VoiceOver 순방향 2연타 → 1차 확인 도착 시 배지 "+10s", 2차 확인 도착 시 "+20s"(수정 전에는 "+0s"→"+10s"였을 조합).
- `voiceOverStreakBadgeNeverShowsZeroForARealMove`: 회귀 방지용 좁은 단언 — 실제 이동이 있었는데 배지가 "+0s"를 보이면 안 된다는 것만 콕 집어 확인.
- `mixedStreakSharesTheSameAnchorAcrossConsumers`: VoiceOver로 시작된 스트리크 도중 스킵 버튼 스타일(낙관적 렌더 없는) `seekTargetChanged`가 섞여 들어와도 같은 앵커를 계속 쓴다 — 세 소비자가 정말 한 메커니즘을 공유하는지 확인.
- 기존 `seekTargetConfirmationAfterAccessibilityAdjustmentAgreesOnTheFinalValue`에 `#expect(view.seekFeedbackText == "+10s")` 단언을 추가했다(이전엔 라벨 값만 확인하고 배지는 확인하지 않았다).

스킵 버튼·더블탭 경로에는 배지 델타를 단언하는 테스트가 **없었다** — 브리프 지시대로 함께 추가했다:
- `ABPlayerControlsViewTests.swift`(`ABPlayerControlsSkipWiringTests`)에 `skipButtonTapFeedsTheSharedBadgeMechanismCorrectly` 추가 — 실제 `skipForwardButton.sendActions(...)` 탭 후 코어 확인을 흉내 낸 `seekTargetChanged`를 주입해 배지가 "+10s"임을 확인.
- `ABPlayerControlsDoubleTapTests.swift`에 `doubleTapFeedsTheSharedBadgeMechanismCorrectly` 추가 — 실제 `handleDoubleTap(at:)` 호출 경로로 동일하게 확인.

### 스킵·더블탭 경로 무회귀 확인

두 경로의 프리젠터 케이스(`.skipTapped`)는 `[.send(.skip(by: interval))]`만 반환하고 `currentPlaybackTime`을 건드리지 않는다 — 이번 수정은 `adjustTimelineForAccessibility`(VoiceOver 전용 메서드) 안에서만 일어나므로 이 두 경로의 코드 경로 자체를 전혀 지나지 않는다. 신규 테스트 2건(위)이 실제 탭 경로로 배지가 여전히 정상임을 직접 확인했고, 기존 배지 관련 테스트(`firstSeekTargetShowsDeltaFromBaseline` 등, 코어 이벤트를 직접 주입해 세 경로를 대표하는 테스트)도 전부 무수정으로 계속 통과한다.

## 2. 작업 2 — D-10 Sendable

**부착 성공(Xcode 26.2 기준). 5개 타입 전부, 프리셋 `@MainActor` 제거도 함께 성립했다.**

| 타입 | 결과 |
|---|---|
| `ABPlayerControlsStyle` | `Sendable` 부착 성공 |
| `ABControlIcon` | `Sendable` 부착 성공 |
| `ABControlsBackgroundStyle` | `Sendable` 부착 성공 |
| `ABTrackCornerRadius` | `Sendable` 부착 성공 |
| `ABRateLabelStyle` | `Sendable` 부착 성공 |

`@unchecked Sendable`은 사용하지 않았다 — 5개 타입 모두 저장 프로퍼티가 이미 `Sendable`인 값 타입(`UIColor`/`UIFont`/`UIImage`/`CGSize`/`CGFloat`/`String`/열거형 등)으로만 구성돼 있어 순수 `Sendable` 부착만으로 컴파일이 통과했다.

`ABPlayerControlsStyle.default`/`.minimal`/`.tinted`의 `@MainActor` 격리도 제거했다 — 타입 자체가 `Sendable`이 되면서 더 이상 필요하지 않았고, 제거 후에도 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 하에서 경고 0건으로 컴파일된다.

**Xcode 26.2(Swift 6.2.3) 컴파일 결과**: 전체 스킴 `build`가 경고 0건으로 통과했다(로그 확인 완료). **이것은 필요조건일 뿐 확정이 아니다** — CI는 Xcode 16.4로 돌아가고, `UIColor`/`UIFont`/`UIImage`의 `NS_SWIFT_SENDABLE` 노출이 SDK 버전에 따라 다를 수 있다는 브리프의 경고를 그대로 따른다. **16.4에서의 최종 판정은 PR CI가 낸다.**

`SwiftUI/` 4파일(파일 경계상 수정 금지)이 `await ABPlayerControlsStyle.default` 같은 패턴으로 이 프리셋들을 참조하는지 확인했다 — 참조 없음(주석 언급만 2곳). 격리 제거로 인한 새 경고가 그 파일들에 생기지 않는다.

CHANGELOG에 `### Changed` 항목(Sendable 부착 + 프리셋 격리 제거)과 마이그레이션 노트(`await` 관련 경고 안내)를 추가했다.

## 3. 검증

**전체 스킴 3회 연속 그린** (증분 빌드 아님 — 매 실행 전 `.dd` 완전 삭제 후 재실행):

| 회차 | 결과 | 테스트 수 (Cache/Controls/Metrics/Core) | 실패 |
|---|---|---|---|
| RUN 1 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 322 / 8 / 250 = 652 | 0 |
| RUN 2 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 322 / 8 / 250 = 652 | 0 |
| RUN 3 | BUILD SUCCEEDED / TEST SUCCEEDED | 72 / 322 / 8 / 250 = 652 | 0 |

- **docbuild**: `DOCC_WARNINGS_AS_ERRORS=YES`로 재실행 — `BUILD DOCUMENTATION SUCCEEDED`(에러 0건). fix1 이전부터 있던 사전 존재 경고(`View`/`EnvironmentValues` 미해결 링크, diff 0줄 파일)만 남아 있고 이번 변경으로 인한 신규 경고는 없다.
- **데모 빌드**: `BUILD SUCCEEDED`, 에러 0건.
- **SwiftLint**: `swiftlint --strict` — 150개 파일, 0 violations.
- **위생 스캔**: `git diff -U0 | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(round[0-9])|(§)|...)'` 0건. `@unchecked Sendable`/`MainActor.assumeIsolated`/`@available(*, deprecated)` 신규 0건.

## 4. 회귀 여부

**기존 641건 전부 통과 + 신규 11건 추가 = 652건, 전부 그린.** 세부:

- Controls: 311건(직전 라운드 종료 시점) → **322건**(작업 1의 배지 델타 테스트 4건 신규 + 스킵/더블탭 배지 테스트 2건 신규 + 작업 2의 Sendable 컴파일 증명 테스트 6건 신규 — 단, `voiceOverAdjustmentsKeepLabelAndPresenterTimeInAgreement` 등 기존 테스트는 그대로 두고 한 건의 기존 테스트에만 단언을 추가했으므로 신규 테스트 함수 개수는 11개).
- Cache 72건, Metrics 8건, Core 250건 — 전부 무수정, 전부 통과(트랙 C는 이 타깃들의 파일을 전혀 건드리지 않았다).
- §5.2 보호 목록(`ABControlsPresenterTests.swift`, `ABControlsVisibilityMachineTests.swift`, `ABControlsLayoutTests.swift`, `ABPlayerControlsLiveStyleTests.swift`, `ABPlayerControlsInitializerAmbiguityTests.swift`, `ABControlsPlayPauseReentrancyCharacterizationTests.swift`) — `git diff --stat`으로 재확인, 전부 무수정(뒤 4개는 diff 0줄, 앞 2개는 말미 추가만이었던 지난 라운드 상태에서 이번 fix1은 손대지 않음).

## 5. 파일 경계

**수정한 파일**:
```
CHANGELOG.md
Sources/ABPlayerKitControls/Model/ABControlIcon.swift              (Sendable 부착)
Sources/ABPlayerKitControls/Model/ABPlayerControlsStyle.swift      (Sendable 부착 3종 + 프리셋 @MainActor 제거)
Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift        (adjustTimelineForAccessibility 앵커 캡처 순서)
Tests/ABPlayerKitControlsTests/ABPlayerControlsSeekFeedbackTests.swift  (배지 델타 테스트 3건 추가 + 1건 강화)
Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift     (스킵 버튼 배지 델타 테스트 1건 추가)
Tests/ABPlayerKitControlsTests/ABPlayerControlsDoubleTapTests.swift (더블탭 배지 델타 테스트 1건 추가)
```

**신규 파일**:
```
Tests/ABPlayerKitControlsTests/ABPlayerControlsStyleSendableTests.swift  (D-10 컴파일 증명 6건, 작업 1과 파일 분리)
```

지난 라운드에서 이미 존재하던 `Sources/ABPlayerKitControls/Model/ABControlsTimeLabelFormatter.swift`, `Sources/ABPlayerKitControls/Model/ABPlayerControlsConfiguration.swift`, `Sources/ABPlayerKitControls/Resources/*.lproj/Localizable.strings`, `Sources/ABPlayerKitControls/StateMachine/ABControlsPresenter.swift`, `Sources/ABPlayerKitControls/StateMachine/ABControlsVisibilityMachine.swift`, `Sources/ABPlayerKitControls/View/ABControlButton.swift`, `Sources/ABPlayerKitControls/View/ABSeekBar.swift`, `Tests/ABPlayerKitControlsTests/ABControlsPresenterTests.swift`, `Tests/ABPlayerKitControlsTests/ABControlsTimeLabelFormatterTests.swift`, `Tests/ABPlayerKitControlsTests/ABControlsVisibilityMachineTests.swift`, `Tests/ABPlayerKitControlsTests/ABPlayerControlsAccessibilityTests.swift`, `Tests/ABPlayerKitControlsTests/ABPlayerControlsRateTests.swift`의 diff는 fix1에서 추가로 건드리지 않았다(이전 라운드분 그대로).

**파일 경계 확인**: `Sources/ABPlayerKitControls/SwiftUI/` 4파일 diff 0줄, `Sources/ABPlayerKit/`·`Sources/ABPlayerKitMetrics/`·`Sources/ABPlayerKitCache/`·`Package.swift`·`.github/`·`Examples/` diff 0줄, `Tests/` 중 `ABPlayerKitControlsTests` 이외 diff 0줄 — 전부 `git diff --stat`/`git status --short`로 재확인.

**작업 1/작업 2 분리**: 작업 1은 `ABPlayerControlsView.swift`(뷰 로직)와 3개 테스트 파일만 건드렸다. 작업 2는 `ABControlIcon.swift`·`ABPlayerControlsStyle.swift`(Sendable 부착)와 신규 테스트 파일 1개만 건드렸다 — 겹치는 파일이 없어, CI가 D-10을 거부하더라도 작업 2의 두 소스 파일만 되돌리면 작업 1은 전혀 영향받지 않는다.
