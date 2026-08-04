# REVIEW: 리뷰 라운드3 Phase 1+2 심층 리뷰 (시니어 iOS 면접관 관점)

- **대상 범위**: `3d54138..HEAD` (9개 커밋 — Phase 1 정합성 패치 5개 + Phase 2 테스트 보강 4개)
- **작업 지시서**: `docs/briefs/BRIEF-fix-round3-phase1.md`, `docs/briefs/BRIEF-fix-round3-phase2.md`
- **판정**: **REQUEST-CHANGES**

## 대상 커밋

```
68aadaa test: replace polling loops with deadline helper
4169b7d test: cache concurrency, error paths, index recovery
2bb8183 test: cover ABPlayer target event handling
bb86a3a test: cover ReadyWaitState races and waitUntilReady integration
562d91c docs: fix DocC typo and cleanup obsolete files
471fd42 fix: cache waitForProgress cancellation
3726a0a fix: tuning defaults and reapply guard
0726ecc feat: apply audioSessionPolicy with restore
b2dd66c fix: deinit cleanup for AVPlayer observer/tasks
```

## 실측 검증

리뷰 전에 실제로 빌드·테스트를 돌렸다.

```
xcodebuild test -scheme ABPlayerKit-Package -destination 'id=65CDD0F3-DEE7-4132-B823-E86003329F5E'
→ 356 tests / 0 failures / 0 warnings  (iPhone Air, iOS 26.4, macOS 26.4 빌드)
```

zero-warning 요건 및 전체 스위트 통과는 사실이다. 아래 지적은 전부 "테스트가 통과하는데도 남아 있는" 문제다.

---

## Critical

### C1. 다중 ABPlayer 인스턴스가 프로세스 전역 AVAudioSession 스냅샷을 상호 오염시킨다

`Sources/ABPlayerKit/Engine/ABPlayer.swift:613-646`, `Sources/ABPlayerKit/Policy/ABAudioSession.swift:54-73`

각 `ABPlayer`가 **싱글턴** `AVAudioSession`을 자기 인스턴스 필드(`savedAudioSessionSnapshot`)에 스냅샷한다. 그런데 `applyAudioSessionPolicyIfNeeded`는 `guard grade == .current`(ABPlayer.swift:614)로 게이트되지만, **강등(`.current` → `.preloaded`/`.instanceOnly`) 시 복원 트리거가 없다**. 이 라이브러리의 핵심 유스케이스(피드 = preload/current 다중 인스턴스, `Model/ABPlaybackTuning.swift:33` "landing-cell", `StateMachine/ABGradePlanner.swift` 전체 설계)에서 다음이 발생한다:

1. A가 `.current` → snapshot = 호스트의 `.soloAmbient`, activate `.playback`
2. 스크롤 → A가 `.preloaded`로 강등. **복원 없음.** `appliedAudioSessionPolicy`는 유지
3. B가 `.current` → `snapshotCurrentCategory()`가 호스트가 아닌 **A의 `.playback`**을 캡처
4. A `release()` → `restore(.soloAmbient)` + `setActive(false)` — **B가 재생 중인데** 카테고리가 되돌려지고 세션이 비활성화됨
5. B `release()` → `restore(.playback)` → 호스트 앱은 영구히 `.playback`에 갇힘

`Tests/ABPlayerKitTests/ABAudioSessionPolicyTests.swift:16-24`의 `makePlayer()`는 항상 단일 플레이어만 만들기 때문에 이 경로는 테스트가 전혀 없다.

**근본 원인**: 전역 자원의 소유권을 인스턴스별 상태로 모델링했다. 스냅샷/refcount는 프로세스 단위 공유 owner에 있어야 한다.

### C2. `restore()`가 세션 활성 상태를 무시하고 무조건 deactivate한다 → 호스트 오디오를 깬다

`Sources/ABPlayerKit/Policy/ABAudioSession.swift:68-72`

```swift
func restore(_ snapshot: ABAudioSessionCategorySnapshot) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(snapshot.category, mode: snapshot.mode, options: snapshot.options)
    try session.setActive(false, options: [.notifyOthersOnDeactivation])
}
```

