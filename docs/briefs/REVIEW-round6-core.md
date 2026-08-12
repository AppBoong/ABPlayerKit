# REVIEW: 라운드6 트랙 A 최종 게이트 (A-8)

담당: Sonnet(A-8 게이트, 임무는 Opus 게이트와 동일). 기준 커밋 995bb6d + 미커밋 작업 트리(브랜치 `round6/core`).
입력: `git diff`(전체), `DESIGN-round6-core.md`, `RESULT-round6-core.md`, `ROADMAP-round6.md` §0·§2·§6, `REVIEW-round6-portfolio-audit.md` §A·§B.
**정적 리뷰만 수행 — 부팅된 시뮬레이터가 없어 테스트 스위트 실행 없음(브리프 지시대로 새 부팅 금지). 잔여 리스크는 §7에 명시.**

---

## 1. 범위 경계 확인

- `git status --porcelain`의 모든 변경 파일이 `Sources/ABPlayerKit/`, `Tests/ABPlayerKitTests/`, `Examples/ABPlayerKitDemo/`(1파일) 내부. `Sources/ABPlayerKitControls|Cache|Metrics/`, `Tests/ABPlayerKitControlsTests/` 무변경 확인.
- §5.2 수정 금지 파일 4종 — `git diff` 결과 전부 공백(0바이트 변경) 확인:
  - `Sources/ABPlayerKit/StateMachine/ABSeekCoalescer.swift`
  - `Tests/ABPlayerKitTests/ABSeekCoalescerTests.swift`
  - `Tests/ABPlayerKitTests/ABScrubbingEngineTests.swift`
  - `Tests/ABPlayerKitTests/ABPeriodicTimeEngineTests.swift`
  - (`Tests/ABPlayerKitControlsTests/`도 함께 확인, 무변경)
- §5의 명시적 비범위(`ABPlayer` 3분할, `ABAVPlaybackTarget` 분할, 시크 상태 별도 머신化, `ABGradePlanner`/`ABSeekCoalescer`/`ABObservationBag`/`PeriodicObserverBox` 수정) — 전부 미실시, 위반 없음.

결론: **범위·경계 위반 없음.**

---

## 2. A-5w 스크럽 회귀 — 코드 추적 결과

`enqueueSeek(to:tolerance:)`는 `clampToPlayableRange` → (스크럽 세션 밖일 때만) `pendingSeekTime` 갱신+방송 → `seekCoalescer.request` → `startSeekWorker`만 수행하며 `grade` 검사를 하지 않는다(설계 그대로). 4개 진입점(`seek(to:tolerance:)`, 비스크럽 `skip(by:)`, 세션 밖 `scrub(to:)`, `.seekToStart` 플래너 액션) 전부 이 게이트를 통과하도록 재배선됐고, 기존 `runSeekWorker`(무수정)의 `generation == seekGeneration` 가드를 자동으로 상속받는다 — `seekGeneration`은 `resetSeeking()`(무수정, `+= 1`)에서만 증가하므로 세대 보호 로직 자체는 손대지 않았다.

- **스크럽 세션 중 `skip(by:)`**: `isScrubbing`이면 여전히 `scrub(to:)`로 위임하고 `return`하며 `await`하지 않는다(교착 방지, I-3 그대로 성립).
- **세션 중 `scrub(to:)`**: `lastScrubTime = time; seekCoalescer.request(...); startSeekWorker(...)` — 구조 무변경.
- **`endScrubbing()`**: 전체 함수 골격(플러시 → 워커 대기 → standalone commit 분기 → `seekCoalescer.reset()` → `isScrubbing = false` → `scrubbingChanged` → `broadcastPeriodicTime`)이 그대로이고, standalone commit 분기에만 `let generation = seekGeneration`(await 직전 캡처) → `if generation == seekGeneration { broadcast(.seekCompleted...) }`(await 직후 재검증) 가드가 추가됐다. 순서 계약(I-5: `.seekCompleted` → `.scrubbingChanged(false)` → `.periodicTime`)은 가드가 `.seekCompleted`를 건너뛰는 경우에도(스테일 세대) 나머지 두 이벤트 순서에 영향을 주지 않으므로 성립.
- **`ABSeekCoalescer.swift`/`ABSeekCoalescerTests.swift`/`ABScrubbingEngineTests.swift`/`ABPeriodicTimeEngineTests.swift`**: §1에서 확인한 대로 diff 0.

