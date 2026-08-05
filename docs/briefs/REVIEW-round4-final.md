# REVIEW: 라운드4 최종 게이트 리뷰

- **대상 범위**: `4be7135..HEAD` (7커밋 — minors 2 + 격리 수정 1 + Controls 분해 2 + accessoryViews B트랙 2)
- **대조 기준**: `docs/briefs/ROADMAP-round4.md`, `docs/briefs/REVIEW-round3-final.md`
- **판정**: **REQUEST-CHANGES**

## 대상 커밋

```
5f6c53e docs: revise Q6 decision and add API stability policy
49e2b11 feat: add ViewBuilder accessory API with hosting box; deprecate UIView initializers
93c72a4 docs: record controls decomposition results and hook census
9141829 refactor: decompose ABPlayerControlsView into layout, formatter and presenter
0e44695 fix: make error log formatter nonisolated for Swift 6 strict concurrency
555dc34 test: cover passthrough chunking, observation and interruption gates
f806f68 fix: tighten audio session reactivation and cache metadata lifecycle
```

## 실측 검증

```
xcodebuild test -scheme ABPlayerKit-Package -destination 'id=65CDD0F3-…' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
→ 399 tests / 0 failures / 0 warnings   (373 → 399, +26)
```

CI 게이트와 동일한 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`로 돌려 deprecation 도입 후에도 내부 잔존 사용이 0건임을 확인했다 — WP-B3의 최대 리스크(R-B1)는 실측으로 해소됐다.

| 파일 | 줄 수 |
|---|---|
| `View/ABPlayerControlsView.swift` | 1109 → **957** (−152, −14%) |
| `Layout/ABControlsLayout.swift` | +123 |
| `Model/ABControlsTimeLabelFormatter.swift` | +109 |
| `StateMachine/ABControlsPresenter.swift` | +211 |
| `SwiftUI/ABAccessoryHostingBox.swift` | +85 |

---

# Major

## MJ-1. N1 dirty 플래그가 기본 설정(`interruptionPolicy: .ignore`)에서 M1 버그를 재도입한다

`Sources/ABPlayerKit/Engine/ABPlayer.swift` — `handleInterruptionBegan()`

```swift
private func handleInterruptionBegan() {
    guard configuration.interruptionPolicy != .ignore else { return }   // ← 여기서 반환
    audioSessionActivationDirty = true                                  // ← 도달 못 함
    …
}
```

가드가 dirty 설정보다 **먼저** 있다. dirty 플래그는 "세션이 비활성화됐을 수 있다"는 **세션 상태**에 관한 사실인데, "인터럽션 시 일시정지/재개할 것인가"라는 **정책**으로 게이트돼 있다. 둘은 독립적인 관심사다.

**재현 (전부 기본값 + `audioSessionPolicy` 옵트인만)**

1. `audioSessionPolicy = .playback(mixWithOthers: false)`, `interruptionPolicy = .ignore`(**기본값**), `pausesOnRouteChangeDeviceUnavailable = true`(**기본값**)
2. `.current` 승격 → `apply(force: true)` 성공 → `audioSessionActivationDirty = false`
3. 전화 수신 → iOS가 세션 비활성화 → `AVAudioSession.interruptionNotification(.began)` 도착
4. 옵저버는 **설치돼 있다**(`pausesOnRouteChangeDeviceUnavailable == true`이므로 `reconcileInterruptionObserver`가 통과) → `handleInterruptionBegan()` 호출 → **`.ignore` 가드에서 즉시 반환, dirty는 여전히 `false`**
5. 통화 종료 → 사용자가 재생 탭 → `play()` → `applyAudioSessionPolicyIfNeeded(force: false)` → `guard force || audioSessionActivationDirty` 실패 → **`setActive(true)` 미호출 → 무음**

`interruptionPolicy`와 `pausesOnRouteChangeDeviceUnavailable`이 **둘 다** 꺼진 경우엔 옵저버 자체가 없어 결과가 동일하다. `backgroundPolicy = .ignore`에서도 `ABApplicationStateObserver`가 설치되지 않아 `handleWillEnterForeground`의 무조건 re-dirty가 발화하지 않는 같은 계열의 구멍이 있다(`.pause`가 기본값이라 확률은 낮다).

이는 라운드3 Phase1+2 리뷰 **M1**으로 지적하고 Phase3에서 "절대 메모이즈하지 않는다"로 고쳤던 바로 그 결함이, 최적화를 도입하면서 **기본 정책 경로에 한해 되살아난** 것이다.

**테스트 공백이 이를 놓친 이유**: `ABAudioSessionPolicyTests.playReactivatesForInterruptionRecovery`가 `interruptionPolicy: .pauseAndResume`으로만 실행된다. M1 보증을 검증하는 유일한 테스트가 문제가 존재하지 않는 유일한 정책에서만 돈다.

**수정 방향**: `audioSessionActivationDirty = true`를 `.ignore` 가드보다 **위로** 이동(관측만으로 세션 상태를 기록하고, 일시정지/재개 여부만 정책으로 게이트). 옵저버 자체가 없는 조합은 `reconcileInterruptionObserver`의 설치 조건을 `audioSessionPolicy != .unmanaged`까지 포함하도록 확장하거나, 그 조합에서는 `force: false` 최적화를 끄는 방식이 필요하다.

## MJ-2. `ABAccessoryHostingBox.attach`가 일반적인 첫 표시 경로에서 발화하지 않는다 — Q6 완화책이 실제로 작동하지 않음

`Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift` `update(_:coordinator:)`

```swift
if view.window != nil {
    box.attach(to: view)
}
```

`attach`의 **유일한** 호출 지점이 SwiftUI의 `update(_:coordinator:)`다. 그런데 `makeUIView` 시점에는 뷰가 아직 계층에 들어가기 전이라 `view.window`는 **항상 nil**이다. 따라서 첫 시도는 반드시 실패한다. 이후 성공하려면 "뷰가 window에 붙은 *뒤에* `updateUIView`가 한 번 더 호출"돼야 하는데, SwiftUI는 상태가 바뀔 때 `updateUIView`를 호출할 뿐 **window 부착을 트리거로 삼지 않는다.** 정적인 액세서리(상태 변화가 없는 일반적인 경우) 는 `makeUIView` → `updateUIView`(window nil) → 레이아웃/window 부착 순서로 끝나고, 그 뒤 아무도 `attach`를 다시 부르지 않는다.

결과: `isAttachedToParent`가 계속 `false` → 부모 VC 미부착 → safe-area 전파·appearance 콜백·trait 상속 미보장. 이는 `ABAccessoryHostingBox` 문서 주석 항목 5가 "부모를 못 찾은 경우"로 기술한 바로 그 상태이며, **Q6이 우려한 호스팅 어긋남 그 자체**다. Q6-A 개정의 근거가 "완화책이 이 위험을 라이브러리가 명시적으로 흡수한다"인데, 흡수 장치가 일반 경로에서 켜지지 않는다.

**로드맵 WP-B1 항목 4는 트리거를 `didMoveToWindow` 시점으로 명시**했다("call once that view has a non-nil `window`" — 박스 자신의 문서 주석도 이 문구를 그대로 옮겨 적었다). 구현은 그 트리거를 SwiftUI 업데이트 주기에 얹었고, 그 주기는 window 변화를 관측하지 않는다.

**테스트 공백**: `ABAccessoryHostingBoxTests.attachAdoptsParentAndDetachReleasesIt`은 이미 VC 계층 안에 있는 뷰를 넘겨 `attach`를 **직접** 호출하므로 통과한다 — 박스의 로직은 맞다. 그러나 `ABPlayerControlsSwiftUITests.accessoriesContentIsHosted`는 window 없는 뷰로 `update(...)`를 부르고 `accessoryViews.count == 1`만 단언한다. **호출부의 트리거 조건은 어느 테스트도 검증하지 않는다.**

**수정 방향**: 박스가 `didMoveToWindow`를 스스로 관측하도록 한다 — 예: `controller.view`를 `didMoveToWindow`를 오버라이드해 콜백하는 얇은 컨테이너 `UIView`에 감싸고, window가 생기는 즉시 `attach`. 테스트는 실제 `UIWindow`에 붙인 뒤 `isAttachedToParent == true`를 단언.

## MJ-3. `togglePlayback`의 상태 출처가 바뀌었다 — "순수 이동"이 아니며 characterization 테스트가 덮지 못한다

`Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift` `togglePlayback()` / `ABControlsPresenter.handle(.playPauseTapped)`

| | 분기 기준 |
|---|---|
| 이전 | `player.isPlaying` — **플레이어의 라이브 상태** (`avPlayer.rate != 0 && timeControlStatus != .paused`) |
| 현재 | `presenter.isPlaying` — **프레젠터의 캐시 상태** (`status == .playing`으로만 갱신) |

두 값은 `timeControlStatus == .waitingToPlayAtSpecifiedRate`(버퍼링 중)에서 **갈라진다**: `player.isPlaying`은 `true`(rate≠0, paused 아님), `presenter.isPlaying`은 `false`(`.playing`이 아니므로).

**발산 시나리오** — 느린 네트워크에서 재생 탭 → 버퍼링(`.waitingToPlay`) → 사용자가 다시 탭:

- 이전: `player.isPlaying == true` → **`pause()`** (버퍼링 취소)
- 현재: `presenter.isPlaying == false` → **`promote` + `play()`** (버퍼링 계속)

**새 동작이 오히려 더 낫다**는 점은 인정한다 — 아이콘은 `.waitingToPlay`에서 "재생"을 표시하는데 이전 코드는 탭 시 일시정지했으므로 아이콘/동작 불일치 버그가 있었고, 지금은 둘이 같은 출처를 공유해 일치한다. 문제는 **이 변경이 `refactor:` 커밋에서, 어느 문서에도 기록되지 않은 채, 그리고 이를 막으라고 만든 characterization 테스트가 덮지 못한 상태로** 들어왔다는 것이다.

`ABControlsPlayPauseReentrancyCharacterizationTests`는 진짜 테스트다 — 실제 버튼에 `sendActions`를 보내고 재진입 `.gradeChanged`를 포함한 이벤트 시퀀스 전체를 배열로 고정한다. 그러나 **순서(ordering)만** 고정하고 **분기 기준(state source)** 은 고정하지 않는다. `pauseTapProducesNoSynchronousReentrantPlayerEvent`는 사전에 `handlePlayerEvent(.timeControlStatusChanged(.playing))`을 수동 주입해 두 출처를 일치시킨 상태에서만 돈다.

**수정 방향**: 둘 중 하나를 택하고 명시적으로 고정한다 — (a) `presenter.isPlaying` 유지 + `.waitingToPlay` 상태에서의 탭 동작을 테스트로 고정 + CHANGELOG `### Changed`에 동작 변경 1줄, 또는 (b) `.playPauseTapped(isPlaying:allowsPromotionTap:)`으로 라이브 값을 주입해 이전 동작 복원.