`ABAudioSessionCategorySnapshot`(ABAudioSession.swift:33-37)은 category/mode/options만 담고 **세션이 원래 active였는지를 기록하지 않는다.** 호스트 앱이 자체 오디오를 재생 중(세션 active)인 상태에서 ABPlayer가 `release()`되면 호스트의 오디오가 그대로 끊긴다. `.notifyOthersOnDeactivation`은 *다른 앱*에게 알리는 옵션이지 호스트를 보호하지 않는다.

BRIEF WP2.2가 명시적으로 요구한 "`deactivate()`가 호스트 앱 오디오를 깨지 않도록 복원 로직 포함"이 **미충족**이다. 복원은 category/mode/options 되돌리기까지만 하고, active 상태는 원래 값으로만 복구(또는 건드리지 않음)해야 한다.

---

## Major

### M1. 최초 적용 이후 세션이 재활성화되지 않는다 (인터럽션 후 무음)

`Sources/ABPlayerKit/Engine/ABPlayer.swift:616`

```swift
guard policy != .unmanaged, appliedAudioSessionPolicy != policy else { return }
```

첫 성공 적용 이후 `appliedAudioSessionPolicy`가 메모이즈되어 `play()`(ABPlayer.swift:201)와 `.current` 재승격(ABPlayer.swift:163)이 **영구히 no-op**이 된다. 그러나 iOS는 인터럽션(전화, Siri, 타 앱의 세션 탈취) 시 세션을 deactivate하고, 앱은 `.interruptionEnded` 후 `setActive(true)`를 **다시** 호출해야 한다.

재현 경로:

- `backgroundPolicy: .demoteToInstance` → 백그라운드 → `handleDidEnterBackground`가 `.instanceOnly`로 강등(ABPlayer.swift:569-573) → 포그라운드 → `promote(to: restoredGrade)`(ABPlayer.swift:594) → `applyAudioSessionPolicyIfNeeded`가 616에서 short-circuit → **`setActive(true)` 미호출 → 무음**

`appliedAudioSessionPolicy`는 "적용된 정책"이 아니라 "정책 값 캐시"로만 기능하고 있고, 세션의 실제 활성 상태를 추적하지 않는다.

### M2. 부분 실패 시 스냅샷을 폐기해 복원 불가 상태로 남는다

`Sources/ABPlayerKit/Engine/ABPlayer.swift:620-628`, `Sources/ABPlayerKit/Policy/ABAudioSession.swift:12-21`

`ABAudioSession.activate`는 **두 개의 호출**(`setCategory` → `setActive(true)`)이다. `setCategory` 성공 후 `setActive`가 던지는 경우(흔한 `AVAudioSessionErrorCodeCannotInterruptOthers`)에:

```swift
} catch {
    if appliedAudioSessionPolicy == nil {
        savedAudioSessionSnapshot = nil          // ABPlayer.swift:624-626
    }
    surfaceAudioSessionFailure(error)
}
```

호스트의 카테고리는 **이미 덮어써진 상태인데** 원본 기록만 지워진다. 이후 `release()`는 복원하지 않는다.

그리고 `Tests/ABPlayerKitTests/ABAudioSessionPolicyTests.swift:106-128`(`applyFailureSurfacesEvent`)는 `#expect(!audioSession.calls.contains { restore })`(127)로 **이 잘못된 동작을 스펙으로 고정**해버렸다 — fake(`Tests/ABPlayerKitTests/Fakes/ABFakeAudioSessionController.swift:33-38`)가 activate를 원자적 단일 호출로 축약해 부분 실패를 표현할 수 없기 때문이다. 심(seam)이 실제 실패 모드를 재현하지 못하는 전형적 케이스.

### M3. `deinit`이 메인 스레드 밖에서 `AVPlayer.removeTimeObserver`를 호출할 수 있다

`Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:23-24, 71-75, 169-171`