**판정: 회귀 없음.** 구조·시맨틱 보존 확인.

---

## 3. A-6w `@Observable` 상호작용 — 코드 레벨 검증

- **미러 3종(`isPlaying`/`duration`/`isBuffering`) + `pendingSeekTime`의 값-비교-후-대입**: `refreshPlaybackMirrors()`가 3종 전부 `if new != old { ... }` 패턴이고, `pendingSeekTime`도 `enqueueSeek`/`runSeekWorker`/`resetSeeking()` 3개 대입 지점 전부 조건부(`pendingSeekTime != destination` 또는 `pendingSeekTime != nil`)다. 예외 없음.
- **`@ObservationIgnored` 규칙**: 신규 내부 상태(`displaySize`, `desiresPlayback`, `isStallOutstanding`, `lastBroadcastFiniteDuration`, `lastBroadcastPresentationSize`)는 전부 부착됨. 신규 관찰 대상 저장 프로퍼티(`isPlaying`/`duration`/`isBuffering`/`pendingSeekTime`/`lastFailure`/`lastDiagnostic`)는 전부 미부착. `deinit`(라인 253-257)은 `prerollTask`/`seekWorkerTask`/`audioSessionCoordinator`/`audioSessionToken`만 접근하며 이들은 기존 `@ObservationIgnored nonisolated(unsafe)`를 그대로 유지 — 신규 프로퍼티는 어느 것도 `deinit`에서 접근되지 않음(I-8 충족).
- **`target.play()`/`target.pause()` 직접 호출 지점**: `grep`으로 전수 확인 — `target.play()`/`target.pause()`가 나타나는 모든 지점(직후 라인)에 `refreshPlaybackMirrors()`가 동행. 누락 없음. `desiresPlayback` 대입도 `target.pause()` 5곳 전부와 정확히 1:1 대응(라인 383/665/922/1013/1040 직전).
- **동기성(I-1)**: `play()`/`pause()` 본문에서 `target.play()`/`target.pause()` 직후 동일 함수 스코프에서 동기적으로 `refreshPlaybackMirrors()` 호출 — `await` 경유 없음.
- **`ABBufferingEvaluator`**: 설계 §결정2의 순수 함수와 바이트 단위로 동일. `hasItem: avPlayerItem != nil`, `intendsToPlay: desiresPlayback`을 정확히 사용.
- **재진입/순서**: `refreshPlaybackMirrors()` 내부는 대입 후 방송(assign-then-broadcast) 패턴 일관 — 설계의 "먼저 대입, 다음 방송" 요구 충족.
- **신규 관찰 테스트**: `ABPlayerObservationTests.swift`에 4종 추가(`isPlayingChangeFiresObservation`, `durationChangeFiresObservation`, `isBufferingChangeFiresObservation`, `pendingSeekTimeChangeFiresObservation`) + 동일값 재대입 무발화 테스트(`identicalMirrorReassignmentDoesNotFireObservation`, `target.emit(.timeControlStatusChanged(.playing))`을 2회 호출 후 20 tick 동안 미발화 확인) — 설계 요구사항과 일치.

**판정: 위반 없음.** (단, 실 시뮬레이터에서의 실증은 §7 잔여 리스크로 별도 기재.)

---

## 4. 설계 §5.1 불변식 I-1~I-8 개별 검증

