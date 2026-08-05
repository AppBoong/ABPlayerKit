# REVIEW: 라운드4 게이트 재판정

- **대상**: `7e4ba47` (수정) + `88ee471` (문서)
- **대조 기준**: `docs/briefs/REVIEW-round4-final.md` (판정 REQUEST-CHANGES — Major 3 / Minor 8), `docs/briefs/RESULT-round4-fixes.md` (처리 표)
- **판정**: **APPROVE**

## 실측 검증

```
xcodebuild test -scheme ABPlayerKit-Package -destination 'id=65CDD0F3-…' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
→ 406 tests / 0 failures / 0 warnings   (399 → 406, +7)
```

번들별 실측이 `RESULT-round4-fixes.md`의 표와 **정확히 일치**한다:

| 번들 | RESULT 주장 | 실측 |
|---|---|---|
| ABPlayerKitTests | 175 | **175** ✓ |
| ABPlayerKitControlsTests | 184 | **184** ✓ |
| ABPlayerKitCacheTests | 39 | **39** ✓ |
| ABPlayerKitMetricsTests | 8 | **8** ✓ |

CI 게이트와 동일한 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`로 통과했다 — mn-8 재구조화가 새 deprecation 경고를 만들지 않았다는 **경험적 증거**다(구조적 검증은 아래 §mn-8).

---

# Major 검증

## MJ-1 — 해소 ✓ (요청한 두 반쪽 모두, N1 최적화는 무효화되지 않음)

**수정 내용 대조** (`Sources/ABPlayerKit/Engine/ABPlayer.swift`)

| 리뷰가 요구한 것 | 구현 | 확인 |
|---|---|---|
| `audioSessionActivationDirty = true`를 `.ignore` 가드 **위로** 이동 | `handleInterruptionBegan()`에서 대입이 `guard configuration.interruptionPolicy != .ignore` **앞**에 위치 | ✓ |
| 옵저버 자체가 없는 조합(`interruptionPolicy == .ignore` **및** 라우트 플래그 off) 대응 | `reconcileInterruptionObserver()`의 설치 조건에 `|| configuration.audioSessionPolicy != .unmanaged` 추가 | ✓ |
| (구현자가 추가로 파악) 설치 조건이 넓어졌으므로 그 값의 변경도 재평가를 유발해야 함 | `applyConfigurationChange`의 재평가 조건에 `previousConfiguration.audioSessionPolicy != configuration.audioSessionPolicy` 추가 | ✓ |

세 번째 항목은 리뷰가 명시하지 않았지만 두 번째 수정의 **필연적 귀결**이다 — 설치 조건이 `audioSessionPolicy`에 의존하게 됐으니 그 값이 바뀔 때 옵저버를 재조정하지 않으면 `.unmanaged` ↔ 관리 전환 시 옵저버가 어긋난다. 지시받지 않은 결과를 스스로 추적한 것으로, 정확한 판단이다.

### `.ignore` 시맨틱이 훼손되지 않았는가

옵저버가 더 많은 설정에서 설치되므로, `.ignore`에서 **관측 가능한 동작이 새로 생기지 않는지**가 핵심이다. 소스 확인 결과:

```swift
audioSessionActivationDirty = true                                  // 세션 상태 기록 — 무조건
guard configuration.interruptionPolicy != .ignore else { return }   // 그 아래 전부 게이트
wasPlayingBeforeInterruption = isPlaying
if grade == .current { target.pause() }
broadcast(.audioInterruptionBegan)                                  // ← 방송도 가드 아래
```

`handleInterruptionEnded`(`.ignore` 가드 유지), `handleRouteChangeDeviceUnavailable`(`pausesOnRouteChangeDeviceUnavailable` 가드 유지)도 그대로다. **`.ignore`에서 pause도 broadcast도 발생하지 않는다** — public 이벤트 스트림에 변화 없음. ✓

### N1 최적화가 다시 무효화되지 않는가 (요청 항목)

**무효화되지 않는다.** `audioSessionActivationDirty = true`가 실행되는 지점은 세 곳뿐이다:

1. 초기화 시 `= true`
2. `handleInterruptionBegan` — **실제 `AVAudioSession.interruptionNotification(.began)` 도착 시에만**
3. `handleWillEnterForeground` — 실제 포그라운드 복귀 시에만

가드 위로 옮긴 것은 *조건*을 넓힌 게 아니라 *같은 이벤트*에서의 실행 순서를 바꾼 것이다. `play()`가 반복 호출되는 정상 경로에서는 셋 중 어느 것도 발화하지 않으므로 플래그는 `false`로 유지되고 `force: false` 스킵이 그대로 동작한다. 이를 고정하는 `repeatPlayWithoutInterruptionDoesNotReactivate`(연속 3회 `play()` → `.activate` 1회만)가 여전히 통과한다(175개 전원 통과). ✓

### 회귀 테스트 실효성

`ABAudioSessionPolicyTests.playReactivatesForInterruptionRecoveryUnderIgnorePolicy` — 리뷰가 서술한 재현 조건(전부 기본값 + `audioSessionPolicy` 옵트인만)을 그대로 실행하고 **양방향**을 단언한다:

- `#expect(!target.calls.contains(.pause))` → `.ignore` 시맨틱 보존
- `#expect(audioSession.calls == [snapshot, activate, activate])` → 인터럽션 후 재활성화

