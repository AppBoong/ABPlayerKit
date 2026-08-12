# DESIGN: 라운드6 트랙 A — 코어 엔진 신뢰성 + 관찰성 (A-0 설계 게이트)

기준 커밋 995bb6d. 입력: `ROADMAP-round6.md` §2 트랙 A, `REVIEW-round6-portfolio-audit.md` §A·§B, `docs/POLICY-api-stability.md`, 실소스 `Sources/ABPlayerKit/`.
산출 목적: (1) 트랙 A 구현 브리프(A-1w~A-7w)가 그대로 인용할 결정, (2) **Wave 2 트랙 C/F/G 설계의 입력이 되는 확정 이벤트 표면**.

이 문서에서 "확정"으로 표기된 시그니처는 Wave 2 설계가 의존해도 되는 계약이다. 변경이 필요하면 A-8 게이트에서 본 문서를 개정하고 C-0/F-0에 통지한다.

---

## 0. 전역 제약 (모든 결정에 선행)

| 제약 | 내용 | 근거 |
|---|---|---|
| additive-only | `ABPlayerEvent`/`ABPlayerError`는 **케이스 추가만**. 기존 케이스에 연관값 추가·이름 변경·삭제 금지 | `POLICY-api-stability.md` "Adding `enum` cases", `ABPlayerEvent.swift:23-26` |
| deprecated 금지(이번 라운드) | 신규 대체 심볼이 생겨도 기존 심볼에 `@available(*, deprecated)`를 붙이지 않는다. 라이브러리 내부가 그 심볼을 계속 방송하므로 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 하에서 자기 경고가 발생 | `POLICY-api-stability.md` §"Worked example" 마지막 항목과 동일한 논리 |
| Sendable 유지 | 신규 공개 값 타입은 전부 `Sendable, Equatable`. `NSError`/`AVFoundation` 객체를 공개 페이로드에 넣지 않는다(문자열·Int로 환원) | `ABPlayerError.swift:11`, `ABAVPlaybackTarget.swift:396-401` |
| 관찰 이중 체계 유지 | `@Observable` 프로퍼티(단순 값 읽기)와 `ABPlayerEvent`(이산 사건·이유·UIKit 소비자)는 **병렬 체계이며 서로를 대체하지 않는다** | `ABPlayer.swift:9-18` (Q3/Q7) |
| 관찰 대상 프로퍼티에 `@ObservationIgnored` 금지 | 반대로, `deinit`에서 읽히는 것(`prerollTask`/`seekWorkerTask`)에는 **반드시** 유지 | `ABPlayer.swift:59-68` (WP9.2 함정) |
| 동작 변경 시 마이그레이션 노트 | 시그니처가 같아도 관찰 가능한 출력이 바뀌면 CHANGELOG에 Migration 한 줄 | `POLICY-api-stability.md` "Behavior changes" |

---

## 결정 1 — 에러 모델: `(domain, code)` 캐리 방식

### 선택안: `ABPlayerError`는 **불변**, 프로비넌스를 담는 병행 값 타입 2종 + 신규 이벤트 1종 + 프로퍼티 채널 분리

```swift
// Model/ABPlayerError.swift (동일 파일에 추가)

/// 실패를 일으킨 하위 시스템의 원본 식별자. `NSError`의 (domain, code)를
/// 문자열·정수로 환원해 Sendable/Equatable을 유지한다.
public struct ABErrorOrigin: Sendable, Equatable, Hashable {
    public let domain: String
    public let code: Int
    public init(domain: String, code: Int)
}

/// 실패의 종류(`kind`)와 출처(`origin`)를 함께 나르는 값.
/// `ABPlayerError`는 종류 분류 체계로 그대로 두고, 이 타입이 프로비넌스를 더한다.
public struct ABPlayerFailure: Sendable, Equatable {
    public let kind: ABPlayerError
    public let origin: ABErrorOrigin?
    public var isTerminal: Bool { kind.isTerminal }
    public init(kind: ABPlayerError, origin: ABErrorOrigin? = nil)
}

extension ABPlayerError {
    /// `.itemErrorLogEntry`만 비종료(진단) — 나머지는 종료성 실패.
    public var isTerminal: Bool { get }
}
```

공개 표면 변화:

| 심볼 | 이전 | 이후 |
|---|---|---|
| `ABPlayer.lastError` | `public private(set) var lastError: ABPlayerError?` (저장) | `public var lastError: ABPlayerError? { lastFailure?.kind }` (계산, **종료성 실패만**) |
| `ABPlayer.lastFailure` | — | `public private(set) var lastFailure: ABPlayerFailure?` (저장, @Observable 추적) |
| `ABPlayer.lastDiagnostic` | — | `public private(set) var lastDiagnostic: ABPlayerFailure?` (저장, 비종료 `.itemErrorLogEntry` 전용) |
| `ABPlayerEvent.failed(ABPlayerError)` | 유지 | 유지(레거시 채널, 계속 방송) |
| `ABPlayerEvent.failureReported(ABPlayerFailure)` | — | 신규. `.failed` **직후** 같은 지점에서 방송 |

`lastError`를 계산 프로퍼티로 강등해도 Observation은 유지된다 — 계산 프로퍼티가 추적 대상 저장 프로퍼티(`lastFailure`)를 읽으므로 `withObservationTracking { _ = player.lastError }`가 그대로 발화한다. 이는 `ABPlayerObservationTests.swift:107-126`이 그대로 통과해야 하는 근거이며, 동시에 `ABPlayerObservationTests.swift:128-150`(비추적 계산 프로퍼티 `avPlayer`는 발화하지 않아야 함)과 모순되지 않는다 — 후자는 **비관찰 객체**를 읽기 때문에 발화하지 않는 것이지, 계산 프로퍼티라서가 아니다.

### 내부 seam 변경 (`ABTargetEvent`)

`ABPlaybackTarget.swift:12`의 `case failed(ABPlayerError)` → `case failed(ABPlayerFailure)`로 **교체**한다(내부 타입이므로 정책 대상 아님). 병행 케이스를 두지 않는 이유는 타깃→플레이어 실패 경로가 둘로 갈라지면 `lastFailure`/`lastDiagnostic` 라우팅이 두 곳에 생기기 때문이다. 대가는 테스트 기계적 수정 2파일(§5 무회귀 가드 참조).

`origin` 채집 지점(전부 `ABAVPlaybackTarget.swift`):

| 지점 | origin 소스 |
|---|---|
| `:348-350` 상태 KVO의 `.failed` 분기 | `item.error as NSError` → `(domain, code)` |
| `:402-416` `AVPlayerItemFailedToPlayToEndTime` | `userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError` → 없으면 `item.error as NSError` |
| `:418-430` `AVPlayerItemNewErrorLogEntry` | `AVPlayerItemErrorLogEvent.errorDomain` + `.errorStatusCode` (이미 `:196-202`에서 문자열화 중 — 값도 함께 뽑는다) |
| `ABPlayer.swift:830-836` 오디오 세션 실패 | `(error as NSError)` → `(domain, code)` |
| `ABPlayer.swift:552-560` preroll 타임아웃/실패 | `origin = nil` (AVFoundation 에러가 아님) |