| # | 불변식 | 검증 근거 | 판정 |
|---|---|---|---|
| I-1 | `isPlaying`은 `play()`/`pause()` 직후 동기적으로 참/거짓 | §3의 동기성 확인 | **충족** |
| I-2 | `isPlaying` 의미 `rate != 0 && timeControlStatus != .paused` 불변 | `ABAVPlaybackTarget.swift:26-29`의 `isPlaying` getter 무수정(diff 밖) 확인 | **충족** |
| I-3 | 스크럽 중 `skip(by:)` 비대기 | §2에서 코드 확인(`return` 직전 `await` 없음) | **충족** |
| I-4 | `ABSeekCoalescer` 3메서드 시맨틱 불변 | 파일 diff 0 | **충족** |
| I-5 | 스크럽 종료 순서 `.seekCompleted → .scrubbingChanged(false) → .periodicTime` | §2에서 구조 보존 확인 | **충족** |
| I-6 | 모든 release 경로가 `.detachItem` 정확히 1회 경유 | `release()` → `set(source:nil, grade:.released)` → 무수정 `ABGradePlanner`가 액션 생성(플래너 자체는 비범위, 무수정) → `.detachItem` 액션이 여전히 `target.detachItem()` 1회만 호출(순서만 방송 이후 → 이전으로 변경) | **충족** |
| I-7 | 신규 KVO는 수명 결속 + hop 후 stale-item 가드 | `presentationSize`/`didPlayToEnd` 재시작 경로는 가드 있음. `duration`/`isPlaybackLikelyToKeepUp`/`isPlaybackBufferEmpty`/`reasonForWaitingToPlay` 4종은 가드 없음(값-전달이 아닌 재평가-신호이므로 `refreshPlaybackMirrors()`가 처리 시점에 라이브 상태를 재조회해 자기교정) | **좁은 해석으로 충족 — §6-3 판정 참조** |
| I-8 | `deinit` 접근 프로퍼티 `@ObservationIgnored` 유지 | §3에서 확인 | **충족** |

---

## 5. 이벤트 표면 — 설계 §3.2 대조 (9개 케이스)

전 케이스 시그니처가 `ABPlayerEvent.swift`에 설계 문서와 정확히 일치하는 형태로 존재함을 확인(`ABRejectedCall` 7케이스 포함). 방송 지점·중복 억제·순서를 각각 코드에서 추적:

| # | 케이스 | 방송 지점 확인 | 중복 억제 확인 |
|---|---|---|---|
| 1 | `bufferingChanged(Bool)` | `refreshPlaybackMirrors()` 내, 값 변경 시 | `newIsBuffering != isBuffering` 가드 |
| 2 | `durationAvailable(CMTime)` | 동일 함수 내, `isNumeric && seconds > 0` 확인 후 | `lastBroadcastFiniteDuration` 비교, detach 시 리셋 |
| 3 | `stallEnded` | `.timeControlStatusChanged(.playing)` 처리부, `isStallOutstanding` 참일 때만 | 플래그 1회성, detach 시 조용히 폐기(방송 없음) — 설계 §3.4 그대로 |
| 4 | `itemAttached(source:)` | `.attachItem` 액션, `target.attachItem` 직후·`.tuningApplied` 직전 | 액션당 1회(자연 보장) |
| 5 | `presentationSizeChanged(CGSize)` | `.presentationSizeChanged` 타깃 이벤트 처리 | `.zero` 제외 + `lastBroadcastPresentationSize` 비교, detach 시 리셋 |
| 6 | `mutedChanged(Bool)` | `applyConfigurationChange`의 `target.setMuted` 직후, 값 변경 조건절 내부 | 상위 `if previousConfiguration.isMuted != configuration.isMuted` |
| 7 | `callRejected(ABRejectedCall, grade:)` | `rejectCall(_:)` 헬퍼, `.playbackRejected` 직후 동일 지점. 7개 공개 진입점(`play`/`pause`/`seek`/`skip`/`beginScrubbing`/`scrub`/`endScrubbing`) 전부 `grep` 확인 | 없음(설계 그대로) |
| 8 | `failureReported(ABPlayerFailure)` | `routeFailure(_:)`, `.failed` 직후 동일 지점 | 없음(설계 그대로) |
| 9 | `seekTargetChanged(CMTime?)` | `enqueueSeek`(세팅)/`runSeekWorker`·`resetSeeking()`(해제) | 매 사이트 값-변경 조건 |

**순서 계약(§3.3) 코드 추적**:
- attach: `.itemAttached` → `.tuningApplied` (같은 액션 내 순서 확인)
- detach: `target.detachItem()` → `.itemDetached` (순서 교체 확인, `ABFakePlaybackTarget.detachItem()`도 `avPlayerItem = nil` 반영해 테스트 가능하게 보강됨)
- 실패: `.failed` → `.failureReported` (`routeFailure` 내 순서)
- 거부: `.playbackRejected` → `.callRejected` (`rejectCall` 내 순서)
- 스톨: `.playbackStalled`(→ 동기 `refreshPlaybackMirrors()`가 `bufferingChanged(true)` 방송) → … → `timeControlStatusChanged` 처리부에서 `refreshPlaybackMirrors()`(→ `bufferingChanged(false)`) → 곧바로 `stallEnded` 체크 — 동일 MainActor 동기 실행이므로 개입 이벤트 없음
- 스크럽 종료: §2에서 확인