수정 전 코드에서는 세 번째 `.activate`가 발생하지 않으므로 **확실히 실패하는** 판별력 있는 테스트다. ✓

한 가지 특이 패턴: `waitUntil { player.play(); return audioSession.calls.count == 3 }`처럼 술어 안에서 부작용(`play()`)을 일으킨다. 주석이 이유를 정확히 설명한다 — `.ignore`에서는 동기화할 수 있는 관측 가능한 신호(pause/broadcast)가 없고, 플래그가 아직 `false`인 동안의 `play()`는 무해한 no-op이다. 관용적이진 않으나 정당하고 결정론적이다.

## MJ-2 — 해소 ✓ (첫 표시에서 실제로 발화한다)

**트리거가 호출자 주기에서 소스로 이동했다.** `ABAccessoryHostingContainerView`(신설, `private final class`)가 `didMoveToWindow`를 오버라이드하고, `window != nil`인 순간 `onDidMoveToWindow`로 박스에 통지 → `attach(to: container)`. `ABPlayerControls.update(_:coordinator:)`의 기존 `if view.window != nil { box.attach(to: view) }`는 **제거됐다**(근거가 사라진 코드를 남기지 않은 처리가 좋다).

`UIHostingController.view`가 private SwiftUI 타입이라 서브클래싱 불가 → 얇은 컨테이너로 감싸는 것이 유일한 방법이며, 컨테이너는 4변 핀 + `intrinsicContentSize` 포워딩으로 이전과 동일한 사이징을 유지한다. 설계로서 정확하다.

### 첫 표시 발화 검증 (요청 항목)

**두 테스트가 서로 다른 층위에서 이를 증명한다:**

1. `ABAccessoryHostingBoxTests.attachFiresAutomaticallyOnOrdinaryFirstDisplay` — window **이전**에 `#expect(!box.isAttachedToParent, "must not attach before a window exists")`로 전제를 고정하고, window 부착 **이후** `#expect(box.isAttachedToParent)`를 단언한다. **`attach(to:)` 수동 호출이 없다.** `didMoveToWindow` 훅을 제거하면 확실히 실패한다.
2. `ABPlayerControlsSwiftUITests.accessoriesAttachToParentOnRealWindowDisplay` — 실제 `UIHostingController` + `UIWindow`로 SwiftUI 래퍼 전 경로를 태우고 `hostingController.children.count == 1`을 단언한다. 리뷰가 "호출부의 트리거 조건은 어느 테스트도 검증하지 않는다"고 지적한 정확한 공백을 메운다.

`makeUIView` → 계층 구성 → window 부착 순서(수동 `update` 호출 없음)를 재현하므로, MJ-2의 실패 모드를 직접 겨냥한다. ✓

