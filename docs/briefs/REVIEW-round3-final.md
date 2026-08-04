# REVIEW: 리뷰 라운드3 최종 재리뷰 (Phase 3 + Phase 4)

- **대상 범위**: `68aadaa..HEAD` (11개 커밋 — Phase 3 수정 5개 + Phase 4 신기능/문서 6개)
- **대조 기준**: `docs/briefs/REVIEW-round3-phase1-2.md` (직전 REQUEST-CHANGES 리뷰)
- **작업 지시서**: `docs/briefs/BRIEF-fix-round3-phase3.md`, `docs/briefs/BRIEF-fix-round3-phase4.md`

## 대상 커밋

```
fef3c09 docs: document custom time format contract and passthrough behavior
958ae5a docs: refresh README, CHANGELOG and maintainer docs; ci: enable coverage
73fccb0 fix: stop double-combining custom time format output
ce4d1ef feat: add cache passthrough fallback for distant offsets
f6d60f7 feat: handle audio interruptions and route changes
96ab689 feat: adopt @Observable on ABPlayer
a294c7a docs: add round-3 review record and phase briefs
ae104d1 test: strengthen ReadyWaitState race coverage and cleanups
eda2e9c fix: coalesce duplicate metadata requests in cache store
82efb3a fix: remove time observer on main thread in deinit
ccc8d9b refactor: redesign audio session ownership with shared coordinator
```

## 실측 검증

```
xcodebuild test -scheme ABPlayerKit-Package -destination 'id=65CDD0F3-…'
→ 373 tests / 0 failures / 0 warnings  (iPhone Air, iOS 26.4)
```

빌드 경고는 `appintentsmetadataprocessor`의 "No AppIntents.framework dependency" 노이즈뿐이며 컴파일러 경고는 0건이다.

추가로 `@Observable` + `didSet` 상호작용은 스크래치패드에서 별도 실증했다 (레포 미변경):

```
didSet-property Observation-tracked: true | didSet body ran: 1 | plain tracked: true
```

→ `ABPlayer.configuration`의 `didSet { applyConfigurationChange(from:) }`는 `@Observable` 매크로 전개 후에도 **정상 발화하며 동시에 Observation 추적 대상**이다. WP9.2의 우려는 실제로 발생하지 않는다.

---

## 1. 직전 리뷰 항목별 해소 검증

### Critical

#### C1 — 다중 인스턴스 AVAudioSession 스냅샷 오염 → **해소 ✓**

`Sources/ABPlayerKit/Policy/ABAudioSessionCoordinator.swift` 신설. 리뷰 권고(인스턴스 상태 → 프로세스 단위 공유 owner)를 그대로 채택했다.

- `apply(_:for:)` — `if participants.isEmpty { hostSnapshot = controller.snapshotCurrentCategory() }` (56-58). **최초 참여자만** 스냅샷.
- `leave(_:)` — `guard participants.isEmpty, let snapshot = hostSnapshot else { return nil }` (87). **마지막 참여자만** 복원.

네 가지 인터리빙을 추적해 검증했다: A단독 → A퇴장(복원, 스냅샷 nil) → B진입(재스냅샷) ✓ / A+B → A퇴장(무복원, 스냅샷 보존) → B퇴장(호스트 복원) ✓ / apply 실패 후 퇴장 ✓ / 미등록 토큰 퇴장 no-op ✓.

테스트도 실질적이다. 특히 `Tests/ABPlayerKitTests/ABAudioSessionPolicyTests.swift:203-230` (`demotedParticipantPreventsSnapshotContamination`)는 직전 리뷰 C1의 **정확한 재현 시나리오**(A `.current`→`.preloaded` 강등, B `.current` 승격, A 먼저 release)를 그대로 테스트로 옮겼고, `#expect(snapshotCurrentCategory 호출 == 1)`로 오염 부재를 단언한다. `twoPlayersShareSessionUntilLastRelease`(173-201)가 refcount 경로를 커버한다.

#### C2 — 무조건 deactivate로 호스트 오디오 차단 → **실질 해소 ✓ (잔여 한계 문서화 필요)**