**`.tuningApplied` 해상값 vs 미해상값**: `target.applyTuning`/`target.attachItem(tuning:)` 호출 4곳 전부 `resolvedTuning(for:)`(해상값)을 쓰고, `broadcast(.tuningApplied(...))` 4곳 전부 `tuning(for:)`(미해상값)을 쓴다 — `grep`으로 4쌍 전수 확인, 예외 없이 일관.

**판정: 이벤트 표면이 설계 §3.2·§3.3과 정확히 일치.** Wave 2가 이 표면에 의존해도 안전.

---

## 6. RESULT §2 게이트 문의 3건 판정

### 6-1. `.tuningApplied` 미해상값 유지 (채택안) vs 해상값 방송

**판정: 채택안(미해상값 유지)을 승인.** 근거:
- DESIGN 문서가 이 지점을 명시적으로 결정하지 않은 것은 RESULT의 지적대로 사실 — A-7w 지침(§4)은 "target에 전달되는 tuning은 항상 해상값"만 규정하고 이벤트 페이로드는 언급하지 않는다.
- 미해상값 유지는 기존 테스트(`.tuningApplied(.current, .displayCapped)` 등 리터럴 비교 다수)를 무수정으로 통과시키며, `.tuningApplied`가 "무엇을 요청했는가"를 나타낸다는 기존 의미를 유지한다 — additive-only 정신에 더 부합(기존 소비자의 관찰 가능한 동작이 안 바뀜).
- 해상값 방송으로 전환할 경우 §5.3 밖의 광범위한 테스트 수정이 필요해 이번 게이트의 "명시적 비범위"(대규모 리팩터 금지) 취지와도 충돌.

**후속 조치 요청(코드 변경 아님)**: 이 결정은 Wave 2(C/F/G)가 의존할 확정 표면(§5.5)에 속하므로, `DESIGN-round6-core.md` §3.2 표 9번 행 또는 §5.5에 "`.tuningApplied`는 미해상 프리셋 값을 방송한다. 해상된 픽셀 캡이 필요하면 `ABPlayer.reportDisplaySize`가 트리거한 재적용을 관찰하거나 `avPlayerItem.preferredMaximumResolution`을 직접 읽어야 한다"는 문장을 명시적으로 추가해 동결할 것을 권고. 코드 변경은 불필요.

### 6-2. `ABBackgroundPolicyMachine` 액션 세분화 수준

**판정: 채택 구현을 승인.** `ABPlayer.swift`의 원본 스위치문(수정 전)과 `interpretBackgroundActions`의 `.demoteToInstance`/`.restoreCapturedGrade` 처리부를 라인 단위로 대조한 결과, 조건부 로직(`gradeBeforeBackground = grade`는 무조건, 실제 데모트는 `grade.holdsItem`일 때만; 복원도 `gradeBeforeBackground` 존재 여부로 조건부)이 **정확히 동일하게** 해석 함수 쪽에 보존됐다 — 0비트 동작 변경. `willEnterForegroundActions`가 `.ignore` 정책에서도 `.markAudioSessionDirty`를 무조건 먼저 내는 부분도 원본의 "switch 이전에 무조건 실행되는 라인" 구조를 정확히 재현한다. `ABBackgroundPolicyMachine`은 `internal`이며 설계 §5.5의 Wave 2 동결 대상 표면에 포함되지 않으므로, 이 결정은 트랙 A 내부 구현 디테일에 그친다. 표 테스트(`ABBackgroundPolicyMachineTests`)가 `grade.holdsItem == false`인 조합까지 커버하는지는 §8에서 별도 확인.

### 6-3. 신호-전용 KVO 4종의 stale-item 가드 생략 (I-7의 좁은 해석)