**Q6-A의 전제가 이제 실제로 성립한다** — 완화책이 일반 경로에서 작동하므로 (B) 트랙 승인 조건이 충족됐다.

## MJ-3 — 해소 ✓ (옵션 (b), 사전-추출 시맨틱 정확 복원)

`ABControlsPresenter.Input.playPauseTapped(isPlaying:allowsPromotionTap:)`로 라이브 값을 주입하고, 프레젠터는 **자신의 캐시가 아닌 그 값**으로 분기한다. `ABPlayerControlsView.togglePlayback()`이 `player.isPlaying`을 읽어 전달한다.

사전-추출 코드와 1:1 대조:

| 원본 | 현재 |
|---|---|
| `if player.isPlaying { player.pause(); isPlayingState = false }` | `isPlaying == true` → `self.isPlaying = false`, `[.send(.pause)]` |
| `else { if canPromote { promote }; player.play(); isPlayingState = true }` | `isPlaying == false` → `self.isPlaying = true`, `[.send(.promoteToCurrent)?, .send(.play)]` |

`self.isPlaying = !isPlaying` 낙관적 대입도 원본의 `isPlayingState = true/false` 위치·의미와 일치한다. **정확한 복원이다.** ✓

**요청한 테스트 고정도 완료**: `ABControlsPresenterTests.playPauseTappedFollowsLiveValueOverItsOwnCache`가 발산 조건을 명시적으로 구성한다 — `.timeControlStatusChanged(.waitingToPlay)`로 캐시를 `false`로 만든 뒤(`#expect(!presenter.isPlaying, "…the premise of the divergence this test exercises")`), `playPauseTapped(isPlaying: true, …)` → `[.send(.pause)]`를 단언. 수정 전 코드(캐시 분기)라면 `[promote, play]`가 나와 **확실히 실패한다.** ✓

---

# Minor 검증

| ID | RESULT 주장 | 검증 결과 |
|---|---|---|
| **mn-1** | 죽은 파라미터 제거 | ✓ `.attached(grade:)`로 축소, 호출부·테스트 갱신 확인 |
| **mn-2** | 불변식 테스트 추가(단일화는 보류) | ✓ **판별력 있음** — `seekCompletedKeepsPresenterPlaybackTimeInSyncForAccessibilityAdjustment`가 `"00:01:30/00:02:00"`을 단언하며, `syncPlaybackTime` 누락 시 stale 10s 기준으로 `"00:00:20"`이 나와 실패한다. 리뷰가 제시한 두 선택지 중 "최소한 불변식 테스트" 쪽을 택했고, 단일화 보류 사유(범위)도 명시됐다 |
| **mn-3** | API 불변 + 문서 보강 + 컴파일 테스트 | ✓ CHANGELOG `### Deprecated`에 `{}` 마이그레이션과 **"왜 기본값을 줄 수 없는지"**(모호성)까지 기재, README(영)에 콜아웃 추가. `videoPlayerWithControlsAllDefaultsCompileForBothOverloads`가 두 해소 경로를 컴파일로 증명. 리뷰가 "간단한 해법은 없다"고 인정한 범위 내의 최선 |
| **mn-4** | Task 본문으로 캐시·정리 이동 | **코드 ✓ / 테스트 △** — 아래 별도 항목 |
| **mn-5** | `isolated deinit` → `deinit` + Task 홉 | ✓ `swift-tools-version: 6.0` 유지(툴체인 하한 상향은 별도 결정으로 보류 — 타당). `accessoryBox`가 `@MainActor final class`라 Sendable이므로 `Task { @MainActor }` 캡처가 합법이고, 값 캡처로 detach 실행까지 생존이 보장된다. detach가 한 MainActor 턴 늦춰질 뿐 기능은 동일 |
| **mn-6** | 표준 해제 순서 | ✓ `willMove(toParent:)` → `container.removeFromSuperview()` → `removeFromParent()`, `#expect(box.view.superview == nil)` 단언 추가 |
| **mn-7** | 이미 충족(확인만) | ✓ **RESULT 측 주장이 맞다** — `RESULT-round4-A.md:23`이 "1109 → 957줄(−13.7%). 로드맵이 예측한 ~620줄(−44%)에는 못 미친다"와 그 사유를 처음부터 기록하고 있었다. **mn-7은 내 지적 오류였다** |
| **mn-8** | 내부 이니셜라이저 deprecate + 재구조화 | ✓ 아래 별도 항목 |