`ABAudioSessionControlling.restore(_:deactivate:)`로 시그니처를 확장하고(`Policy/ABAudioSession.swift:55`), 어댑터는 `guard deactivate else { return }`(93)로 조건부 처리한다. 코디네이터는 `didActivateSession`(40)이 참일 때만 `true`를 넘긴다(89-92).

`didActivateSession` 의미론을 4가지 조합으로 검증했다:

| A | B | 마지막 퇴장 시 deactivate | 판정 |
|---|---|---|---|
| 성공 | — | true | ✓ |
| 부분실패 | — | false | ✓ (우리가 활성화한 적 없음) |
| 성공 | 실패 | true | ✓ (B의 실패가 A의 활성화를 무효화하지 않음) |
| 실패 | 실패 | false | ✓ |

`applyFailureSurfacesEventAndKeepsSnapshotRestorable`(122-150)이 `.restore(snapshot, deactivate: false)`를 정확히 단언한다.

**잔여 한계 (수정 불가, 문서화 권장)**: `didActivateSession`은 "우리가 `setActive(true)`에 성공했다"를 기록하지, "우리 이전에 세션이 비활성이었다"를 기록하지 않는다. 호스트가 이미 자기 오디오를 재생 중(세션 active)인 상태에서 ABPlayer가 정책을 적용하면 우리의 `setActive(true)`도 성공하고, 마지막 퇴장 시 `setActive(false)`로 **호스트 오디오가 여전히 끊긴다**. 다만 `AVAudioSession`에는 공개된 활성 상태 getter가 없어 스냅샷으로 표현할 방법이 원천적으로 없다. C2의 핵심(형제 플레이어 차단, 활성화하지도 않은 세션 강제 비활성화)은 제거됐고 남은 것은 OS API 한계이므로 **해소로 판정**한다. README "Audio Session and Interruptions" 절에 이 한 줄 단서를 추가할 것을 권한다.

### Major

#### M1 — 인터럽션 후 재활성화 안 됨 → **해소 ✓**

`applyAudioSessionPolicyIfNeeded`(ABPlayer.swift:613 부근)에서 `appliedAudioSessionPolicy != policy` 메모이제이션을 제거하고, 코디네이터가 항상 `controller.activate`를 통과시킨다(60-63). `playReactivatesForInterruptionRecovery`(ABAudioSessionPolicyTests.swift:58-72)가 `[.snapshotCurrentCategory, .activate, .activate]`로 두 번째 활성화를 단언한다.

#### M2 — 부분 실패 시 스냅샷 폐기 → **해소 ✓**

`catch` 블록(64-74)이 `hostSnapshot`과 `participants` 엔트리를 **모두 유지**하며, 주석이 그 이유(setCategory가 이미 적용됐을 수 있음)를 정확히 서술한다. 직전 리뷰가 "잘못된 동작을 박제했다"고 지적한 테스트도 `.restore(..., deactivate: false)`를 기대하도록 재작성됐다.

#### M3 — deinit이 메인 밖에서 removeTimeObserver 호출 → **해소 ✓**

`nonisolated(unsafe)` 두 프로퍼티를 폐기하고 `PeriodicObserverBox`(ABAVPlaybackTarget.swift:396-431)로 교체했다. 두 가지를 동시에 해결한다:

1. 락 보호 — 모든 접근(정상 `@MainActor` 경로 + `deinit`)이 단일 박스를 통과하므로, 직전 리뷰가 지적한 "어노테이션이 8곳 이상의 격리 검사를 전부 무력화한다"는 과광범위성이 사라졌다.
2. `if Thread.isMainThread { … } else { DispatchQueue.main.async { … } }`(423-429) — `queue: nil`(메인 큐) 옵저버와의 경합 제거.

토큰/플레이어를 락 안에서 먼저 nil로 만든 뒤 락 밖에서 `removeTimeObserver`를 호출하므로 멱등성도 유지된다(중복 호출 시 두 번째는 guard에서 반환).