**판정: 구현을 승인하되, 후속 보강을 권고(비차단).**
- `isPlaybackLikelyToKeepUp`/`isPlaybackBufferEmpty`/`duration`은 값을 나르지 않고 `.bufferStateChanged`/`.durationChanged`(페이로드 없음)만 방송하며, `ABPlayer.handle(_:)`이 이를 받아 `refreshPlaybackMirrors()`를 호출한다 — 이 함수는 이벤트 페이로드가 아니라 **호출 시점의 `target` 라이브 상태를 다시 읽는다**(결정 2의 "재계산 미러" 원리 자체가 이 자기교정을 설계 목적으로 명시). 아이템이 이미 교체됐어도 새 아이템의 값을 정확히 읽으므로 관찰 가능한 오동작 경로가 없다.
- `reasonForWaitingToPlay`는애초에 `AVPlayer`(아이템이 아닌 플레이어) 레벨 KVO이므로 "stale **item**" 개념 자체가 적용되지 않는다 — 기존 `timeControlStatus` 관찰(무수정 코드)도 동일한 이유로 stale-item 가드가 없다는 선례와 일치.
- 다만 이는 설계 문서의 문언("결정 2의 KVO 5종 등록... 모든 신규 관찰은 기존 관례를 따른다... hop 후 stale-item 가드")을 문자 그대로 충족하지는 않는다. 관찰 가능한 결함은 없으나, 방어적 일관성(및 향후 리뷰어가 "왜 이 4곳만 예외인지" 재추론하는 비용) 관점에서 4곳에도 가드를 추가하는 편이 낫다.
- **차단 사유 아님** — 순수 방어적 보강이며 동작 변경이 없어 이번 게이트를 막을 이유가 아니다. Wave 3(H-1w) 또는 차기 소형 PR에서 처리 권고.

---

## 7. §5.3 밖 테스트 수정 4건 (RESULT §3 열거) 타당성

| 파일 | 수정 | 타당성 판정 |
|---|---|---|
| `ABPlayerEngineTests.swift` — `ABDefaultAssetFactoryTests` | 개명 + 무헤더 케이스 추가 | **타당**. B-6 구현(헤더 실제 적용)으로 기존 테스트명("core는 헤더를 무시한다")이 틀린 전제가 됨 — 개명은 사실 정정, 신규 케이스는 순수 추가 |
| `ABPlayerEngineTests.swift` — `target.emit(.failed(error))` 2곳 | `.failed(.init(kind: error))`로 기계적 치환 | **타당**. `ABTargetEvent.failed`의 페이로드 타입 변경(`ABPlayerError` → `ABPlayerFailure`)에 따른 컴파일 필수 수정이며, §5.3에 명시된 `ABPlayerObservationTests.swift:123`과 성격이 동일(같은 근본 원인의 기계적 파급) |
| `ABPlayerEngineTests.swift` — `ABObservationTokenLifecycleTests` 2곳 | 삭제된 레지스트리 타입 → `ABHandlerRegistry<Payload>` 치환 | **타당**. H-6 레지스트리 통합(A-7w 범위)의 직접 결과. 삭제된 타입을 참조하던 테스트는 신규 타입으로 치환하지 않으면 컴파일 자체가 불가 |
| `Fakes/ABFakePlaybackTarget.swift` — `detachItem()`에 `avPlayerItem = nil` 추가 | §5.3이 "프로토콜 신규 멤버 구현 추가"만 명시했으나 이 한 줄은 그 밖 | **타당**. A-4/A-8의 detach 순서 수정을 검증하는 신규 테스트(`ABDetachOrderingTests`)가 요구하는 최소 보강이며, 실 타깃(`ABAVPlaybackTarget.detachItem()`)의 실제 동작을 그대로 반영한 것 — 페이크를 실물에 더 가깝게 만드는 방향이라 회귀 리스크 없음 |

4건 모두 §5.3 정신(허용 목록은 좁게, 그러나 새 기능이 요구하는 최소 파급은 게이트 문의 대상)에 부합. **전부 승인.**

---

## 8. 신규 테스트 커버리지 표본 확인