---

# Minor

## mn-1. `.attached`의 `promotesToCurrentOnPlay`가 사용되지 않는 죽은 파라미터

`ABControlsPresenter.swift`

```swift
case .attached(grade: ABPlaybackGrade, promotesToCurrentOnPlay: Bool)
…
case .attached(let grade, _):                                   // ← 두 번째 값 폐기
    return [.setEnabled(grade == .current, allowsPromotionTap: true)]   // ← 하드코딩
```

`allowsPromotionTap`은 실제 의미가 있다(`setControlsEnabled`가 `enabled || (allowsPromotionTap && canPromoteToCurrentOnPlayTap)`로 사용). 그런데 `.attached`는 전달받은 값을 버리고 항상 `true`를 낸다 — 이전 `setControlsEnabled(player.grade == .current)`의 기본값과 동치라 **현재는 정확**하지만, Input이 출력에 절대 영향을 줄 수 없는 값을 나르고 있어 "존중된다"고 오해할 여지가 있다. 파라미터를 제거하거나 실제로 사용해야 한다.

## mn-2. `currentPlaybackTime`이 뷰와 프레젠터에 이중으로 존재하며 수동 동기화에 의존

뷰(`:55, :627, :655`)와 프레젠터(`:74`)가 각각 `currentPlaybackTime`을 보유하고, `presenter.syncPlaybackTime(_:)`을 `.itemStatusChanged(.readyToPlay)`(:438)와 `.seekCompleted`(:453) 두 곳에서 수동 호출해 맞춘다.

