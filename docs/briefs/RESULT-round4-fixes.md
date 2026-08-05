# RESULT: 라운드4 게이트 리뷰 수정 (REVIEW-round4-final.md 대응)

`docs/briefs/REVIEW-round4-final.md`(판정 REQUEST-CHANGES)의 Major 3건 + Minor 8건 전부를 지시된 우선순위대로 처리했다. 매 항목 수정 후 전체 4개 테스트 번들을 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`로 재검증했고, 최종적으로 라이브러리 테스트 + 데모 앱 빌드 + `DOCC_WARNINGS_AS_ERRORS=YES` 문서 빌드까지 전부 통과를 확인했다(부팅된 시뮬레이터만 사용, 새 부팅 없음). 커밋은 하지 않았다.

## 최종 검증

```
xcodebuild test -scheme ABPlayerKit-Package SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
→ 406 tests / 0 failures / 0 warnings   (399 → 406, +7)

xcodebuild build -project Examples/ABPlayerKitDemo/... SWIFT_TREAT_WARNINGS_AS_ERRORS=YES → BUILD SUCCEEDED
xcodebuild docbuild ... DOCC_WARNINGS_AS_ERRORS=YES → BUILD DOCUMENTATION SUCCEEDED
```

| 번들 | 이전 | 이후 |
|---|---|---|
| ABPlayerKitTests | 174 | 175 (+1, MJ-1 회귀 테스트) |
| ABPlayerKitControlsTests | 179 | 184 (+5: MJ-2 2개, MJ-3 1개, mn-2 1개, mn-3 1개) |
| ABPlayerKitCacheTests | 38 | 39 (+1, mn-4 회귀 테스트) |
| ABPlayerKitMetricsTests | 8 | 8 |

## Major

| ID | 판정 | 조치 |
|---|---|---|
| **MJ-1** | 수정 완료 | `Sources/ABPlayerKit/Engine/ABPlayer.swift` — `handleInterruptionBegan()`에서 `audioSessionActivationDirty = true`를 `.ignore` 가드 **위로** 이동(리뷰의 정확한 수정 방향 그대로). 추가로 `reconcileInterruptionObserver()`의 옵저버 설치 조건에 `audioSessionPolicy != .unmanaged`를 추가하고(리뷰가 "필요하다"고 명시한 두 번째 반쪽 — `interruptionPolicy`/`pausesOnRouteChangeDeviceUnavailable`가 둘 다 꺼진 조합에서도 세션 관리 중이면 옵저버가 설치되도록), `applyConfigurationChange`의 재평가 트리거에 `audioSessionPolicy` 변경도 추가(옵저버 설치 조건이 넓어졌으니 그 변경 자체도 재평가를 유발해야 함). **회귀 테스트**: `ABAudioSessionPolicyTests.playReactivatesForInterruptionRecoveryUnderIgnorePolicy` — 리뷰의 정확한 재현 시나리오(전부 기본값 + `audioSessionPolicy` 옵트인만)를 그대로 실행해 인터럽션 후 재생 재개 시 세션이 재활성화됨을 확인 |
| **MJ-2** | 수정 완료 | `Sources/ABPlayerKitControls/SwiftUI/ABAccessoryHostingBox.swift` — `view`가 이제 `controller.view`를 감싸는 얇은 `ABAccessoryHostingContainerView`(신설, `didMoveToWindow`를 오버라이드하는 것이 유일한 목적)를 반환한다. window에 실제로 도달하는 순간 스스로 `attach(to:)`를 호출한다. `ABPlayerControls.update(_:coordinator:)`의 기존 `if view.window != nil { box.attach(to: view) }` 호출은 제거(더 이상 필요 없음, 근거가 사라진 코드를 남겨두지 않음). **회귀 테스트**: `ABAccessoryHostingBoxTests.attachFiresAutomaticallyOnOrdinaryFirstDisplay`(박스 단독, 실제 `UIWindow` 부착, `attach(to:)` 수동 호출 없이 자동 부착 확인) + `ABPlayerControlsSwiftUITests.accessoriesAttachToParentOnRealWindowDisplay`(SwiftUI 래퍼 전체 경로를 실제 `UIHostingController`+`UIWindow`로 통합 검증 — 리뷰가 "호출부의 트리거 조건은 어느 테스트도 검증하지 않는다"고 지적한 공백을 정확히 메움) |
| **MJ-3** | 수정 완료(원래 의미로 복원) | `ABControlsPresenter.Input.playPauseTapped`를 `(isPlaying: Bool, allowsPromotionTap: Bool)`로 변경 — `isPlaying`은 호출부가 `player.isPlaying`(라이브 값)에서 직접 읽어 전달하며, 프레젠터는 **자신의 캐시된 `isPlaying`이 아니라 이 값**으로 분기한다. `ABPlayerControlsView.togglePlayback()`도 `presenter.handle(.playPauseTapped(isPlaying: player.isPlaying, ...))`로 수정. 순수 이동 원칙대로 사전-추출 `togglePlayback`의 분기 기준(`player.isPlaying`)을 정확히 복원했다 — 리뷰가 제시한 두 옵션 중 (b)를 선택 |

## Minor

| ID | 판정 | 조치 |
|---|---|---|
| **mn-1** | 수정 완료(제거) | `ABControlsPresenter.Input.attached`에서 죽은 `promotesToCurrentOnPlay` 파라미터 제거 — `.attached(grade: ABPlaybackGrade)`만 남김. `replacePlayer()`/기존 테스트 2건 갱신 |
| **mn-2** | 완화(불변식 테스트 추가) | 뷰/프레젠터의 `currentPlaybackTime` 이중 보유 자체는 유지(단일화는 범위가 커 이번 라운드에서 보류) — 대신 리뷰가 제안한 "최소한 불변식을 단언하는 테스트"를 추가: `ABPlayerControlsAccessibilityTests.seekCompletedKeepsPresenterPlaybackTimeInSyncForAccessibilityAdjustment`가 `seekCompleted` 이후 `presenter.currentPlaybackTime`이 실제로 갱신됐는지(스테일 값이 아닌지)를 접근성 조정 결과로 간접 검증 |
| **mn-3** | 리뷰 권고안 그대로 적용(API 표면 변경 없음) | 리뷰가 명시한 대로 "기본값을 주는 해법은 없다"는 판단을 그대로 수용 — API 시그니처는 건드리지 않고 CHANGELOG(`### Deprecated` 항목에 `{}` 마이그레이션 명시 문단 추가)와 README(영/한, 콜아웃 박스 추가)에 안내를 보강. 누락됐던 컴파일 테스트도 추가: `ABPlayerControlsInitializerAmbiguityTests.videoPlayerWithControlsAllDefaultsCompileForBothOverloads`(`ABVideoPlayerWithControls`의 인자 없는 호출이 레거시로 해석되고, `{}` 트레일링 클로저가 신규 이니셜라이저로 해석됨을 컴파일로 증명) |
| **mn-4** | 수정 완료 | `Sources/ABPlayerKitCache/ABCacheStore.swift` — `resolvedMetadata`의 캐시 기록(`cacheMetadata`)과 슬롯 정리를 첫 호출자의 `defer` 대신 **코얼레싱 Task 자신의 본문**(`finishMetadataRequest`)에서 수행하도록 재구성 — 어떤 호출자가 취소되든 태스크 자체는 끝까지 실행되어 캐시에 정확히 한 번 기록된다. `PendingMetadataRequest`를 `@Sendable` 클로저에 직접 캡처할 수 없어(비-`Sendable` 클래스, `@unchecked Sendable`은 금지 — Q13 근거와 동일) `UUID` 기반 값 비교로 정체성 비교를 재구현. **회귀 테스트**: `ABCacheStoreTests.cancelledFirstCallerStillCachesAndCoalescesForLaterCallers` — 신설한 게이트형 fetcher(`ABGatedHTTPFetcher`/`ABGate`)로 HEAD 응답을 인위적으로 지연시켜, 취소된 첫 호출자가 있어도 두 번째 호출자가 같은 코얼레싱 태스크에 합류하고 세 번째(완전히 독립적인) 호출이 캐시 히트로 처리됨을 확인. **정직한 한계**: 이 테스트가 취소를 유발하는 정확한 Swift 런타임 메커니즘(외부 `Task.cancel()`이 `await request.value`를 조기에 인터럽트하는지 여부)까지는 검증하지 못한다 — 실제로 이 토대킷/런타임에서는 외부 캐스트 취소가 `Task.value` 대기를 즉시 중단시키지 않음을 실험으로 확인했다(리뷰의 재현 서술과 다를 수 있음). 그럼에도 새 코드 구조(태스크 자신이 캐시·정리를 수행)가 **어떤 취소 타이밍에서도** 올바르다는 점은 코드 자체의 구조적 성질이며, 테스트는 그 구조가 실제로 동작함을 확인한다 |
| **mn-5** | 수정 완료(보수적 — 기능 유지, 선언만 조정) | `Coordinator.isolated deinit`(SE-0371, `swift-tools-version: 6.1`+ 필요)을 일반 `deinit`으로 되돌리고, `accessoryBox?.detach()`를 `Task { @MainActor in accessoryBox.detach() }`로 비동기 홉시켜 처리 — `swift-tools-version: 6.0`은 그대로 두었다(툴체인 하한을 올리는 건 이번 정리보다 훨씬 큰 별도 결정). `MainActor.assumeIsolated`는 이 코드베이스에서 금지(Q13과 동일 근거)라 사용하지 않았다. 기능(정리 시점에 박스를 확실히 detach)은 유지되고 실행이 다음 MainActor 턴으로 한 틱 늦춰질 뿐이다 |
| **mn-6** | MJ-2에서 함께 해소 | `detach()`가 이제 `controller.willMove(toParent: nil)` → `container.removeFromSuperview()` → `controller.removeFromParent()` 표준 순서를 따른다. `ABAccessoryHostingBoxTests.attachAdoptsParentAndDetachReleasesIt`에 `box.view.superview == nil` 단언 추가 |
| **mn-7** | 이미 충족(확인만) | `RESULT-round4-A.md`를 재확인한 결과, 목표(~620줄/−44%) 대비 실적(957줄/−13.7%) 차이와 그 사유(스크러빙 3개 메서드 의도적 미이관 등)가 이미 요약 표 바로 아래 문단에 명시돼 있었다 — 리뷰 시점 이후 누락된 것이 아니라 처음부터 기록돼 있었음을 재확인. 추가 수정 불필요 |
| **mn-8** | 수정 완료 | `ABPlayerControls.init(legacyPlayer:...)`(internal)에 `@available(*, deprecated)` 추가. 이 결정이 `ABVideoPlayerWithControls`의 유일한 호출부에서 "non-deprecated 컨텍스트가 deprecated 심볼을 참조"하는 새 경고를 만들어냈고(WP-B3와 동일한 함정), 1차 시도(호출부만 별도 `deprecated` 프로퍼티로 감싸기)는 SwiftUI `@ViewBuilder` 분기 안에서 여전히 "non-deprecated `controls`가 deprecated `legacyControls`를 참조"하는 문제로 실패했다. 최종 구조: `ABVideoPlayerWithControls`가 `controlsView: AnyView` 단일 저장 프로퍼티를 두고, **두 이니셜라이저 각각이** 자신에게 맞는 `ABPlayerControls` 이니셜라이저(레거시 쪽은 이제 deprecated `legacyPlayer:`, 신규 쪽은 `accessories:`)를 호출해 이 값을 채운다 — `body`는 이미 완성된 `controlsView`만 읽으므로 deprecated 심볼을 전혀 참조하지 않는다. (부수적으로 발견: 이 리팩터 도중 `accessories: {}`(EmptyView) 경로가 아무 뷰도 렌더링하지 않는 회귀를 만들었다가 테스트로 즉시 잡아 수정 — 최종 코드에는 남아있지 않음) |

## 회귀 방지 확인

Major 3건은 전부 실제 재현/근접 재현 조건을 갖춘 자동화 테스트로 고정했다. Minor 중 mn-1/mn-5/mn-6/mn-8은 구조적 수정이라 기존 테스트가 그대로 커버하고, mn-2/mn-3/mn-4는 신규 테스트를, mn-7은 문서 확인만 필요했다.