기존 `describe(errorLogEvent:)`(`:196-202`)의 문자열 포맷은 **바꾸지 않는다** — `ABAVPlaybackTargetErrorEventsTests`가 그 문자열을 검증한다.

### 기각안

| 기각안 | 사유 |
|---|---|
| `case itemFailed(description:domain:code:)` — 기존 케이스에 연관값 추가 | breaking. `.itemFailed(description:)` 생성·패턴 매치·`==` 비교가 전부 깨진다. POLICY 정면 위반 |
| 케이스 미러링(`itemFailedWithOrigin`, `itemErrorLogEntryWithOrigin`, …) | NSError 기반 케이스 수만큼(현재 4종) 케이스가 늘고, 앞으로 추가되는 모든 에러 종류가 2배로 증식. 소비자 `switch`가 영구 이중화 |
| `lastErrorOrigin: ABErrorOrigin?` 프로퍼티만 추가 | 이벤트 스트림에서 domain/code에 접근 불가 → F-3w(에러율 집계)가 이벤트 수신 후 프로퍼티를 되읽어야 하고, 그 사이 다음 실패가 덮어쓰면 오귀속. 이벤트에 실려야 한다 |
| `ABPlayerError`를 `struct` + `LocalizedError`로 재설계 | 전면 breaking. non-exhaustive enum 관례(`ABPlayerError.swift:7-9`)와 기존 소비자 `switch`를 전부 파괴 |
| `.failed`를 폐기하고 `.failureReported`만 방송 | 기존 소비자(`ABMetricsRecorder`, `ABControlsPresenter.swift:205`, 데모) 무음 회귀 |

### 이중 방송의 명시적 대가

한 번의 실패가 `.failed`와 `.failureReported` 두 이벤트를 낸다. 전 이벤트를 로깅하는 소비자에겐 중복으로 보인다. 이는 additive-only 계약의 필연적 비용이며, 두 케이스의 DocC에 "짝을 이루어 방송된다. 새 코드는 `.failureReported`만 소비하라"를 명시한다. 1.0.0에서 `.failed` 제거가 정식 경로다(POLICY "Removal timing").

---

## 결정 2 — 관찰성: `isPlaying`/`duration`/`isBuffering`의 저장 프로퍼티 전환

### 핵심 원리: "재계산 미러(recompute-from-target)"

세 프로퍼티 모두 **의미를 새로 정의하지 않는다.** 저장 프로퍼티로 바꾸되, 값의 출처는 언제나 `target`을 그 자리에서 다시 읽은 결과다. 이렇게 하면 의미 드리프트가 원천적으로 0이 된다.

```swift
// ABPlayer.swift
public private(set) var isPlaying = false          // 이전: { target.isPlaying }  (:40)
public private(set) var duration: CMTime?          // 이전: { target.duration }   (:44)
public private(set) var isBuffering = false        // 신규
public private(set) var pendingSeekTime: CMTime?   // 신규 (결정 4)

/// 미러 3종을 target에서 다시 읽어 반영하고, 실제로 값이 바뀐 것만 방송한다.
/// 값이 같으면 대입 자체를 생략한다 — @Observable은 동일 값 대입에도
/// `withMutation`을 돌려 SwiftUI 무효화를 유발하기 때문이다.
private func refreshPlaybackMirrors()
```

### 갱신 시점 (이 목록이 계약이다)

| 트리거 | 동기/비동기 | 비고 |
|---|---|---|
| `play()` / `pause()` 직후 (`:283`, `:291`) | **동기** | 필수. §5의 Controls 불변식 참조 |
| `target.play()`/`target.pause()` 직접 호출 지점 전부 (`:656`, `:661`, `:750`, `:775`, `interpret`의 `.pause`) | **동기** | A-2w가 `:683`/`:689`를 `self.play()`로 옮긴 뒤에도 남는 지점들 |
| `setRate` / `applyConfigurationChange`의 rate·mute 반영 (`:582-591`) | 동기 | |
| 그레이드 전이 종료 시(`set(source:grade:)` 말미) | 동기 | attach/detach 후 duration·buffering 재평가 |
| `.timeControlStatusChanged` 타깃 이벤트 (`:473`) | 비동기(KVO hop) | `ABAVPlaybackTarget.swift:433-444` |
| `.itemStatusChanged` (`:467`) | 비동기(KVO hop) | |
| 신규 `.durationChanged` / `.bufferStateChanged` 타깃 이벤트 | 비동기(KVO hop) | 아래 KVO 소스 표 |
| `.playedToEnd` (`:471`) | 비동기 | `desiresPlayback = false` 후 재평가 |

### KVO 소스 선정 (B-2)

`ABAVPlaybackTarget.observeItem(_:)`(`:337-447`)에 추가 등록. 모든 신규 관찰은 기존 관례를 따른다 — `observations.add { … invalidate() }`로 수명 결속, `Task { @MainActor in }` hop, hop 후 `self.avPlayerItem === item` stale 가드(`:412`, `:423`의 패턴).

| KVO 대상 | 옵션 | 용도 |
|---|---|---|
| `AVPlayerItem.isPlaybackLikelyToKeepUp` | `[.initial, .new]` | 버퍼링 판정 주 신호 |
| `AVPlayerItem.isPlaybackBufferEmpty` | `[.initial, .new]` | `automaticallyWaitsToMinimizeStalling == false` 튜닝에서의 스톨 판정 |
| `AVPlayerItem.duration` | `[.initial, .new]` | `durationAvailable` 이벤트 + `duration` 미러 |
| `AVPlayerItem.presentationSize` | `[.initial, .new]` | `presentationSizeChanged` 이벤트 (B-4, `ABPlayerView.swift:99-109` 폴링 제거) |
| `AVPlayer.reasonForWaitingToPlay` | `[.new]` | `.noItemToPlay` 억제 전용. **스피너 판정을 이것만으로 하지 않는다**(B-2) |
| `AVPlayer.timeControlStatus` | 기존 `[.new]` 유지 | |

`isPlaybackBufferFull`은 관찰하지 않는다 — 판정에 기여하지 않고 이벤트 소음만 늘린다.

### 버퍼링 판정: 순수 평가기

`ABAVPlaybackTarget`은 원시 신호만 노출하고, 판정은 `AVFoundation` 의존이 없는 순수 함수가 한다(`ABGradePlanner` 스타일 — 시뮬레이터 없이 표 테스트 가능).

```swift
// StateMachine/ABBufferingEvaluator.swift (신규, internal)
struct ABBufferingEvaluator {
    static func isBuffering(
        hasItem: Bool,
        intendsToPlay: Bool,            // ABPlayer.desiresPlayback
        timeControlStatus: ABTimeControlStatus,
        isWaitingWithNoItem: Bool,      // reasonForWaitingToPlay == .noItemToPlay
        isPlaybackLikelyToKeepUp: Bool,
        isPlaybackBufferEmpty: Bool
    ) -> Bool {
        guard hasItem, intendsToPlay, !isWaitingWithNoItem else { return false }
        switch timeControlStatus {
        case .playing:      return false                                       // 프레임이 진행 중이면 버퍼링이 아니다
        case .waitingToPlay: return true
        case .paused:       return isPlaybackBufferEmpty || !isPlaybackLikelyToKeepUp
        }
    }
}
```