전 경로를 추적한 결과 **현재는 일관성이 유지된다**(`render` 호출부 6곳, `resetTimeline` 1곳 모두 프레젠터 측도 함께 갱신됨). 그러나 이는 테스트가 아니라 규율로만 지켜지는 불변식이다 — 향후 `render(...)` 호출부가 하나 추가되고 `syncPlaybackTime`을 빠뜨리면 VoiceOver 조정(`accessibilityAdjusted`가 `presenter.currentPlaybackTime`을 읽음)이 조용히 낡은 시간으로 계산한다. 뷰가 자체 사본 대신 `presenter.currentPlaybackTime`을 읽도록 단일화하거나, 최소한 불변식을 단언하는 테스트가 필요하다.

## mn-3. `ABVideoPlayerWithControls(player:)` — 가장 흔한 호출이 deprecation 경고를 낸다

신규 `accessories:` 파라미터에 기본값이 없어, 액세서리를 **전혀 쓰지 않는** 소비자도 non-deprecated 형태를 만들려면 `ABVideoPlayerWithControls(player: p) {}`처럼 빈 트레일링 클로저를 써야 한다. 그렇지 않은 `ABVideoPlayerWithControls(player: p)`는 deprecated 이니셜라이저로 해소되어 경고가 난다 — 소비자가 자체적으로 warnings-as-errors를 쓴다면 빌드가 깨진다.