- `ABBackgroundPolicyMachineTests.swift`: 4정책×3시그널 표 커버 확인. `grade.holdsItem == false`(예: `.instanceOnly`/`.released`에서 배경 진입) 조합이 포함돼 §6-2의 조건부 데모트 분기까지 실질적으로 검증되는지는 파일을 열어 표 케이스를 확인했고, `grade` 축이 `.released`/`.instanceOnly`/`.preloaded`/`.current`를 포괄해 조건 분기 커버리지가 확보됨을 확인.
- `ABSeekUnificationTests.swift`: 연속 skip 누적, `pendingSeekTime`/`seekTargetChanged` 발생 시점, duration 클램프, stale 세션-밖 scrub 무시, 5연타 코얼레싱, 스크럽 중 skip 비대기 — A-5w 신규 테스트 요구사항 6개 항목 전부 파일 내에 존재.
- `ABObservabilityEventsTests.swift` / `ABAVPlaybackTargetObservabilityTests.swift` / `ABBufferingEvaluatorTests.swift`: A-6w 요구 테스트 목록(동기 `isPlaying`, `bufferingChanged` 값-변경시만, `durationAvailable` 1회+재attach 재발, `itemAttached`→`tuningApplied` 순서, `.failed`→`.failureReported` 순서, `ABBufferingEvaluator` 전 조합) 확인.

---

## 9. 주석 위생 — 새 주석/문자열의 리뷰·설계 ID 인용

**위반 발견. 리뷰 항목 #8 기준 미충족.** `git diff`의 추가 라인(`+`)만 대상으로 감사 ID 패턴(`A-`/`B-`/`D-`/`I-` 등)을 전수 스캔한 결과:

**Sources/ (3건)**:
- `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:222` — `(B-7 — a feed cell's correct cap is the cell's size, never UIScreen.main)`
- `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:420` — `since this isn't ABPlayer's seek path (A-5w owns that channel)`
- `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:504` — `Buffering-suppression signal only (B-2) — never the sole basis...`
- `Sources/ABPlayerKit/Engine/ABPlayer.swift:685` — `the confirmed attach-order contract Wave 2 depends on`(리뷰 ID는 아니나 briefs 이전 후 의미 불명해질 로드맵 용어)

**Tests/ (다수, 신규 파일 헤더 독크 코멘트 중심)**:
- `ABAVPlaybackTargetObservabilityTests.swift:6` — "A-6/B-2"
- `ABBackgroundLifecycleEngineTests.swift:7,31` — "A-2/A-6"
- `ABBackgroundPolicyMachineTests.swift:7` — "A-2/A-6"
- `ABDetachOrderingTests.swift:6` — "A-4/A-5/A-8"
- `ABDisplaySizeTuningTests.swift:6` — "B-7"
- `ABFailureLifecycleTests.swift:6` — "A-3"
- `ABObservabilityEventsTests.swift:6` — "A-6/B-1~B-5"; 65행 부근 "D-2"
- `ABRateTuningTargetTests.swift:6` — "B-8"
- `ABSeekUnificationTests.swift:6` — "A-5/A-7/D-1"; 131행 `@Test` 이름 문자열 내 "pre-existing I-3 invariant"
- `Fakes/ABFakePlaybackTarget.swift` — "the A-4/A-8 ordering fix"
- `Examples/.../DemoModel.swift:474` — "round6 cases"(감사 ID는 아니나 라운드 넘버 인용)

대조군으로 `ABLoopRestartTests.swift`, `ABBufferingEvaluatorTests.swift`는 동일한 정보를 ID 없이 순수 불변식 서술로 작성함 — 같은 PR 내에서 두 방식이 공존하므로 ID 인용 없이 쓰는 것이 실제로 가능했음을 보여준다.

**심각도 판단**: 기능적 결함은 전혀 아니며 전부 기계적으로(찾아 바꾸기 수준으로) 고칠 수 있다. 그러나 이 규칙은 `ROADMAP-round6.md` §0("모든 브리프에 명시"), `DESIGN-round6-core.md` §4("전 WP 공통... 새 주석에 내부 리뷰 ID 인용 금지"), 그리고 본 게이트 브리프 리뷰 항목 #8에 **세 번 반복 명시**된 요구사항이고, 감사 항목 H-2가 바로 이 패턴(~90곳)을 포트폴리오 공개 부적합 사유로 지목한 바 있다. `docs/briefs/`가 H-3w에서 orphan branch로 이전되면 이 인용들은 전부 참조 불명(dangling reference)이 되어, 이번 라운드가 방지하려던 문제를 새 코드에서 그대로 재생산한다. 11개 이상 파일에 걸친 체계적 패턴이라 단발 실수로 보기 어렵다.

**판정: 병합 전 수정 요구.** 단, 로직 변경이 전혀 없는 텍스트 치환이므로 별도의 전면 재검토 없이 빠르게 재게이트 가능.

---

## 10. CHANGELOG 초안 정확성 검증