- `.paused` 분기가 필요한 이유: `automaticallyWaitsToMinimizeStalling == false`(튜닝 가능, `ABPlaybackTuning.swift:15`)면 스톨 시 `rate`가 0으로 떨어져 `.paused`가 된다. 이 경우 `.waitingToPlay`가 오지 않는다.
- `intendsToPlay`(`ABPlayer.desiresPlayback`, `@ObservationIgnored`)는 "사용자가 재생을 원하는 상태인가"다. `play()`에서 true, `pause()`/`playedToEnd`/`.current` 이탈/배경 정책 pause/인터럽션 pause에서 false. **`target.isPlaying`으로 대체 불가** — 위 `.paused` 케이스에서 rate가 0이라 의도가 소실된다.
- 히스테리시스/디바운스는 넣지 않는다. `bufferingChanged`는 값이 실제로 바뀔 때만 방송하므로 중복은 없고, 타이머 도입은 테스트 결정성을 해친다(sleep 금지 규약).

### `duration` 미러의 의미 보존

현재 `target.duration`은 `avPlayerItem?.duration`(`ABAVPlaybackTarget.swift:38-40`)이며 라이브에서 `kCMTimeIndefinite`를 그대로 낸다. 미러도 **정규화하지 않고 그대로** 담는다. 정규화는 지금처럼 `ABPlaybackTime.init`(`ABPlaybackTime.swift:36-41`)이 담당한다. `durationAvailable` 이벤트만 정규화된 유한 값에서 발화한다.

### @Observable 매크로 상호작용 함정 (WP9.2류) 검토

| 함정 | 신규 미러에서의 판정 |
|---|---|
| 매크로가 저장 프로퍼티를 계산 프로퍼티로 재작성 → `nonisolated` 접근 불가 (`ABPlayer.swift:59-68`) | **안전**. 미러 3종은 `@MainActor`에서만 접근하며 `deinit`에서 읽지 않는다. 따라서 `@ObservationIgnored`를 붙이면 **안 된다**(붙이면 SwiftUI가 갱신되지 않아 목적 자체가 소실) |
| 동일 값 재대입도 `withMutation`을 유발 | `refreshPlaybackMirrors()`에서 값 비교 후에만 대입. 미준수 시 periodic tick마다 SwiftUI 전체 무효화 |
| `didSet`과 매크로 확장의 상호작용 (`configuration`이 유일 사례, `ABPlayerObservationTests.swift:93-104`) | 미러에는 `didSet`을 두지 않는다. 부수효과는 전부 `refreshPlaybackMirrors()` 본문에 명시적으로 |
| 관찰 콜백 재진입 | 미러 갱신 → 이벤트 방송 순서를 고정(먼저 대입, 다음 방송). 방송 핸들러가 다시 플레이어를 만져도 값은 이미 확정 상태 |

### 기각안

| 기각안 | 사유 |
|---|---|
| 계산 프로퍼티 유지 + `ObservationRegistrar` 수동 호출 | 매크로 생성 저장소는 private. 공식 API 없음 |
| Controls 측 미러 유지(현상 유지) | B-1이 지적한 워크어라운드의 존속. `ABControlsPresenter.swift:73`·`ABPlayerControlsView.swift:54-55`의 3중 미러가 D-9로 그대로 남는다 |
| periodic tick으로 미러 폴링 | `periodicTimeInterval`이 기본 `nil`(`ABPlayerConfiguration.swift:46`)이라 대부분의 소비자에게 아예 동작하지 않는다 |
| `isBuffering`을 `.waitingToPlay`만으로 유도 | B-2가 명시 기각. 레이트 평가 대기(`.evaluatingBufferingRate`)와 실제 리버퍼가 구분되지 않고, `automaticallyWaits == false` 경로를 놓친다 |
| `isBuffering` 판정을 `ABAVPlaybackTarget` 안에 두기 | 시뮬레이터 없이 테스트 불가. 순수 평가기로 빼면 표 테스트로 전 조합 커버 |

---

## 결정 3 — 확정 이벤트 표면 (Wave 2 소비 계약)

### 3.1 신규 공개 타입

```swift
// Observation/ABPlayerEvent.swift
/// 어떤 호출이 `grade != .current` 때문에 무시됐는지 식별한다.
public enum ABRejectedCall: Sendable, Equatable {
    case play
    case pause
    case seek
    case skip
    case beginScrubbing
    case scrub
    case endScrubbing
}
```

### 3.2 확정 케이스 목록 (전부 additive)

| # | 케이스 시그니처 | 방송 시점 | 스레딩/전달 | 중복 억제 | 주 소비자 |
|---|---|---|---|---|---|
| 1 | `case bufferingChanged(Bool)` | `refreshPlaybackMirrors()`에서 `isBuffering` 값이 실제로 바뀐 직후 | MainActor. KVO 유래는 **비동기**(다음 런루프), 명령 유래(`play()`/`pause()`)는 **동기** | 값 변화 시에만 | C-1w(스피너), F-1w(리버퍼 구간) |
| 2 | `case durationAvailable(CMTime)` | 아이템의 유한 duration(`isNumeric && seconds > 0`)이 처음 확정되거나 **다른 유한 값으로 바뀔 때** | 비동기(duration KVO hop) | 직전 방송값과 다를 때만. 아이템 detach 시 내부 기억값 리셋 | C(스크러버), F |
| 3 | `case stallEnded` | 미종결 `.playbackStalled` 이후 `timeControlStatus == .playing` 도달 시 **1회** | 비동기(timeControlStatus KVO hop) | 미종결 스톨이 있을 때만 | F-1w |
| 4 | `case itemAttached(source: ABMediaSource)` | `target.attachItem(...)` 직후, 같은 액션의 `.tuningApplied` **이전** (`ABPlayer.swift:500-511`) | **동기**(`set(source:grade:)` 호출 스택) | 매 attach 1회 | F, G |
| 5 | `case presentationSizeChanged(CGSize)` | `presentationSize` KVO. `.zero`는 방송하지 않음 | 비동기(KVO hop) | 값 변화 시에만 | `ABPlayerView`(A-6w 내부 소비), G-2w(PiP) |
| 6 | `case mutedChanged(Bool)` | `applyConfigurationChange`가 `target.setMuted`를 호출한 직후 (`ABPlayer.swift:582-584`) | 동기 | 값 변화 시에만 | C |
| 7 | `case callRejected(ABRejectedCall, grade: ABPlaybackGrade)` | 기존 `.playbackRejected` **직후**, 같은 지점 | 동기 | 없음(호출당 1회) | C(왜 아무 일도 안 일어났는지), 데모 |
| 8 | `case failureReported(ABPlayerFailure)` | 기존 `.failed(_)` **직후**, 같은 지점 | `.failed`와 동일 | 없음 | F-3w |
| 9 | `case seekTargetChanged(CMTime?)` | `pendingSeekTime`이 바뀔 때(요청 시 값, 정착 시 `nil`). **스크럽 세션 중에는 방송하지 않음** | 동기 | 값 변화 시에만 | C-2w(누적 skip 표시) |

