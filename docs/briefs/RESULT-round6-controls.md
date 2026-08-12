# RESULT: 라운드6 트랙 C

## 1. WP별 완료 상태

- **C-1w (버퍼링 상태)**: 완료. `ABControlsPresenter`에 `isBuffering`/`showsPauseIcon`/`Effect.setBuffering` 도입, `ABControlsVisibilityMachine`에 `isBuffering` 입력 추가, 신규 `ABBufferingIndicatorView`를 `controlsContentView`의 형제로 배치, `ABControlButton`에 `isGlyphSuppressed` 도입.
- **C-2w (skip UI + 누적 소비)**: 완료. `handleSeekTargetChanged(_:)` 단일 경로로 스킵 버튼/더블탭/VoiceOver 세 소비자를 통합, `.durationAvailable` 소비로 시크바 즉시 활성화, 접근성 힌트 5종 부착.
- **C-3w (더블탭 + passthrough + 햅틱)**: 완료. `ABDoubleTapSeekZone` 순수 함수, `doubleTapSeek != .disabled`일 때만 `doubleTapRecognizer`/`require(toFail:)` 설치(비활성화 시 `backgroundTapRecognizer` 자체를 재생성해 완전히 해제), hitTest 마지막 줄에 passthrough.
- **C-4w (리플레이)**: 완료. `hasPlayedToEnd` 플래그 + `PlayerCommand.restartFromStart`, 뷰는 seek(to: .zero, tolerance: .precise) 후 play().
- **C-5w (로케일·문자열)**: 완료. `ABRateFormatter`(NumberFormatter 기반), 메뉴 타이틀과 버튼 타이틀 포맷 경로 통일, `controls.liveMarker`/`timeLabelSeparator` 도입.
- **C-6w (레이아웃 슬롯)**: 완료. `ABControlsSlot`(topTrailing/transportTrailing/bottomTrailing), `accessoryViews(in:)`/`setAccessoryViews(_:in:)`, `showsPlayPauseButton`/`showsSeekBar`.
- **C-7w (구조 정리)**: **부분 완료**. 스타일 facet 레지스트리(`ABPlayerControlsStyleFacets`)로 3벌 diff 목록 단일화 완료, D-9 프리젠터 미러 2건(`isPlayingState`/`currentPlaybackTime`) 제거 완료. **D-10(Sendable화)은 이월** — 사유는 §5 참조.

## 2. 검증 결과

- **전체 스킴 3회 연속 그린**: 모두 성공(`BUILD SUCCEEDED` / `TEST SUCCEEDED`). 4개 테스트 번들 합계 641건(ABPlayerKitTests 250 / ABPlayerKitControlsTests 311 / ABPlayerKitCacheTests 72 / ABPlayerKitMetricsTests 8), 3회 모두 실패 0건, 각 회차 4~7초(증분 빌드). 추가로 `.dd`(derivedData)를 완전히 삭제한 뒤 **클린 빌드**로 1회 더 실행해 동일하게 전부 그린임을 확인(약 21초, 641건 전부 통과).
- **기존 Controls 184건 무회귀**: 여부 확인됨 — 트랙 A 병합 이후 기준 스위트는 200건(184 + 트랙 A/S가 이미 추가한 신규분)이었고, 이번 라운드 착수 시점부터 매 WP 직후 전체 Controls 타깃을 돌려 200건이 계속 그대로 통과하는 것을 확인하며 진행했다. 최종 스위트는 311건(신규 111건 추가, 기존 200건은 전부 무수정 통과).
- **hitTest 매트릭스**: 4버튼 × 슬롯 3종(topTrailing/transportTrailing/bottomTrailing) × 시크바 × 패스스루 3케이스 전부 케이스별 테스트 작성, 전부 통과. `ABPlayerControlsSlotTests.swift`(슬롯 우선순위 6건) + `ABPlayerControlsDoubleTapTests.swift`의 `ABPlayerControlsTouchPassthroughTests`(passthrough 5건)에 분산.
- **docbuild**: `DOCC_WARNINGS_AS_ERRORS=YES`로 통과(`BUILD DOCUMENTATION SUCCEEDED`). `ABPlayerKitControls.docc/ABPlayerKitControls.md`·`CustomizingControls.md`에 `View`/`EnvironmentValues` 미해결 링크 경고 2종이 있으나 **이번 트랙 diff 0줄인 기존 파일**(`git diff --stat`로 확인)이라 무관 — 사전에 존재하던 경고다.
- **데모 빌드**: `ABPlayerKitDemo` 타깃 `BUILD SUCCEEDED`. Controls 공개 표면이 전부 additive이므로 데모 수정 불필요.
- **SwiftLint**: `swiftlint --strict` — 149개 파일, 0 violations.