Added/Fixed 8개 항목, Migration Notes 8개 항목을 각각 대응 코드와 대조:

| Migration Note | 코드 근거 | 판정 |
|---|---|---|
| 1. `seek(to:)` duration 클램프 | `clampToPlayableRange(_:)` | 정확 |
| 2. `rewindOnDemotion` 데모션 시 `.seekCompleted(to: .zero)` 신규 방송 | `.seekToStart` 액션이 `enqueueSeek(to: .zero, ...)` 경유 → 워커가 `.seekCompleted` 방송 | 정확 |
| 3. 세션 밖 `scrub(to:)` 연타 코얼레싱 | per-call `Task` 제거, `enqueueSeek` 경유 확인 | 정확 |
| 4. 연속 `skip(by:)` 누적 | `base = pendingSeekTime ?? currentTime` | 정확 |
| 5. `.itemErrorLogEntry`가 `lastError` 갱신 중단 | `routeFailure`의 `isTerminal` 분기, `lastError`는 `lastFailure?.kind` 계산 프로퍼티 | 정확 |
| 6. `.itemDetached` 순서(detach 먼저) | `.detachItem` 액션 순서 확인 | 정확 |
| 7. `displaySizeSentinel`이 뷰 미부착 시 "캡 없음" | `displaySize` 기본 `.zero`, `resolved(displaySize:)`가 `.zero`를 그대로 대입(`.zero`는 "no cap"으로 문서화됨) | 정확 |
| 8. `.tuningApplied` 미해상값 유지 | §5·§6-1 확인 | 정확 |

Added/Fixed 항목도 각 WP 절에서 확인한 코드와 모순 없음. **CHANGELOG 초안 승인.**

---

## 11. 잔여 리스크 (실행 검증 미실시)

- 빌드/테스트 빌드는 구현자가 `xcodebuild`로 그린 확인(RESULT §3). 본 게이트는 부팅된 시뮬레이터가 없어 **테스트 스위트를 1건도 실행하지 않았다** — 병합 후 PR CI가 최초 실행 검증을 담당해야 한다.
- 특히 다음은 정적 추론으로는 고신뢰이나 실기기/시뮬레이터 실행으로만 최종 확증되는 항목: (a) `withObservationTracking` 기반 4개 신규 발화 테스트 및 동일값 무발화 테스트의 실제 통과 여부, (b) `ABAVPlaybackTargetObservabilityTests`의 실 `AVPlayerItem` KVO 통합(특히 `[.initial, .new]` 조합이 번들 `tiny.mp4`에서 타이밍대로 발화하는지), (c) TSan 잡(CI-2, 아직 미도입) 관점의 신규 KVO 5종 동시성 안전성.
- §6-3에서 승인한 stale-item 가드 생략 4곳은 이론적으로 안전하지만, 실제 detach/reattach 레이스를 시뮬레이터에서 재현하는 통합 테스트는 아직 없다(신규 테스트는 대부분 `ABFakePlaybackTarget` 기반).

---

## 12. 종합 판정

- 코어 엔지니어링(시크 통일, 관찰성 미러, 이벤트 표면, 에러 라우팅, 배경 정책 리듀서, 소형 정리 5종)은 설계 문서·불변식·§3.2 이벤트 계약과 **정확히 일치**하며 정적 리뷰로 발견된 기능적 결함은 없음.
- 3건의 게이트 문의는 전부 검토 후 승인(§6), §5.3 밖 테스트 수정 4건도 전부 타당(§7).
- 유일한 차단 사유는 **§9 주석/테스트명 위생 위반**(신규 코드 11개 이상 파일에 걸친 감사·설계 ID 인용) — 로직 변경이 필요 없는 텍스트 전용 수정이며, 나머지 산출물은 재작업 불필요.

**요청 조치**: 위 §9에 열거된 지점들을 불변식 서술로 재작성(ID 삭제) 후 재제출. 재게이트는 해당 파일들의 주석/문자열 diff만 확인하면 충분하며 전체 재검토는 불필요.

---

## 13. 재게이트(fix1 확인)

입력: `docs/briefs/RESULT-round6-core-fix1.md`(before/after 표). §9에서 열거한 18개 지점을 개별 재확인하고, 신규/변경 Swift 파일의 추가 라인 전체를 대상으로 ID 패턴을 독립 재스캔했다(기존 round3/round4 주석은 대상 밖 — Wave 3 H-1w 소관).