#### M4 — deinit이 오디오 세션 복원 안 함 → **해소 ✓**

`ABPlayer.deinit`(167-171)이 `audioSessionCoordinator.leave(audioSessionToken)`을 호출한다. 코디네이터가 actor가 아니라 락 보호 클래스라 nonisolated deinit에서 호출 가능하다는 설계 근거가 성립한다. `audioSessionToken`은 `private nonisolated var { ObjectIdentifier(self) }`(computed)라 `@Observable` 매크로가 건드리지 않고 deinit에서 읽을 수 있다.

`deinitLeavesCoordinator`(ABAudioSessionPolicyTests.swift:234-257)가 `release()` 없이 스코프 이탈 후 `.restore(…, deactivate: true)`까지 도달함을 단언한다.

#### M5 — 동시 load의 HEAD 중복 → **해소 ✓**

`pendingMetadataRequests`(ABCacheStore.swift:167)로 in-flight HEAD를 키별 공유한다. `resolvedMetadata`(382-408)에서 조회(396)와 저장(400) 사이에 서스펜션 포인트가 없으므로 actor 내에서 coalescing이 성립한다.

무엇보다 직전 리뷰가 "테스트가 문제를 덮었다"고 지적한 부분이 정면으로 수정됐다: `dataReplies`가 20개 → **1개**로 줄었고(ABCacheStoreTests.swift:481), `#expect(HEAD 요청 == 1)`(507)이 추가됐다. 이제 회귀 시 테스트가 실패한다.

### Minor