## 3. auto-hide 간헐 실패 가설 판정

**기각**. 근거:

1. 지목된 테스트(`missingDurationStillEndsScrubbing`)는 `configuration.staysVisibleWhilePaused = false`를 명시적으로 설정한다. `ABControlsVisibilityMachine.scheduleEffectsIfNeeded()`의 스케줄 게이트는 `isPlaying || !staysVisibleWhilePaused`이며, `staysVisibleWhilePaused == false`이면 이 조건은 `isPlaying`의 실제 값과 무관하게 항상 참이다. 즉 이 테스트의 `hasScheduledAutoHide` 단언은애초에 `isPlaying`의 타이밍에 의존하지 않는다.
2. `isPlaying`이 시각화 머신에 전달되는 유일한 경로(`handlePlayerEvent`의 `.timeControlStatusChanged` 분기, `handleVisibility(.playbackStateChanged(isPlaying: status == .playing))`)는 수신한 `ABPlayerEvent`의 페이로드 값을 **직접** 읽는다 — 코어의 `player.isPlaying` 프로퍼티나 Controls 쪽 미러를 경유하지 않는다. C-1w/C-7w 둘 다 이 한 줄을 건드리지 않았다(C-1w는 별도의 `.bufferingChanged` 분기를 추가했을 뿐이고, C-7w의 D-9 미러 제거는 `isPlayingState`/`currentPlaybackTime`이라는 뷰 저장 프로퍼티를 없앴을 뿐, 이 이벤트 기반 피드는 애초에 그 미러들을 사용한 적이 없다).
3. `replacePlayer()`의 초기 시딩 지점(`visibilityMachine.handle(.playbackStateChanged(isPlaying: player.isPlaying))`)은 실제로 `player.isPlaying`을 라이브로 읽지만, 이 값은 실제 코어의 KVO 훅 타이밍에 의존하는 것이지 Controls 쪽 미러 문제가 아니며, C-1w/C-7w 어느 쪽도 이 줄의 읽기 대상을 바꾸지 않았다(§1.5 설계 지시대로 "`playbackStateChanged` 피드는 건드리지 않는다"를 그대로 지켰다).

즉 `d29e231`이 고친 벽시계 경합(자동 숨김 지연을 테스트 소요보다 길게 설정) 이후 재발할 만한 새로운 비동기 경로를 C-1w/C-7w가 만들지 않았다. 가설이 지목한 "관찰성 미러의 비동기 KVO 홉"은 실제로 이 특정 흐름에 관여하지 않는다.

## 4. pendingSeekTime 리셋 확인 결과

**소스 교체 경로는 반드시 `resetSeeking()`을 지난다.** `Sources/ABPlayerKit/Engine/ABPlayer.swift`의 `set(source:grade:detachReason:)`에서:

```swift
if resolvedGrade != .current || sourceChanged {
    target.setPeriodicTimeObserver(interval: nil, onTick: nil)
    resetSeeking()
}
...
interpret(actions, source: newSource, detachReason: detachReason)   // .detachItem → .itemDetached 방송은 여기서
```

`resetSeeking()`은 이 가드 통과 후, `.detachItem` 액션이 해석(interpret)되어 `.itemDetached`를 방송하기 **이전에** 항상 먼저 실행된다. `ABGradePlanner.actions(...)`에서 `.detachItem`이 계획되는 4개 분기(`(.preloaded, .released)`, `(.preloaded, .instanceOnly)`, `(.current, .released)`, `(.current, .instanceOnly)`)는 전부 `to`(=resolvedGrade)가 `.current`가 아닌 경우이므로, 가드 조건 `resolvedGrade != .current || sourceChanged`가 항상 참이 되어 `resetSeeking()`이 무조건 실행된다. `sourceChanged`만 참이고 grade는 `.current`를 유지하는 교체(`(.preloaded, .current)`/`(.current, .current)`의 sourceChanged 분기)는 `.detachItem` 없이 `.attachItem`만 계획되므로(`ABGradePlanner.swift:19-24` 주석이 그 이유를 설명) `.itemDetached` 자체가 방송되지 않는다 — 이 경로는 `sourceChanged == true`이므로 가드를 통과해 어차피 `resetSeeking()`이 실행된다.