기존 케이스는 하나도 바뀌지 않는다(`ABPlayerEvent.swift:27-72` 전부 그대로).

### 3.3 순서 계약 (Wave 2가 의존해도 되는 것)

- attach: `.itemAttached(source:)` → `.tuningApplied` → (이후 비동기) `.itemStatusChanged` / `.durationAvailable` / `.presentationSizeChanged`
- detach(A-4w 수정 후): `target.detachItem()` → `.itemDetached(reason:)`. **즉, 이벤트 수신 시점에 `player.avPlayerItem`은 이미 `nil`이다.** `ABPlayerView.swift:74-88`은 이 순서에 의존하도록 바뀐다
- 실패: `.failed(kind)` → `.failureReported(failure)`
- 거부: `.playbackRejected` → `.callRejected(call, grade:)`
- 스톨 1주기: `.playbackStalled` → (버퍼링 미러가 참이면) `.bufferingChanged(true)` → … → `.bufferingChanged(false)` → `.stallEnded`
- 스크럽 종료: `.seekCompleted` → `.scrubbingChanged(isScrubbing: false)` → `.periodicTime` (기존 계약, `ABPlayer.swift:395-402` 유지. `ABPeriodicTimeEngineTests.swift:59`가 고정)

### 3.4 F 트랙(F-0)에 주는 명시적 지침

- **리버퍼 구간의 1차 소스는 `.playbackStalled`가 아니라 `bufferingChanged(true/false)` 쌍이다.** `AVPlayerItemPlaybackStalled`는 `automaticallyWaitsToMinimizeStalling == true`(기본값, `ABPlaybackTuning.swift:15`)에서 발생하지 않는 경우가 흔하다.
- `stallEnded`는 `.playbackStalled`와만 짝을 이룬다. **아이템이 detach되거나 release되면 미종결 스톨은 조용히 폐기되며 `stallEnded`는 오지 않는다** — 미종결 세션 처리(F-1w)는 F 측 책임이다. 코어는 `.itemDetached`가 그 경계 신호임을 보장한다.
- 에러율(F-3w)은 `.failureReported(ABPlayerFailure)`를 쓴다. `failure.origin?.domain`/`.code`로 `NSURLErrorDomain -1009`(재시도 가능)와 `AVFoundationErrorDomain -11829`(포기)를 구분한다. `failure.isTerminal == false`(진단 로그)는 에러율 분자에서 제외한다.

### 3.5 C 트랙(C-0)에 주는 명시적 지침

- 스피너는 `bufferingChanged` 또는 `player.isBuffering`으로 그린다. `.waitingToPlay` 추론 금지.
- 아이콘 역전(D-2)의 해소 축은 `player.isPlaying`(의미 불변) + `player.isBuffering`의 **조합**이다. `isPlaying == true && isBuffering == true`가 "재생을 원하지만 멈춰 있음"이다.
- 누적 skip 표시(C-2w)는 `seekTargetChanged`/`player.pendingSeekTime`을 읽는다. Controls가 자체 누적기를 두지 않는다.
- `player.isPlaying`은 **명령 직후 동기적으로 참**이다(§5 불변식). `ABControlsPresenter.swift:113-131`의 MJ-3 근거는 그대로 유효하다.

---

## 결정 4 — 시크 통일 + skip 누적 시맨틱

### 현재 4개 진입점

| # | 진입점 | 코얼레서 | 세대 가드 | duration 클램프 | 비고 |
|---|---|---|---|---|---|
| 1 | `seek(to:tolerance:)` `ABPlayer.swift:305-312` | ✗ | ✗ | ✗ | 직접 `await target.seek` |
| 2 | `skip(by:)` `:315-340` | 세션 중에만(간접) | ✗ | ✓ | 라이브 상한 없음(의도) |
| 3 | `scrub(to:)` 세션 밖 `:362-369` | ✗ | ✗ | ✗ | **호출당 무제한 `Task` 생성** |
| 4 | `.seekToStart` 액션 `:522-523` | ✗ | ✗ | — | `.seekCompleted` 미방송 |

(+ 준-5번: `endScrubbing()`의 standalone commit `:389-391` — 코얼레서 밖이며 await 후 세대 재검증 없음)

### 선택안: 단일 내부 게이트 `enqueueSeek`

```swift
// ABPlayer.swift (private)
/// 모든 시크의 유일한 통로. 그레이드 검사를 하지 않는다 —
/// 공개 진입점이 자신의 거부 이벤트를 먼저 낸 뒤 호출하고,
/// 플래너 유래 시크(.seekToStart)는 그레이드 전이 도중 호출되기 때문이다.
@discardableResult
private func enqueueSeek(to time: CMTime, tolerance: ABSeekTolerance) -> Bool

/// 0...duration으로 클램프. duration이 없거나 비유한이면 하한만 적용.
private func clampToPlayableRange(_ time: CMTime) -> CMTime

/// 현재 세대의 시크 워커가 모두 정착할 때까지 대기.
private func awaitSeekSettled(generation: Int) async
```

- `enqueueSeek`은 `clampToPlayableRange` → `seekCoalescer.request` → `startSeekWorker`만 한다. 세대 가드는 기존 워커(`:846-857`)가 이미 갖고 있으므로 **모든 진입점이 자동으로 세대 보호를 받는다**.
- `ABSeekCoalescer`(`StateMachine/ABSeekCoalescer.swift`)는 **한 줄도 바꾸지 않는다**. `ABSeekCoalescerTests.swift`(74줄) 무수정 통과가 이 결정의 검증 조건이다.
- `awaitSeekSettled`는 `Task`가 `Equatable`인 점을 이용해 자신이 기다린 워커가 여전히 현재 워커일 때만 `seekWorkerTask = nil`로 정리한다.

### 진입점별 재배선 (await 시맨틱 보존이 핵심)

| 진입점 | 재배선 후 |
|---|---|
| `seek(to:tolerance:)` | 그레이드 거부 → `enqueueSeek(clamped, tolerance)` → `await awaitSeekSettled(...)`. **duration 클램프가 새로 생긴다**(A-7 지적) |
| `skip(by:)` 비스크럽 | 기준점을 `pendingSeekTime ?? currentTime`으로 바꾼 뒤 기존 클램프 로직 유지 → `enqueueSeek` → `await awaitSeekSettled(...)` |
| `skip(by:)` 스크럽 중 | **현행 유지: await하지 않는다.** `scrub(to:)`로 위임 |
| `scrub(to:)` 세션 밖 | per-call `Task` 제거 → `enqueueSeek(to: time, tolerance: configuration.scrubTolerance)`, await 없음 |
| `scrub(to:)` 세션 중 | 현행 유지(`:371-373`) + `pendingSeekTime`은 갱신하지 않음 |
| `.seekToStart` 액션 | `Task { await target.seekToStart() }` 제거 → `enqueueSeek(to: .zero, tolerance: .precise)`. `target.seekToStart()`는 프로토콜에 남긴다(A-1w의 루프 재시작이 타깃 내부에서 계속 사용) |
| `endScrubbing()` standalone commit | 로직 구조는 그대로 두고, `await` 전후로 `seekGeneration`을 캡처·재검증한 뒤에만 `.seekCompleted`를 방송하는 가드만 추가 |