`@MainActor` 클래스지만 `deinit`은 nonisolated이며 **마지막 참조를 놓는 스레드에서 실행**된다. `ABPlayer`는 `@MainActor final class`라 Sendable이고 어떤 executor에서든 보유·해제될 수 있다 — 이 레포 스스로 `Sources/ABPlayerKit/Observation/ABObservationBag.swift:5-7`에서 "either can run on any thread"라고 인정하고 있다. 옵저버는 `queue: nil`(=메인 큐)로 등록되어 있으므로(ABAVPlaybackTarget.swift:169-171), 백그라운드 스레드에서의 `removeTimeObserver`는 실행 중인 옵저버 블록과 경합하는 문서화된 위험 조합이다. WP1이 크래시를 막으려다 다른 크래시 창을 여는 셈이다.

그리고 `nonisolated(unsafe)`는 **deinit만이 아니라 해당 프로퍼티의 모든 접근에서** 격리 검사를 제거한다 — `periodicTimeObserverToken`/`periodicTimeObserverPlayer`(ABAVPlaybackTarget.swift:23-24), `prerollTask`/`seekWorkerTask`(ABPlayer.swift:51,56)는 8곳 이상에서 읽기/쓰기된다. 컴파일러가 이 문제를 잡아줬을 진단을 정확히 그 어노테이션이 침묵시켰다.

선례로 든 `ABApplicationStateObserver`는 deinit이 `NotificationCenter.removeObserver`(문서상 스레드 안전)만 호출하므로 그 논리가 여기로 전이되지 않는다.

**권장**: NSLock 보호 박스(`final class Box: @unchecked Sendable`)로 옮기거나 — 툴체인이 지원하면 — isolated `deinit`(SE-0371). 현재 `Package.swift:1`이 `swift-tools-version: 6.0`이므로 후자는 버전 상향이 필요할 수 있다.

### M4. `ABPlayer.deinit`이 오디오 세션을 복원하지 않는다 — WP1과 WP2가 조합되지 않는다

`Sources/ABPlayerKit/Engine/ABPlayer.swift:109-112`

WP1의 전제 자체가 "소비자가 `release()` 없이 참조를 버린다"인데, 바로 그 경로에서 `restoreAudioSessionPolicyIfNeeded()`(ABPlayer.swift:636)는 절대 실행되지 않는다. 호스트의 `AVAudioSession`이 플레이어의 카테고리에 영구히 남는다.

nonisolated deinit에서는 현 구조상 호출조차 불가능한데, 이는 apply/restore 상태가 `@MainActor` 인스턴스 필드가 아니라 Sendable 박스 또는 공유 owner에 있어야 한다는 C1의 결론과 같은 방향을 가리킨다.

### M5. 동시 `load`의 메타데이터(HEAD) 중복 제거가 안 된다 — 새 테스트가 이를 우회한다

`Sources/ABPlayerKitCache/ABCacheStore.swift:362-374`, `Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift:475-480`

```swift
// 테스트가 스스로 인정한다:
dataReplies: (0..<20).map { _ in metadataReply(length: 8) },
// "Buffer well past 10 in case concurrent tasks race ahead of each
//  other's metadata caching and each issue their own HEAD"
```

`resolvedMetadata`는 캐시 확인과 `cacheMetadata` 쓰기 사이에 `await remoteMetadata`(ABCacheStore.swift:371) 서스펜션이 있어, cold key에 대한 N개 동시 `load`는 N개의 HEAD를 발사한다.

fill(GET)은 `startFillIfNeeded`의 `guard fills[key] == nil`(ABCacheStore.swift:381)이 actor 내 동기 구간이라 정상적으로 1회로 수렴한다 — 즉 브리프 WP7.1의 "fetcher 요청이 1회"는 절반만 달성됐고, 피드 스크롤 시 실제 thundering herd다. 20개 버퍼는 문제를 고친 게 아니라 테스트가 통과하도록 덮은 것.

---

## Minor

### m1. 튜닝 가드가 role 스코프가 아니다

`Sources/ABPlayerKit/Engine/ABPlayer.swift:530-531`

```swift
guard previousConfiguration.currentTuning != configuration.currentTuning
    || previousConfiguration.preloadTuning != configuration.preloadTuning else { return }
```