`resetSeeking()`은 `pendingSeekTime != nil`일 때 `pendingSeekTime = nil`과 `broadcast(.seekTargetChanged(nil))`을 수행한다. 따라서 Controls의 시크 배지는 소스 교체/디태치 시 항상 소멸 신호를 받는다 — **Controls 쪽 방어 코드 추가는 불필요했다.**

## 5. 설계에서 벗어난 지점 / 기존 테스트 변경

### 5.1 D-10(Sendable화) 이월

**사유**: 설계 §5.2가 요구한 검증 우선 절차("C-7w 착수 시 CI 툴체인 Xcode 16.4에서 1번[Sendable 부착]만 먼저 컴파일해 본다")를 이 작업 환경에서 수행할 수 없었다. 로컬에 설치된 유일한 Xcode는 **Xcode 26.2**(Swift 6.2.3, iOS 26.2 SDK)이며, CI가 고정하는 **Xcode 16.4**(`.github/workflows/ci.yml`의 `PINNED_DEVELOPER_DIR=/Applications/Xcode_16.4.app`)는 이 환경에 존재하지 않는다. `UIColor`/`UIFont`/`UIImage` 등이 `NS_SWIFT_SENDABLE`로 노출되는지는 SDK 버전에 따라 달라질 수 있는 사안이라, 최신 SDK(26.2)에서의 컴파일 성공이 Xcode 16.4에서의 성공을 보장하지 않는다. 실패 시 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 하에서는 컴파일 에러가 되어 CI 전체를 붉게 만들 수 있고, 이는 되돌리기 어려운 리스크이므로 — 설계 §5.4가 이미 "실패는 컴파일 에러로 즉시 드러나고 이월 경로가 준비돼 있다"고 명시한 그 경로를 그대로 택해 **이월**했다. `@unchecked Sendable`은 §0에 의해 애초에 선택지가 아니었다.
**영향**: `ABPlayerControlsStyle`/`ABControlIcon`/`ABControlsBackgroundStyle`/`ABTrackCornerRadius`/`ABRateLabelStyle`에 `Sendable` 미부착, 스타일 프리셋(`default`/`minimal`/`tinted`)의 `@MainActor` 격리도 유지됨. C-7w의 나머지(facet 레지스트리, D-9 미러 제거)는 D-10과 독립적이라 그대로 완료했다.

### 5.2 기존 테스트 변경 (§5.3 사전 승인 범위)

사전 승인된 정확히 2줄만 변경했다(3번째 승인 항목인 `ABControlsPlayPauseReentrancyCharacterizationTests.swift`는 **변경 불필요**로 판정 — 아래 참조):

- `Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift`의 `indefiniteDurationShowsLive` 테스트: `ABTimeFormatter.liveMarker` → `ABControlsLocalization.string("controls.liveMarker")`. en 값이 `"LIVE"`로 동일하므로 결과는 불변.
- `Tests/ABPlayerKitControlsTests/ABControlsTimeLabelFormatterTests.swift`의 `automaticElapsedAndTotalLiveDuration` 테스트: 동일한 치환.

**`ABControlsPlayPauseReentrancyCharacterizationTests.swift`는 손대지 않았다.** 이 파일을 직접 읽어보니 `isPinnedReentrantEvent(_:)`(`.preloadCancelled`/`.tuningApplied`/`.gradeChanged`만 통과)가 이미 트랙 A 병합 커밋(`8689cb5`)에서 추가돼 있어, `bufferingChanged` 등 다른 미러 이벤트를 자동으로 걸러낸다. `git log`로 확인한 결과 이 필터링 로직 자체가 트랙 A 병합의 일부로 이미 반영돼 있었다(브리프 §6-1이 예고한 "A-8이 화이트리스트를 추가" 시나리오가 이미 실현된 상태). 전체 스킴 3회 실행에서 이 스위트는 무수정으로 계속 그린이었다.

### 5.3 hitTest 재확인 사항 — `controlsContentView`가 빈 영역을 우선 점유