**`skip(by:)`가 스크럽 중 await하지 않아야 하는 이유는 강제 제약이다.** `ABScrubbingEngineTests.swift:136-153`("Given rapid skips during scrubbing, they share the seek coalescer")은 `waitsForSeekContinuation = true` 상태에서 `await player.skip(by: 5)`를 5회 호출한 뒤에야 `completeNextSeek()`을 부른다. skip이 정착을 기다리면 이 테스트는 영구 교착한다.

### skip 누적 시맨틱 (D-1의 코어 절반)

```swift
public private(set) var pendingSeekTime: CMTime?   // @Observable 추적
```

- 세팅: `enqueueSeek`이 `!isScrubbing`일 때 목적지로 설정하고 `seekTargetChanged(time)` 방송.
- 해제: 시크 워커가 정착했고 코얼레서에 `inFlight`/`pending`이 모두 없을 때 `nil` + `seekTargetChanged(nil)`.
- 무효화: `resetSeeking()`(`:859-868`) — 세대 증가와 함께 `nil`.
- 스크럽 세션 중에는 갱신하지 않는다(시크바가 위치의 주인).

`skip(by:)`의 기준점:

```
base = pendingSeekTime ?? currentTime      // 이 한 줄이 누적을 만든다
proposed = max(0, base + interval)
destination = duration이 유한하면 min(proposed, duration) else proposed
```

+20을 두 번 빠르게 누르면 20 → 40이 된다. AVPlayer의 in-flight seek 취소와 무관하다 — 누적이 엔진 상태(`pendingSeekTime`)에서 일어나기 때문이다. 기존 단발 skip 테스트(`ABSkipEngineTests.swift:26-69`)는 `pendingSeekTime`이 `nil`이므로 `currentTime` 기준으로 동일하게 동작한다.

### 기각안

| 기각안 | 사유 |
|---|---|
| 4개 진입점을 전부 await로 통일 | 위 교착. 스크럽 중 skip은 fire-and-forget이어야 한다 |
| 누적을 Controls 측(D-1)에서 처리 | 엔진 밖 상태 이중화. `ABPlayer`를 직접 쓰는 소비자(데모·SwiftUI)에는 여전히 비누적. B-1이 지적한 미러 패턴의 반복 |
| `ABSeekCoalescer`에 "요청 출처" 필드를 추가해 방송 억제 | 코얼레서와 그 테스트를 건드린다. 얻는 것은 `.seekToStart`의 `.seekCompleted` 억제뿐 — 그건 아래처럼 그냥 허용하는 편이 낫다 |
| `AVPlayer.seek(to:completionHandler:)` 직접 다중 발행 | 취소 시맨틱을 다시 손으로 다루게 됨. 코얼레서(강점 목록에 등재)의 존재 이유를 부정 |

### 관찰 가능한 동작 변화 (CHANGELOG Migration 필요)

1. `seek(to:)`가 duration을 넘는 시간을 클램프한다(이전: 그대로 전달).
2. `rewindOnDemotion == true`(기본 `false`)일 때 `.seekCompleted(to: .zero)`가 새로 방송된다.
3. 세션 밖 `scrub(to:)` 연타가 코얼레싱된다(이전: 호출 수만큼 시크).
4. 연속 skip이 누적된다.

---

## 결정 5 — `ABPlayer` 분해 범위

### 이번 라운드에서 추출하는 것 (2개, `ABGradePlanner` 스타일의 순수 값 타입)

**(1) `Policy/ABBackgroundPolicyMachine.swift`** — `AVFoundation`/`UIKit` 의존 없음.

```swift
enum ABAppLifecycleSignal: Equatable { case willResignActive, didEnterBackground, willEnterForeground }

enum ABBackgroundAction: Equatable {
    case capturePlaying          // wasPlayingBeforeBackground = isPlaying
    case pause
    case setLayerAttachment(Bool)
    case demoteToInstance
    case restoreCapturedGrade
    case resumePlay              // self.play() 경유 (A-2 수정의 핵심)
    case markAudioSessionDirty
    case clearCapture
}

struct ABBackgroundPolicyMachine: Sendable {
    func actions(
        for signal: ABAppLifecycleSignal,
        policy: ABBackgroundPolicy,
        grade: ABPlaybackGrade,
        wasPlayingBeforeBackground: Bool,
        hasCapturedGrade: Bool
    ) -> [ABBackgroundAction]
}
```

`ABPlayer`는 `handleWillResignActive`/`handleDidEnterBackground`/`handleWillEnterForeground`에서 이 리듀서를 호출하고 액션만 해석한다(현재 `:649-698`의 switch를 대체). `.resumePlay`는 반드시 `self.play()`로 해석한다 — A-2의 근본 원인이 `:683`/`:689`의 `target.play()` 직접 호출이기 때문이다.

**(2) `Policy/ABAudioSessionGate.swift`** — 현재 `audioSessionActivationDirty`(`:116-135`, `:803-814`)에 흩어진 M1/N1/MJ-1 규칙의 순수 리듀서.

```swift
enum ABAudioSessionTrigger: Equatable {
    case playbackStart, gradePromotion, policyChanged, interruptionBegan, willEnterForeground, release
}

enum ABAudioSessionDecision: Equatable { case apply, skip, restore }

struct ABAudioSessionGate: Sendable {
    /// 순수. 결정과 다음 dirty 상태를 함께 돌려준다.
    func decide(
        trigger: ABAudioSessionTrigger,
        policy: ABAudioSessionPolicy,
        grade: ABPlaybackGrade,
        isDirty: Bool
    ) -> (decision: ABAudioSessionDecision, isDirtyAfter: Bool)
}
```

이 추출의 실익은 주석 20줄(`:116-135`)로만 존재하던 규칙이 표 테스트로 고정된다는 것이며, H-1w(주석 정리)의 사전 작업이기도 하다.

### 명시적 비범위 (A-8 게이트에서 위반 시 REQUEST-CHANGES)

- `ABPlayer`의 엔진/정책/관찰 3분할, `ABAVPlaybackTarget`의 분할
- 시크/스크럽 상태를 별도 머신으로 추출(코얼레서 + 세대 가드로 충분)
- `ABGradePlanner`/`ABSeekCoalescer`/`ABObservationBag`/`PeriodicObserverBox` 수정 (감사 "강점" 목록)
- `ABPlayerConfiguration`의 재구성(프로퍼티 추가는 A-7w 범위 내에서 허용)

---

## 4. WP별 구현 지침 (A-1w ~ A-7w)