`ABPlayerControls` 쪽은 `ABPlayerControlsInitializerAmbiguityTests.allDefaultsCompileForBothOverloads`가 `(player:) {}` 형태를 검증하지만, `ABVideoPlayerWithControls`의 인자 없는 호출 형태는 어느 테스트도 다루지 않는다. CHANGELOG의 Migration 노트도 `accessoryViews: [...]`를 쓰던 경우만 안내하고, **액세서리를 아예 안 쓰던 다수 소비자**에게 `{}`를 추가하라는 안내가 없다.

기본값을 주면 인자 없는 호출이 두 오버로드 사이에서 모호해지므로 간단한 해법은 없다 — 최소한 CHANGELOG/README에 `{}` 마이그레이션을 명시하는 것이 필요하다.

## mn-4. N12는 절반만 해소됐다

`ABCacheStore.resolvedMetadata`의 `PendingMetadataRequest` 홀더 도입은 **참조 동일성 비교로 슬롯을 정확히 정리**한다 — `reset()`이 이미 다른 홀더를 설치한 뒤 원래 호출자의 `defer`가 그것을 지워버리는 문제를 막는다. 이건 실제 위험이고 올바른 수정이다.

그러나 라운드3 리뷰 N12가 지적한 원래 문제는 남아 있다: 첫 호출자의 **대기가 취소**되면 `try await request.value`가 `CancellationError`를 던지고 `defer`가 슬롯을 비우지만 `request` Task는 **계속 실행된다.** 이후 도착한 호출자는 두 번째 HEAD를 발사하고, 고아 Task의 결과는 `cacheMetadata`되지 않고 버려진다. `load`가 `ABResourceLoaderDelegate`의 취소 가능한 Task에서 호출되므로 현실적인 경로다.

근본 수정은 슬롯 수명을 첫 호출자의 `await`에 묶지 않는 것이다 — Task **본문**이 `cacheMetadata`와 슬롯 정리를 수행하도록.

## mn-5. `isolated deinit`(SE-0371)과 `swift-tools-version: 6.0`의 툴체인 하한 불일치

`ABPlayerControls.Coordinator`(:155)가 `isolated deinit`을 사용한다. 현 개발 툴체인은 Swift 6.2.3이라 빌드되지만, `Package.swift:1`은 `swift-tools-version: 6.0`을 선언한다. Swift 6.0/6.1 툴체인의 기여자·CI는 컴파일에 실패한다. tools-version을 올리거나, `deinit` 내부에서 `MainActor.assumeIsolated`를 쓰는 형태로 낮추어야 정합이 맞는다. (iOS 17 최소 배포 타깃에서의 런타임 back-deployment 가능 여부도 함께 확인 권장 — 시뮬레이터 iOS 26.4에서만 검증됐다.)

## mn-6. `detach()`가 `removeFromSuperview()`를 하지 않는다

표준 자식 VC 해제 순서는 `willMove(toParent: nil)` → `view.removeFromSuperview()` → `removeFromParent()`인데, 중간 단계가 빠져 있다. 실제로는 `ABPlayerControlsView.accessoryViews` setter가 뷰를 스택에서 제거하고, 코디네이터 수명과 컨트롤 뷰 수명이 함께 끝나므로 **누수는 확인되지 않았다**. 다만 박스가 살아 있는 채로 `accessoryViews`만 교체되는 경로에서는 자식 VC 관계와 뷰 계층이 어긋난 상태가 남는다.

**누수 점검 결과 (요청 항목)**: `Coordinator.isolated deinit`이 `accessoryBox?.detach()`를 호출하고, 부모 VC의 강한 참조가 그 시점에 해제된다. `attach`가 성공한 적 없으면 `detach`는 no-op이고 부모 참조도 애초에 없다. **어느 경로에서도 누수는 발견되지 않았다.**

## mn-7. 로드맵의 규모 목표 미달 — RESULT 문서에 명시 필요

로드맵은 세 추출 후 뷰를 **~620줄(−44%)** 로 예측했으나 실제는 **957줄(−14%)** 이다. 원인은 프레젠터 추출 범위를 의도적으로 좁힌 것이다 — 스크러빙 전체, `.itemDetached`/`.sourceChanged`/`.readyToPlay`/`.seekCompleted` 4개 이벤트, `isPlayingState`/`currentPlaybackTime` 사본이 뷰에 남았다.