## mn-4 — 코드는 해소, 테스트는 특성화 등급 (그리고 내 원 지적의 메커니즘 정정)

**코드 재구조화는 정확하다.** `finishMetadataRequest(key:holderID:metadata:)`를 코얼레싱 `Task`의 **본문 안에서** 호출해, 성공/실패 어느 경로로 끝나든 캐시 기록과 슬롯 정리가 정확히 한 번 일어난다. 어떤 호출자의 프레임에도 의존하지 않으므로 `reset()`·에러·취소 어느 타이밍에서도 올바르다 — 구조적 성질로서의 개선이다.

`@Sendable` 클로저가 non-`Sendable` 클래스를 캡처할 수 없어 `===` 대신 `UUID` 값 비교로 정체성을 재구현한 것도 옳다. `@unchecked Sendable`을 붙였다면 실제로 거짓말이 됐을 것이다.

**정정 — 내 원 지적의 메커니즘이 부정확했다.** REVIEW-round4-final.md mn-4는 "첫 호출자의 대기가 취소되면 `try await request.value`가 `CancellationError`를 던진다"고 서술했으나, `Task.value`는 *대기하는* 쪽의 취소로 중단되지 않는다(비구조적 Task는 awaiter의 취소와 무관하게 계속 실행되고, `.value`는 그 완료를 기다린다). 구현자가 실험으로 이를 확인해 `RESULT-round4-fixes.md`에 기록했고, 그 기록이 맞다. 따라서 내가 서술한 "두 번째 HEAD 발사" 시나리오는 그 경로로는 재현되지 않는다.

**그럼에도 수정은 유효하다** — 캐시 기록을 어느 호출자 프레임에도 묶지 않는 편이 `reset()`·에러 경로까지 포함해 구조적으로 옳고, 실제로 `defer` 기반보다 단순하다.

**테스트 한계는 RESULT가 정직하게 자진 신고했다.** `cancelledFirstCallerStillCachesAndCoalescesForLaterCallers`는 게이트형 fetcher로 코얼레싱(HEAD 1회)과 사후 캐시 히트(HEAD 여전히 1회)를 확인하지만, 위 메커니즘 정정에 따라 **수정 전 코드에서도 통과할 가능성이 높다** — 즉 회귀 방지용 판별 테스트가 아니라 새 구조의 특성화 테스트다. RESULT 표의 "회귀 테스트" 표기는 이 점에서 약간 과하지만, 한계를 문서 본문에 명시했으므로 은폐가 아니다. 판정에 영향을 주지 않는다.

## mn-8 — 해소 ✓ (새 경고 없음, 구조적으로도 건전)

**요청 항목: 재구조화가 새 deprecation 경고를 만드는가 → 만들지 않는다.**

구조 확인:

```swift
// ABPlayerControls
@available(*, deprecated, …) public init(player:…accessoryViews:…onEvent:)   // 기존
@available(*, deprecated, …) init(legacyPlayer:…)                            // mn-8에서 추가

// ABVideoPlayerWithControls
private let controlsView: AnyView                     // ← body는 이것만 읽는다
@available(*, deprecated, …) public init(…accessoryViews:) { controlsView = AnyView(ABPlayerControls(legacyPlayer: …)) }
public init<Accessories: View>(…accessories:)         { controlsView = AnyView(ABPlayerControls(…accessories: …)) }
public var body: some View { … controlsView … }       // deprecated 심볼 미참조
```