각 WP는 독립 커밋 단위. 전 WP 공통: Swift 6 zero-warning, 새 시뮬레이터 부팅 금지, `sleep` 금지(`Support/ABWaitUntil.swift` 사용), 커밋 금지, 새 주석에 내부 리뷰 ID 인용 금지(불변식만 서술).

### A-1w — 루프가 재생을 재개하지 않음 (A-1)

**위치**: `ABAVPlaybackTarget.swift:122-124`(`setLooping`), `:355-368`(`didPlayToEnd` 관찰), `:142-144`(`seekToStart`).
**지침**:
1. `setLooping(_:)`이 `avPlayer?.actionAtItemEnd`를 함께 설정한다 — 루프면 `.none`, 아니면 `.pause`. `makePlayer()`/`attachItem` 이후에도 유지되도록 attach 경로에서 재적용(`ABPlayer.swift:510`이 이미 attach마다 `setLooping`을 호출하므로 그 경로로 충족된다).
2. `didPlayToEnd` 핸들러: `onEvent?(.playedToEnd)`를 **먼저** 방송하고, `isLooping`이면 `await seekToStart()` 후 `avPlayer.rate = desiredRate`(또는 A-7w 적용 후 `avPlayer.play()`)로 재생을 재개한다.
3. 루프 재시작 시 `.seekCompleted`는 방송하지 않는다(타깃 내부 동작이며 `ABPlayer`의 시크 경로가 아니다). 대신 `.playedToEnd` 뒤 정상 `timeControlStatus` KVO가 재생 재개를 알린다.

**기각**: `AVPlayerLooper` + `AVQueuePlayer` 전환 — `ABPlaybackTarget` 전 표면과 레이어 바인딩(`ABPlayerView.swift:91-97`)에 파급. 회귀 리스크가 이득을 초과.

**테스트**:
- 타깃 레벨(실 `AVPlayerItem` + 번들 `tiny.mp4`, `ABAVPlaybackTargetErrorEventsTests.swift:23-34` 패턴): `setLooping(true)` 후 `AVPlayerItemDidPlayToEndTime` 포스트 → `avPlayer.actionAtItemEnd == .none`이고 `waitUntil { target.isPlaying }`.
- `setLooping(false)`면 재개하지 않음(부재 검증은 기존 관례대로 바운드된 `Task.yield()` 드레인).

### A-2w — 포그라운드 복귀의 오디오 세션 우회 + 배경 캡처 시점 (A-2, A-6)

**위치**: `ABPlayer.swift:649-698`, `ABApplicationStateObserver.swift:22-39`.
**지침**:
1. `ABApplicationStateObserver`에 `onWillResignActive` 콜백과 `UIApplication.willResignActiveNotification` 구독을 추가(기존 2종은 유지).
2. `wasPlayingBeforeBackground` 캡처를 `didEnterBackground` → `willResignActive`로 이관. pause/detach/demote 등 **실제 부수효과는 계속 `didEnterBackground`에서** 수행한다(전환 취소된 임시 resign에서 재생을 멈추지 않기 위함).
3. 캡처가 상하지 않는 근거를 주석에 불변식으로 서술: `didEnterBackground`는 항상 `willResignActive` 뒤에 오고, 매 resign마다 캡처가 덮어써진다.
4. 포그라운드 복귀의 `target.play()` 2곳(`:683`, `:689`)을 `self.play()`로 교체 → `applyAudioSessionPolicyIfNeeded(force: false)`를 경유한다. `audioSessionActivationDirty = true`(`:677`)가 먼저 실행되는 현재 순서를 유지해야 `force: false`가 실제 재활성화로 이어진다.
5. 위 분기 전체를 결정 5의 `ABBackgroundPolicyMachine`으로 이관.

**테스트**:
- `ABBackgroundPolicyMachine` 표 테스트: 4개 정책 × 3개 시그널 × (grade, wasPlaying) 조합.
- 엔진 레벨: 관리형 `audioSessionPolicy` + 가짜 코디네이터로, 배경→포그라운드 복귀 시 `apply`가 1회 발생하고 `target.play()`가 그 **뒤에** 오는지 호출 순서 검증.
- `willResignActive`에서 `isPlaying == true`를 캡처한 뒤 `didEnterBackground`에서 이미 `false`가 된 상황을 가짜 타깃으로 재현 → 복귀 시 재생 재개.
- 기존 `ABPlayerEngineTests.swift:413`(`pauseAndDetachLayer` 배경/복귀)은 **무수정 통과**해야 한다.

### A-3w — `lastError` 라이프사이클 + 진단 채널 분리 (A-3)

**위치**: `ABPlayer.swift:475-477`, `:552-560`, `:830-836`.
**지침**:
1. 결정 1의 `lastFailure`(저장) / `lastError`(계산) / `lastDiagnostic`(저장) 3층 도입.
2. 라우팅: `failure.isTerminal ? (lastFailure = failure) : (lastDiagnostic = failure)`. 두 경우 모두 `.failed(kind)` + `.failureReported(failure)`를 방송(이벤트 표면은 회귀 없음).
3. 리셋: `.attachItem` 액션(`:500-511`), `sourceChanged`, `.detachItem`, `release()`에서 `lastFailure = nil; lastDiagnostic = nil`. 리셋도 `refreshPlaybackMirrors()`와 같은 전이 지점에서 일괄 수행.

**동작 변화(마이그레이션 노트 필수)**: `.itemErrorLogEntry`가 더 이상 `lastError`를 갱신하지 않는다. 소비자는 `lastDiagnostic`을 읽는다.
**허용된 테스트 수정**: `ABPlayerEngineTests.swift:470-482` — 단언 대상을 `lastDiagnostic`으로 옮기고, `lastError`가 `nil`로 유지됨을 추가 단언.

**테스트**: 실패 후 새 소스 attach → `lastError == nil`; 진단 후 `lastError == nil && lastDiagnostic != nil`; `.failureReported`의 `origin.domain/code`가 주입한 `NSError`와 일치.

### A-4w — TTFF 거짓 히트 + preroll TOCTOU + detach 방송 순서 (A-4, A-5, A-8)

**위치**: `ABPlayer.swift:501-502`, `:513-515`, `ABAVPlaybackTarget.swift:299-319`.
**지침**:
1. `.detachItem` 액션에서 `hasDisplayedFirstFrame = false; reportedFirstFrameItem = nil`. `release()`는 `.detachItem`을 경유하므로 이것으로 A-4가 닫힌다(`ABMetricsRecorder.swift:33-41`의 false hit 경로).
2. `.detachItem` 액션 순서를 `target.detachItem()` → `broadcast(.itemDetached(reason:))`로 교체. `ABPlayerView`가 이벤트 수신 시 `avPlayerItem == nil`을 보고 리바인드하도록 확정(§3.3).
3. `waitUntilReady`(`:299-335`)의 상태 관찰을 `[.new]` → `[.initial, .new]`로. `.initial`이 `observe` 호출 시점에 동기 발화하며, `state.install(continuation)`이 이미 그 앞(`:306`)에서 실행되므로 즉시 resolve가 안전하다. 상단 조기 반환(`:300-301`)은 빠른 경로로 유지해도 되고 제거해도 된다 — `.initial`이 동일 결과를 보장한다.