`.current` 상태에서 `preloadTuning`만 바꿔도 가드를 통과해 변하지 않은 `currentTuning`을 재적용하고 `.tuningApplied(.current, 동일값)`을 방송한다. WP3이 없애려던 바로 그 spurious broadcast가 남았다. 브리프 WP3.2가 문자 그대로 이 조건식을 지시했으므로, 구현자가 브리프의 버그를 지적 없이 따른 케이스다. 커버 테스트 없음.

**수정 방향**: 해석된 role에 해당하는 튜닝만 비교 (`grade == .current ? currentTuning : preloadTuning`).

### m2. `ReadyWaitState` 동시성 테스트의 단언이 공허하다

`Tests/ABPlayerKitTests/ABAVPlaybackTargetReadyWaitTests.swift:55-59`

```swift
let validOutcomes: [ABAVPlaybackTarget.ReadyWaitResult] = [.ready, .timedOut, .cancelled, .failed]
#expect(outcome != nil)
if let outcome { #expect(validOutcomes.contains(outcome)) }
```

`validOutcomes`가 네 케이스 **전부**라 `contains`는 실패할 수 없다. 실질 오라클은 `CheckedContinuation`의 double-resume trap뿐이고, "둘 다 이겼다"는 원천적으로 탐지 불가 — `ReadyWaitState.resolve`가 `Void` 반환(`Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:261`)이기 때문이다.

같은 커밋의 `ABCacheProgressWaiter.resolve()`(`Sources/ABPlayerKitCache/ABCacheStore.swift:70-72`)는 이미 `@discardableResult -> Bool`로 되어 있다. 그 패턴을 미러링해 atomic 카운터로 `winCount == 1`을 단언해야 진짜 테스트가 된다.

또한 barrier 없는 5개 `group.addTask`(테스트 19-42행)는 실제로 겹칠 확률이 낮아 "경합을 만든다"고 보기 어렵다 — 시작 게이트(세마포어/atomic)가 필요하다.

### m3. `cancellationBeforeInstallStillResolvesOnce`는 경합이 아니라 순차 실행이다

`Tests/ABPlayerKitTests/ABAVPlaybackTargetReadyWaitTests.swift:63-84`

`state.resolve(.cancelled)`(73) → `state.install(continuation)`(76)은 결정론적 순서이므로 50회 루프(65)가 아무것도 더하지 않는다. 브리프 WP6.1의 "취소가 continuation 설치보다 먼저 도착" 경로는 논리적으로 커버되지만, 테스트 이름·주석(68-72)은 race를 검증하는 것처럼 과장돼 있다.

### m4. Phase 2에서 추가한 파일이 Phase 2가 없애려던 폴링 패턴을 쓴다

`Tests/ABPlayerKitTests/ABAVPlaybackTargetReadyWaitTests.swift:126-130`

```swift
var iterations = 0
while await flag.invalidated == false, iterations < 1000 {
    await Task.yield()
    iterations += 1
}
```

WP8이 제거 대상으로 지목한 바로 그 패턴이다. 게다가 비결정성이 자초된 것이다: `installObservationInvalidator`는 이미 resolved면 클로저를 **동기 실행**하므로(`Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:255-258`) 로컬 클래스 플래그면 폴링 없이 완전 결정론이 된다.

### m5. `.timeLimit` 적용이 23개 중 4개 suite뿐이고, Phase 2가 추가한 suite에는 하나도 없다

적용된 곳:
- `Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift:152`
- `Tests/ABPlayerKitTests/ABPlayerEngineTests.swift:107`
- `Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift:167`
- `Tests/ABPlayerKitMetricsTests/ABMetricsTests.swift:68`

누락된 신규 suite:
- `Tests/ABPlayerKitTests/ABAVPlaybackTargetReadyWaitTests.swift:12` — **30초 `Task.sleep`(97)을 포함**, 회귀 시 CI를 가장 오래 잡아둘 후보
- `Tests/ABPlayerKitTests/ABAVPlaybackTargetReadyWaitTests.swift:139`
- `Tests/ABPlayerKitTests/ABAudioSessionPolicyTests.swift:11`
- `Tests/ABPlayerKitTests/ABPlayerEngineTests.swift:583` (`ABPlayerDeinitCleanupTests`)