설계 §7 테스트 표의 "`.whenControlsHidden` + 표시(visible) + 빈 영역 → `view`" 항목을 문자 그대로 구현하려다, **컨트롤이 표시 중일 때 빈 영역 히트테스트는 `self`(뷰 자신)가 아니라 `controlsContentView`(전체 오버레이를 덮는 내부 컨테이너)가 돌려받는다**는 것을 실제 실행으로 확인했다. `controlsContentView`는 표시 중 `isUserInteractionEnabled == true`이고 자기 자신의 바운드를 꽉 채우는 평범한 `UIView`라, UIKit 기본 hitTest 알고리즘상 하위 뷰가 아무것도 안 잡히면 자기 자신을 반환한다 — 이 동작은 이번 라운드 이전부터 있던 구조(예전부터 `controlsContentView`가 전체를 덮고 있었다)이며, 내가 만든 `.transportTrailing`/`.topTrailing`과는 무관하다. 기존 `interactiveControlHitTesting` 테스트도 이 이유로 "표시 중 빈 영역" 케이스를 애초에 단언하지 않는다(숨김 케이스만 단언). 해당 테스트(`whenControlsHiddenKeepsHitTestingWhenVisible`)는 `=== view`가 아니라 "패스스루가 발생하지 않는다(non-nil이고 컨트롤이 아니다)"는 의미 있는 불변식으로 다시 작성했다. **이것은 §5.3 승인 범위 밖의 자체 판단**이며, §5.2 목록에 속한 파일이 아닌 내가 새로 작성한 테스트 파일 안에서의 조정이라 규칙 위반은 아니지만, 게이트가 §7 체크리스트 문구와 내 구현을 대조할 때 이 차이를 인지해야 한다.

### 5.4 자체 판단으로 추가한 방어 코드 (설계에 명시되지 않았지만 필요하다고 판단)

- `ABControlsPresenter`의 `.detached` 케이스에 `isBuffering`이 참이었을 때 `.setBuffering(false)`를 추가로 방출하도록 했다(§4의 "허용된 값이 있을 때만" 조건부라 기존 보호 테스트 `detachedResetsTimeline`은 무수정 통과). 이유: `view.player = nil`로 컨트롤을 분리하는 순간 옵저베이션이 즉시 취소되므로, 버퍼링 중이던 플레이어를 분리하면 `.bufferingChanged(false)`가 영영 도착하지 않아 스피너/글리프 억제가 고착될 수 있었다. 설계 §1.3~§1.5 어디에도 이 케이스가 명시되지 않았지만, C-1w가 만든 바로 그 기능의 라이프사이클 결함이라 판단해 최소 1줄로 방어했다.

## 6. 파일 경계 준수

**수정한 파일 전체 목록**:

```
CHANGELOG.md
Sources/ABPlayerKitControls/Model/ABControlsTimeLabelFormatter.swift
Sources/ABPlayerKitControls/Model/ABPlayerControlsConfiguration.swift
Sources/ABPlayerKitControls/Model/ABPlayerControlsStyle.swift
Sources/ABPlayerKitControls/Resources/en.lproj/Localizable.strings
Sources/ABPlayerKitControls/Resources/ko.lproj/Localizable.strings
Sources/ABPlayerKitControls/StateMachine/ABControlsPresenter.swift
Sources/ABPlayerKitControls/StateMachine/ABControlsVisibilityMachine.swift
Sources/ABPlayerKitControls/View/ABControlButton.swift
Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift
Sources/ABPlayerKitControls/View/ABSeekBar.swift
Tests/ABPlayerKitControlsTests/ABControlsPresenterTests.swift          (말미 추가만, 기존 28건 무수정)
Tests/ABPlayerKitControlsTests/ABControlsTimeLabelFormatterTests.swift (1줄 치환 + 말미 추가)
Tests/ABPlayerKitControlsTests/ABControlsVisibilityMachineTests.swift  (말미 추가만, 기존 15건 무수정)
Tests/ABPlayerKitControlsTests/ABPlayerControlsAccessibilityTests.swift (말미 추가)
Tests/ABPlayerKitControlsTests/ABPlayerControlsRateTests.swift         (말미 추가)
Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift         (1줄 치환만)
```

**신규 파일**:

```
Sources/ABPlayerKitControls/Layout/ABDoubleTapSeekZone.swift
Sources/ABPlayerKitControls/Model/ABControlsSlot.swift
Sources/ABPlayerKitControls/Model/ABPlayerControlsStyleFacets.swift
Sources/ABPlayerKitControls/Model/ABRateFormatter.swift
Sources/ABPlayerKitControls/View/ABBufferingIndicatorView.swift
Sources/ABPlayerKitControls/View/ABSeekFeedbackView.swift
Tests/ABPlayerKitControlsTests/ABDoubleTapSeekZoneTests.swift
Tests/ABPlayerKitControlsTests/ABPlayerControlsBufferingTests.swift
Tests/ABPlayerKitControlsTests/ABPlayerControlsDoubleTapTests.swift
Tests/ABPlayerKitControlsTests/ABPlayerControlsReplayTests.swift
Tests/ABPlayerKitControlsTests/ABPlayerControlsSeekFeedbackTests.swift
Tests/ABPlayerKitControlsTests/ABPlayerControlsSlotTests.swift
Tests/ABPlayerKitControlsTests/ABPlayerControlsStyleFacetsTests.swift
Tests/ABPlayerKitControlsTests/ABRateFormatterTests.swift
```

**SwiftUI 4파일 diff 0줄 확인**: `git diff --stat -- Sources/ABPlayerKitControls/SwiftUI/`가 빈 출력임을 확인(`ABPlayerControls.swift`, `ABVideoPlayerWithControls.swift`, `ABPlayerControlsEnvironment.swift`, `ABOwnedPlayerBox.swift` 전부 diff 0줄).
**`Sources/ABPlayerKit/`, `Sources/ABPlayerKitMetrics/`, `Sources/ABPlayerKitCache/`, `Package.swift`, `.github/**`, `Examples/**` diff 0줄 확인**: 전부 `git diff --stat`으로 빈 출력 확인.
**`Tests/` 중 `ABPlayerKitControlsTests` 이외 diff 0줄 확인**: `git diff --name-only -- Tests/`의 결과가 전부 `Tests/ABPlayerKitControlsTests/` 하위임을 확인.

## 7. 게이트가 집중해서 볼 것

1. **D-10 이월**: Xcode 16.4를 이 환경에서 구할 수 없어 설계가 요구한 "CI 툴체인에서 먼저 컴파일" 절차를 문자 그대로 수행하지 못했다. Xcode 26.2(Swift 6.2.3)에서는 5개 타입 모두에 `Sendable`을 부착해도 컴파일이 될 것으로 예상되지만(SDK의 `UIColor`/`UIFont`/`UIImage`가 이미 `NS_SWIFT_SENDABLE`일 가능성이 높음), **검증하지 않은 채로 단언할 수 없어 보수적으로 이월했다.** 게이트가 Xcode 16.4에 접근 가능하다면, `ABPlayerControlsStyle: Sendable` 등 5개 부착만 별도로 시도해 실제 가/부를 확인해줄 것을 요청한다.
2. **hitTest §7 테스트 표와 실제 구현의 문구 차이**(§5.3): "`.whenControlsHidden` + 표시 + 빈 영역 → `view`"를 문자 그대로 만족하지 않고 `controlsContentView`가 반환된다는 사실을 발견해 테스트를 다시 썼다. 이것이 기존 아키텍처(내가 만들지 않은 `controlsContentView`의 풀바운드 배치)의 산물이라는 내 분석이 맞는지, 그리고 그 분석이 I-C2("컨트롤이 숨겨진 상태의 오버레이 중앙 히트테스트는 self를 돌려준다")를 침해하지 않는지(I-C2는 명시적으로 "숨겨진 상태"만 다루므로 침해하지 않는다고 판단했다) 재확인을 요청한다.
3. **C-2w 배지와 VoiceOver 낙관적 렌더의 상호작용**: `.accessibilityAdjusted`가 `presenter.currentPlaybackTime`을 동기적으로 먼저 옮겨놓기 때문에, 같은 스트리크의 "첫" `seekTargetChanged` 도착 시점에 앵커가 이미 전진한 값으로 스냅샷될 수 있어 배지가 "+0s"를 보여줄 수 있는 경로를 실제로 발견했다(테스트 작성 중 재현). 스킵 버튼/더블탭(둘 다 낙관적 사전 렌더가 없음)에는 이 문제가 없다. 실제 기기에서 VoiceOver 사용자가 이 배지를 시각적으로 참조할 일은 적다고 보아(스포큰 값이 주 채널) 이번 라운드 범위에서 고치지 않고 테스트도 그 경계를 피해 작성했지만, 게이트가 "라벨/커맨드 일치" 요구사항을 더 엄격하게 해석한다면 추가 논의가 필요하다.