이 축소 자체는 **정당하고 잘 문서화돼 있다**(프레젠터 doc 주석이 각 항목의 이유를 구체적으로 서술하며, 특히 스크러빙은 `scrubbingPlayer` 고정이 player-less 타입으로 표현 불가하다는 논거가 정확하다). 다만 `RESULT-round4-A.md`가 목표 대비 실적 차이와 그 사유를 명시하지 않으면 다음 라운드가 잘못된 기준선에서 출발한다.

## mn-8. `legacyPlayer:` 내부 이니셜라이저에 deprecation 표식이 없다

CI 함정 회피 자체는 타당하다(아래 §3 참조). 다만 non-deprecated `internal init(legacyPlayer:…)`이 모듈 내부에 남아, 향후 새 내부 코드가 이를 채택해도 아무 경고가 나지 않는다. 문서 주석이 용도를 명확히 밝히고 있어 위험은 낮지만, `@available(*, deprecated)`를 내부 이니셜라이저에도 붙이고 호출부(`ABVideoPlayerWithControls.controls`의 legacy 분기)만 별도 헬퍼로 감싸는 편이 더 견고하다.

---

# 검토 포인트별 판정

## (1) Controls 분해가 진짜 순수 이동인가

| 항목 | 판정 |
|---|---|
| `ABControlsLayout` 추출 | **순수 이동 ✓** — `rootStackSpacing`/`bottomRowVisibleContentSlack`/`rateButtonBottomRowSlack`/`frameTopToInkTop`/`scaledTimeLabelFont` 전부 식과 상수가 동일하고, 온디바이스 튜닝 이력이 담긴 주석 블록까지 원문 그대로 이동했다. 로드맵 R-A1의 "상수·식 변경 금지"가 지켜졌다 |
| **R-A2(캐시 금지) 준수** | **✓** — `private var layout: ABControlsLayout { ABControlsLayout(style:traitCollection:) }`로 호출 시점 생성이며, 주석이 "never cache this"와 그 이유(trait 추적 중단)를 명시한다. 로드맵이 "가장 자연스러운 실수, 확률 높음"으로 지목한 함정을 정확히 피했다 |
| `ABControlsTimeLabelFormatter` 추출 | **순수 이동 ✓** — `.custom` 계약(WP12)이 그대로 옮겨졌고, 라운드3 N14(죽은 `.custom` 분기 + stale 주석)가 부수적으로 해소됐다 |
| `ABControlsPresenter` — 이벤트 순서 | **보존 ✓** — 8개 이벤트 케이스를 1:1 대조한 결과 프레젠터 effect 적용 → 잔여 switch 순서가 이전 코드의 문장 순서와 전부 일치한다 |
| `ABControlsPresenter` — 상태 출처 | **✗ MJ-3** — `togglePlayback`의 분기 기준이 `player.isPlaying` → `presenter.isPlaying`으로 바뀌었다 |

### characterization 테스트의 실효성

**실효성 있음 — 단, 축이 하나뿐이다.** `ABControlsPlayPauseReentrancyCharacterizationTests`는 실제 `UIControl.sendActions`로 구동하고 `[player(preloadCancelled), player(tuningApplied), player(gradeChanged: preloaded→current), controls(playPauseTapped)]`라는 정확한 시퀀스를 단언한다. `promote(to:)`가 `play()`보다 먼저 동기 재진입한다는 사실이 실제로 고정된다 — 로드맵이 WP-A4b 착수 전제로 요구한 것을 충족한다. `ABObserverRegistry.broadcast`가 디스패치 홉 없이 핸들러를 직접 순회한다는 근거까지 주석에 명시돼 정확하다.

한계는 **순서만 고정하고 분기 기준은 고정하지 않는다**는 점이며, 그 결과가 MJ-3이다.

### ABControlsPresenter 양방향 분리의 재진입 안전성

**안전하다.** 핵심 장치는 `applyPresenterEffects(_:player:)`의 `targetPlayer` 파라미터다:

```swift
/// `targetPlayer` is only consulted for `.send` effects, and only the
/// specific player instance the caller resolved *before* calling
/// `presenter.handle(...)` — never re-read from `self.player` here.
```

`.promoteToCurrent`가 effect 루프 **안에서** `.gradeChanged`를 동기 브로드캐스트해 `handlePlayerEvent`로 재진입하는데, 그 사이 소비자가 `self.player`를 교체해도 이어지는 `.play` effect는 **핀 고정된 인스턴스**로 간다. 스크러빙의 `scrubbingPlayer` 핀과 같은 논거이며, effect 리스트 간접화가 만들 수 있었던 가장 위험한 재진입 구멍을 정확히 막았다.