WP8.3 "각 테스트 타겟의 주요 @Suite에 `.timeLimit`" 미충족.

### m6. WP8.2 치환이 미완이다

고정 yield 횟수에 의존하는 대기가 남아 있다:

- `Tests/ABPlayerKitTests/ABScrubbingEngineTests.swift:186` — `for _ in 0..<10 { await Task.yield() }`
- `Tests/ABPlayerKitTests/ABScrubbingEngineTests.swift:69`, `:233` — `Task { await player.endScrubbing() }` 직후 단일 `await Task.yield()`
- `Tests/ABPlayerKitTests/ABPlayerEngineTests.swift:313`, `:319`

이들은 "아무 일도 안 일어남"을 기다리는 케이스라 `waitUntil`로 표현 불가한 건 맞지만, 고정 yield도 해법은 아니다 — 결정론적 신호(fake가 seek를 완료시키는 등)나 최소한 왜 그런지에 대한 주석이 필요하다.

`Task.sleep` 대기도 2곳 생존 — WP8 "sleep 기반 대기 금지"와 충돌:
- `Tests/ABPlayerKitControlsTests/ABPlayerControlsAutoHideTests.swift:43`
- `Tests/ABPlayerKitControlsTests/ABPlayerControlsAccessibilityTests.swift:73`

### m7. `ABWaitUntil.swift`가 3개 테스트 타깃에 33줄씩 그대로 복붙됐다

- `Tests/ABPlayerKitTests/Support/ABWaitUntil.swift`
- `Tests/ABPlayerKitCacheTests/Support/ABWaitUntil.swift`
- `Tests/ABPlayerKitControlsTests/Support/ABWaitUntil.swift`

공용 `ABTestSupport` 타깃이면 3방향 드리프트를 막을 수 있다.

### m8. `targetDeinitRemovesPeriodicTimeObserver`의 `#expect`가 직전 `waitUntil`과 중복이다

`Tests/ABPlayerKitTests/ABPlayerEngineTests.swift:590-610` 부근

`try await waitUntil { weakPlayer.value == nil }` 직후의 `#expect(weakPlayer.value == nil)`은 항상 참이다. 실제 회귀 오라클은 잡히지 않은 `NSInternalInconsistencyException`으로 테스트 프로세스가 죽는 것 — 유효한 오라클이지만 테스트에 그렇게 명시돼야 하고, "deinit이 제거했다"와 "AVFoundation이 더 이상 raise 안 한다"를 구별하지 못한다.

반면 같은 suite의 `playerDeinitCancelsPrerollTask`는 진짜 테스트다 — deinit이 없으면 그 Task를 취소할 주체가 아무도 없으므로(`prerollTask`는 `[weak self, target]` 캡처, ABPlayer.swift:463) 2초 데드라인에서 확실히 실패한다.

### m9. `ABPlayerError.audioSessionOperationFailed`의 semver 문서 정합

`Sources/ABPlayerKit/Model/ABPlayerError.swift:14-20`

public non-`@frozen` enum의 새 case → 소비자의 exhaustive `switch`에 대해 source-breaking. 추가된 주석은 "`ABPlayerEvent`의 doc comment 참조"라 하지만, non-exhaustive 관례는 `ABPlayerEvent`에 대해서만 문서화돼 있고(`Sources/ABPlayerKit/ABPlayerKit.docc/ABPlayerKit.md:23`) `ABPlayerError` 타입 자체에는 그 노트가 없다.

레포가 v0.2.0(`git tag`)이라 0.x 재량 범위이나, DocC 줄과 `ABPlayerError` 타입 doc을 함께 갱신해야 정합이 맞는다.

### m10. 테스트 코멘트 오기

`Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift:501-504`

"fillRequest/stream(for:) requests have no explicit HTTP method set, so `URLRequest.httpMethod` defaults to GET"라 적혀 있으나, 실제로는 `fillRequest`가 `httpMethod = "GET"`을 명시(`Sources/ABPlayerKitCache/ABCacheStore.swift:612`)하고 메타데이터 요청은 `"HEAD"`를 명시(같은 파일 606)한다. 단언 자체는 맞지만 근거가 틀렸다.