deprecated 심볼(`legacyPlayer:`)에 대한 **유일한** 참조가 **deprecated 선언 내부**(`ABVideoPlayerWithControls`의 레거시 이니셜라이저)에서 일어난다. Swift는 deprecated → deprecated 참조에 경고를 내지 않으므로 경고가 발생하지 않는다. `body`는 이미 완성된 `controlsView`만 읽어 deprecated 심볼을 전혀 건드리지 않는다.

**중요한 점: 이전 리뷰가 지적했던 "과잉 억제"가 발생하지 않았다.** `controls`를 통째로 deprecated로 표시했다면 무관한 `accessories:` 경로의 경고까지 억제됐을 것인데, 그 프로퍼티를 없애고 두 이니셜라이저가 각자 자기 값을 채우는 구조로 바꿔 **억제 범위가 정확히 레거시 경로에만 국한**된다. 1차 시도가 실패한 과정과 최종 구조를 RESULT에 남긴 것도 좋다.

실측(`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 통과)이 이를 뒷받침한다. ✓

---

# 잔여 관찰 (판정 비영향)

## obs-1. `AnyView` 타입 소거와 이니셜라이저 시점 즉시 구성 (mn-8의 부수 효과)

`ABVideoPlayerWithControls`가 오버레이를 `@ViewBuilder` 계산 프로퍼티 대신 `AnyView` 저장 프로퍼티로 바꿨다. 기능적으로는 문제없음을 확인했다 — 구조체는 부모 렌더마다 재구성되므로 `style`/`configuration` 변경이 새 `ABPlayerControls`로 전파되고, 감싸인 구체 타입(`ABPlayerControls`, 비제네릭)이 항상 동일해 SwiftUI의 매칭도 안정적이며, `accessories` 클로저는 init 시점에 평가되지 않는다.

다만 `AnyView`는 SwiftUI의 구조적 identity 최적화를 무력화하는 일반적 안티패턴이다. `UIViewRepresentable` 한 겹을 감싸는 용도라 실질 비용은 작지만, 향후 이 오버레이가 복잡해지면 재고 대상이다.

## obs-2. 컨테이너의 `intrinsicContentSize` 무효화 경로 (MJ-2의 부수 효과 — 확인 권장)

`ABAccessoryHostingContainerView.intrinsicContentSize`가 hosted view의 값을 포워딩하지만, `invalidateIntrinsicContentSize()`는 `ABAccessoryHostingBox.update(_:)`에서만 호출된다. SwiftUI 콘텐츠가 **자체 `@State` 변경으로** 크기가 바뀌는 경우(`update(_:)`를 거치지 않는 경로), `UIHostingController`는 hosted view만 무효화한다.

hosted view가 컨테이너 4변에 required로 핀돼 있고 자체 compression resistance(750)를 가지므로 제약 해석만으로 컨테이너가 따라 커질 **가능성이 높지만**, 코드 수정 없이 확정할 수 없어 단정하지 않는다. 실기기/시뮬레이터에서 액세서리 내부 `@State` 변경 시 레이아웃이 따라오는지 한 번 확인해두면 좋다. 확인 결과 문제가 있다면 컨테이너의 `intrinsicContentSize` 오버라이드를 제거하고 4변 핀만으로 크기를 유도하는 편이 더 정확하다.

## obs-3. `detach()`가 window 이탈 시점에는 호출되지 않는다

`didMoveToWindow`에서 `window == nil`이면 조기 반환하므로, 뷰가 계층에서 빠져도 자식 VC 관계는 유지된다. 실제 해제는 `Coordinator.deinit`에서 일어나므로 **누수는 없다**(이전 리뷰 mn-6 검증 시 확인한 바와 동일). 표준 패턴은 window 이탈 시에도 detach하는 것이나, 현 수명 구조에서는 불필요하다.

## obs-4. Q13 인용 범위가 실제보다 넓게 표현됨

`RESULT-round4-fixes.md`의 mn-4/mn-5 항목이 `@unchecked Sendable`과 `MainActor.assumeIsolated`를 "코드베이스에서 금지(Q13 근거)"라고 서술한다. 실제 `DESIGN-OPEN-QUESTIONS.md:159`의 Q13은 **"컴파일을 통과시키기 위해 `@unchecked`를 붙이는 것"** 을 금지한 것이고, 레포에는 락으로 실제 보호되는 정당한 `@unchecked Sendable`이 30곳 있다(`ABObservationBag`, `ReadyWaitState`, `ABAudioSessionCoordinator` 등).

인용 범위는 넓게 표현됐지만 **내려진 결정은 Q13의 취지에 정확히 부합한다** — 두 경우 모두 "컴파일 에러를 피하려고 붙이는" 상황이었고, `UUID` 비교와 `Task` 홉이라는 진짜 해법을 택했다. 문서 표현만 다듬으면 된다.

---

# 종합

**Major 3건 전부, Minor 8건 전부가 해소됐다.** 특히 요청받은 세 가지 정밀 검증 결과:

- **MJ-1의 `.ignore` 가드 위 이동이 N1 최적화를 무효화하지 않는다** — dirty 플래그가 세팅되는 지점은 여전히 실제 인터럽션·포그라운드 복귀 두 이벤트뿐이며, 연속 `play()` 스킵을 고정하는 기존 테스트가 그대로 통과한다. `.ignore`의 관측 가능한 시맨틱(pause 없음, broadcast 없음)도 보존됐다.
- **MJ-2의 `didMoveToWindow` 컨테이너가 실제 첫 표시에서 발화한다** — 박스 단위 테스트가 "window 이전 미부착 → window 이후 부착"을 수동 호출 없이 단언하고, SwiftUI 통합 테스트가 실제 `UIWindow` 경로를 태운다. Q6-A가 약속한 완화책이 이제 실제로 작동한다.
- **mn-8 재구조화가 새 deprecation 경고를 만들지 않는다** — deprecated 심볼 참조가 deprecated 선언 내부 한 곳으로 국한되고, 이전 리뷰가 우려한 "무관한 경로까지 억제"가 발생하지 않는 구조다. warnings-as-errors 실측 통과가 뒷받침한다.

수정의 품질이 특히 높은 지점 세 가지를 기록해 둔다. 첫째, MJ-1에서 지시받지 않은 세 번째 수정(`applyConfigurationChange` 재평가 트리거)을 스스로 도출했다 — 옵저버 설치 조건 확장의 필연적 귀결을 추적한 것이다. 둘째, MJ-2에서 불필요해진 호출부 코드를 남기지 않고 제거했다. 셋째, `RESULT-round4-fixes.md`가 mn-4 테스트의 판별력 한계와 mn-8 리팩터 도중 만들었다 잡은 `EmptyView` 회귀를 **자진 신고**했다 — 검증 가능한 정직성이며, 실제로 그 신고 덕분에 내 원 지적(mn-4)의 메커니즘 오류를 발견해 이 문서에서 정정할 수 있었다.

내 이전 리뷰의 오류도 함께 기록한다: **mn-7은 지적 자체가 틀렸다**(`RESULT-round4-A.md:23`이 목표 미달과 사유를 처음부터 기록하고 있었다). **mn-4의 취소 메커니즘 서술도 부정확했다**(`Task.value`는 awaiter의 취소로 중단되지 않는다).

잔여 관찰 4건은 전부 판정에 영향을 주지 않는다. obs-2(컨테이너 intrinsic size 무효화)만 실행 환경에서 한 번 눈으로 확인해 두길 권하고, 나머지는 문서 표현·설계 취향 수준이다.

## 후속 권장 (라운드5 이후, 비차단)

1. **obs-2** — 액세서리 내부 `@State` 크기 변경 시 레이아웃 추종 확인
2. **mn-2 잔여** — `currentPlaybackTime` 단일 출처화 (이번엔 범위 사유로 보류, 불변식 테스트로 방어 중)
3. **mn-5 잔여** — `swift-tools-version` 상향 여부는 별도 결정으로 유지
4. **obs-4** — `RESULT-round4-fixes.md`의 Q13 인용 범위 표현 정정
5. **obs-1** — 오버레이가 복잡해질 경우 `AnyView` 소거 재고

FINAL-VERDICT: APPROVE