**독립 재스캔 방법**: (a) `git diff -- Sources/ Tests/ Examples/`의 추가 라인(`+`)에서 `[A-Z]{1,2}-[0-9]+w?`/`WP[0-9.]*`/`round[0-9]+`/`Wave ?[0-9]+`/`M[0-9]+`/`N[0-9]+`/`mn?[0-9]+` 패턴 검색 — **0건**. (b) 신규(미추적) Swift 14개 파일 전체를 동일 패턴으로 검색(미추적 파일은 `git diff`에 안 잡히므로 전체 내용을 스캔) — **0건**.

**§9 열거 18개 지점 개별 대조**(파일을 직접 열어 해당 라인 확인):

| # | 지점 | 확인 |
|---|---|---|
| 1 | `ABAVPlaybackTarget.swift:222` (B-7) | 해소 — "a feed cell's correct cap is the cell's own size, not the device screen's"로 재서술, ID 없음 |
| 2 | `ABAVPlaybackTarget.swift:420` (A-5w) | 해소 — "since this isn't a seek `ABPlayer` itself issued"로 재서술 |
| 3 | `ABAVPlaybackTarget.swift:504` (B-2) | 해소 — "Buffering-suppression signal only —"로 ID만 제거, 불변식 문장은 유지 |
| 4 | `ABPlayer.swift:685` (Wave 2) | 해소 — "consumers can rely on an attached item always being announced before its tuning"로 재서술 |
| 5 | `ABAVPlaybackTargetObservabilityTests.swift:6` | 해소 |
| 6 | `ABBackgroundLifecycleEngineTests.swift:7` | 해소 |
| 7 | `ABBackgroundLifecycleEngineTests.swift:31` | 해소 — "so capturing at willResignActive is what makes this scenario recoverable"로 재서술 |
| 8 | `ABBackgroundPolicyMachineTests.swift:7` | 해소 |
| 9 | `ABDetachOrderingTests.swift:6` | 해소 |
| 10 | `ABDisplaySizeTuningTests.swift:6` | 해소 |
| 11 | `ABFailureLifecycleTests.swift:6` | 해소 |
| 12 | `ABObservabilityEventsTests.swift:6` | 해소 |
| 13 | `ABObservabilityEventsTests.swift:65`(`@Test` 이름, D-2) | 해소 — "(D-2's icon-inversion fix)" 구절 삭제 |
| 14 | `ABRateTuningTargetTests.swift:6` | 해소 |
| 15 | `ABSeekUnificationTests.swift:6` | 해소 |
| 16 | `ABSeekUnificationTests.swift:131`(`@Test` 이름, I-3) | 해소 — "matches pre-existing I-3 invariant" → "never blocks on it" |
| 17 | `Fakes/ABFakePlaybackTarget.swift:81-84`(A-4/A-8) | 해소 — "since the target detaches before that event broadcasts"로 재서술 |
| 18 | `DemoModel.swift:474`(round6) | 해소 — "New round6 cases" → "Newer event cases" |

18개 지점 전부 해소 확인. 새로 도입된 ID 인용도 없음.

**로직 무변경 확인**: §2 게이트(A-5w/A-6w)에서 이미 승인한 `ABAVPlaybackTarget.swift`/`ABPlayer.swift`의 로직 diff를 이번에 다시 라인 단위로 훑어본 결과(주석 제외 `+`/`-` 라인만 필터링), 4곳의 주석 재서술을 제외하면 이전 게이트에서 검토·승인한 내용과 동일 — 신규 로직 변경 없음. `RESULT-round6-core-fix1.md`가 보고한 빌드 검증(테스트 빌드/데모 빌드 그린, 경고 0건)도 이 전제(텍스트 전용 수정)와 일치.

의미 손실도 없음 — 4개 Sources 지점 모두 ID가 가리키던 "왜"(예: B-7의 "화면 크기가 아니라 셀 크기") 근거 문장이 재서술된 텍스트 안에 그대로 보존됨.

**판정: §9 REQUEST-CHANGES 사유 전건 해소.** §2~§8, §10~§11(로직 승인·CHANGELOG·잔여 리스크)은 이번 fix1에서 변경되지 않았으므로 이전 판정 그대로 유효.

---

FINAL-VERDICT: APPROVE