### m11. `ABPlaybackTuning.displayCapped`가 `ABPlaybackTuning()`과 중복 정의다

`Sources/ABPlayerKit/Model/ABPlaybackTuning.swift:21-31` vs `:56-61`

기본값 추가로 두 값이 바이트 동일해졌다. `public static let displayCapped = ABPlaybackTuning()`으로 두면 둘의 드리프트를 원천 차단할 수 있다.

### m12. `ABCacheStore`에 teardown deinit이 없다

`Sources/ABPlayerKitCache/ABCacheStore.swift`

서스펜드된 `waitForProgress` waiter가 남은 채 store가 dealloc되면 continuation이 누수된다. WP4 이전에도 동일했던 선재 이슈지만, WP4가 정확히 이 코드를 건드렸고 `resolveEverything()`(127)이 이미 존재한다 — 현재 호출처는 `removeAll()`(265)뿐이다.

---

## 브리프 검토 포인트별 판정

| # | 검토 포인트 | 판정 | 근거 |
|---|---|---|---|
| **(1)** | deinit 박스 안전성 / 이중 해제 멱등 | **부분 통과** | 멱등성은 검증됨 — `releasePlayer()`가 두 프로퍼티를 nil로(ABAVPlaybackTarget.swift:186-187) → deinit은 진짜 no-op, `Task.cancel()`도 nil/완료 Task에 no-op. `attachItem`/`detachItem`도 동일 경로. 그러나 **M3**(off-main 실행 + 과광범위 어노테이션) 미해결 |
| **(2)** | audioSessionPolicy 적용/복원 정확성 | **불통과** | **C1·C2·M1·M2·M4**. Q4 "이전 카테고리 복원"의 문자적 요구는 만족하나 다중 인스턴스·부분 실패·재활성화·deinit 경로가 전부 미처리. 복원 순서 자체(interpret → releasePlayer → restore, ABPlayer.swift:160-171 / setCategory → setActive(false))는 올바름 |
| **(3)** | 튜닝 재적용 가드가 grade 전이를 깨뜨렸나 | **통과** | `ABGradePlanner`의 `→ .current`/`→ .preloaded` 모든 셀이 `.applyTuning`을 방출하고(ABGradePlanner.swift:49,52,62,65,78,96,108,123) `interpret`이 `lastAppliedTuningRole`을 갱신(ABPlayer.swift:413). 가드는 `applyConfigurationChange` 내부에만 있고(ABPlayer.swift:530) planner 경로는 그곳을 지나지 않음. **깨지지 않았다.** 단 **m1** |
| **(4)** | 캐시 waiter 취소의 actor 격리 / leak | **통과** | 4개 인터리빙 전부 추적: (a) add 후 이미 취소 → `onCancel` 선행 → `install`이 `isResolved` 관측 후 즉시 resume, (b) `resolveAll`이 install 전 도착 → 동일, (c) resolve/cancel 동시 → `isResolved` 가드로 한쪽만 승리, (d) 정상 완료. `onCancel`(ABCacheStore.swift:683-686)은 `waiter`(@unchecked Sendable)와 `progressWaiters`(`nonisolated let`, 161)만 만지고 actor 격리 상태를 건드리지 않음. 이중 `remove`는 no-op. **격리 정합, leak 없음** |
| **(5)** | 신규 테스트의 tautology / 실제 경합 | **부분 불통과** | ReadyWaitState 동시성 테스트는 단언이 공허하고 실제 경합을 만들지 않음(**m2·m3·m4**). 반면 캐시 쪽은 우수 — `entryTooLargeMidFillFallsBackToPassthrough`는 브리프(`#expect(throws: .entryTooLarge)`)와 다른 실제 동작을 근거와 함께 검증했고, `ABFakeFetchError`(ABCacheStoreTests.swift:11-13)를 `StoreError`와 구분해 false pass를 막았으며, `cancellingStalledLoadThrowsPromptlyAndFreesReader`(같은 파일 723-765)는 진짜 회귀 테스트다. `ABPlayer.handle(_:)` 5 case와 튜닝 가드 테스트도 유효 |
| **(6)** | ABPlaybackTuning 기본값 semver 비파괴 | **통과** | 기존 public `init`(ABPlaybackTuning.swift:21-31)에 default value 추가는 source-compatible. 기본값이 `.displayCapped`(56-61)와 바이트 동일하고 Q2 확정안(`docs/DESIGN-OPEN-QUESTIONS.md`)과 일치. SPM 소스 배포라 ABI 이슈 없음. 향후 5번째 프로퍼티 추가도 비파괴 |
| **(7)** | 테스트 전용 훅의 public API 오염 | **통과** | `ABCacheStore`는 internal(ABCacheStore.swift:146)이므로 `metadataCacheOrderSnapshot()`(231)·`activeReaderKeys()`(241) 비노출. `ReadyWaitResult`/`ReadyWaitState`/`waitUntilReady` 승격(ABAVPlaybackTarget.swift:209,221,284)은 internal `ABAVPlaybackTarget` 내부. `ABAudioSessionControlling`/`ABAudioSessionCategorySnapshot`/`ABAudioSessionAdapter`(ABAudioSession.swift:33,44,54) 전부 internal. `ABFakePlaybackTarget.emit`은 테스트 타깃. **public API 오염 없음.** 유일한 흠: `#if DEBUG` 게이팅이 없어 모듈 내 프로덕션 코드에서도 호출 가능 |

