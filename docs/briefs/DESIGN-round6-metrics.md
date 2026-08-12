# DESIGN: 라운드6 트랙 F — Metrics QoE (F-0 설계 게이트)

기준 커밋 995bb6d. 입력: `DESIGN-round6-core.md` §3·§3.4·§5.5(확정 계약), `ROADMAP-round6.md` §0·§3 트랙 F, `REVIEW-round6-portfolio-audit.md` §F(F-1~F-6), 실소스 `Sources/ABPlayerKitMetrics/` 전체(373줄) · `Tests/ABPlayerKitMetricsTests/ABMetricsTests.swift`(188줄) · `Examples/ABPlayerKitDemo/`(`DemoModel.swift`, `MetricsScreen.swift`).

산출 목적: F-1w~F-6w 구현 브리프가 그대로 인용할 **이벤트 스키마 v2**와 WP별 지침. 코드 수정 없음.

---

## 0. 전역 제약 (모든 결정에 선행)

| 제약 | 내용 | 근거 |
|---|---|---|
| 파일 경계 | `Sources/ABPlayerKitMetrics/`, `Tests/ABPlayerKitMetricsTests/`, 데모의 `MetricsScreen.swift`·`DemoModel.swift`만 수정. **`Sources/ABPlayerKit/`·`ABPlayerKitControls/`·`ABPlayerKitCache/`는 한 줄도 건드리지 않는다** | ROADMAP §6 "worktree 병합 충돌" |
| additive-only | `ABMetricEvent`는 **케이스 추가만**. 기존 5케이스의 연관값·이름 불변. 공개 struct는 **기존 init 파라미터 목록 뒤에 기본값 있는 파라미터만 추가** | `POLICY-api-stability.md` "Adding `enum` cases", 코어 A-7w의 `audioTimePitchAlgorithm` 선례 |
| JSONL 하위호환 | v1에서 나가던 5종 레코드는 **같은 입력에 같은 바이트**를 낸다. 허용되는 유일한 변화는 `access` 서브오브젝트의 **키 추가** | 결정 7 |
| Sendable/Equatable | 신규 공개 값 타입 전부 `Sendable, Equatable`. `AVPlayerItem`/`NSError`를 공개 페이로드에 넣지 않는다 | 기존 `ABMetricSample`/`ABAccessSnapshot` 관례 |
| 코어 표면 소비만 | `DESIGN-round6-core.md` §5.5 동결 표면을 **소비**한다. 추가 요구는 §12 "타 트랙 전달 사항"에 기록만 하고 설계는 현 표면으로 닫는다 | BRIEF §입력 1 |
| 타이머 금지 | 하트비트/폴링 타이머를 도입하지 않는다. 모든 시각은 주입된 `ABClock`에서 온다 | ROADMAP §0 "sleep 대기 금지", 테스트 결정성 |
| 결정성 | 신규 로직의 100%는 **순수 리듀서**에서 표 테스트 가능해야 한다. 시뮬레이터·네트워크·대기 없이 | 코어 `ABBufferingEvaluator`/`ABGradePlanner` 선례 |

---

## 결정 1 — 세션 모델: 순수 누적기 + `(playerID, sessionStartedAt)` 복합 키

### 문제

F-1~F-5의 모든 지표(리버퍼 비율, watch time, 완료율, 에러율, accessLog 롤업)는 **"한 아이템의 재생 세션"**이라는 공통 스코프를 요구한다. 현재 `ABMetricsRecorder`는 `ttffStarts: [ABPlayerID: TTFFStart]` 하나뿐이고, 그마저도 세션 경계 개념이 없다.

### 선택안: `ABPlaybackSessionAccumulator`(internal, 순수 값 타입) + 얇은 번역 계층

```swift
// Session/ABPlaybackSessionAccumulator.swift (신규, internal)

/// 코어 이벤트를 지표 스코프로 정규화한 입력. `ABPlayerEvent`를 직접 받지 않는
/// 이유는 (1) AVFoundation 의존을 번역 계층에 가두고 (2) 표 테스트에서
/// 조합 폭발 없이 전이만 검증하기 위해서다.
enum ABSessionInput: Equatable {
    case attached(sourceURL: String?, wallClockEpoch: TimeInterval, isPartial: Bool)
    case ttffResolved(ABMetricSample.Outcome)
    case firstFrame
    case bufferingChanged(Bool)
    case stalled
    case stallEnded
    case timeControl(ABTimeControlStatus)
    case scrubbing(Bool)
    case position(seconds: Double, duration: Double?)
    case durationAvailable(seconds: Double)
    case playedToEnd
    case failure(ABPlayerFailure)
    case detached(reason: ABDetachReason, access: ABAccessSnapshot?)
    case finalize(access: ABAccessSnapshot?)
}

struct ABPlaybackSessionAccumulator {
    /// 순수. 상태를 전이시키고 이번 입력이 만들어낸 v2 이벤트만 순서대로 돌려준다.
    /// 레거시 이벤트(.ttff/.stall/.preloadStarted/.itemDetached/.tuning)는
    /// 여기서 만들지 않는다 — 레코더가 v1과 동일한 지점에서 직접 낸다(§10).
    mutating func ingest(
        _ input: ABSessionInput,
        playerID: ABPlayerID,
        at now: CFTimeInterval
    ) -> [ABMetricEvent]

    /// 비변이 스냅샷. 열린 버퍼 구간·재생 구간을 `now`까지 가상으로 닫아
    /// `endReason == .active`인 요약을 만든다. 데모(F-6w)의 라이브 표시용.
    func snapshot(playerID: ABPlayerID, at now: CFTimeInterval, access: ABAccessSnapshot?) -> ABSessionSummary?
}
```

`ABMetricsRecorder`는 `[ABPlayerID: ABPlaybackSessionAccumulator]`를 들고, `handle(_:from:)`이 `ABPlayerEvent` → `ABSessionInput` 번역만 한다. 번역 계층에서만 `player.avPlayerItem`/`player.hasDisplayedFirstFrame` 같은 플레이어 상태를 읽는다.

### 세션 키: `(playerID, sessionStartedAt)`

세션 식별자를 새 타입(`ABSessionID: UUID`)으로 만들지 **않는다**. 모든 v2 이벤트는 `playerID` + `sessionStartedAt: CFTimeInterval`을 나르고, 이 쌍이 JSONL 조인 키다.

| 기각안 | 사유 |
|---|---|
| `ABSessionID`(UUID) 신설 | 주입 불가능한 랜덤 값이 이벤트 페이로드에 들어가 **`ABMetricEvent`의 `Equatable` 단언과 골든 JSONL 테스트가 전부 비결정적**이 된다. 결정성이 이 트랙 전체의 테스트 전략(제약 §0)이므로 수용 불가 |
| `playerID`만으로 식별 | 한 플레이어가 attach/detach를 반복하면 로그에서 세션 구분 불가(데모가 정확히 그 패턴) |
| 이벤트 인덱스/시퀀스 번호 | 싱크가 여러 개일 때(멀티 싱크는 v1부터 가능) 번호가 갈라진다 |

### 세션 경계

| 경계 | 트리거 | 비고 |
|---|---|---|
| 열림(정상) | `.itemAttached(source:)` — 코어 §3.2 #4, **동기** 방송 | `isPartial = false` |
| 열림(부분) | 세션이 없는데 아이템을 함의하는 이벤트가 도착(`.itemStatusChanged`/`.firstFrameDisplayed`/`.timeControlStatusChanged`/`.periodicTime`/`.bufferingChanged`)하고 `player.avPlayerItem != nil` | `isPartial = true`. 레코더를 재생 도중 붙인 소비자를 무음으로 버리지 않기 위함. 요약의 `isPartial`로 소비자가 분모에서 제외할 수 있다 |
| 닫힘(정상) | `.itemDetached(reason:)` | 코어 I-6이 "모든 release 경로는 `.detachItem`을 정확히 1회 경유"를 보장 |
| 닫힘(방어) | `.gradeChanged(from:to:)`에서 `from.holdsItem && !to.holdsItem`인데 세션이 열려 있음 | `endReason = .finalized`. 정상 경로에서는 detach가 먼저 오므로 도달하지 않는다 |
| 닫힘(명시) | 신규 공개 API `endSession(for:)` | 토큰 취소 직전에 소비자가 부르는 경로(§결정 7의 토큰 규칙) |