**테스트**:
- release 후 `hasDisplayedFirstFrame == false`, 이어지는 `beginTTFF`가 `.hit`을 기록하지 않음(메트릭 타깃 테스트).
- `.itemDetached` 수신 핸들러 안에서 `player.avPlayerItem == nil` 단언.
- `waitUntilReady`: 이미 `.readyToPlay`인 아이템을 넘겨도 타임아웃 없이 즉시 `.ready`(`ABAVPlaybackTargetReadyWaitTests.swift` 확장).

### A-5w — 시크 통일 + skip 누적 (A-7, D-1 코어 절반)

**위치**: `ABPlayer.swift:300-340`, `:356-374`, `:377-403`, `:522-523`, `:838-868`.
**지침**: 결정 4를 그대로 구현. 순서 권고 — (1) `enqueueSeek`/`clampToPlayableRange`/`awaitSeekSettled` 도입, (2) 진입점 4곳 재배선, (3) `pendingSeekTime` + `seekTargetChanged` 추가, (4) `endScrubbing`의 세대 재검증 가드.
**금지**: `ABSeekCoalescer.swift` 및 `ABSeekCoalescerTests.swift`/`ABScrubbingEngineTests.swift` 수정.
**테스트(신규)**:
- 정착 전 연속 skip 2회(+20, +20) → 두 번째 시크 목적지가 40초.
- `pendingSeekTime`이 요청 시 값이 되고 정착 후 `nil`, `seekTargetChanged`가 그 두 시점에만 방송.
- `seek(to:)`가 duration 초과 시간을 클램프.
- 소스 교체 후 도착한 stale 시크가 `.seekCompleted`를 방송하지 않음(세션 밖 `scrub` 경로로도 재현 — 기존 테스트는 세션 안 경로만 커버).
- 세션 밖 `scrub` 연타 5회가 코얼레싱되어 시크 호출이 5회 미만.

### A-6w — 관찰성 + 신규 이벤트 + 에러 프로비넌스 (B-1~B-5)

**위치**: `ABPlayer.swift:40-52`, `:465-479`, `ABAVPlaybackTarget.swift:337-447`, `ABPlaybackTarget.swift:7-13,34-68`, `ABPlayerEvent.swift`, `ABPlayerError.swift`.
**지침**:
1. `ABPlaybackTarget` 프로토콜에 읽기 전용 신호 추가: `isPlaybackLikelyToKeepUp`, `isPlaybackBufferEmpty`, `timeControlStatus`, `isWaitingWithNoItem`, `presentationSize`. `ABTargetEvent`에 `.bufferStateChanged`, `.durationChanged`, `.presentationSizeChanged(CGSize)` 추가, `.failed`는 `ABPlayerFailure` 페이로드로 교체.
2. `ABAVPlaybackTarget.observeItem`에 결정 2의 KVO 5종 등록. **모든 신규 관찰은 `observations.add`로 수명 결속 + hop 후 `self.avPlayerItem === item` stale 가드.**
3. `ABPlayer`에 미러 3종 + `ABBufferingEvaluator` + `desiresPlayback` 도입, `refreshPlaybackMirrors()`를 결정 2의 갱신 시점 표대로 호출.
4. `stallEnded` 추적(`isStallOutstanding`, `@ObservationIgnored`), `durationAvailable` 중복 억제(`lastBroadcastFiniteDuration`), `itemAttached`/`mutedChanged`/`callRejected`/`failureReported` 방송 지점 배선.
5. `ABPlayerView`가 `presentationSizeChanged`를 소비하도록 `:99-109`의 폴링을 이벤트 구동으로 교체(레이아웃 변경 시의 재평가는 `layoutSubviews` 경로로 유지).
6. 신규 케이스 전부를 DocC/CHANGELOG에 non-exhaustive 관례대로 기재.

**테스트**:
- `ABBufferingEvaluator` 표 테스트(전 조합).
- 가짜 타깃으로 buffering 미러 전이 → `bufferingChanged`가 값 변화 시에만 1회.
- `play()` 직후 **동기적으로** `player.isPlaying == true`(Controls 불변식의 코어 측 고정).
- 동일 값 재대입이 Observation을 발화시키지 않음(`withObservationTracking` + 바운드 드레인 부재 검증).
- `durationAvailable`가 아이템당 1회, detach 후 재attach 시 다시 1회.
- `itemAttached` → `tuningApplied` 순서, `.failed` → `.failureReported` 순서.
- `ABPlayerObservationTests`에 `isPlaying`/`duration`/`isBuffering`/`pendingSeekTime` 발화 테스트 4종 추가.

### A-7w — 소형 정리 (B-6, B-7, B-8, H-6)

**위치**: `ABAssetFactory.swift:13-15`, `ABAVPlaybackTarget.swift:204-210`·`:110-116`, `ABPlaybackTuning.swift`, `Observation/ABObserverRegistry.swift`·`ABLayerAttachmentObserverRegistry.swift`, `Policy/ABAudioSession.swift:7-22,76-88`.

1. **httpHeaders(B-6)**: `ABDefaultAssetFactory.makeAsset`이 `source.httpHeaders`가 비어있지 않으면 `AVURLAsset(url:options: ["AVURLAssetHTTPHeaderFieldsKey": headers])`를 쓴다. DocC에 (a) 이 키가 문서화되지 않은 키라는 점, (b) HLS 하위 요청에는 적용이 보장되지 않으며 그 경우 `ABPlayerKitCache`의 리소스 로더가 지원 경로라는 점을 명시. `ABMediaSource.swift:13-15`의 "Phase 2 코어는 적용하지 않음" 주석을 갱신.
2. **`UIScreen.main`(B-7)**: 제거. 대신 `ABPlayerView`가 자신의 픽셀 크기(`bounds.size × traitCollection.displayScale`)를 `layoutSubviews`에서 `ABPlayer`에 보고(`internal func reportDisplaySize(_:)`)하고, `ABPlayer`가 그 값을 `tuning.resolved(displaySize:)`에 넘긴다. 뷰가 없으면 `.zero`(= 캡 없음). 값이 실제로 바뀐 경우에만 재적용해 루프를 막는다. `ABPlaybackTuning.resolved`(`:73-78`)는 이미 순수이므로 수정 불필요.
   **동작 변화(마이그레이션 노트)**: 뷰에 부착되지 않은 플레이어의 `displaySizeSentinel`은 이제 화면 크기가 아니라 "캡 없음"으로 해석된다.