| 항목 | 판정 | 근거 |
|---|---|---|
| m1 (튜닝 가드 role 스코프) | **미처리** | `ABPlayer.swift:589-590` 가드가 여전히 `currentTuning \|\| preloadTuning` OR 조건. Phase 3 브리프 그룹 E 목록에 애초에 없어 **의도적 이월**로 보인다 |
| m2 (공허한 동시성 단언) | **해소 ✓** | `ReadyWaitState.resolve`가 `@discardableResult -> Bool`로 변경(ABAVPlaybackTarget.swift:257-283). 테스트가 `#expect(wins.count == 1)` + `#expect(resumed == wins)`로 실제 오라클 확보 |
| m3 (순차 실행을 race로 위장) | **해소 ✓** | `ABAsyncGate` actor 도입으로 resolve → open → wait → install 순서를 **다른 Task에서** 결정론적으로 강제. 브리프 D.2가 요구한 "결정론적 순서 제어"와 정확히 일치 |
| m4 (신규 파일의 구식 폴링) | **해소 ✓** | 1000회 yield 루프 제거, 동기 호출을 그대로 단언(`#expect(flag.invalidated)`). 테스트가 `async`조차 아니게 됨 |
| m5 (.timeLimit 미적용) | **해소 ✓** | `@Suite` 50개 / `timeLimit` 50개 — 전수 적용 |
| m6 (폴링 치환 미완) | **부분** | 남은 사이트에 근거 주석이 붙었으나(ABPlayerEngineTests.swift:316, ABScrubbingEngineTests.swift:72/251) `for _ in 0..<10 { await Task.yield() }`는 여전히 ABScrubbingEngineTests.swift:201에 있고, Phase 4가 같은 패턴을 3곳 **추가**했다(ABAudioInterruptionTests.swift:142,189 / ABPlayerObservationTests.swift:101) |
| m7 (ABWaitUntil 3벌 복붙) | **해소 ✓ (스코프대로)** | 3개 파일 모두에 "의도적 복제, 별도 타깃은 스코프 밖, 수동 동기화" 주석 추가 |
| m8 (중복 #expect) | **해소 ✓** | ABPlayerEngineTests.swift:613-615 — 중복 제거 + 근거 주석 |
| m9 (ABPlayerError 비전수 문서) | **해소 ✓** | 타입 doc(ABPlayerError.swift:6-9)과 DocC(ABPlayerKit.md:23) 양쪽 갱신 |
| m10 (테스트 코멘트 오기) | **미처리** | ABCacheStoreTests.swift:508-510이 여전히 "fillRequest는 method 미지정이라 GET 기본값"이라 적혀 있으나 실제로는 `httpMethod = "GET"` 명시(ABCacheStore.swift:656), HEAD도 명시(650). 브리프 그룹 E에 명시된 항목인데 누락 |
| m11 (displayCapped 중복) | **해소 ✓** | `public static let displayCapped = ABPlaybackTuning()` (ABPlaybackTuning.swift:59) |
| m12 (ABCacheStore teardown) | **해소 ✓** | `deinit { progressWaiters.resolveEverything() }` (ABCacheStore.swift:230) |

**합계: Critical 2/2 해소, Major 5/5 해소, Minor 9/11 해소 (m1 의도적 이월, m10 누락).**

---

## 2. 신규 오디오 세션 coordinator 정밀 검토

정확성은 위에서 검증했고, 아래는 **새로 도입된** 이슈다.

### N1 (Minor) — `play()`마다 동기 `setCategory` + `setActive` IPC

`ABPlayer.play()` → `applyAudioSessionPolicyIfNeeded()` → `coordinator.apply` → `AVAudioSession.setActive(true)`. M1의 "절대 메모이즈하지 않는다" 수정이 정확성 문제를 고친 대신, **모든 play 탭이 mediaserverd로 가는 동기 IPC를 메인 스레드에서 유발**한다. 피드 자동재생 시 셀마다 발생한다. 부작용 하나 더: 활성화가 지속적으로 실패하는 상황(다른 앱이 세션 점유)에서 `.failed` 이벤트가 play마다 반복 방송된다 — 이전에는 메모이제이션이 이를 가렸다.

절충안: 무조건 재활성화 대신 "세션이 비활성일 수 있는 시점"(인터럽션 `.began` 관측 후, 백그라운드 복귀 후)에만 재활성화하도록 dirty 플래그를 두는 것.

### N2 (Minor) — 블로킹 I/O 구간 전체에서 NSLock 보유

`apply`(54-55)와 `leave`(84-85)가 `defer { lock.unlock() }` 아래에서 `snapshotCurrentCategory`/`activate`/`restore`를 호출한다. `setActive`는 수십~수백 ms 블로킹될 수 있다. 백그라운드 스레드의 `ABPlayer.deinit` → `leave` → `restore`가 락을 잡고 있는 동안 메인 스레드의 `play()` → `apply`가 그대로 블로킹된다 — 잠재적 UI 히치 경로다.

다만 락을 I/O 밖으로 빼면 apply/leave 시퀀스의 원자성이 깨져 C1이 재발할 수 있으므로, 현 설계는 **방어 가능한 트레이드오프**다. 실행 컨텍스트를 직렬 큐로 옮기는 편이 정석이지만 nonisolated deinit 요구사항과 충돌한다. 기록만 해둔다.

### N3 (Minor) — 프로토콜이 `Sendable`이 아닌데 코디네이터는 `@unchecked Sendable`

`ABAudioSessionControlling`은 `AnyObject`만 요구(ABAudioSession.swift:46)하는데, `ABAudioSessionCoordinator: @unchecked Sendable`(20)이 이를 저장하고 여러 스레드에서 호출한다. 실제 안전성은 코디네이터의 락이 보장하지만, **컴파일러가 검증할 수 없다** — 미래에 자체 상태를 가진 conformer가 추가되면 조용히 깨진다. 프로토콜을 `AnyObject & Sendable`로 좁히면 계약이 강제된다.

### N4 (Minor) — `didActivateSession`이 외부 비활성화를 추적하지 않음

인터럽션이 세션을 비활성화해도 플래그는 `true`로 남아, 그 상태에서 마지막 퇴장 시 이미 비활성인 세션에 `setActive(false)`를 호출한다. 무해하지만 의미가 어긋난다. 관련해서 `apply`에 `.unmanaged` 가드가 없어(ABPlayer 쪽에서만 막고 있음) 코디네이터를 단독 호출하면 아무것도 활성화하지 않고 `didActivateSession = true`가 된다 — 현재는 도달 불가이나 방어가 없다.

### N5 (관찰) — 강등 시 참여 유지는 이제 **의도된 동작**

`.current` → `.preloaded` 강등에서 `leave`를 호출하지 않는 것은 직전 리뷰에서 C1의 원인이었으나, 코디네이터 도입 후에는 오히려 **정확한 선택**이다 (형제가 쓰는 세션을 강등만으로 되돌리면 안 됨). 다만 결과적으로 피드의 모든 플레이어가 release 될 때까지 호스트 세션은 관리 상태로 남는다. README가 이를 정확히 서술하고 있어 문제없다.

---

## 3. Phase 4 신규 코드

### 3-1. `@Observable` (WP9) — **충돌 없음 ✓**

- **deinit 충돌 없음**: `prerollTask`/`seekWorkerTask`를 포함한 모든 내부 `var`에 `@ObservationIgnored`(ABPlayer.swift:66-95)가 붙어 저장 프로퍼티로 유지되고, `audioSessionCoordinator`는 `let`, `audioSessionToken`은 computed다. deinit이 접근하는 4가지 모두 매크로가 재작성하지 않는다. 주석(59-65)이 이 위험을 정확히 식별하고 있다.
- **이벤트 체계 충돌 없음**: `observerRegistry`는 `let`이라 무영향. Q3 결정(옵저버+토큰 유지)대로 두 체계가 병존한다.
- **`configuration`의 `didSet` 충돌 없음**: 위 실증 참조 — 매크로 전개 후에도 `didSet`이 발화하고 동시에 추적된다. `applyConfigurationChange` 의존 테스트 다수가 통과하는 것이 이를 뒷받침한다.
- **데모 앱 정리(WP9.3)**: `DemoModel`의 미러링 `var grade` 제거, 전 호출부가 `player.grade` 직독으로 전환. `transitionToSelectedSource`/`resumeCurrentPlaybackIfNeeded`에서 `player.release()` 이전에 `targetGrade`를 캡처하는 순서 주석까지 정확하다.

**Minor N6**: 클래스 doc과 CHANGELOG가 **6개** 프로퍼티(`grade`/`isScrubbing`/`hasDisplayedFirstFrame`/`lastError`/`source`/`configuration`)의 추적을 주장하지만, `ABPlayerObservationTests`는 `grade`와 `isScrubbing` **2개만** 검증한다. 내가 별도로 실증해 주장 자체는 성립함을 확인했으나, 회귀 방어는 1/3 수준이다. 특히 `configuration`(유일하게 `didSet`을 가진 것)과 `lastError`에 대한 `withObservationTracking` 케이스 추가를 권한다.

`untrackedComputedPropertyDoesNotFireObservation`(82-104)은 좋은 음성 케이스다 — 추적 범위가 과도하게 넓어지는 회귀를 잡는다.

### 3-2. 인터럽션 처리 (WP10) — **userInfo 파싱·재개 조건 정확 ✓**

`Policy/ABAudioInterruptionObserver.swift` 파싱 검증:

- `userInfo[AVAudioSessionInterruptionTypeKey] as? UInt`(39) — 시스템은 `NSNumber(value: UInt)`를 싣고 Swift가 브리징한다. ✓
- `AVAudioSession.InterruptionType(rawValue:)` 실패 시 조용히 무시(40) ✓
- `.ended`에서 옵션 키 부재 시 `?? 0` → `shouldResume == false`(45-46) — **보수적 방향으로 실패**한다. ✓
- `@unknown default: break`(48) ✓
- 라우트 변경은 `.oldDeviceUnavailable`만 필터(62) — HIG 준수 ✓

재개 조건(ABPlayer.swift `handleInterruptionEnded`)은 4개 논리곱이다: `policy == .pauseAndResume && shouldResume && wasPlayingBeforeInterruption && grade == .current`. 정확하며, `wasPlayingBeforeInterruption`은 방향과 무관하게 리셋된다. ✓

관측자 소유권도 `ABApplicationStateObserver` 패턴(인스턴스 소유 + 자체 `deinit`에서 `removeObserver`)을 정확히 따랐다. ✓

**Minor N7**: 재개 조건 4개 중 `wasPlayingBeforeInterruption == false` 게이트(일시정지 상태에서 인터럽션 → `.shouldResume`이 와도 재개 금지)에 **테스트가 없다**. 또한 인터럽션 × `backgroundPolicy` 합성 미검증 — `wasPlayingBeforeBackground`와 `wasPlayingBeforeInterruption`이 독립 플래그라 순서에 따라 양쪽이 `play()`를 낼 수 있다. 추적해 두 케이스 모두 테스트 권장.

### 3-3. 캐시 passthrough 폴백 (WP11) — 경계 조건 검증

`ABCacheStore.load`의 신규 분기(365-368)를 선행 가드와 함께 추적했다:

| 조건 | 처리 위치 | 판정 |
|---|---|---|
| `contentLength` 미지 | 306-309 `rawPassthrough` | ✓ 신규 분기에 **도달하지 않음** |
| `contentLength > cacheableEntryLimit` | 310-313 `passthrough` | ✓ 도달하지 않음 |
| `lowerBound >= contentLength` | 318-325 빈 EOF 리소스 | ✓ 도달하지 않음 |
| prefix가 이미 커버 | 332-340 캐시 반환 | ✓ 신규 분기보다 **먼저** 평가 |
| gap 음수 (underflow) | 위 항목이 선행하므로 `entry.size <= lowerBound` 보장 | ✓ Int64 언더플로 불가 |
| gap == 임계 정확히 | `>= threshold` → passthrough | ✓ 문서("이상")와 일치 |
| 콜드 캐시 + offset >= 2MB | `currentPrefixEnd = 0` → passthrough | ✓ 비-faststart MP4 의도 그대로 |

청킹(WP11.2)도 검증했다: `isEndOfResource: requestedUpperBound == contentLength - 1`(600)이 **잘린 청크의 상한**을 쓰므로 조기 EOF 오보가 없고, `ABResourceLoaderDelegate`의 `while currentOffset <= requiredEndOffset` 루프(85-99)가 `currentOffset += resource.data.count`로 재요청하므로 조합이 성립한다. `store.load` 호출부는 이 델리게이트 2곳뿐이며 청킹 미대응 경로는 없다.

**Major N8 (테스트 공백)** — 1MB 청킹 경로에 **테스트가 0건**이다. 기존 passthrough 테스트(`unknownLength`, `entryTooLarge`)와 신규 `distantOffsetRequestUsesPassthroughWithoutWaitingForFill`의 페이로드가 전부 1MB 미만이라 `requestedUpperBound` 축소가 한 번도 발동하지 않는다. 즉 `min(fullUpperBound, lowerBound + chunk - 1)`, `expectedCount` 재계산, `isEndOfResource` 판정, 델리게이트 루프와의 합성이 전부 미검증이다. 이 클래스의 버그는 **조용한 데이터 절단**으로 나타나며 passthrough는 WP11이 만든 핫패스다. 내가 양쪽 코드를 수동 대조해 정확함을 확인했기에 결함이 아니라 공백으로 분류하지만, 최우선 후속 항목이다.

**Minor N9**: 임계 정확히 경계(`gap == threshold`, `gap == threshold - 1`) 테스트가 없다. 현재 테스트는 3MB(임계 2MB 대비 여유) / offset 1(임계 훨씬 아래)로 양극단만 짚는다. `nearOffsetRequestStillWaitsForFill`이 "passthrough로 새면 두 번째 dataReply가 없어 throw한다"는 영리한 오라클을 쓴 것은 좋다.

**Minor N10**: `passthroughGapThreshold`에 검증/클램핑이 없다. `0`을 넣으면 `gap >= 0`이 항상 참이라 **캐시가 사실상 전면 비활성화**된다(0을 "항상 캐시"로 읽는 직관과 정반대). 음수도 동일. 최소한 doc에 "0 이하는 전량 passthrough를 의미한다"를 명시하거나 `max(1, …)` 클램프를 권한다.

**Minor N11**: 원거리 seek 시 백그라운드 선형 fill이 **취소·일시정지되지 않는다**. 100MB 비-faststart 파일의 끝으로 시크하면 fill이 앞에서부터 계속 받으면서 passthrough가 뒤를 스트리밍해 대역폭이 이중으로 소모된다. README가 "The background fill keeps crawling forward untouched"로 정직하게 명시하고 sparse range 개편을 스코프 밖으로 선언했으므로 결함이 아닌 **문서화된 트레이드오프**로 기록한다.

**Minor N12**: `pendingMetadataRequests` — 첫 호출자의 대기가 취소되면 `defer { pendingMetadataRequests[key] = nil }`(404)이 **아직 실행 중인 HEAD Task를 남긴 채** 엔트리를 지운다. 이후 도착한 호출자가 두 번째 HEAD를 발사하고, 고아 Task의 결과는 `cacheMetadata`되지 않고 버려진다. 좁은 엣지지만 coalescing 보장이 취소 하에서 깨진다.

### 3-4. custom timeFormat 계약 변경 (WP12) — semver 수용 가능 ✓ (단서 있음)

구현(ABPlayerControlsView.swift:695-710)은 `.custom`일 때 조기 반환해 `timeLabelLayout` 조합을 건너뛴다. 레이블이 `elapsedLabel` 하나뿐이라 조기 반환이 다른 레이블을 방치하는 문제는 없다(확인함). 테스트도 박제된 `"12s/90s/90s/90s"`를 `"12s/90s"`로 갱신하고, `customTimeFormatIgnoresTimeLabelLayout`로 계약을 명시적으로 고정했다.

**semver 판정: 0.x에서 수용 가능.** 근거 — (a) 타입/시그니처 파괴 없음(순수 behavior change), (b) 기존 출력이 명백히 무의미했음, (c) 레포가 v0.2.0 pre-1.0, (d) CHANGELOG에 기록됨.

**단, 단서**: 이전 doc 주석은 `.custom`을 "각 라벨마다 호출되는 포매터"로 서술했다("so a formatter can keep field widths consistent across the elapsed/total/remaining labels it renders"). **그 문서화된 계약대로** 경과 시간만 반환하도록 작성한 포매터는 이제 total/remaining을 잃는다 — 합리적인 사용 패턴의 실질 회귀다. CHANGELOG가 이를 `### Fixed`에 넣었는데, 마이그레이션 한 줄("`.custom`이 elapsed만 반환하도록 작성돼 있었다면 duration을 직접 합성하도록 수정하십시오")을 붙이는 편이 정확하다. **Minor N13.**

**Minor N14**: `formattedTime(_:referenceDuration:)`의 doc 주석(ABPlayerControlsView.swift:733-735)이 여전히 "`.automatic`/`.custom`에 referenceDuration을 넘겨 렌더 패스의 모든 라벨이 필드 폭에 합의하게 한다"고 서술한다. `.custom`은 더 이상 이 함수를 거치지 않으므로 stale이고, 이 함수의 `.custom` 분기(753)는 시간 라벨 경로에서 도달 불가한 죽은 코드가 됐다.

---

## 4. 신규 테스트 실효성

**우수**

- `demotedParticipantPreventsSnapshotContamination` — 리뷰 지적의 재현 시나리오를 그대로 테스트화. 단순 "동작한다"가 아니라 `snapshot 호출 횟수 == 1`이라는 정확한 불변식을 짚는다.
- `concurrentResolveYieldsSingleWinner` 재작성 — `#expect(wins.count == 1)` + `#expect(resumed == wins)`. 이제 락 버그(두 resolve가 모두 승리)가 실제로 테스트를 실패시킨다. `resolve`를 `-> Bool`로 바꿔 오라클을 **만들어낸** 것이 핵심이며, 직전 리뷰가 권고한 `ABCacheProgressWaiter` 미러링과 정확히 일치한다.
- `concurrentLoadsForSameKeyDedupeToOneFill` — `dataReplies`를 1개로 줄인 것이 결정적이다. 여유 버퍼가 회귀를 가리던 구조가 제거됐다.
- `distantOffsetRequestUsesPassthroughWithoutWaitingForFill` — 영구 정지된 fill + `totalSize() == 0` 단언으로 "정말 passthrough로 갔는가"를 양방향 검증.
- `ABAudioInterruptionTests` 전반 — 실제 notification name/userInfo 키를 쓰되 프로세스 전역 `AVAudioSession`은 건드리지 않는다. 양성 단언은 `waitUntil`, 음성 단언은 근거 주석이 달린 유한 yield로 분리한 것이 일관적이다.
- `untrackedComputedPropertyDoesNotFireObservation` — 추적 범위 확대 회귀를 잡는 음성 케이스.

**남은 공백** (위 N6/N7/N8/N9에 상술)

- passthrough 1MB 청킹: 0건 (**Major 공백**)
- 임계 정확 경계: 0건
- `@Observable` 6개 주장 중 2개만 검증
- 인터럽션 재개 조건 4개 중 `wasPlayingBeforeInterruption` 게이트 미검증

**tautology 잔존 여부**: 직전 리뷰가 지목한 공허 단언(`validOutcomes.contains(outcome)`)은 완전히 제거됐다. 신규 테스트 중 검증하는 척만 하는 것은 발견하지 못했다.

---

## 5. 종합

직전 리뷰의 **Critical 2건, Major 5건이 전부 해소**됐고, 그중 5건은 회귀 시 실제로 실패하는 전용 테스트를 동반한다. 특히 C1은 권고한 대로 개별 패치가 아닌 소유권 재설계로 풀렸고, 리뷰가 서술한 5단계 오염 시나리오가 그대로 테스트가 됐다. M3는 지적한 두 가지 결함(과광범위 어노테이션 + off-main 호출)을 하나의 박스로 동시에 정리했다. M5는 "테스트가 문제를 덮었다"는 지적까지 정면으로 수정했다.

Phase 4 신규 코드에서 설계상의 결함은 발견하지 못했다. `@Observable`은 deinit·이벤트 체계·`didSet` 어디와도 충돌하지 않으며(실증 확인), 인터럽션 파싱과 재개 조건은 정확하고 보수적 방향으로 실패한다. 캐시 passthrough는 선행 가드 덕에 미지 contentLength·언더플로·조기 EOF 어느 경계도 새지 않는다.

남은 것은 Minor 12건과 **Major 등급의 테스트 공백 1건(N8, passthrough 청킹)** 이다. N8은 실증된 결함이 아니라 커버리지 부재이고, 계약 양쪽(`isEndOfResource` 산정과 델리게이트 재요청 루프)을 수동 대조해 정확함을 확인했으므로 0.x 머지를 막지 않는다. 다만 다음 라운드의 최우선 항목으로 추적되어야 한다.

미처리 항목 중 m1(튜닝 가드 role 스코프)은 Phase 3 브리프에 애초에 포함되지 않은 의도적 이월이고, m10(테스트 코멘트 오기)은 브리프에 명시됐으나 누락된 단순 실수다.

### 후속 권장 (우선순위)

1. **N8** — passthrough 1MB 청킹 테스트 추가 (>1MB 범위가 여러 청크로 돌아오고 `isEndOfResource`가 마지막 청크에서만 true)
2. **N6** — `configuration`/`lastError`의 `withObservationTracking` 케이스 추가
3. **N7** — 일시정지 상태 인터럽션이 `.shouldResume`에도 재개하지 않음을 단언
4. **N1** — `play()`마다의 `setActive` IPC를 dirty 플래그로 축소
5. **C2 잔여** — README에 "호스트가 이미 세션을 활성화한 상태였다면 복원 시 비활성화될 수 있음(AVAudioSession에 활성 상태 조회 API 없음)" 단서 추가
6. **N13** — CHANGELOG의 `.custom` 항목에 마이그레이션 한 줄 추가
7. m10, N10, N12, N14 — 단순 정리

FINAL-VERDICT: APPROVE