**`beginTTFF`/`abandonTTFF`/토큰 취소는 세션을 열지도 닫지도 않는다.** 이것은 스타일 선택이 아니라 무회귀 요구다 — §10 참조.

### 아이템 보유 정책 (결정 5의 전제)

세션은 `.itemAttached` 시점에 `player.avPlayerItem`을 **강한 참조로** 붙들고, `.itemDetached` 처리 말미에 즉시 놓는다.

- 근거: 코어 §3.3이 detach 순서를 `target.detachItem()` → `.itemDetached` 방송으로 확정했다. **이벤트 수신 시점에 `player.avPlayerItem`은 이미 `nil`이다.** 현재 코드 `ABMetricsRecorder.swift:75`의 `accessSnapshot(for: player.avPlayerItem)`은 A 병합 직후 **항상 `nil`을 반환**한다(무음 회귀, §11 R-1).
- 수명 영향: 정상 경로에서 detach와 이벤트 처리는 같은 런루프 턴이므로 아이템 수명 연장은 사실상 0이다. 세션 구간 동안은 어차피 `AVPlayer`가 같은 아이템을 붙들고 있다.
- 누수 방어: 다음 `.itemAttached`가 교체, `.gradeChanged` 방어 경로가 해제, `endSession(for:)`이 해제, 레코더 자체가 해제되면 딕셔너리와 함께 해제(`@MainActor` 클래스의 `deinit`은 격리 저장소를 건드릴 수 없으므로 **명시 정리 코드를 쓰지 않는다** — ARC가 처리한다).

| 기각안 | 사유 |
|---|---|
| `weak` 참조 | `replaceCurrentItem(with: nil)` 이후 `.itemDetached` 핸들러에서 살아있다는 보장이 없다. 실측이 아니라 오토릴리스풀 타이밍에 지표가 좌우된다 |
| `AVPlayerItemNewAccessLogEntry` 알림으로 증분 폴드 | 커서 관리(로그 축소 시 이중 계수) + 알림 관찰 수명 결속이 추가된다. 얻는 것은 "세션 중 실시간 accessLog"인데, 그건 아이템을 들고 있으면 `snapshot(for:)`에서 그냥 폴드하면 된다 |
| 코어에 `.itemDetaching`(사전 통지) 이벤트 요구 | §5.5 동결 표면 개정 요구. 아이템 보유로 F 내부에서 닫을 수 있는 문제에 타 트랙 재설계를 유발 |

---

## 결정 2 — 리버퍼 구간 (F-1)

### 1차 소스는 `bufferingChanged` 쌍, `.playbackStalled`는 2차 (코어 §3.4)

단일 구간 상태기 하나가 두 입력을 모두 받는다. **이중 계수 없음** — 구간은 최대 1개만 열린다.

```
         bufferingChanged(true) / stalled
   idle ───────────────────────────────────► open(startedAt, trigger, phase)
     ▲                                              │
     │  bufferingChanged(false) / stallEnded        │ emit .buffering(interval, end: .resumed)
     ├──────────────────────────────────────────────┤
     │  detached                                    │ emit .buffering(interval, end: .detached)
     ├──────────────────────────────────────────────┤
     │  failure(isTerminal)                         │ emit .buffering(interval, end: .failed)
     └──────────────────────────────────────────────┘ finalize → end: .finalized
```

| 규칙 | 내용 |
|---|---|
| 열림 | `bufferingChanged(true)`(trigger `.buffering`) 또는 `.stalled`(trigger `.stall`) 중 **먼저 오는 것**. 이미 열려 있으면 무시(트리거는 최초값 유지) |
| 닫힘 | `bufferingChanged(false)` 또는 `stallEnded` 중 **먼저 오는 것**(end `.resumed`). 열린 구간이 없으면 무시 |
| phase | `firstFrame`을 이미 본 세션이면 `.rebuffer`, 아니면 `.startup` |
| 미종결 | `detached`/`failure(terminal)`/`finalize`가 열린 구간을 `now`까지로 잘라 닫고 `end`에 이유를 남긴다. **버리지 않는다** |
| 레거시 | `.playbackStalled`는 v1과 동일하게 `.stall(playerID:at:)`도 계속 방송한다(§10) |

**미종결 처리가 F 책임인 근거**: 코어 §3.4 — "아이템이 detach되거나 release되면 미종결 스톨은 조용히 폐기되며 `stallEnded`는 오지 않는다. 코어는 `.itemDetached`가 그 경계 신호임을 보장한다."

### startup 버퍼링을 리버퍼에서 분리하는 이유

첫 프레임 이전의 버퍼링은 **이미 TTFF가 측정하고 있는 구간**이다. 이를 리버퍼 분자에 넣으면 스타트업이 두 지표에 이중 계상되고, 업계 QoE의 표준 페어(스타트업 시간 / 리버퍼 비율)가 서로 오염된다. 그래서 이벤트는 둘 다 내되(`phase`로 구분), 요약의 `rebufferMilliseconds`는 `.rebuffer` phase만, `startupBufferMilliseconds`는 `.startup` phase만 더한다.

### 리버퍼 비율의 정의(문서에 고정)

```
rebufferRatio = rebufferMilliseconds / (rebufferMilliseconds + watchedMilliseconds)
```

분모에 리버퍼를 포함한다(Conviva/Mux 관례). 분모가 0이면 `nil`. `ABSessionSummary.rebufferRatio`가 이 계산의 유일한 구현이고, 데모·문서·테스트가 전부 그것을 인용한다.

| 기각안 | 사유 |
|---|---|
| `.playbackStalled`만으로 리버퍼 측정 | 코어 §3.4 명시 기각 — `automaticallyWaitsToMinimizeStalling == true`(기본값)에서 스톨 알림이 오지 않는 경우가 흔하다 |
| `timeControlStatusChanged(.waitingToPlay)`로 리버퍼 판정 | 코어 B-2가 기각한 추론과 동일. 레이트 평가 대기와 실제 리버퍼가 구분되지 않는다. 판정은 코어의 `ABBufferingEvaluator`가 이미 하고 있고, F는 그 결과(`bufferingChanged`)를 소비만 하는 것이 옳다 |
| 스톨/버퍼링을 별도 구간으로 각각 집계 | 같은 물리적 정지가 두 번 계상된다. 트리거만 기록하고 구간은 하나로 |
| 히스테리시스(짧은 구간 무시) | 임계값이 곧 정책이고, 정책은 소비자 것이다. 원시 구간을 다 내보내고 필터는 소비자에게 남긴다(요약에는 총합만) |

---

## 결정 3 — watch time과 완료율 (F-2)

### watch time의 1차 소스는 `.timeControlStatusChanged`, `.periodicTime`이 아니다

```
watch time += (now - playingSince)  when leaving .playing
```

- 누적 시작: `.timeControlStatusChanged(.playing)`
- 누적 종료: `.timeControlStatusChanged(.paused|.waitingToPlay)`, `scrubbing(true)`, `detached`, `finalize`
- 재개: `scrubbing(false)`이고 마지막 상태가 `.playing`이면 다시 시작
- 스크럽 중 제외 근거: 스크럽 세션은 `scrubbingPlayer`를 고정해 재생을 유지할 수 있어(코어 강점 목록) 상태가 `.playing`인 채로 사용자는 탐색 중이다. 시청으로 계상하지 않는다

이 정의는 **`periodicTimeInterval`이 기본 `nil`(`ABPlayerConfiguration.swift:46`)이어도 정확히 동작한다.** 이것이 이 결정의 핵심이다.

### `periodicTimeInterval == nil` 처리 방침