3. **rate(B-8)**: `desiredRate`를 진실의 원천으로 유지하되 `setRate`에서 `avPlayer.defaultRate`에도 미러링하고, `play()`는 `avPlayer.play()`를 쓴다. 실익은 시스템 주도 재개(인터럽션 종료 등)가 설정된 배속을 존중한다는 것. `ABPlaybackTuning`에 `audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm?`(기본 `nil` = AVFoundation 기본값 미변경)을 **init 파라미터 목록 맨 끝에** 추가해 소스 호환을 유지. 이 항목에서 rate 관련 테스트가 붉어지면 `defaultRate` 미러링만 되돌리고 `audioTimePitchAlgorithm` 노출은 유지한다.
4. **레지스트리 통합(H-6)**: 제네릭 `ABHandlerRegistry<Payload>` 하나로 통합. `ABPlayer.addObserver`가 `[weak self]`로 플레이어를 캡처해 `observer.player(self, didEmit:)`를 호출하면 페이로드가 `ABPlayerEvent` 단일 값이 되어 두 레지스트리가 같은 제네릭으로 수렴한다(~55줄 감소). `ABPlayerKitControls`의 `ABControlsObserverRegistry`는 별도 타깃이므로 **건드리지 않는다**(C-7w 소관).
5. **`ABAudioSession.activate` 중복(H-6)**: `nonisolated` 내부 자유 함수 하나를 두고 공개 `@MainActor` 파사드(`:7-22`)와 `ABAudioSessionAdapter.activate`(`:76-88`)가 함께 호출한다. 격리 의도(주석 `:71-75`)는 그대로 보존.

**테스트**: 헤더 주입 옵션이 실제로 `AVURLAsset`에 실렸는지(옵션 딕셔너리 검증), 표시 크기 보고 시 `preferredMaximumResolution`이 셀 크기로 해석되는지, 통합 레지스트리의 다중 관찰자/토큰 취소/off-main deinit 시나리오가 기존 테스트(`ABPlayerEngineTests.swift:538-640`)로 그대로 통과하는지.

---

## 5. 리스크와 무회귀 가드

### 5.1 절대 불변식 (위반 시 A-8 게이트 REQUEST-CHANGES)

| # | 불변식 | 근거 |
|---|---|---|
| I-1 | `player.isPlaying`은 `play()`/`pause()` **호출 직후 동기적으로** 참/거짓이다 | `ABControlsPlayPauseReentrancyCharacterizationTests.swift:70`(`#expect(player.isPlaying)`), `ABPlayerControlsView.swift:690`. 미러를 KVO에만 의존시키면 이 단언이 깨진다 |
| I-2 | `isPlaying`의 **의미**는 `rate != 0 && timeControlStatus != .paused`로 불변 — 버퍼링 중에도 `true` | `ABAVPlaybackTarget.swift:29-32`, MJ-3 근거(`ABControlsPresenter.swift:113-131`). `timeControlStatus == .playing`으로 좁히면 D-2가 악화된다 |
| I-3 | 스크럽 중 `skip(by:)`은 정착을 기다리지 않는다 | `ABScrubbingEngineTests.swift:136-153` 교착 |
| I-4 | `ABSeekCoalescer`의 3개 메서드 시맨틱 불변 | `ABSeekCoalescerTests.swift` 무수정 |
| I-5 | 스크럽 종료 순서 `.seekCompleted` → `.scrubbingChanged(false)` → `.periodicTime` | `ABPeriodicTimeEngineTests.swift:59-79`, `ABScrubbingEngineTests.swift:117-134` |
| I-6 | 모든 release 경로는 `.detachItem`을 정확히 1회 경유 | `ABPlayerEngineTests.swift:45-95` |
| I-7 | 신규 KVO/알림 관찰은 `ABObservationBag`으로 수명 결속 + hop 후 stale-item 가드 | `ABAVPlaybackTarget.swift:337-447` 전역 관례 |
| I-8 | `deinit`에서 접근되는 저장 프로퍼티는 `@ObservationIgnored` 유지 | `ABPlayer.swift:59-68`, `:187-191` |

### 5.2 수정 금지 테스트 파일

- `Tests/ABPlayerKitTests/ABSeekCoalescerTests.swift`
- `Tests/ABPlayerKitTests/ABScrubbingEngineTests.swift`
- `Tests/ABPlayerKitTests/ABPeriodicTimeEngineTests.swift`
- `Tests/ABPlayerKitControlsTests/` 전체 (트랙 A는 Controls 타깃을 건드리지 않는다)

### 5.3 허용된 테스트 변경 (사전 승인, 그 외에는 게이트 문의)

| 파일:라인 | 변경 | WP |
|---|---|---|
| `ABPlayerEngineTests.swift:470-482` | `.itemErrorLogEntry` 단언을 `lastDiagnostic`으로 이동 | A-3w |
| `ABAVPlaybackTargetErrorEventsTests.swift:53,88,124,130,174,182` | `case .failed(.itemFailed(let d))` → `case .failed(let f)` + `f.kind` 패턴 (기계적) | A-6w |
| `ABPlayerObservationTests.swift:123` | `.failed(.itemFailed(…))` → `.failed(.init(kind: .itemFailed(…)))` | A-6w |
| `Fakes/ABFakePlaybackTarget.swift` | 프로토콜 신규 멤버(버퍼 신호·presentationSize) 구현 추가, `.emit` 헬퍼 유지 | A-6w |
| `ABSkipEngineTests.swift` | **수정 없음**. 신규 누적 테스트는 새 파일 또는 파일 말미 추가로 | A-5w |

### 5.4 리스크 등급

| 리스크 | 등급 | 완화 |
|---|---|---|
| A-6w의 @Observable 미러 도입이 SwiftUI 무효화 폭풍을 유발 | **높음** | 값 비교 후 대입(결정 2). Observation 발화 부재 테스트로 고정 |
| A-5w의 시크 통일이 스크럽 회귀 | **높음** | I-3/I-4/I-5, 수정 금지 파일 3종, `endScrubbing` 본문 구조 보존 |
| `ABTargetEvent.failed` 페이로드 교체가 예상보다 넓게 번짐 | 중 | §5.3의 6개 지점이 전부. 그 이상 번지면 설계 재검토 신호 |
| `.itemDetached` 순서 변경이 `ABPlayerView` 리바인드를 깨뜨림 | 중 | A-8은 "우연한 자기수정"(`.gradeChanged` 뒤따름)에 의존하던 상태 — 순서 수정 후 `avPlayerItem == nil` 단언 테스트로 고정 |
| `defaultRate` 도입이 배속 회귀 | 낮음 | 단독 되돌림 가능하도록 A-7w 마지막 서브아이템으로 배치 |
| 신규 KVO 5종이 detach 시 누수/크래시 | 중 | I-7. TSan 잡(CI-2)이 병합 후 2차 안전망 |
| CI 러너 지연 | 낮음 | 기존 규약 유지(suite `timeLimit` 3분, `ABWaitUntil`) |

### 5.5 Wave 2 인터페이스 동결

§3.2의 9개 케이스 시그니처, `ABRejectedCall`/`ABErrorOrigin`/`ABPlayerFailure` 정의, §3.3 순서 계약, 그리고 공개 프로퍼티 `isPlaying`/`duration`/`isBuffering`/`pendingSeekTime`/`lastFailure`/`lastDiagnostic`은 **C-0/F-0/G-0 설계가 의존해도 되는 확정 표면**이다. A 구현 중 변경이 불가피하면 본 문서를 개정하고 해당 트랙 설계에 통지하는 것이 유일한 경로다.