---

## 잘된 점 (크레딧)

- **WP4의 waiter 설계는 정확하다.** `ABCacheProgressWaiter`/`ABCacheProgressWaiterRegistry`(ABCacheStore.swift:46-135)의 "resolved 상태를 install까지 보존" 패턴은 `ReadyWaitState`와 일관되며, 네 인터리빙 어디서도 double-resume이나 leak이 없다.
- **WP1 멱등성**은 실제로 성립한다 — `releasePlayer()` 이후 deinit은 진짜 no-op.
- **WP3이 grade 전이 경로를 깨지 않았다**는 것을 planner 전 셀을 훑어 확인했다.
- **캐시 테스트가 브리프에 맹종하지 않았다.** WP7.2가 요구한 `#expect(throws: .entryTooLarge)`를 그대로 쓰지 않고, 스토어가 의도적으로 복구한다는 실제 동작을 근거와 함께 검증했다.
- **`ABVideoPlayerWithControlsTests.swift:10-23`의 단언 0개 테스트**를 삭제 대신 실제 계층 탐색 + style/configuration 단언으로 승격했다(WP8.4).
- **DocC 오기 수정**(`ABPlayerKit.md:21`)과 빈 `ABPlayerKitControls.swift` 삭제는 정확히 수행됐고 빌드 영향 없음.

---

## 최종 판정: REQUEST-CHANGES

머지 차단 사유는 **WP2(오디오 세션) 한 곳에 집중**돼 있다.

**C1·C2**는 이 라이브러리가 존재하는 이유인 다중 플레이어 피드 시나리오에서 프로세스 전역 상태를 복구 불가능하게 오염시키고, WP2.2의 명시적 수용 기준("deactivate가 호스트 오디오를 깨지 않을 것")을 충족하지 못한다. **M1·M2·M4**는 같은 서브시스템의 상태 모델(인스턴스별 `appliedAudioSessionPolicy`/`savedAudioSessionSnapshot`)이 전역 자원을 표현하기에 부적합하다는 동일한 근본 원인에서 파생된다.

→ 개별 패치보다 **소유권 재설계**를 권한다: 프로세스 단위 공유 owner + refcount + 실제 active 상태 추적, 그리고 다중 인스턴스 시나리오를 커버하는 테스트 추가.

나머지는 머지 가능한 수준이다. WP1의 멱등성, WP3의 grade 전이 보존, WP4의 취소 처리, WP5·WP6 대부분, WP7 캐시 테스트는 검증했고 견고하다. **M3**(deinit off-main)는 WP2 재작업과 함께 처리하면 되고, **M5**와 Minor들은 후속 커밋으로 분리해도 무방하다.