| 방침 | 내용 |
|---|---|
| watch time | `.periodicTime`에 **의존하지 않는다**. 위 상태 기반 누적기로 완전히 계산된다 |
| 위치/길이 | `.periodicTime(ABPlaybackTime)`가 오면 `lastPositionSeconds`/`durationSeconds`를 갱신. 오지 않으면 `.durationAvailable(CMTime)`(코어 §3.2 #2)로 길이를, `.seekCompleted(to:)`로 위치를 갱신 |
| 완료율 | `playedToEnd`면 1.0. 아니면 `lastPositionSeconds / durationSeconds`(둘 다 있을 때). 둘 다 없으면 **`nil`(0이 아니다)** — "모름"과 "0%"를 구분한다 |
| 문서화 | DocC에 "`completionRatio`의 정밀도는 `periodicTimeInterval`을 설정하면 올라간다. `watchedMilliseconds`는 설정과 무관하게 정확하다"를 명시 |

### 레코더가 `periodicTimeInterval`을 건드리지 않는 이유 (강한 기각)

`ABPlayerKitControls`의 `ABPeriodicIntervalLease`(`ABPeriodicIntervalLease.swift:10-14`)는 **자신이 붙던 시점의 이전 값**을 캡처해 복원한다. 레코더가 그 뒤에 `periodicTimeInterval`을 덮어쓰면, 컨트롤이 사라질 때 레코더의 값이 아니라 컨트롤이 기억한 옛 값으로 되돌아가고, 레코더의 복원은 컨트롤의 값을 지운다. **두 리스가 last-writer-wins로 서로를 오염시킨다.** 관측 라이브러리가 관측 대상의 설정을 바꾸지 않는다는 원칙과도 맞다.

| 기각안 | 사유 |
|---|---|
| 레코더가 `periodicTimeInterval`을 리스 | 위 상호 오염. 그리고 관측이 관측 대상의 KVO 부하를 바꾼다 |
| `.periodicTime` 델타 합으로 watch time 산출 | 간격이 `nil`이면 0. 배속·시크·루프에서 델타가 시청 시간과 다르다 |
| `.rateChanged`로 재생 여부 판정 | rate는 의도이고 실제 진행이 아니다. 스톨 중에도 rate는 유지된다(코어 I-2) |
| 콘텐츠 시간(배속 반영) 별도 누적 | 이번 라운드 비범위(§13). 벽시계 시청 시간이 QoE 분모의 표준 |

### 완료율(세션 넘어) 정의

```
completionRate = (playedToEnd == true 인 세션 수) / (firstFrame 을 본 세션 수)
```

분모에서 첫 프레임 없이 끝난 세션(= 이탈)을 제외한다. 이탈은 `ABPlaybackStatistics.abandonRate`가 이미 담당하는 별개 지표다.

---

## 결정 4 — 실패 이벤트 (F-3)

### `.failureReported(ABPlayerFailure)`만 소비한다

| 규칙 | 내용 | 근거 |
|---|---|---|
| 소비 대상 | `.failureReported`만. **`.failed`는 의도적으로 무시** | 코어 §3.3이 "`.failed(kind)` → `.failureReported(failure)`" 쌍 방송을 확정. 둘 다 소비하면 모든 실패가 2배로 계상된다 |
| 페이로드 보존 | `ABPlayerFailure`를 통째로 이벤트에 싣는다(`Sendable, Equatable`) — `kind`, `origin?.domain`, `origin?.code`, `isTerminal` 전부 보존 | B-3의 요구 그대로 |
| 에러율 분자 | `failure.isTerminal == true`인 세션만. `.itemErrorLogEntry`(진단)는 `diagnosticCount`로 따로 센다 | 코어 §3.4 |
| 에러율 정의 | `terminalFailureRate = (터미널 실패가 1회 이상 있었던 세션 수) / (세션 수)`. **이벤트 수가 아니라 세션 수** — 한 세션의 연쇄 실패가 비율을 왜곡하지 않게 | |
| 재시도 정책 | 라이브러리는 분류하지 않는다. `domain`/`code`를 원형 그대로 내보내고 `-1009` vs `-11829` 판단은 소비자 몫 | 코어 §3.4는 "구분한다"고만 요구. 정책을 굽는 순간 오분류가 지표가 된다 |

### JSONL을 위한 `kind` 안정 문자열

`String(describing:)`은 `"itemFailed(description: \"...\")"`처럼 연관값이 섞여 집계 키로 못 쓴다. 싱크에 **내부 매핑 함수**를 둔다.

```swift
// internal, ABMetricsSink.swift
static func kindName(_ kind: ABPlayerError) -> String   // "itemFailed" | "prerollTimedOut" | ... | "unknown"
```

`ABPlayerError`는 non-exhaustive이므로 `default: "unknown"`을 반드시 둔다. **이 매핑은 유지보수 지점이다** — 코어에 에러 케이스가 추가되면 여기도 늘려야 하고, 안 늘리면 `"unknown"`으로 떨어진다(무음 실패가 아니라 명시적 버킷). 전 케이스 매핑 테스트를 F-3w에 둔다.

| 기각안 | 사유 |
|---|---|
| `.failed`와 `.failureReported`를 둘 다 소비하고 중복 제거 | 같은 턴의 두 이벤트를 시각으로 짝짓는 휴리스틱이 필요. 코어가 순서를 계약으로 준 마당에 불필요 |
| `ABPlayerError`에 `Hashable` 요구 후 딕셔너리 키로 사용 | 타 트랙(A) 표면 변경 요구. `ABErrorOrigin`이 이미 `Hashable`이므로 origin 기준 집계로 충분(§12에 선택 요청으로만 기록) |
| 실패마다 세션 강제 종료 | 종료성 실패 후에도 코어는 아이템을 붙들고 있을 수 있고, 실제 세션 종료는 `.itemDetached`다. 실패는 세션 **안의 사건**으로 기록한다 |

---

## 결정 5 — `.hit`/waited 분포 분리(F-4)와 accessLog 전체 순회(F-5)

### 5.1 분포 분리: 기존 필드 의미를 바꾸지 않고 새 분포를 추가

현재 `ABPlaybackStatistics.aggregate`(`ABPlaybackStatistics.swift:42-52`)는 `.hit`을 `successfulDurations`에 **0으로 밀어넣는다**. 프리로드가 흔한 피드에서 p50이 0으로 붕괴한다(F-4).

```swift
public struct ABLatencyDistribution: Sendable, Equatable {
    public let count: Int
    public let p50: Double
    public let p95: Double
    public let max: Double
    public static let empty: ABLatencyDistribution
    public init(count: Int, p50: Double, p95: Double, max: Double)
}

extension ABPlaybackStatistics {
    /// `.waited` 샘플만으로 만든 분포. `.hit`(0 ms)이 섞이지 않는다.
    public let waited: ABLatencyDistribution      // 저장. 기존 init 맨 끝에 `waited: ... = .empty`
}
```

- **기존 `p50`/`p95`/`max`의 값과 의미는 그대로 둔다**(= `.hit`을 0으로 포함한 "성공 샘플 전체"). DocC에 "레거시 분포. 새 코드는 `waited`를 읽어라"를 명시.
- `init`은 `max: Double` 뒤에 `waited: ABLatencyDistribution = .empty`를 추가 — 소스 호환 유지(`ABMetricsTests.swift:57`의 호출이 무수정 통과).

| 기각안 | 사유 |
|---|---|
| `p50`/`p95`/`max`를 waited-only로 재정의 | 관측 가능한 출력 변경 + `ABMetricsTests.swift:48`(p50 == 100 → 300)이 깨진다. 무회귀 가드가 이 트랙의 유일한 안전망인데 그것부터 수정하는 설계는 채택하지 않는다 |
| `hit` 분포 추가 | `.hit`은 정의상 전부 0 ms다. 분포가 무의미하고 `hitCount`가 이미 있다 |
| 별도 타입 `ABTTFFStatistics` 신설 | 기존 타입이 이미 그 역할. 이름만 늘고 데모/문서가 둘로 갈라진다 |

### 5.2 accessLog 전체 순회 — 폴드 결과를 `ABAccessSnapshot`에 **키 추가로** 담는다

현재 `accessSnapshot(for:)`(`ABMetricsRecorder.swift:94-103`)은 `events.last`만 읽어 스위치 횟수·dropped frames·누적 바이트를 전부 버린다(F-5).

```swift
// Session/ABAccessLogFolder.swift (신규, internal)
/// AVFoundation 비의존 값. 어댑터가 `AVPlayerItemAccessLogEvent`를 이 값으로 옮긴다.
struct ABAccessLogEntry: Equatable { /* bytes, indicatedBitrate, observedBitrate, startupTime,
                                        numberOfStalls, droppedVideoFrames, durationWatched,
                                        segmentsDownloaded, mediaRequests */ }

enum ABAccessLogFolder {
    static func fold(_ entries: [ABAccessLogEntry]) -> ABAccessSnapshot
}
```

폴드 규칙(음수 = "unknown"이므로 **합산에서 제외**한다 — `AVPlayerItemAccessLogEvent`의 다수 필드는 값이 없으면 음수를 돌려준다):

| 필드 | v1 의미 | v2에서의 처리 |
|---|---|---|
| `numberOfBytesTransferred` | 마지막 엔트리 | **그대로 유지**(마지막 엔트리) |
| `indicatedBitrate` | 마지막 엔트리 | **그대로 유지** |
| `observedBitrate` | 마지막 엔트리 | **그대로 유지** |
| `startupTime` | 마지막 엔트리 | **그대로 유지** |
| `stallCount` | 마지막 엔트리의 `numberOfStalls` | **그대로 유지** |
| `totalBytesTransferred` | — | 신규: 전 엔트리 합(음수 제외) |
| `totalStallCount` | — | 신규: 전 엔트리 `numberOfStalls` 합 |
| `droppedVideoFrameCount` | — | 신규: 전 엔트리 합 (F-5) |
| `bitrateSwitchCount` | — | 신규: 인접 엔트리 `indicatedBitrate`가 **달라진 횟수**(양쪽 다 > 0인 경우만) (F-5) |
| `durationWatchedSeconds` | — | 신규: 전 엔트리 합 |
| `segmentsDownloadedCount` / `mediaRequestCount` | — | 신규: 합 |
| `observedBitrateAverage` | — | 신규: `durationWatched` 가중 평균, 가중치 총합 0이면 0 |
| `initialStartupTimeSeconds` | — | 신규: **첫** 음수 아닌 `startupTime`(`nil` 가능) |
| `entryCount` | — | 신규: 엔트리 수 |

- **`bitrateSwitchCount`를 `entryCount - 1`로 세지 않는 이유**: 새 access log 엔트리는 비트레이트 스위치 외에 서버 주소 변경·플레이백 세션 변경에서도 추가된다. 인접 비교가 감사가 요구한 "스위치 횟수"에 더 가깝다.
- 기존 5필드를 그대로 두는 것이 **JSONL 하위호환의 핵심**이다(결정 7).
- `ABAccessSnapshot.init`은 기존 5파라미터 뒤에 신규 파라미터를 **전부 기본값과 함께** 붙인다.

### 5.3 폴드 시점

| 시점 | 동작 |
|---|---|
| `.itemDetached` | 세션이 붙들고 있던 아이템(결정 1)의 `accessLog()?.events` 전체를 어댑터로 옮겨 폴드 → `.itemDetached`(레거시)와 `.sessionSummary`의 `access`에 사용 → 아이템 해제 |
| `snapshot(for:)` | 요청 시점에 같은 폴드를 즉시 수행(데모 라이브 표시) |
| 그 외 | 폴드하지 않는다. 세션 중 반복 폴드는 비용만 늘고 소비자가 없다 |

---

## 결정 6 — 벽시계 앵커

### 세션 시작 시 1회, `ABSessionAnchor`에 실어 방송

```swift
public struct ABSessionAnchor: Sendable, Equatable {
    public let playerID: ABPlayerID
    /// 단조 시계 값. 이 세션의 모든 v2 이벤트의 `sessionStartedAt`과 같다(세션 키).
    public let startedAt: CFTimeInterval
    /// 1970 기준 초. `startedAt`을 서버 로그와 조인하기 위한 유일한 매핑점.
    public let wallClockEpoch: TimeInterval
    public let sourceURL: String?
    public let isPartial: Bool
}
```

- **단조/벽시계 역할 분리**: 모든 구간 계산은 단조 시계(`CACurrentMediaTime`)로만 한다. 벽시계는 세션당 1회의 앵커로만 등장한다. NTP 보정·사용자의 시계 변경이 리버퍼 duration을 음수로 만드는 사고를 원천 차단.
- **`sourceURL`의 취급**: 조인 가치가 가장 큰 필드지만 URL은 쿼리 파라미터에 토큰이 실릴 수 있다. 레코더 `init`에 **기본값 있는 파라미터 하나**(`includesSourceURL: Bool = true`)를 두어 끌 수 있게 하고, DocC에 "서명된 URL을 쓰는 소비자는 끄거나 자체 싱크에서 마스킹하라"를 명시한다. 라이브러리가 마스킹 규칙을 굽지는 않는다(정책은 소비자 것).
- **알려진 한계(DocC에 기재)**: `CACurrentMediaTime()`은 기기 슬립 중 진행하지 않는다. 앵커는 세션 시작 시점의 매핑이므로, 슬립을 낀 장시간 세션에서는 앵커 기준 환산과 실제 벽시계가 벌어질 수 있다. 정밀 조인이 필요하면 세션을 짧게 끊는 것이 답이다.

### `ABClock` 확장 방식 (외부 준수 타입을 깨지 않는 유일한 형태)

```swift
public protocol ABClock: Sendable {
    var now: CFTimeInterval { get }
    /// 1970 기준 초. 기본 구현은 `Date().timeIntervalSince1970`.
    var wallClockEpoch: TimeInterval { get }
}

extension ABClock {
    public var wallClockEpoch: TimeInterval { Date().timeIntervalSince1970 }
}
```

프로토콜에 **요구사항으로 선언 + extension에 기본 구현**. 기존 외부 준수 타입은 무수정 컴파일되고(기본 구현 상속), 테스트 페이크는 오버라이드해 결정적 값을 준다. 요구사항 선언 없이 extension에만 두면 `any ABClock` 경유 호출이 정적 디스패치돼 페이크의 오버라이드가 무시되므로, **둘 다** 필요하다.

| 기각안 | 사유 |
|---|---|
| 별도 `ABWallClock` 프로토콜 + 레코더 init 파라미터 추가 | 주입 지점이 둘로 늘고, 두 시계가 다른 페이크로 갈라질 수 있다 |
| 앵커를 싱크가 붙임(레코드 시각) | 싱크는 비동기 큐에서 쓴다. 이벤트 발생 시각이 아니라 기록 시각이 되어 조인이 어긋난다 |
| 모든 이벤트에 벽시계를 함께 실음 | 레코드마다 비단조 값이 늘어나고, 시계 점프가 이벤트별로 다르게 반영된다. 앵커 1회 + 단조 오프셋이 정확하다 |

---

## 결정 7 — JSONL 하위호환과 싱크 개선 (F-6)

### 7.1 하위호환 계약 (구현 브리프가 그대로 인용할 규칙)

| 규칙 | 내용 |
|---|---|
| R1 | v1의 5종 레코드(`ttff`/`stall`/`preloadStarted`/`itemDetached`/`tuning`)는 **같은 입력에 같은 바이트**를 낸다. 키 이름·타입·`.sortedKeys` 정렬·개행 모두 불변 |
| R2 | 유일한 예외는 `itemDetached.access` 서브오브젝트의 **키 추가**. 기존 5키의 값 산출식은 결정 5.2대로 불변 |
| R3 | 신규 이벤트는 새 `"event"` 값으로만 등장한다(`sessionStarted`/`buffering`/`failure`/`sessionSummary`). 소비자는 모르는 `"event"` 값을 무시해야 한다는 계약을 DocC에 명시 |
| R4 | **전역 `"schema"`/`"v"` 키를 추가하지 않는다.** R1을 깨는 유일한 후보였고, 얻는 것(버전 감지)은 `sessionStarted` 레코드의 존재 여부로 대체된다 |
| R5 | 값이 `nil`인 선택 필드는 **키를 내보내지 않는다**(v1의 `resumedFromTime` 관례 계승) |

### 7.2 싱크 개선 (F-6 항목별)

| 항목 | 결정 |
|---|---|
| 핸들 유지 | `FileHandle`을 최초 쓰기에서 열어 큐 위에 보관. 매 레코드 open/close 제거. `deinit`에서 close |
| `flush()` 공개 | `func flush()` → `public func flush()`(additive). `queue.sync {}` + `try? handle.synchronize()` |
| 에러 카운터 | `public var writeFailureCount: Int`(큐 경유 읽기), `public var lastWriteErrorDescription: String?`. 쓰기 실패 시 **핸들을 1회 재개방 후 재시도**, 그래도 실패하면 카운터 증가 + `Logger`(이미 `OSLog` import 중)에 `.error` 1줄. 여전히 예외를 밖으로 던지지 않는다(싱크는 관측 경로이며 재생을 깨선 안 된다) |
| 로테이션 | `init(fileURL:maxFileSizeBytes:maxRotatedFiles:)` — **기존 init 뒤에 기본값 파라미터 추가**. `maxFileSizeBytes: Int? = nil`(기본 = 현행 동작, 로테이션 없음), `maxRotatedFiles: Int = 1`. 초과 시 `metrics.jsonl` → `metrics.jsonl.1` 회전, 초과분 삭제. 회전은 쓰기 직전 큐 위에서 동기 수행 |
| 앵커 | 결정 6의 `sessionStarted` 레코드를 직렬화(§8.3) |

기본값을 "로테이션 없음"으로 두는 이유: 동작 변경 없는 기본값이 하위호환 규칙과 일관되고, 켜는 쪽이 명시적 선택이 된다. 데모(F-6w)는 켜서 시연한다.

### 7.3 토큰과 세션 종료

`attach(to:)`가 돌려주는 `ABObservationToken`이 취소돼도 레코더는 그것을 알 수 없다(코어에 훅 없음). 따라서:

- **토큰 취소는 어떤 이벤트도 만들지 않는다**(무회귀 요구, §10 T-1).
- 소비자가 세션 요약을 원하면 취소 **전에** `endSession(for:)`를 부른다. DocC에 이 순서를 명시.
- 코어에 취소 훅을 요구하지 않는다(§12에 기록만).

---

## 8. 이벤트 스키마 v2 — 전체 표

### 8.1 `ABMetricEvent` (기존 5 + 신규 4, 전부 additive)

| # | 케이스 | 방출 시점 | 상태 |
|---|---|---|---|
| 1 | `ttff(ABMetricSample)` | 기존과 동일 | 불변 |
| 2 | `stall(playerID:at:)` | `.playbackStalled` 수신 시 (기존과 동일) | 불변 |
| 3 | `preloadStarted(playerID:at:)` | 기존과 동일 | 불변 |
| 4 | `itemDetached(playerID:reason:access:)` | 기존과 동일. `access`는 이제 폴드 결과(결정 5.2) | 시그니처 불변 |
| 5 | `tuning(playerID:role:)` | 기존과 동일 | 불변 |
| 6 | `sessionStarted(ABSessionAnchor)` | 세션 열림(결정 1) | 신규 |
| 7 | `buffering(ABBufferingInterval)` | 버퍼 구간이 닫힐 때 1회 | 신규 |
| 8 | `failure(ABFailureRecord)` | `.failureReported` 수신 시 | 신규 |
| 9 | `sessionSummary(ABSessionSummary)` | 세션 닫힘 | 신규 |

`ABMetricEvent`의 doc comment와 DocC 페이지에 non-exhaustive 관례를 `ABPlayerEvent`와 같은 문장으로 추가한다(POLICY "Adding `enum` cases").

### 8.2 신규 공개 값 타입

```swift
public struct ABSessionAnchor: Sendable, Equatable {
    public let playerID: ABPlayerID
    public let startedAt: CFTimeInterval
    public let wallClockEpoch: TimeInterval
    public let sourceURL: String?
    public let isPartial: Bool
}

public struct ABBufferingInterval: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case startup, rebuffer }
    public enum Trigger: Sendable, Equatable { case buffering, stall }
    public enum End: Sendable, Equatable { case resumed, detached, failed, finalized }

    public let playerID: ABPlayerID
    public let sessionStartedAt: CFTimeInterval
    public let startedAt: CFTimeInterval
    public let endedAt: CFTimeInterval
    public let phase: Phase
    public let trigger: Trigger
    public let end: End
    public var milliseconds: Double { max(0, endedAt - startedAt) * 1_000 }
}

public struct ABFailureRecord: Sendable, Equatable {
    public let playerID: ABPlayerID
    public let sessionStartedAt: CFTimeInterval?   // 세션 밖 실패 허용
    public let at: CFTimeInterval
    public let failure: ABPlayerFailure            // kind / origin(domain, code) / isTerminal
}

public struct ABSessionSummary: Sendable, Equatable {
    public enum EndReason: Sendable, Equatable {
        case active                     // snapshot(for:) 전용
        case detached(ABDetachReason)
        case finalized
    }

    public let playerID: ABPlayerID
    public let startedAt: CFTimeInterval
    public let wallClockEpoch: TimeInterval
    public let endedAt: CFTimeInterval
    public let endReason: EndReason
    public let isPartial: Bool
    public let sourceURL: String?

    public let startupOutcome: ABMetricSample.Outcome?   // hit / waited(ms) / abandoned
    public let watchedMilliseconds: Double
    public let startupBufferMilliseconds: Double
    public let rebufferMilliseconds: Double
    public let rebufferCount: Int
    public let stallEventCount: Int
    public let terminalFailureCount: Int
    public let diagnosticCount: Int
    public let lastFailure: ABPlayerFailure?
    public let playedToEnd: Bool
    public let lastPositionSeconds: Double?
    public let durationSeconds: Double?
    public let access: ABAccessSnapshot?

    public var rebufferRatio: Double?        // 결정 2의 식. 분모 0이면 nil
    public var completionRatio: Double?      // 결정 3의 식. 모르면 nil
    public var startupMilliseconds: Double?  // startupOutcome == .waited(ms) 일 때만
}

public struct ABQoESummary: Sendable, Equatable {
    public let sessionCount: Int
    public let partialSessionCount: Int
    public let firstFrameSessionCount: Int
    public let completedSessionCount: Int
    public let failedSessionCount: Int
    public let watchedMilliseconds: Double
    public let rebufferMilliseconds: Double
    public let rebufferCount: Int
    public let droppedVideoFrameCount: Int
    public let bitrateSwitchCount: Int

    public var rebufferRatio: Double?
    public var completionRate: Double?
    public var terminalFailureRate: Double?
    public var rebuffersPerHourWatched: Double?

    /// `.sessionSummary` 이벤트만 접어 만든다. 다른 케이스는 무시.
    public static func aggregate(_ events: [ABMetricEvent]) -> ABQoESummary
}
```

모든 신규 struct의 `public init`은 **선택/수치 필드 전부에 기본값**을 준다. 다음 라운드에서 필드를 추가할 때 소스 호환을 지킬 수 있는 유일한 형태다.

### 8.3 JSONL 직렬화 표

기존 5종(불변, R1):

| event | 키 |
|---|---|
| `ttff` | `event`, `sample{playerID, startedAt, outcome{kind[, milliseconds]}[, resumedFromTime]}` |
| `stall` | `event`, `playerID`, `at` |
| `preloadStarted` | `event`, `playerID`, `at` |
| `itemDetached` | `event`, `playerID`, `reason`, `access{…}`(선택) |
| `tuning` | `event`, `playerID`, `role` |

`access` 오브젝트(기존 5키 + 신규 키, R2):

| 키 | 타입 | 상태 |
|---|---|---|
| `numberOfBytesTransferred` / `indicatedBitrate` / `observedBitrate` / `startupTime` / `stallCount` | Int64 / Double×3 / Int | 기존, 값 산출식 불변 |
| `totalBytesTransferred` | Int64 | 신규 |
| `totalStallCount` / `droppedVideoFrameCount` / `bitrateSwitchCount` / `segmentsDownloadedCount` / `mediaRequestCount` / `entryCount` | Int | 신규 |
| `durationWatchedSeconds` / `observedBitrateAverage` | Double | 신규 |
| `initialStartupTimeSeconds` | Double | 신규(선택, R5) |

신규 4종:

| event | 키 |
|---|---|
| `sessionStarted` | `event`, `playerID`, `startedAt`, `wallClockEpoch`, `isPartial`, `sourceURL`(선택) |
| `buffering` | `event`, `playerID`, `sessionStartedAt`, `startedAt`, `endedAt`, `milliseconds`, `phase`(`startup`\|`rebuffer`), `trigger`(`buffering`\|`stall`), `end`(`resumed`\|`detached`\|`failed`\|`finalized`) |
| `failure` | `event`, `playerID`, `at`, `isTerminal`, `kind`(안정 문자열, 결정 4), `description`, `sessionStartedAt`(선택), `domain`(선택), `code`(선택) |
| `sessionSummary` | `event`, `playerID`, `startedAt`, `wallClockEpoch`, `endedAt`, `endReason`(`detached:<reason>`\|`finalized`), `isPartial`, `watchedMilliseconds`, `startupBufferMilliseconds`, `rebufferMilliseconds`, `rebufferCount`, `stallEventCount`, `terminalFailureCount`, `diagnosticCount`, `playedToEnd`, 선택: `sourceURL`, `startupOutcome{…}`, `lastPositionSeconds`, `durationSeconds`, `rebufferRatio`, `completionRatio`, `access{…}` |

- `endReason == .active`인 요약은 **직렬화 대상이 아니다**(`snapshot(for:)` 전용, 싱크로 가지 않음).
- 전 레코드 `JSONSerialization`의 `.sortedKeys` 유지.

### 8.4 이벤트 순서 계약 (소비자가 의존해도 되는 것)

- 세션 시작: `.sessionStarted` → (이후 세션 이벤트들)
- 스톨 1주기: `.stall`(레거시, 즉시) → … → `.buffering(interval)`(구간이 닫힐 때)
- 실패: `.failure` (코어의 `.failed`/`.failureReported` 쌍당 정확히 1개)
- 세션 종료: `.itemDetached`(레거시) → `.buffering`(미종결 구간이 있으면) → `.sessionSummary`
- TTFF: v1과 동일 지점·동일 순서

---

## 9. WP별 구현 지침 + 테스트 전략

전 WP 공통: Swift 6 zero-warning, 시뮬레이터 부팅 금지, `sleep` 금지, 커밋 금지, 새 주석에 내부 리뷰 ID 인용 금지(불변식만 서술). WP는 **직렬**로 진행한다(같은 파일을 연속 수정).

### F-1w — 세션 스캐폴딩 + 리버퍼 구간 (F-1, 결정 1·2·6의 이벤트 방출)

**신규 파일**: `Session/ABPlaybackSessionAccumulator.swift`, `Session/ABSessionInput.swift`, `Model/ABSessionAnchor.swift`, `Model/ABBufferingInterval.swift`, `Model/ABSessionSummary.swift`.
**수정**: `ABMetricEvent.swift`(케이스 6·7·9 추가 + non-exhaustive doc), `ABMetricsRecorder.swift`(세션 딕셔너리 + 번역 계층 + `endSession(for:)` + 아이템 보유), `ABClock.swift`(`wallClockEpoch`).

지침:
1. 순수 누적기를 먼저 만들고, 레코더는 `ABPlayerEvent` → `ABSessionInput` 번역과 세션 딕셔너리 관리만 한다. **누적기에 `import AVFoundation`이 들어가면 설계 위반**이다.
2. 레코더에 테스트 심(seam)을 둔다: `internal func ingest(_ event: ABPlayerEvent, playerID: ABPlayerID, hasItem: Bool, at now: CFTimeInterval)`. 공개 `handle(_:from:)`은 플레이어에서 `hasItem`/`sourceURL`을 뽑아 이 심을 호출한다. 코어의 test-only init(`ABPlayer.swift:153`)과 같은 관례.
3. 레거시 이벤트 방출 지점(`.ttff`/`.stall`/`.preloadStarted`/`.itemDetached`/`.tuning`)은 **한 줄도 옮기지 않는다**. v2 이벤트는 그 뒤에 덧붙인다(§8.4).
4. `endSession(for:)`는 멱등 — 열린 세션이 없으면 아무것도 하지 않는다.
5. `ABMetricsRecorder.init`에 `includesSourceURL: Bool = true`를 **기존 파라미터 뒤에** 추가(결정 6). `false`면 앵커/요약의 `sourceURL`이 `nil`.
6. `ABMetricEvent`/`ABMetricSample`/`ABAccessSnapshot`의 DocC 토픽 그룹에 신규 타입 등재.

테스트(신규 파일 `ABSessionAccumulatorTests.swift`, 전부 순수·동기):
- 버퍼 구간 표 테스트: (열림 트리거 2종) × (닫힘 트리거 4종) × (firstFrame 전/후) 조합 → `phase`/`trigger`/`end`/`milliseconds` 검증.
- 이중 열림(`bufferingChanged(true)` 2연속)이 구간 1개만 만든다.
- 닫힘만 온 경우(`stallEnded` 단독)가 아무 이벤트도 만들지 않는다.
- detach 시 미종결 구간이 `end == .detached`로 닫히고, 그 뒤 `.sessionSummary`가 이어진다(순서 단언).
- 부분 세션: `attached` 없이 `timeControl(.playing)`부터 시작 → `isPartial == true`.
- 앵커: 페이크 시계의 `wallClockEpoch`가 `.sessionStarted`에 실린다.
- 통합(실 `ABPlayer` 사용, 기존 테스트 관례): `set(source:grade:.current)` → `.sessionStarted` 1회, `release()` → `.sessionSummary` 1회.

### F-2w — watch time + 완료율 (F-2, 결정 3)

**수정**: 누적기(재생 구간 누적, 위치/길이 추적), 레코더 번역(`.timeControlStatusChanged`/`.scrubbingChanged`/`.periodicTime`/`.seekCompleted`/`.durationAvailable`/`.playedToEnd`).

지침:
1. 재생 누적은 `timeControl` 입력에서만 시작/정지. `scrubbing(true)`는 정지, `scrubbing(false)`는 마지막 상태가 `.playing`일 때만 재개.
2. `player.configuration`을 **읽지도 쓰지도 않는다**(결정 3의 리스 상호 오염).
3. `durationSeconds`는 `.durationAvailable` 또는 `.periodicTime`의 `duration` 중 나중 값. `lastPositionSeconds`는 `.periodicTime`/`.seekCompleted` 중 나중 값.
4. `completionRatio`는 계산 프로퍼티. 모르면 `nil`.

테스트:
- 표: `playing`(t=10) → `paused`(t=25) → `playing`(t=30) → `detached`(t=40) ⇒ `watchedMilliseconds == 25_000`.
- `periodicTimeInterval == nil` 시나리오(= `position` 입력 0회)에서도 watch time이 정확하고, `completionRatio == nil`.
- `playedToEnd` ⇒ `completionRatio == 1`.
- 스크럽 중 시간은 계상되지 않는다.
- 리버퍼 구간과 재생 구간이 겹치지 않음: `playing` → `bufferingChanged(true)`(상태도 `.waitingToPlay`로 전이) 시나리오에서 `watched + rebuffer`가 실제 경과를 넘지 않는다.

### F-3w — 실패 이벤트 (F-3, 결정 4)

**신규**: `Model/ABFailureRecord.swift`. **수정**: 누적기(카운터), 레코더 번역, 싱크(`kindName`).

지침:
1. `.failureReported`만 소비. `.failed`는 `default`로 흘린다(주석에 이유 1줄: 코어가 쌍으로 방송하므로 이중 계수 방지).
2. 터미널 실패는 열린 버퍼 구간을 `end == .failed`로 닫는다.
3. 세션이 없어도 `.failure`는 방출한다(`sessionStartedAt == nil`) — preroll 실패처럼 attach 이전/이후 경계에서 나는 실패를 잃지 않기 위해.

테스트:
- `origin`의 `domain`/`code`가 이벤트에 그대로 실린다(`NSURLErrorDomain`/-1009).
- `isTerminal == false`(`.itemErrorLogEntry`)가 `diagnosticCount`만 올리고 `terminalFailureCount`는 올리지 않는다.
- `kindName`이 현재 `ABPlayerError` 전 케이스에 대해 안정 문자열을 낸다(케이스 추가 시 `"unknown"`).
- 세션 밖 실패가 `sessionStartedAt == nil`로 기록된다.

### F-4w — 분포 분리 + accessLog 폴드 + 집계 v2 (F-4, F-5, 결정 5)

**신규**: `ABLatencyDistribution.swift`, `Session/ABAccessLogFolder.swift`, `ABQoESummary.swift`. **수정**: `ABPlaybackStatistics.swift`, `ABMetricEvent.swift`(`ABAccessSnapshot` 필드 추가), `ABMetricsRecorder.swift`(`accessSnapshot(for:)`를 폴드로 교체 + `snapshot(for:)` 공개).

지침:
1. `ABAccessSnapshot`/`ABPlaybackStatistics`의 신규 init 파라미터는 **기존 파라미터 뒤 + 기본값**. 순서를 바꾸면 소스 호환이 깨진다.
2. 폴드는 `[ABAccessLogEntry]` 순수 함수. `AVPlayerItemAccessLogEvent` → `ABAccessLogEntry` 어댑터만 AVFoundation을 안다.
3. 음수 필드는 "unknown"이므로 합산에서 제외하고, 전부 unknown이면 해당 신규 필드는 0(또는 `initialStartupTimeSeconds`는 `nil`).
4. `snapshot(for player:) -> ABSessionSummary?`는 `endReason == .active`를 돌려주고 **싱크에 기록하지 않는다**.

테스트:
- 폴드 표 테스트: 3엔트리(비트레이트 A→A→B) ⇒ `bitrateSwitchCount == 1`; 음수 dropped frames가 합산에서 빠짐; 가중 평균이 `durationWatched` 가중임; 빈 배열 ⇒ 전부 0/`nil`.
- 기존 5필드가 마지막 엔트리 값과 같다(하위호환 잠금).
- `ABPlaybackStatistics.aggregate`: `.hit` 1 + `.waited(100/300/900)` ⇒ 레거시 `p50 == 100`(불변) **그리고** `waited.p50 == 300`, `waited.count == 3`.
- `ABQoESummary.aggregate`가 `.sessionSummary` 외 케이스를 무시하고, 세션 0개에서 비율이 `nil`.
- **회귀 잠금**: `.itemDetached` 이벤트의 `access`가 `nil`이 아니다(A-4w 순서 변경 이후에도) — 아이템 보유 정책의 실증.

### F-5w — 싱크 (F-6, 결정 7)

**수정**: `ABMetricsSink.swift`.

지침:
1. 핸들 지연 개방 + 큐 보관 + `deinit` close. 큐는 기존 직렬 큐 그대로.
2. `flush()` public 승격 + `synchronize()`.
3. 쓰기 실패 → 1회 재개방 재시도 → 실패 시 카운터 증가 + `Logger` `.error`. 예외를 밖으로 던지지 않는다.
4. 로테이션 파라미터를 init 맨 뒤에 기본값과 함께 추가. 회전 시 `.1`부터 밀어내고 `maxRotatedFiles` 초과분 삭제.
5. 신규 4종 직렬화(§8.3). `nil`은 키 생략.

테스트(신규 `ABJSONLinesSinkTests.swift`, 임시 디렉터리 사용, 대기 대신 `flush()`):
- **골든 v1 테스트**: v1의 5종 레코드가 기대 JSON 문자열과 **정확히** 일치(하위호환 R1의 기계 잠금).
- `access`에 신규 키가 추가돼도 기존 5키의 값이 그대로.
- 신규 4종의 키 집합·타입 검증, `nil` 필드 키 생략.
- 로테이션: 작은 `maxFileSizeBytes`로 N개 기록 → `.1` 파일 생성, 초과분 삭제, 현재 파일이 계속 유효.
- 에러 카운터: 파일을 읽기 전용 디렉터리로 만들거나 핸들을 무효화한 뒤 기록 → `writeFailureCount > 0`, 크래시 없음.
- `flush()` 후 파일 내용이 완전(부분 라인 없음).

### F-6w — 데모 Metrics 탭 (얇음 해소)

**수정**: `Examples/.../MetricsScreen.swift`, `DemoModel.swift`.

지침:
1. `DemoModel`에 `sessionSummaries: [ABSessionSummary]`(싱크 이벤트에서 추출)와 `liveSession: ABSessionSummary?`(`recorder.snapshot(for: player)`), `qoe: ABQoESummary`를 추가. 기존 `statistics` 경로는 유지.
2. 카드 추가: **watch time**, **리버퍼 비율**, **리버퍼 횟수**, **완료율**, **터미널 실패 수**, **dropped frames**, **비트레이트 스위치**, 그리고 TTFF는 `waited.p50`/`waited.p95`(레거시 p50과 나란히 두어 F-4의 차이를 눈으로 보여준다).
3. JSONL 싱크를 로테이션 켠 채 추가하고(파일 경로 표시 + `flush()` 버튼), 멀티 싱크로 in-memory와 병행.
4. 기존 `scheduleStatisticsRefresh()`의 `Task.yield()` 관례를 그대로 재사용(옵저버 호출 순서 비결정성 회피). 새 폴링 타이머를 만들지 않는다.
5. 데모 문구는 새 지표의 **정의**(특히 리버퍼 비율 분모, startup vs rebuffer 구분)를 1~2줄로 설명한다.

테스트: 데모는 테스트 대상이 아니다. 대신 `ABQoESummary.aggregate`가 화면이 쓰는 모든 값을 커버하는지 F-4w 테스트로 보장한다.

---

## 10. 무회귀 가드

### 10.1 기존 테스트 8개는 **한 줄도 수정하지 않는다**

`Tests/ABPlayerKitMetricsTests/ABMetricsTests.swift`는 **수정 금지 파일**이다. 설계가 이를 만족하는 근거:

| 테스트 | 통과 근거 |
|---|---|
| `aggregatesFixedSamples`(:33) | 레거시 `p50/p95/max/hitRate/abandonRate` 의미 불변(결정 5.1). `waited`는 새 필드 |
| `emptyAggregation`(:56) | `init`의 신규 파라미터가 기본값 `.empty`이고 `aggregate([])`도 `.empty` ⇒ `==` 성립 |
| `tokenCancellationDetachesRecorder`(:74) | **T-1**: 토큰 취소·`release()`가 취소 후에 새 이벤트를 만들지 않는다. 취소 전 방출된 v2 이벤트는 `countBeforeCancellation`에 포함되므로 차이가 0 |
| `recordsWaitedTTFFWithResumeTime`(:89) | `contains` 단언. v2 이벤트가 늘어도 무관 |
| `recordsHitForDisplayedFrame`(:110) | **T-2**: 레코더를 attach하지 않은 테스트. `sink.events == [.ttff(…)]` 배열 **완전 일치**를 요구하므로 **`beginTTFF`는 어떤 v2 이벤트도 만들면 안 된다**(결정 1의 "세션은 `.itemAttached`에서만 열린다"가 이 단언에서 나온 요구다) |
| `recordsAbandonedTTFFOnce`(:128) | 동일. `abandonTTFF`도 v2 이벤트를 만들지 않는다 |
| `itemDetachmentAbandonsPendingTTFF`(:146) | ttff 샘플만 `compactMap`으로 추출해 비교 |
| `recordsPreloadOnlyOnUpwardTransition`(:171) | `preloadStarted`만 필터 |

**T-1/T-2를 위반하는 구현은 F-7 게이트에서 REQUEST-CHANGES 대상이다.**

### 10.2 그 밖의 불변식

| # | 불변식 | 근거 |
|---|---|---|
| M-1 | v1의 5종 JSONL 레코드는 같은 입력에 같은 바이트 | 결정 7 R1, 골든 테스트(F-5w) |
| M-2 | 레거시 이벤트의 방출 지점·순서 불변. v2는 항상 **뒤에** | §8.4 |
| M-3 | `ABMetricSample`/`ABMetricEvent` 기존 5케이스의 시그니처 불변 | POLICY additive-only |
| M-4 | 공개 struct의 기존 init 파라미터 순서·기본값 불변, 추가는 뒤에만 | 소스 호환 |
| M-5 | 순수 누적기·폴더에 AVFoundation/ABPlayer 의존 0 | 결정성(§0) |
| M-6 | 어떤 지표 코드도 `player.configuration`을 쓰지 않는다 | 결정 3 |
| M-7 | 싱크는 예외를 밖으로 던지지 않는다. 실패는 카운터+로그 | 결정 7.2 |
| M-8 | `Sources/ABPlayerKit*`(Metrics 제외) 수정 0 | ROADMAP §6 |

### 10.3 CHANGELOG 마이그레이션 노트 (H-2w가 회수)

1. `ABMetricEvent`에 4케이스 추가 — 소비자 `switch`에 `default` 필요(non-exhaustive 관례).
2. `ABAccessSnapshot`/`ABPlaybackStatistics`에 필드 추가 — 기존 필드 값 의미는 불변. `p50/p95/max`는 레거시(`.hit` 0 ms 포함)이며 새 코드는 `waited`를 읽을 것.
3. `ABClock`에 `wallClockEpoch` 요구사항 추가 — 기본 구현 제공으로 기존 준수 타입 무수정.
4. `ABJSONLinesMetricsSink.flush()` public 승격, init에 로테이션 파라미터 추가(기본값 = 현행 동작).
5. `ABMetricsRecorder.endSession(for:)`/`snapshot(for:)` 추가. 토큰 취소 전에 `endSession`을 부르지 않으면 마지막 세션 요약이 나오지 않는다.

---

## 11. 리스크

| # | 리스크 | 등급 | 완화 |
|---|---|---|---|
| R-1 | A-4w의 detach 순서 변경으로 `.itemDetached`의 `access`가 무음으로 `nil`이 된다 | **높음** | 결정 1의 아이템 보유 + F-4w의 "`access != nil`" 회귀 테스트. **F-4w는 v0.4.0 릴리스 전에 반드시 들어가야 한다** — 코어 병합만 되고 F가 빠지면 기존 JSONL 소비자가 필드를 잃는다 |
| R-2 | `bufferingChanged`/`stallEnded`/`durationAvailable`/`itemAttached`/`failureReported`가 A 구현 중 바뀐다 | 중 | §5.5 동결 계약에 의존. 그래도 트리거를 enum(`.buffering`/`.stall`)으로 분리해 뒀으므로 `bufferingChanged`가 늦어져도 스톨 경로만으로 구간이 성립(성능 저하는 있으나 무음 아님) |
| R-3 | 아이템 강한 보유가 누수로 이어짐 | 중 | detach·재attach·`gradeChanged` 방어 경로·`endSession`·레코더 해제의 5중 해제 지점. F-1w에 "detach 후 세션 딕셔너리가 비어 있음" 단언 추가 |
| R-4 | 공개 표면이 한 라운드에 크게 늘어(타입 6종) 유지보수 부담 | 중 | 신규 타입은 전부 값 타입 + 기본값 init. 순수 리듀서는 internal로 감춘다. DocC 토픽 그룹을 "QoE"로 신설해 탐색성 확보 |
| R-5 | 데모 파일이 트랙 G(G-1w 데모 연동)와 충돌 | 낮음 | 병합 순서가 F → G → C이므로 F가 먼저 착지. G 브리프에 "`MetricsScreen.swift`는 F 소유" 전달(§12) |
| R-6 | JSONL 골든 테스트가 플랫폼 부동소수 표기에 취약 | 낮음 | 골든 값은 정수·짧은 소수만 쓰고, 비교는 `JSONSerialization`으로 파싱한 딕셔너리 동등성 + 키 정렬 문자열 1건으로 한정 |
| R-7 | `kindName` 매핑이 코어의 새 에러 케이스를 놓친다 | 낮음 | `default: "unknown"`은 무음이 아니라 명시 버킷. F-3w의 전 케이스 테스트가 추가 시점에 붉어진다 |

---

## 12. 타 트랙 전달 사항

### 트랙 A(코어) — 통지 1건, 확인 요청 2건, 선택 요청 1건

1. **[통지]** A-4w의 `.itemDetached` 순서 변경은 `ABMetricsRecorder.swift:75`(`accessSnapshot(for: player.avPlayerItem)`)를 무음으로 깨뜨린다. F가 아이템 보유로 자체 해결하므로 **코어 수정은 요청하지 않는다.** A-8 게이트에서 "메트릭 access 필드"를 회귀 항목으로 인지만 해 달라.
2. **[확인]** `.itemAttached(source:)` 방송 시점에 `player.avPlayerItem`이 **비-nil**이어야 한다(코어 §3.2 #4의 "`target.attachItem(...)` 직후, 동기"에서 도출). F의 세션 아이템 보유가 이 한 가지에 의존한다.
3. **[확인]** `.itemDetached`는 release/sourceChanged/demotion/backgroundPolicy 전 경로에서 **정확히 1회**(코어 I-6). F의 세션 종료가 이것에 의존한다.
4. **[선택, 비차단]** `ABPlayerError: Hashable` 추가(additive). 있으면 F가 에러 종류별 분포를 딕셔너리로 집계할 수 있다. 없으면 `ABErrorOrigin`(이미 `Hashable`) 기준 집계로 진행한다 — **없어도 설계는 닫힌다.**

### 트랙 C(Controls)

- `periodicTimeInterval` 리스는 **Controls 단독 소유**로 유지된다. F는 그 값을 읽지도 쓰지도 않는다(결정 3). C-0이 리스 정책을 바꿔도 F에 영향 없음.

### 트랙 G(NowPlaying/PiP)

- `Examples/.../MetricsScreen.swift`와 `DemoModel.swift`의 **메트릭 관련 프로퍼티/메서드는 F 소유**다. G-1w의 데모 연동은 별도 프로퍼티로 추가하고, 병합 순서(F → G)에 따라 G가 리베이스한다.

### 트랙 CI

- 신규 테스트는 전부 순수·동기(대기 없음)라 TSan 잡(CI-2)에 그대로 추가 가능하다. `ABTestSupport`(CI-4)의 `ABWaitUntil`은 F가 쓰지 않는다.

### 트랙 H(문서)

- §10.3의 마이그레이션 노트 5건과 DocC 토픽 그룹 "QoE" 신설이 H-2w의 회수 대상이다.

---

## 13. 명시적 비범위 (F-7 게이트에서 위반 시 REQUEST-CHANGES)

- 하트비트/주기 타이머, 백그라운드 업로드 싱크, 네트워크 전송
- 콘텐츠 시간(배속 반영) 누적, 시청 구간 커버리지(유니크 포지션) 계산
- `ABPlayerError`/`ABPlayerEvent` 등 코어 표면 수정, `Sources/ABPlayerKit*`(Metrics 외) 수정
- `ABMetricEvent` 기존 케이스 변경·삭제, JSONL 기존 키 이름/타입 변경
- `ABPlaybackStatistics.p50/p95/max` 의미 변경
- 지표의 표본 추출(sampling)·상한(cap)·개인정보 해싱 정책 — 소비자 몫으로 남기고 DocC에 그렇게 적는다
- 데모의 차트/그래프 시각화(카드 + 수치까지)