재진입 중 `presenter` 자신의 mutation 충돌도 없다 — `handle(...)`이 반환한 **뒤에** effect 루프가 돌므로, 재진입한 `handlePlayerEvent`의 `presenter.handle(...)`은 이미 완료된 mutation 위에서 실행된다(Swift의 exclusive access 위반 없음, 실측 통과가 이를 뒷받침).

### 훅 census의 존치 판단 타당성

**타당하다 — 이번 라운드에서 가장 잘 수행된 부분이다.**

`ROADMAP-round4-hook-census.md`는 baseline 시점 "이관 후 삭제 대상"으로 예측했던 5개(`hasFixedWidthTimeLabels`, `fixedTimeLabelMinimumWidth`, `isShowingPauseIcon`, `backgroundContentAlpha`, `lastVisibilityAnimationDuration`)를 재census 후 **전부 존치로 정정**하고, 그 사유를 "순수 타입이 검증하는 로직이 아니라 그 결과가 실제 UIKit 객체(제약조건·아이콘 상태·알파·애니메이션 duration)에 반영됐는지 확인하는 **배선 검증**"으로 정확히 판별했다. 로드맵 R-A5("훅을 과하게 지워 커버리지 상실 — 삭제 전 census 재실행 필수")가 예방하려던 상황이 실제로 발생했고 안전장치가 작동했음을 문서가 스스로 기록한다.

최종 삭제는 2개(`renderedBackgroundContentView` 0회 + `scaledTimeLabelFont` 오버로드 2종)에 그쳤고, 축소 대상 3개(`displayedElapsedText`/`displayedRateText`/`controlsAreEnabled`)는 **미착수로 명시**했다 — 커버리지가 이미 순수 테스트에 중복 존재하므로 미착수가 회귀를 일으키지 않는다는 판단도 맞다. "훅 개수를 줄였다"고 과장하지 않은 점이 특히 좋다.

## (2) ABAccessoryHostingBox의 Q6 완화 실효성

| 로드맵 WP-B1 필수 항목 | 구현 | 테스트 |
|---|---|---|
| 1. `sizingOptions = [.intrinsicContentSize]` | ✓ (:45) | ✓ `intrinsicContentSizeIsNonZero`, `updateChangesRenderedContent` |
| 2. `backgroundColor = .clear` | ✓ (:46) | ✓ `backgroundIsTransparent` |
| 3. `translatesAutoresizingMaskIntoConstraints = false` | ✓ (:47) | — |
| 4. 부모 VC 부착 (responder chain) | ✓ 로직은 정확 (:59-65, :75-84) | ✓ `attachAdoptsParentAndDetachReleasesIt` (직접 호출) |
| 5. 부모 미발견 시 한계 명시 | ✓ 문서 주석 항목 5 + `attachWithoutParentDoesNotCrash` | ✓ |
| 6. `rootView` 재대입 | ✓ (:51) | ✓ `accessoriesUpdateReusesTheSameHostedView` |

**박스 자체는 6개 항목을 모두 정확히 구현했다.** 그러나 **호출부의 트리거가 잘못돼(MJ-2) 항목 4가 일반 경로에서 발화하지 않으므로, Q6-A가 약속한 완화가 실제로는 작동하지 않는다.** 이것이 (B) 트랙의 핵심 결함이다.

- **attach 실패 시 재시도 경로**: 설계상 "성공할 때까지 매 업데이트 패스에서 재호출"이지만, 트리거인 `updateUIView`가 window 부착을 관측하지 않아 정적 액세서리에서는 재시도가 발생하지 않는다. → MJ-2
- **detach 누수**: **없음.** `Coordinator.isolated deinit → accessoryBox?.detach()`로 부모의 강한 참조가 해제되고, attach가 성공한 적 없으면 애초에 참조가 없다. `removeFromSuperview()` 누락은 순서상 비표준이나 누수는 아니다(mn-6).

## (3) deprecation의 CI 함정 회피 — semver·경고 정책상 옳은가

**옳다.**

`ABVideoPlayerWithControls.controls`가 deprecated public 이니셜라이저 대신 non-deprecated `internal init(legacyPlayer:…)`를 호출하는 구조다. 평가:

- **문제 인식이 정확하다** — Swift는 호출 지점 단위 deprecation 억제 수단(`#pragma`류)이 없고, deprecated 심볼을 non-deprecated 컨텍스트에서 부르면 경고가 난다. `controls`(`some View` 계산 프로퍼티)를 통째로 deprecated로 표시하면 **무관한 `accessories:` 경로의 경고까지 억제**되므로 쓸 수 없다. 이 논거가 코드 주석과 `POLICY-api-stability.md`에 모두 정확히 기술돼 있다.
- **semver 영향 없음** — 추가된 것은 `internal` 이니셜라이저뿐이라 공개 표면이 늘지 않는다. public 이니셜라이저 2개의 deprecation은 경고일 뿐 소스 호환이며, 제거 시점을 1.0.0으로 명시했다.
- **정책 문서와 일치** — `POLICY-api-stability.md`가 additive-first / 같은 마이너에서 deprecate / 1.0.0 이전 제거 금지 / 패치에서 deprecation 도입 금지를 규정하고, 이번 사례를 worked example로 기록했다. 라운드3 N13(behavior change에 migration 노트 누락)을 상시 규칙으로 승격한 것도 좋다.
- **`ABPlayerControlsView.accessoryViews`를 deprecate하지 않은 판단이 옳다** — UIKit 소비자의 1급 API이며, 붙였다면 테스트 4곳·DocC 3곳이 함께 무너졌을 것이다. 정책 문서가 이 판단을 명시적으로 기록했다.
- **Q6-A 기록이 모범적이다** — 재결정 사유, 완화책, 결정일, 승인 주체를 모두 남겼다. 기록된 사용자 결정을 뒤집을 때의 올바른 절차다.

잔여는 mn-8(내부 이니셜라이저 자체에 표식 없음)과 mn-3(액세서리 미사용 소비자의 마이그레이션 안내 부재)뿐이다.

## (4) minors 커밋이 새 레이스를 만드는가

**N1 dirty 플래그 — 데이터 레이스 없음, 논리적 구멍 있음.** `audioSessionActivationDirty`는 `@ObservationIgnored private var`로 `@MainActor` 클래스에 있고 모든 읽기/쓰기(`play()`, `applyAudioSessionPolicyIfNeeded`, `handleInterruptionBegan`, `handleWillEnterForeground`)가 MainActor 격리 안에서만 일어난다. `deinit`은 접근하지 않는다. **동시성 레이스는 없다.** 문제는 상태 머신의 커버리지이며 → MJ-1.

다중 인스턴스 관점에서도 각 플레이어가 자기 dirty 플래그를 갖고 코디네이터는 여전히 매 `apply` 호출을 처리하므로, 코디네이터의 refcount/스냅샷 불변식은 영향받지 않는다. ✓

**N12 홀더 교체 — 새 레이스 없음.** `PendingMetadataRequest`는 actor 격리 안에서만 접근되고(`pendingMetadataRequests`는 actor의 저장 프로퍼티), 홀더는 참조 동일성 비교에만 쓰인다. 조회(:406)와 설치(:415) 사이에 서스펜션 포인트가 없어 coalescing 불변식도 유지된다. Task는 `[weak self]`라 순환 없음. ✓ 다만 해소 범위가 절반 → mn-4.

**격리 수정(0e44695) — 정확하다.** `nonisolated private static func describe(errorLogEvent:)`는 non-Sendable한 `AVPlayerItemErrorLogEvent`를 `Task { @MainActor }` 홉 **이전에** `String`으로 환원한다. 경계를 넘는 값이 `String`뿐이므로 Swift 6 strict concurrency 하에서 올바른 최소 수정이다. ✓

**m1 (튜닝 가드 role 스코프) 해소 ✓** — 라운드3에서 이월했던 항목이 이번에 정리됐다. `previousRoleTuning != tuning(for: role)`로 해소 role만 비교하며, `preloadTuningChangeWhileCurrentDoesNotReapply` 테스트가 이를 고정한다.

**N10 (임계값 ≤ 0) 해소 ✓** — 클램프 대신 문서화를 택했고, "0이 직관과 반대"임을 명시했다. 권고 범위 내다.

## (5) 신규 테스트의 tautology 여부

**공허한 테스트는 발견되지 않았다.** 표본:

- `distantOffsetPassthroughSplitsIntoOneMegabyteChunks` — 라운드3 N8(청킹 커버리지 0건)을 정면 해소. 3개 청크의 **크기·내용·`isEndOfResource` 플래그**를 각각 단언하고 마지막 청크만 `true`임을 확인한다. 조기 EOF 오보와 절단을 모두 잡는다.
- `ABControlsLayoutTests` — `frameTopToInkTop` 경계와 AX 사이즈 분기를 순수 타입에 직접 건다. 뷰 인스턴스 불필요.
- `ABAccessoryHostingBoxTests` — `intrinsicContentSize` 증가를 실제 `layoutIfNeeded` 후 비교하고, 부모 부재 시 `!isAttachedToParent`를 단언한다(단순 "크래시 안 남"이 아님).
- `ABPlayerControlsInitializerAmbiguityTests` — 컴파일 자체가 오라클인 구조이며, deprecated 호출을 쓰는 테스트에만 `@available(*, deprecated)`를 국소 적용해 CI 게이트를 우회하지 않고 통과시킨 처리가 정확하다.
- `repeatPlayWithoutInterruptionDoesNotReactivate` / `playReactivatesForInterruptionRecovery` — N1 최적화의 양방향(스킵/재활성화)을 모두 고정한다.
- `accessoriesUpdateReusesTheSameHostedView` — 코디네이터 보유 실패(rootView 갱신 중단) 회귀를 실제로 잡는다.

**공백은 tautology가 아니라 미커버 축이다**: MJ-1(`.ignore` 정책의 인터럽션 복구), MJ-2(호스팅 박스 attach 트리거), MJ-3(`.waitingToPlay` 상태의 탭 동작), mn-2(두 `currentPlaybackTime` 사본의 동기화 불변식), mn-3(`ABVideoPlayerWithControls` 인자 없는 호출).

---

# 종합

라운드4의 **설계 품질과 문서화는 라운드3보다 뚜렷하게 낫다.** 로드맵이 "가장 자연스러운 실수, 확률 높음"으로 지목한 R-A2(layout 캐시)를 정확히 피했고, R-A5(훅 과다 삭제)는 안전장치가 실제로 작동해 5개를 존치로 정정했으며, R-B1(CI 함정)은 실측으로 해소됐다. 프레젠터의 `targetPlayer` 핀 고정은 effect 간접화가 만들 수 있었던 최악의 재진입 구멍을 선제적으로 막았고, Q6-A 개정 기록과 `POLICY-api-stability.md`는 기록된 결정을 뒤집는 올바른 절차의 모범이다. 라운드3 잔여 항목(N8/N6/N7/N10/N12-일부/m1/N14)도 대부분 정리됐다.

머지를 막는 것은 **세 건의 Major**이며, 공통점은 전부 **"장치는 올바르게 만들었는데 발화 조건이 좁거나 틀렸고, 그 축을 검증하는 테스트가 없다"** 는 것이다.

- **MJ-1** — dirty 플래그 자체는 옳으나 `.ignore`(기본값) 경로에서 세팅되지 않아 라운드3 M1이 부분 재발한다. 한 줄 이동으로 고칠 수 있으나, 고친 뒤 `.ignore` 정책용 테스트가 반드시 필요하다.
- **MJ-2** — 호스팅 박스는 Q6의 6개 실패 모드를 모두 정확히 처리했으나 `attach` 트리거가 SwiftUI 업데이트 주기에 얹혀 있어 정적 액세서리의 첫 표시에서 발화하지 않는다. Q6-A 개정의 전제(완화책이 작동한다)가 성립하지 않으므로 (B) 트랙 승인 조건에 직결된다.
- **MJ-3** — `refactor:` 커밋의 미기록 동작 변경. 새 동작이 더 낫다고 판단되면 그대로 두되, 테스트로 고정하고 CHANGELOG에 기록해야 한다.

Minor 8건은 후속으로 분리 가능하며, 그중 mn-5(`isolated deinit` vs tools-version 6.0)는 다른 툴체인의 기여자·CI를 즉시 깨뜨릴 수 있어 우선순위가 높다.

## 후속 권장 (우선순위)

1. **MJ-1** — `audioSessionActivationDirty = true`를 `.ignore` 가드 위로 이동 + `.ignore` 정책 인터럽션 복구 테스트
2. **MJ-2** — 박스가 `didMoveToWindow`를 자체 관측하도록 변경 + 실제 `UIWindow` 부착 후 `isAttachedToParent == true` 통합 테스트
3. **MJ-3** — `.waitingToPlay` 상태 탭 동작 테스트 고정 + CHANGELOG `### Changed` 기재
4. **mn-5** — `swift-tools-version` 상향 또는 `isolated deinit` 회피
5. **mn-2** — `currentPlaybackTime` 단일 출처화
6. **mn-4** — `pendingMetadataRequests` 슬롯 수명을 Task 본문으로 이동
7. **mn-3** — `{}` 마이그레이션을 CHANGELOG/README에 명시
8. mn-1, mn-6, mn-7, mn-8 — 단순 정리

FINAL-VERDICT: REQUEST-CHANGES
