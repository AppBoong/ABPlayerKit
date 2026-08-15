# 설계서 — ABPlayerKit v0.2 (엔진 보강 + 컨트롤 레이어)

> 대상: `github.com/AppBoong/ABPlayerKit` · iOS 17+ · Swift 6 언어 모드 · MIT
> 기준 문서: `docs/BRIEF-v0.2-CONTROLS.md`, `docs/PLANNING.md` §6·§7, `docs/DESIGN-ABPlayerKit.md`
> 전제: v0.1.0 공개 API에 **파괴적 변경 없음**(additive only) · semver `v0.2.0`
> **미결 쟁점 Q9~Q15 전부 확정됨 (사용자 승인, 2026-08-04).** 결과는 §12 상단 표와 `docs/DESIGN-OPEN-QUESTIONS.md` 참조.
> Q9 확정 시 수정안 1건 반영: `ABSeekBarGeometry`·`ABTimeFormatter`는 컨트롤 타겟이 아니라 **코어 `ABPlayerKit`의 공개 API**로 승격한다(ABShortsKit v0.2가 숏폼 제스처 UI에서 재사용).

---

## 0. 요약

| 축 | v0.2에서 하는 것 |
|---|---|
| 엔진 | `setRate`, `skip(by:)`, 주기적 시간 이벤트(+버퍼 구간), 스크러빙 전용 seek 경로 |
| 신규 타겟 | **`ABPlayerKitControls`** — UIKit 코어(`ABPlayerControlsView`) + SwiftUI 래퍼(`ABPlayerControls`) |
| 커스터마이징 | 값 타입 `ABPlayerControlsStyle`(아이콘/색/치수) + `ABPlayerControlsConfiguration`(동작) |
| 순수 로직 분리 | 코어: `ABSeekCoalescer`(internal), **`ABSeekBarGeometry`·`ABTimeFormatter`(public)** / 컨트롤: `ABControlsVisibilityMachine`(internal) — 전부 `@Suite` 100% 대상 |
| 비목표 | 자막/오디오 트랙 UI, 전체화면 전환, PiP, AirPlay 라우트 버튼, 챕터 마커, 제스처 기반 밝기/볼륨 |

핵심 설계 판단 3개(근거는 §2·§4·§11):
1. 컨트롤은 **코어에 넣지 않고 별도 타겟**으로 분리한다. `DESIGN-ABPlayerKit.md` §1이 컨트롤 UI를 명시적 비목표로 선언했고, 숏폼 소비자(ABShortsKit)는 시크바를 링크할 이유가 전혀 없다.
2. `rate`는 `ABPlayerConfiguration.playbackRate`에 둔다. `isMuted`/`isLooping`이 이미 그 경로(`configuration didSet` → `applyConfigurationChange` → target)를 쓰고 있으므로, 새 상태 채널을 만들지 않는 것이 규칙 준수다.
3. 스크러빙은 **엔진 책임**이다. 코얼레싱을 컨트롤 뷰에 두면 UIKit·SwiftUI 두 벌로 중복되고 테스트가 UI에 묶인다. 순수 `ABSeekCoalescer`를 `ABPlayer`가 소유한다.

---

## 1. 엔진 보강 — 공개 API 스케치

### 1.1 `ABPlayerConfiguration` 추가 필드 (전부 기본값 있음 → memberwise init 소스 호환)

```swift
public struct ABPlayerConfiguration: Sendable, Equatable {
    // ... v0.1 필드 그대로 ...

    /// 재생 배속. `play()`가 적용하는 rate이며, 일시정지 상태에서 바꿔도
    /// 재생이 시작되지 않는다. 허용 범위 밖 값은 클램프된다(`ABPlaybackRate.allowedRange`).
    public var playbackRate: Float = 1.0

    /// `nil` = 주기 시간 이벤트를 발행하지 않는다(기본값 — v0.1 동작 유지).
    /// 값이 있으면 `grade == .current`인 동안 그 간격으로 `.periodicTime`을 방송한다.
    public var periodicTimeInterval: TimeInterval? = nil

    /// 스크러빙 중(`scrub(to:)`) 사용하는 seek 허용 오차. 손가락 추종성을 위해
    /// 기본은 느슨하게 두고, `endScrubbing()`의 최종 seek만 `.precise`로 확정한다.
    public var scrubTolerance: ABSeekTolerance = .coarse(before: .seconds(0.5), after: .seconds(0.5))
}
```

> `Equatable`은 기존과 동일하게 수동 `==`(assetFactory 제외)에 세 필드를 추가한다.

### 1.2 신규 값 타입

```swift
/// seek 정밀도. AVFoundation의 toleranceBefore/After를 그대로 노출하되
/// 소비자가 CMTime 조합을 직접 만들지 않아도 되게 프리셋을 준다.
public enum ABSeekTolerance: Sendable, Equatable {
    /// toleranceBefore/After = .zero. 프레임 정확, 느림.
    case precise
    /// 지정한 허용 오차. 스크러빙·프리뷰용.
    case coarse(before: CMTime, after: CMTime)

    /// ±0.5초
    public static let scrubbing = ABSeekTolerance.coarse(before: .seconds(0.5), after: .seconds(0.5))
    /// 허용 오차 무한 — 키프레임으로 즉시 점프
    public static let nearest = ABSeekTolerance.coarse(before: .positiveInfinity, after: .positiveInfinity)
}

/// 시크바 한 프레임을 그리는 데 필요한 전부. 주기 이벤트의 페이로드이자
/// `ABPlayer.playbackTime`의 스냅샷 타입.
public struct ABPlaybackTime: Sendable, Equatable {
    public let currentTime: CMTime
    /// 라이브/미확정 스트림에서는 `nil` (`CMTIME_IS_INDEFINITE`).
    public let duration: CMTime?
    /// `currentTime`을 포함하는 연속 로드 구간의 끝. 버퍼 바 전용.
    /// 로드 구간이 없거나 현재 시각을 포함하지 않으면 `nil`.
    public let bufferedUntil: CMTime?

    /// 0...1. `duration`이 없거나 0이면 `nil`.
    public var progress: Double? { get }
    /// 0...1. `bufferedUntil`/`duration`이 없으면 `nil`.
    public var bufferedProgress: Double? { get }

    public static let zero = ABPlaybackTime(currentTime: .zero, duration: nil, bufferedUntil: nil)
}

/// 배속 클램프 규칙을 한 곳에 모은 순수 네임스페이스.
public enum ABPlaybackRate {
    /// 0.25...4.0 — AVPlayer가 `canPlaySlowForward`/`canPlayFastForward`로
    /// 거절할 수 있는 구간까지 포함한다. 라이브러리는 클램프만 하고 거절은 하지 않는다.
    public static let allowedRange: ClosedRange<Float> = 0.25...4.0
    public static func clamped(_ rate: Float) -> Float
    /// 흔한 프리셋 — 컨트롤의 기본 rateOptions와 같은 값
    public static let common: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]
}
```

### 1.3 `ABPlayer` 추가 API

```swift
@MainActor
public final class ABPlayer {
    // ... v0.1 그대로 ...

    // MARK: - 배속

    /// 현재 원하는 배속(= `configuration.playbackRate`). 일시정지 중에도 유지된다.
    public var rate: Float { get }

    /// 배속 변경. 범위 밖 값은 클램프되고 클램프된 값으로 `.rateChanged`가 방송된다
    /// (throw/crash 없음 — DESIGN-ABPlayerKit.md §6 원칙 3).
    /// 재생 중이면 즉시 반영되고, 정지 중이면 다음 `play()`에 반영된다.
    /// `grade != .current`에서도 **거절하지 않는다** — 배속은 설정값이지 재생 명령이 아니다.
    public func setRate(_ rate: Float)

    // MARK: - 탐색

    /// 상대 이동. `currentTime + interval`을 `0...duration`으로 클램프해 seek한다.
    /// `duration`을 모르면(라이브) 상한 클램프 없이 하한(0)만 적용한다.
    /// 스크러빙 중이면 코얼레서를 통과한다(스킵 연타가 seek 큐를 쌓지 않는다).
    public func skip(by interval: TimeInterval) async

    /// v0.1 API 유지 — `seek(to:tolerance: .precise)`와 동치.
    public func seek(to time: CMTime) async

    /// 허용 오차 지정 seek. `grade != .current`면 `.playbackRejected` 후 무시.
    public func seek(to time: CMTime, tolerance: ABSeekTolerance) async

    // MARK: - 스크러빙

    /// 드래그 시작. 이 시점부터 `endScrubbing()`까지:
    /// (1) `.periodicTime` 방송이 **중단**되고, (2) `scrub(to:)`가 코얼레싱된다.
    /// 이미 스크러빙 중이면 no-op.
    public func beginScrubbing()

    /// 드래그 중 목표 시각 갱신. **비동기가 아니다** — 호출자는 60/120Hz로 부담 없이 호출한다.
    /// 진행 중인 seek이 있으면 목표만 갱신되고(가장 최근 값만 살아남는다) 완료 시 이어서 발행된다.
    /// `beginScrubbing()` 없이 호출하면 단발 coarse seek으로 동작한다(관용 처리).
    public func scrub(to time: CMTime)

    /// 드래그 종료. 마지막 목표로 `.precise` seek을 **await**하고,
    /// `.seekCompleted` → `.scrubbingChanged(false)` 순으로 방송한 뒤 주기 이벤트를 재개한다.
    public func endScrubbing() async

    public private(set) var isScrubbing: Bool

    // MARK: - 시간 스냅샷

    /// 이벤트를 기다리지 않고 현재 값을 직접 읽는다(초기 렌더/복원용).
    public var playbackTime: ABPlaybackTime { get }
}
```

### 1.4 `ABPlayerEvent` 추가 케이스

```swift
public enum ABPlayerEvent: Sendable, Equatable {
    // ... v0.1 그대로 ...

    /// `setRate`가 실제로 값을 바꿨을 때만(클램프 후 비교) 방송된다.
    case rateChanged(Float)
    /// `configuration.periodicTimeInterval` 간격으로 방송. 스크러빙 중에는 중단된다.
    case periodicTime(ABPlaybackTime)
    /// `beginScrubbing`/`endScrubbing` 경계.
    case scrubbingChanged(isScrubbing: Bool)
    /// 모든 seek(스크럽 중간 seek 포함)의 완료 지점. 실제 착지 시각을 싣는다.
    case seekCompleted(to: CMTime)
}
```

> ⚠️ **소스 호환성 주의.** SPM 라이브러리(library evolution 미사용)에서 public enum에 케이스를 추가하면, `default` 없이 전수 `switch`하던 소비자는 **재컴파일 시 에러**가 난다. 바이너리 호환 문제는 없고 0.x semver 범위 안이지만 무시할 사안은 아니다 → **Q10** 참조.

### 1.5 `ABPlaybackTarget`(internal) 확장

```swift
@MainActor
protocol ABPlaybackTarget: AnyObject {
    // ... v0.1 그대로 ...

    /// 현재 원하는 rate를 저장한다. 재생 중이면 즉시 반영, 정지 중이면 다음 play()에 반영.
    func setRate(_ rate: Float)
    /// `avPlayer.rate = desiredRate` — v0.1의 `play()`(rate 1.0 고정)를 대체한다.
    func play()
    func seek(to time: CMTime, tolerance: ABSeekTolerance) async -> CMTime   // 착지 시각 반환
    /// `loadedTimeRanges`에서 `currentTime`을 포함하는 구간의 끝.
    var bufferedUntil: CMTime? { get }
    /// 주기 관찰 설치/해제. AVPlayer 폐기 **전에** 반드시 remove되어야 한다(불변식 T3).
    func setPeriodicTimeObserver(interval: TimeInterval?, onTick: (@MainActor (CMTime) -> Void)?)
}
```

`ABFakePlaybackTarget`은 `Call`에 `.setRate(Float)`, `.seek(CMTime, ABSeekTolerance)`, `.setPeriodicObserver(TimeInterval?)`를 추가하고, `tick(_:)` 테스트 헬퍼로 주기 이벤트를 수동 발화한다.

### 1.6 엔진 불변식 (테스트로 고정)

| # | 불변식 |
|---|---|
| T1 | `beginScrubbing()`~`endScrubbing()` 사이에 `.periodicTime`은 **0회** 방송된다. |
| T2 | `scrub(to:)`를 N회 연타해도 target `seek` 호출은 **≤ 2 + 1**회(진행 중 1 + 최신 pending 1 + 최종 precise 1). 오래된 목표는 절대 발행되지 않는다. |
| T3 | 주기 관찰자는 `detachItem`/`releasePlayer`/등급 강등/`periodicTimeInterval = nil` 어느 경로로든 **반드시** 먼저 제거된다. AVPlayer 폐기 시점에 살아있는 관찰자 0개. |
| T4 | `play()` 직후 target에 적용된 rate == `configuration.playbackRate`. (`play()`가 배속을 1.0으로 되돌리지 않는다.) |
| T5 | `pause()` → `play()` 왕복 후 `rate`는 보존된다. 등급 강등→승격 왕복에서도 보존된다(`isMuted`와 동일 규칙). |
| T6 | `skip(by:)` 결과 시각은 항상 `0...duration` 안에 있다. `duration == nil`이면 하한만 적용. |
| T7 | `endScrubbing()`이 반환된 뒤 방송 순서는 `.seekCompleted` → `.scrubbingChanged(false)` → `.periodicTime`(즉시 1틱). |

### 1.7 배속 · preroll · 등급 상호작용 결정

| 상황 | 결정 | 근거 |
|---|---|---|
| `play()`가 배속을 복원하는가 | **한다.** `target.play()`는 `avPlayer.rate = desiredRate`. | AVPlayer의 `play()`는 rate=1.0 강제라서, 이걸 그대로 쓰면 "배속 켜고 일시정지했다 재생" 시 배속이 조용히 풀린다. 소비자가 매번 재설정하게 만드는 API는 실패다. |
| `setRate`가 재생을 시작하는가 | **하지 않는다.** 정지 중 호출은 저장만. | `play()`/`pause()`가 재생 명령의 유일한 진입점이라는 v0.1 계약을 깨지 않는다. |
| `setRate`가 `grade != .current`에서 거절되는가 | **거절하지 않는다.** `.playbackRejected` 미발행. | 배속은 `isMuted`와 같은 설정값이다. 프리로드 셀에 미리 배속을 걸어두고 승격하는 사용을 막을 이유가 없다. |
| preroll rate | **`configuration.prerollRate`를 문자 그대로 유지**(기본 1.0). `playbackRate`를 따라가지 않는다. | preroll은 디코드 파이프라인 워밍이지 재생이 아니다. 자동 연동은 "2× 재생 중 셀 진입 시 프리롤이 2×로 실행" 같은 비직관을 만든다. 다만 배속≠1일 때 첫 프레임 직후 AVPlayer가 내부 재프리롤을 하는 비용은 존재 → **Q12**. |
| 등급 전이 시 rate | **보존.** `ABGradePlanner` 전이표 **무변경**. | rate는 등급 액션이 아니라 설정 적용 경로(`applyConfigurationChange`)에 속한다. 전이표를 건드리면 v0.1의 32케이스 전수 테스트가 전부 흔들린다. |
| 강등 시 실제 rate | target이 `pause()`로 0이 되고 `desiredRate`만 남는다. 승격 후 `play()`에서 복원. | T5 |

---

## 2. 파일 · 타겟 레이아웃

### 2.1 결정 — 컨트롤은 **신규 타겟 `ABPlayerKitControls`**

```swift
// Package.swift (v0.2)
products: [
  .library(name: "ABPlayerKit",         targets: ["ABPlayerKit"]),
  .library(name: "ABPlayerKitControls", targets: ["ABPlayerKitControls"]),   // 신규
  .library(name: "ABPlayerKitMetrics",  targets: ["ABPlayerKitMetrics"]),
  .library(name: "ABPlayerKitCache",    targets: ["ABPlayerKitCache"]),
],
targets: [
  .target(name: "ABPlayerKit"),
  .target(name: "ABPlayerKitControls", dependencies: ["ABPlayerKit"]),        // 신규
  .target(name: "ABPlayerKitMetrics",  dependencies: ["ABPlayerKit"]),
  .target(name: "ABPlayerKitCache",    dependencies: ["ABPlayerKit"]),
  .testTarget(name: "ABPlayerKitTests",         dependencies: ["ABPlayerKit"]),
  .testTarget(name: "ABPlayerKitControlsTests", dependencies: ["ABPlayerKitControls", "ABPlayerKit"]),  // 신규
  // ...
]
```

**근거 4개:**
1. `DESIGN-ABPlayerKit.md` §1이 "커스텀 컨트롤 UI(시크바/타임라인)"를 **코어의 명시적 비목표**로 공개 문서화했다. 코어에 넣으면 설계서가 거짓이 되고, 포트폴리오 품질 게이트(PLANNING §7)의 "타겟 분리 근거 문서화" 항목을 스스로 위반한다.
2. **주 소비자가 필요로 하지 않는다.** ABShortsKit(릴스형 피드)은 시크바·배속 메뉴를 쓰지 않는다. 컨트롤을 코어에 넣으면 숏폼 앱이 UIKit 컨트롤 계층·심볼 이미지 코드를 무조건 링크한다.
3. **선례가 이미 규칙이다.** §11이 "책임/실패 모드가 다르면 옵트인 링크"라고 Metrics/Cache 분리 근거를 세워뒀다. 컨트롤은 실패 모드가 완전히 다르다(재생이 아니라 레이아웃/제스처/접근성).
4. **비용이 실제로 낮다.** SwiftUI 래퍼를 코어에 넣은 §2 결정의 근거는 "40줄, 링크 비용 0, import 1개"였다. 컨트롤은 40줄이 아니라 ~900줄이고, 소비자가 컨트롤을 원할 때만 `import ABPlayerKitControls` 한 줄을 더 쓰면 된다.

**반대 논거와 기각 사유.** "import 2개는 번거롭다" — 사실이지만 v0.1 소비자(숏폼)의 바이너리에 UI 코드를 강제하는 비용보다 작다. "타겟이 4개면 과분할" — 4개 전부 서로 다른 링크 결정(코어 필수 / 컨트롤·메트릭·캐시 각각 옵트인)을 가지므로 분할 축이 명확하다.

**SwiftUI 래퍼는 컨트롤 타겟 안에 둔다** — §2의 "래퍼는 자기 코어와 같은 타겟" 방침을 그대로 따른다(일관성).

### 2.2 디렉터리

```
Sources/
├─ ABPlayerKit/                                   # 코어 (기존 + 추가)
│  ├─ Model/
│  │  ├─ ABPlayerConfiguration.swift              # ✎ playbackRate, periodicTimeInterval, scrubTolerance
│  │  ├─ ABPlaybackTime.swift                     # ✚ 신규 (순수)
│  │  ├─ ABSeekTolerance.swift                    # ✚ 신규 (순수)
│  │  └─ ABPlaybackRate.swift                     # ✚ 신규 (순수 클램프)
│  ├─ StateMachine/
│  │  └─ ABSeekCoalescer.swift                    # ✚ 신규 (순수, internal, CoreMedia만 의존)
│  ├─ Presentation/                               # ✚ 신규 디렉터리 — UI가 재사용하는 공개 순수 로직
│  │  ├─ ABSeekBarGeometry.swift                  # ✚ 신규 (순수, public)
│  │  └─ ABTimeFormatter.swift                    # ✚ 신규 (순수, public)
│  ├─ Engine/
│  │  ├─ ABPlayer.swift                           # ✎ setRate/skip/seek(tolerance)/scrub API
│  │  ├─ ABPlaybackTarget.swift                   # ✎ 프로토콜 5개 멤버 추가
│  │  └─ ABAVPlaybackTarget.swift                 # ✎ rate/tolerance seek/periodic/buffered
│  └─ Observation/ABPlayerEvent.swift             # ✎ 4개 케이스 추가
│
└─ ABPlayerKitControls/                           # ✚ 신규 타겟
   ├─ Model/
   │  ├─ ABPlayerControlsStyle.swift              # 외형 (색/치수/아이콘)
   │  ├─ ABControlIcon.swift                      # SF Symbol | UIImage
   │  ├─ ABPlayerControlsConfiguration.swift      # 동작 (간격/배속 목록/자동숨김)
   │  └─ ABControlsEvent.swift                    # 컨트롤 → 소비자 이벤트
   ├─ StateMachine/
   │  └─ ABControlsVisibilityMachine.swift        # 순수 — 자동 숨김 (internal)
   │     ※ ABSeekBarGeometry / ABTimeFormatter는 코어 Presentation/ 으로 승격 — 여기서는 import해 쓴다
   ├─ View/
   │  ├─ ABPlayerControlsView.swift               # 공개 UIKit 진입점
   │  ├─ ABSeekBar.swift                          # internal
   │  ├─ ABControlButton.swift                    # internal
   │  └─ ABControlsBackgroundView.swift           # internal (gradient/blur/color)
   ├─ SwiftUI/
   │  ├─ ABPlayerControls.swift                   # UIViewRepresentable
   │  └─ ABVideoPlayerWithControls.swift          # ZStack 조립 편의 View
   └─ ABPlayerKitControls.docc/ABPlayerKitControls.md

Tests/
├─ ABPlayerKitTests/                              # ✎ 스위트 8개 추가 (엔진 6 + 프레젠테이션 순수 2)
└─ ABPlayerKitControlsTests/                      # ✚ 신규 (스위트 4개)
```

### 2.3 `Presentation/` — 코어에 공개 순수 로직을 두는 이유 (Q9 수정안)

`ABSeekBarGeometry`와 `ABTimeFormatter`는 컨트롤 타겟이 아니라 **코어의 public API**다.

| 근거 | 내용 |
|---|---|
| 재사용 소비자가 이미 확정됨 | ABShortsKit v0.2가 숏폼 제스처 UI(하단 슬림 시크바, 탭 재생/일시정지, 롱프레스 2× 배속)에서 두 타입을 그대로 쓴다. 컨트롤 타겟에 두면 ABShortsKit이 **쓰지도 않는 시크바 뷰·배속 메뉴·자동숨김 머신을 통째로 링크**해야 한다 — §2.1에서 컨트롤을 분리한 이유와 정확히 같은 문제가 반대 방향으로 재발한다 |
| 코어 비목표를 침범하지 않음 | 코어 설계서 §1의 비목표는 "커스텀 컨트롤 **UI**(시크바/타임라인)"이다. 이 둘은 UIView도 아니고 UIKit을 import하지도 않는다(`CoreGraphics` + `CoreMedia`만). 위젯이 아니라 **좌표·시간 산술**이다 |
| 링크 비용 0 | 두 파일 합계 ~120줄, 값 타입 + enum 네임스페이스. 코어에 추가되는 바이너리 비용은 무시 가능하다 |
| 타겟 분리 축이 유지됨 | 분리 기준은 "책임/실패 모드"였다. 이 둘의 실패 모드는 산술 오류(0 나눗셈, NaN)이며 코어의 다른 순수 타입(`ABPlaybackTime`, `ABPlaybackRate`)과 동일하다 |

**대가.** 공개 API 표면이 2개 늘고, 시그니처가 v0.2 이후 semver 대상이 된다. 그래서 API를 최소로 유지한다 — 상태 없음, 저장 프로퍼티는 생성자 주입 3개뿐, 나머지는 전부 `static`/순수 함수(§5.3·§5.4).

**`Presentation/`이라는 새 디렉터리를 만드는 이유.** `StateMachine/`은 코어 설계서 §2에서 "순수, AVFoundation 미의존"으로 정의됐지만 의미상 등급 전이 로직의 자리다. `Model/`은 재생 도메인 값 타입의 자리다. 두 타입은 어느 쪽도 아니고 "UI가 재사용하는 순수 표현 로직"이라는 세 번째 성격이므로 이름 붙은 자리를 준다.

---

## 3. 컨트롤 레이어 — 공개 API 스케치

### 3.1 UIKit 진입점

```swift
import ABPlayerKit
import UIKit

/// 재생 컨트롤 오버레이. 영상 위에 얹는 것을 전제로 하며 배경을 스스로 그리지 않는다
/// (style.backgroundStyle == .none이면 완전 투명).
/// 자기 bounds 안의 탭만 처리한다 — 영상 전체 탭으로 토글하려면 이 뷰를 영상과 같은 크기로 깔거나
/// `handlesBackgroundTap = true`로 둔다(기본 true).
@MainActor
public final class ABPlayerControlsView: UIView {

    /// 부착. 교체 시 이전 플레이어의 관찰을 먼저 끊고 새로 건다(ABPlayerView와 동일한 순서 계약).
    /// 부착 시 `configuration.periodicTimeInterval`을 플레이어 설정에 기록하고,
    /// 해제 시 **부착 이전 값으로 복원**한다(§7 Q11).
    public var player: ABPlayer? { didSet }

    /// 외형. 대입 즉시 반영된다(레이아웃 영향 프로퍼티는 setNeedsLayout까지 수행).
    public var style: ABPlayerControlsStyle { didSet }

    /// 동작. 대입 즉시 반영된다(자동 숨김 타이머 재무장 포함).
    public var configuration: ABPlayerControlsConfiguration { didSet }

    public init(
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init()
    )

    // MARK: - 가시성
    public private(set) var isControlsVisible: Bool
    /// 프로그램적 토글. animated == true면 style.visibilityAnimationDuration으로 alpha 전이.
    /// 호출은 자동 숨김 타이머를 재무장한다(사용자 조작과 동일 취급).
    public func setControlsVisible(_ visible: Bool, animated: Bool = true)

    // MARK: - 관찰 (코어와 동일한 토큰 규약 — delegate 슬롯을 쓰지 않는다)
    public func addObserver(
        _ handler: @escaping @MainActor @Sendable (ABControlsEvent) -> Void
    ) -> ABObservationToken

    // MARK: - 확장 슬롯
    /// 오른쪽 끝(배속 버튼 옆)에 소비자 버튼을 꽂는 자리. 전체화면/PiP/자막 버튼용.
    /// v0.2는 컨테이너만 제공하고 내용은 소비자 책임.
    public var accessoryViews: [UIView] { get set }
}
```

```swift
public enum ABControlsEvent: Sendable, Equatable {
    case visibilityChanged(isVisible: Bool)
    case playPauseTapped(isPlayingAfterTap: Bool)
    case skipTapped(by: TimeInterval)
    case rateSelected(Float)
    case scrubbingChanged(isScrubbing: Bool)
    /// 드래그 확정 지점. 아날리틱스용(소비자가 seek을 다시 할 필요는 없다).
    case seekCommitted(to: CMTime)
}
```

### 3.2 SwiftUI 래퍼

```swift
public struct ABPlayerControls: UIViewRepresentable {
    public init(
        player: ABPlayer,
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init(),
        onEvent: (@MainActor (ABControlsEvent) -> Void)? = nil
    )
}

/// 영상 + 컨트롤 조립 편의. 직접 ZStack을 쓰고 싶으면 위 두 타입을 쓰면 된다.
public struct ABVideoPlayerWithControls: View {
    public init(
        player: ABPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        style: ABPlayerControlsStyle = .default,
        configuration: ABPlayerControlsConfiguration = .init()
    )
    // body = ZStack { ABVideoPlayer(...); ABPlayerControls(...) }
}
```

`updateUIView`는 `player` 동일성(`!==`)·`style`/`configuration` 동등성(`!=`)을 비교해 **바뀐 것만** 대입한다. 무조건 대입하면 style didSet이 매 프레임 레이아웃을 유발한다.

### 3.3 동작 설정 `ABPlayerControlsConfiguration`

```swift
public struct ABPlayerControlsConfiguration: Sendable, Equatable {
    /// 스킵 버튼 이동량(초). 기본 10.
    public var skipInterval: TimeInterval = 10

    /// `skipInterval`이 SF Symbol이 제공하는 값(5/10/15/30/45/60/75/90)과 일치하면
    /// `goforward.N`/`gobackward.N`을 자동 선택한다. style에서 아이콘을 명시하면 그쪽이 이긴다.
    public var synchronizesSkipIconWithInterval: Bool = true

    /// 배속 선택지. 비어 있으면 배속 버튼을 숨긴다.
    public var rateOptions: [Float] = ABPlaybackRate.common

    public enum RateInteraction: Sendable, Equatable {
        case menu     // UIButton.menu — 목록에서 선택 (기본)
        case cycle    // 탭할 때마다 rateOptions를 순환
        case hidden
    }
    public var rateInteraction: RateInteraction = .menu

    /// `nil` = 자동 숨김 없음(항상 표시). 기본 3초.
    public var autoHideDelay: TimeInterval? = 3

    /// 일시정지 중에는 자동 숨김을 하지 않는다. 기본 true
    /// (정지 화면에서 컨트롤이 사라지면 다시 부르는 방법이 없어 보인다).
    public var staysVisibleWhilePaused: Bool = true

    /// `.periodicTime` 간격. 부착 시 player.configuration에 기록되고 해제 시 복원된다.
    /// 0.25s = 3pt 바에서 눈에 띄는 계단 없음 + 프레임당 비용 무시 가능.
    public var periodicTimeInterval: TimeInterval? = 0.25

    public var showsBufferedProgress: Bool = true
    public var showsTimeLabels: Bool = true

    public enum TimeLabelLayout: Sendable, Equatable {
        case elapsedAndTotal      // 0:12 / 3:45  (기본)
        case elapsedAndRemaining  // 0:12 / -3:33
        case elapsedOnly
    }
    public var timeLabelLayout: TimeLabelLayout = .elapsedAndTotal

    public var showsSkipButtons: Bool = true

    /// 컨트롤 bounds 안 빈 영역 탭으로 표시/숨김을 토글한다. 기본 true.
    public var handlesBackgroundTap: Bool = true

    /// 시크바 트랙 어디든 탭하면 그 지점으로 즉시 이동. 기본 true.
    public var allowsTrackTapToSeek: Bool = true

    public enum InitialVisibility: Sendable, Equatable { case visible, hidden }
    public var initialVisibility: InitialVisibility = .visible

    public init() {}
}
```

---

## 4. 스타일/테마 — `ABPlayerControlsStyle` 전체 프로퍼티와 기본값

```swift
public enum ABControlIcon: Equatable {
    /// SF Symbol 이름. 존재하지 않으면 렌더 생략(크래시 없음).
    case system(String)
    case image(UIImage)
    /// 버튼 자체를 숨긴다.
    case none
}

public enum ABControlsBackgroundStyle: Equatable {
    case none
    case color(UIColor)
    /// 하단 그라디언트 — 밝은 영상 위에서 흰 아이콘 가독성을 확보하는 기본값.
    case gradient(top: UIColor, bottom: UIColor)
    case blur(UIBlurEffect.Style)
}

public enum ABTrackCornerRadius: Equatable {
    case capsule            // height / 2
    case fixed(CGFloat)
    case square             // 0
}

public enum ABRateLabelStyle: Equatable {
    /// "1.5×" 형태의 텍스트 버튼. `format`은 `%@`에 배속 문자열이 들어간다.
    case text(font: UIFont, format: String)
    /// 아이콘 고정 + (선택) 배지 텍스트
    case icon(ABControlIcon, showsValueBadge: Bool)
}
```

```swift
public struct ABPlayerControlsStyle: Equatable {

    // ── 아이콘 ─────────────────────────────────────────────
    public var playIcon: ABControlIcon          = .system("play.fill")
    public var pauseIcon: ABControlIcon         = .system("pause.fill")
    /// nil이면 configuration.synchronizesSkipIconWithInterval 규칙으로 자동 결정.
    public var skipBackwardIcon: ABControlIcon? = nil     // → .system("gobackward.10")
    public var skipForwardIcon: ABControlIcon?  = nil     // → .system("goforward.10")
    /// SF Symbol에만 적용. .image(_)는 원본 크기를 aspect-fit한다.
    public var iconPointSize: CGFloat           = 22
    public var iconWeight: UIImage.SymbolWeight = .semibold
    public var iconRenderingMode: UIImage.RenderingMode = .alwaysTemplate

    // ── 버튼 ───────────────────────────────────────────────
    /// 시각적 크기. 히트 영역은 항상 최소 44×44로 확장된다(HIG, 접근성).
    public var playPauseButtonSize: CGSize      = CGSize(width: 44, height: 44)
    public var skipButtonSize: CGSize           = CGSize(width: 44, height: 44)
    public var buttonSpacing: CGFloat           = 32
    /// 버튼 눌림 시 alpha. 1.0이면 효과 없음.
    public var buttonHighlightedAlpha: CGFloat  = 0.5

    // ── 틴트 / 텍스트 ──────────────────────────────────────
    public var tintColor: UIColor               = .white
    public var disabledTintColor: UIColor       = UIColor.white.withAlphaComponent(0.35)
    public var timeLabelColor: UIColor          = .white
    public var timeLabelFont: UIFont            = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    /// 라벨 폭이 숫자에 따라 흔들리지 않게 고정폭 예약. 기본 true.
    public var usesFixedWidthTimeLabels: Bool   = true

    // ── 시크바 ─────────────────────────────────────────────
    /// 뒷편색 — 아직 재생/버퍼되지 않은 구간
    public var trackColor: UIColor              = UIColor.white.withAlphaComponent(0.25)
    /// 앞편색 — 재생 완료 구간
    public var progressColor: UIColor           = .white
    /// 버퍼 구간 (progress와 track 사이 레이어)
    public var bufferedColor: UIColor           = UIColor.white.withAlphaComponent(0.5)
    public var trackHeight: CGFloat             = 3
    /// 드래그 중 트랙 확대(iOS 기본 플레이어 관례). trackHeight와 같으면 확대 없음.
    public var trackHeightWhileScrubbing: CGFloat = 6
    public var trackCornerRadius: ABTrackCornerRadius = .capsule
    /// 시크바 좌우 여백(썸이 잘리지 않게 thumb 반지름 이상 권장 — 자동 보정됨)
    public var seekBarHorizontalInset: CGFloat  = 0

    // ── 썸(포인터) ─────────────────────────────────────────
    public var thumbSize: CGSize                = CGSize(width: 12, height: 12)
    public var thumbSizeWhileScrubbing: CGSize  = CGSize(width: 18, height: 18)
    public var thumbColor: UIColor              = .white
    public var thumbBorderColor: UIColor?       = nil
    public var thumbBorderWidth: CGFloat        = 0
    public var thumbCornerRadius: ABTrackCornerRadius = .capsule
    /// 0이면 그림자 없음
    public var thumbShadowOpacity: Float        = 0.25
    public var thumbShadowRadius: CGFloat       = 2
    /// 커스텀 썸 이미지. 있으면 색/크기 프로퍼티 대신 이 이미지를 그린다.
    public var thumbImage: UIImage?             = nil
    public var isThumbHidden: Bool              = false
    /// 썸의 실제 드래그 히트 영역 확장(시각 크기와 별개). 기본 ±16pt.
    public var thumbTouchInflation: CGFloat     = 16

    // ── 배속 표시 ──────────────────────────────────────────
    public var rateLabelStyle: ABRateLabelStyle = .text(
        font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
        format: "%@×"
    )
    public var rateButtonSize: CGSize           = CGSize(width: 52, height: 44)

    // ── 컨테이너 ───────────────────────────────────────────
    public var backgroundStyle: ABControlsBackgroundStyle = .gradient(
        top:    UIColor.black.withAlphaComponent(0.0),
        bottom: UIColor.black.withAlphaComponent(0.55)
    )
    public var contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    public var containerCornerRadius: CGFloat   = 0
    /// 하단 바와 시크바 사이 간격
    public var seekBarBottomSpacing: CGFloat    = 8

    // ── 애니메이션 ─────────────────────────────────────────
    public var visibilityAnimationDuration: TimeInterval = 0.25
    /// Reduce Motion이 켜져 있으면 duration을 0으로 강제한다. 기본 true.
    public var respectsReduceMotion: Bool       = true

    public init() {}

    // ── 프리셋 ─────────────────────────────────────────────
    /// 위 기본값 그대로 — 어두운 그라디언트 위 흰 컨트롤
    public static let `default` = ABPlayerControlsStyle()
    /// 배경/버퍼바/그림자 없음, 얇은 트랙 — 썸네일·인라인 플레이어용
    public static let minimal: ABPlayerControlsStyle
    /// 시스템 accentColor 기반 + 블러 배경 — 라이트 UI에 얹을 때
    public static let tinted: ABPlayerControlsStyle
}
```

### 4.1 라이브 갱신 규칙

`style` didSet은 이전 값과 비교해 필요한 만큼만 수행한다.

| 프로퍼티 군 | 재적용 방식 | 레이아웃 무효화 |
|---|---|---|
| 색상(`tintColor`, `trackColor`, `progressColor`, `bufferedColor`, `thumbColor`, `timeLabelColor`, 배경색) | 즉시 대입 | 불필요 |
| 아이콘(`*Icon`, `iconPointSize`, `iconWeight`) | 이미지 재생성 후 대입 | `invalidateIntrinsicContentSize()` |
| 치수(`trackHeight`, `thumbSize`, `buttonSize`, `contentInsets`, `buttonSpacing`) | 제약 상수 갱신 | `setNeedsLayout()` |
| `backgroundStyle` 종류 변경(`.gradient` → `.blur` 등) | 배경 서브뷰 교체 | `setNeedsLayout()` |
| `visibilityAnimationDuration`, `respectsReduceMotion` | 다음 전이부터 적용 | 불필요 |
| 스크러빙 중 치수(`*WhileScrubbing`) | 현재 스크러빙 중이면 **즉시** 반영 | `setNeedsLayout()` |

`Sendable`: `UIColor`/`UIImage`/`UIFont`는 iOS 17 SDK에서 Sendable로 표기되어 있으므로 `ABPlayerControlsStyle: Sendable` 채택을 **시도**하고, Swift 6 모드에서 경고가 뜨면 **`Sendable`을 떼고 `Equatable`만 유지**한다(이 타입은 MainActor에서만 읽힌다). `@unchecked Sendable`은 쓰지 않는다 — 거짓말이기 때문. → **Q13**

---

## 5. 순수 로직 타입 (테스트 100% 대상)

| 타입 | 타겟 | 가시성 | 이유 |
|---|---|---|---|
| `ABSeekCoalescer` | ABPlayerKit | internal | `ABPlayer`가 소유하는 구현 세부. 소비자가 직접 만들 이유 없음 |
| `ABSeekBarGeometry` | **ABPlayerKit** | **public** | ABShortsKit·자체 UI 제작 소비자가 재사용 (§2.3) |
| `ABTimeFormatter` | **ABPlayerKit** | **public** | 동일 |
| `ABControlsVisibilityMachine` | ABPlayerKitControls | internal | 컨트롤 뷰의 자동 숨김 정책 전용. 숏폼은 전혀 다른 표시 규칙을 쓴다 |

### 5.1 `ABSeekCoalescer` (코어, internal)

```swift
/// 진행 중인 seek이 하나뿐이도록 보장하고, 대기 중 목표는 항상 "가장 최근 하나"만 남긴다.
/// AVFoundation 미의존(CoreMedia의 CMTime만 사용) — 순수 값 전이.
struct ABSeekCoalescer: Equatable {
    enum Decision: Equatable {
        /// 지금 이 시각으로 seek을 발행하라
        case issue(CMTime, tolerance: ABSeekTolerance)
        /// 아무것도 하지 마라 (진행 중 seek 완료 시 이어받는다)
        case hold
    }

    private(set) var inFlight: CMTime?
    private(set) var pending: (time: CMTime, tolerance: ABSeekTolerance)?

    /// 새 목표 요청. 진행 중이면 pending을 **덮어쓴다**(오래된 목표는 소멸).
    mutating func request(_ time: CMTime, tolerance: ABSeekTolerance) -> Decision

    /// 진행 중 seek 완료 통지. pending이 있으면 그것을 발행하라고 답한다.
    mutating func completed() -> Decision

    /// 스크러빙 종료 — 마지막으로 알려진 목표를 precise로 확정한다.
    /// pending도 inFlight도 없으면 `.hold`.
    mutating func flush(finalTolerance: ABSeekTolerance) -> Decision

    /// 아이템 교체/해제 시 전량 폐기 (완료 콜백이 늦게 와도 아무것도 발행하지 않는다).
    mutating func reset()
}
```

### 5.2 `ABControlsVisibilityMachine` (컨트롤, internal)

```swift
struct ABControlsVisibilityMachine: Equatable {
    enum Visibility: Equatable { case visible, hidden }

    enum Input: Equatable {
        case attached(initial: Visibility)
        case tapped                       // 빈 영역 탭
        case controlInteracted            // 버튼/시크바 조작 — 숨기지 않고 타이머만 재무장
        case scrubBegan
        case scrubEnded
        case playbackStateChanged(isPlaying: Bool)
        case autoHideFired
        case setVisible(Bool)             // 프로그램적 호출
        case configurationChanged(autoHideDelay: TimeInterval?, staysVisibleWhilePaused: Bool)
        case detached
    }

    enum Effect: Equatable {
        case show
        case hide
        case scheduleAutoHide(after: TimeInterval)
        case cancelAutoHide
        case notifyVisibility(Bool)       // 중복 방지 — 실제로 바뀔 때만
    }

    private(set) var visibility: Visibility
    private(set) var isScrubbing: Bool
    private(set) var isPlaying: Bool

    mutating func handle(_ input: Input) -> [Effect]
}
```

**규칙표** (테스트가 이 표를 그대로 케이스로 옮긴다):

| 상태 | 입력 | 결과 |
|---|---|---|
| hidden | `.tapped` | `.show`, `.notifyVisibility(true)`, (재생 중 && delay != nil) `.scheduleAutoHide` |
| visible | `.tapped` | `.cancelAutoHide`, `.hide`, `.notifyVisibility(false)` |
| visible | `.controlInteracted` | `.cancelAutoHide`, (재생 중 && delay != nil) `.scheduleAutoHide` — **숨기지 않는다** |
| any | `.scrubBegan` | `.cancelAutoHide`, (hidden이면) `.show` + notify. `isScrubbing = true` |
| any | `.scrubEnded` | `isScrubbing = false`, (재생 중 && delay != nil) `.scheduleAutoHide` |
| visible | `.autoHideFired` (스크러빙 중) | `[]` — 무시 (타이머는 scrubBegan에서 취소되지만 경합 방어) |
| visible | `.autoHideFired` (정지 중 && staysVisibleWhilePaused) | `[]` |
| visible | `.autoHideFired` (그 외) | `.hide`, `.notifyVisibility(false)` |
| any | `.playbackStateChanged(true)` | (visible && delay != nil && !scrubbing) `.scheduleAutoHide` |
| any | `.playbackStateChanged(false)` | (staysVisibleWhilePaused) `.cancelAutoHide` + (hidden이면 유지) |
| any | `.setVisible(v)` | 현재와 같으면 `[]`, 다르면 show/hide + notify + 타이머 재계산 |
| any | `.configurationChanged` | `.cancelAutoHide` + 조건 충족 시 `.scheduleAutoHide` |
| any | `.detached` | `.cancelAutoHide` |

> 자동 숨김 타이머 자체(`Task.sleep` 또는 `DispatchWorkItem`)는 뷰가 소유한다. 머신은 **언제 걸고 언제 끄는지만** 결정한다 — 시간에 의존하지 않으므로 테스트가 sleep 없이 결정적으로 돈다.

### 5.3 `ABSeekBarGeometry` (**코어 `ABPlayerKit`, public**)

시크바를 직접 그리는 모든 UI(컨트롤 타겟, ABShortsKit의 하단 슬림 시크바, 소비자 자체 UI)가 공유하는 좌표 산술. `UIKit`을 import하지 않는다 — `CoreGraphics` + `CoreMedia`만.

```swift
/// 트랙 좌표 ↔ 진행률 ↔ 재생 시각 변환. 상태 없음, 값 타입.
/// UIKit 비의존 — 시크바를 직접 그리는 어떤 UI에서도 쓸 수 있다.
public struct ABSeekBarGeometry: Sendable, Equatable {
    /// 트랙 전체 폭(뷰 폭 - 좌우 inset)
    public let trackWidth: CGFloat
    /// 썸의 시각적 폭. 0이면 썸 없는 슬림 시크바(숏폼용).
    public let thumbWidth: CGFloat
    /// 트랙 좌우 여백
    public let horizontalInset: CGFloat

    public init(trackWidth: CGFloat, thumbWidth: CGFloat, horizontalInset: CGFloat = 0)

    /// 터치 x(뷰 좌표) → 0...1. 썸 반폭만큼 보정해 양 끝에서 정확히 0/1에 도달한다.
    /// 트랙 밖 좌표는 클램프. 유효 폭이 0이면 0을 반환(0 나눗셈 방어).
    public func progress(forTouchX x: CGFloat) -> Double
    /// 0...1 → 썸 중심 x(뷰 좌표)
    public func thumbCenterX(forProgress progress: Double) -> CGFloat
    /// 0...1 → 진행 레이어 폭
    public func progressWidth(forProgress progress: Double) -> CGFloat

    /// 0...1 + duration → CMTime. duration이 nil/0/indefinite면 nil.
    public static func time(forProgress progress: Double, duration: CMTime?) -> CMTime?
    /// CMTime + duration → 0...1(클램프). duration이 nil/0/indefinite면 nil.
    public static func progress(forTime time: CMTime, duration: CMTime?) -> Double?
}
```

### 5.4 `ABTimeFormatter` (**코어 `ABPlayerKit`, public**)

```swift
/// 재생 시각 문자열화. 상태 없는 네임스페이스 — 인스턴스를 만들지 않는다.
/// `DateComponentsFormatter`를 쓰지 않는 이유: 로케일에 따라 "1:00:00"이 아닌 형태가 나올 수 있고,
/// 재생 시간 표기는 로케일 무관 관례(H:MM:SS)를 따르는 편이 예측 가능하다.
public enum ABTimeFormatter {
    /// 0 → "0:00", 3599 → "59:59", 3600 → "1:00:00",
    /// 음수 → "0:00", NaN/infinity → "--:--"
    public static func string(from seconds: TimeInterval) -> String
    /// CMTime 편의 오버로드. indefinite/invalid → "--:--"
    public static func string(from time: CMTime) -> String
    /// 잔여 시간 레이아웃용 — "-3:33". current > duration이면 "-0:00". duration nil이면 "--:--"
    public static func remainingString(current: TimeInterval, duration: TimeInterval?) -> String
    /// duration이 없거나 indefinite일 때 총 시간 자리에 넣는 표시
    public static let liveMarker = "LIVE"
}
```

> **공개 API 안정성 약속.** 두 타입은 v0.2부터 semver 대상이다. 확장이 필요하면(예: 챕터 마커 좌표) **새 메서드 추가**로만 하고 기존 시그니처는 바꾸지 않는다.

---

## 6. 이벤트 흐름

### 6.1 스크러빙

```
  손가락 DOWN (썸 또는 트랙)
      │
      ├─ ABSeekBar → 히트 판정(thumbTouchInflation 포함)
      │
      ▼
  ABPlayerControlsView
      ├─ visibility.handle(.scrubBegan) ──▶ [.cancelAutoHide, (.show)]
      ├─ seekBar.setScrubbing(true)   ──▶ trackHeight/thumbSize 확대 애니메이션
      └─ player.beginScrubbing()
             ├─ isScrubbing = true
             ├─ broadcast(.scrubbingChanged(isScrubbing: true))
             └─ 주기 이벤트 방송 중단 (관찰자는 유지, 브로드캐스트만 게이팅)   ← T1
                    ※ 이유: 관찰자를 떼면 재개 시 첫 틱까지 interval만큼 공백이 생긴다.

  손가락 MOVE (60~120 Hz)
      │
      ▼
  ABSeekBar.progress = geometry.progress(forTouchX:)         ← UI는 즉시 갱신 (낙관적)
  timeLabel = ABTimeFormatter.string(from: 목표시각)           ← 라벨도 즉시
      │
      └─ player.scrub(to: t)              [비동기 아님 — 호출 비용 무시 가능]
             └─ coalescer.request(t, tolerance: config.scrubTolerance)
                    ├─ .issue(t) ──▶ Task { let landed = await target.seek(t, .coarse)
                    │                        broadcast(.seekCompleted(to: landed))
                    │                        switch coalescer.completed() {
                    │                          case .issue(next): ↻ 재귀 발행
                    │                          case .hold: 정지 }
                    └─ .hold  ──▶ pending = t   (직전 pending은 버려짐)          ← T2

  손가락 UP
      │
      ▼
  ABPlayerControlsView → Task { @MainActor in
      await player.endScrubbing()
             ├─ coalescer.flush(finalTolerance: .precise)
             │      └─ .issue(last) ──▶ await target.seek(last, .precise)
             │                          broadcast(.seekCompleted(to: landed))
             ├─ isScrubbing = false
             ├─ broadcast(.scrubbingChanged(isScrubbing: false))
             └─ 주기 방송 재개 + 즉시 1틱 broadcast(.periodicTime(...))          ← T7
      ├─ seekBar.setScrubbing(false)
      ├─ visibility.handle(.scrubEnded) ──▶ [.scheduleAutoHide]
      └─ observers ← .seekCommitted(to:)
  }
```

**왜 낙관적 UI인가.** 시크바 위치를 `.periodicTime` 왕복에 묶으면 손가락과 썸 사이에 항상 최소 1 seek 지연이 낀다. 드래그 중에는 UI가 진실이고, `endScrubbing` 완료 후 다시 엔진이 진실이 된다. 그 전환점에서 스냅백이 생기지 않도록 T1(스크럽 중 주기 이벤트 0회)과 T7(재개 순서)이 존재한다.

### 6.2 자동 숨김

```
  attach(player)
      └─ machine.handle(.attached(initial: config.initialVisibility))
             └─ [.show, .notifyVisibility(true), .scheduleAutoHide(3.0)]  (재생 중일 때)
                     │
                     ▼  Task.sleep(3.0) — hideTask에 보관
                 machine.handle(.autoHideFired) ──▶ [.hide, .notifyVisibility(false)]
                     └─ UIView.animate(duration: reduceMotion ? 0 : style.visibilityAnimationDuration) { alpha = 0 }
                        완료 후 isUserInteractionEnabled = false            ← 숨은 컨트롤이 탭을 먹지 않게

  ┌── 사용자가 화면 탭 (숨김 상태) ──────────────────────────┐
  │  배경 탭 인식기 → machine.handle(.tapped)                │
  │      └─ [.show, .notify(true), .scheduleAutoHide(3.0)]   │
  └──────────────────────────────────────────────────────────┘

  ┌── 재생/일시정지 버튼 탭 (표시 상태) ─────────────────────┐
  │  machine.handle(.controlInteracted) ──▶ [.cancelAutoHide,│
  │                                          .scheduleAutoHide]│  ← 숨기지 않는다
  │  player.play() / player.pause()                           │
  │      └─ .timeControlStatusChanged 이벤트 수신              │
  │             └─ machine.handle(.playbackStateChanged(...))  │
  │                    ├─ playing  → .scheduleAutoHide         │
  │                    └─ paused   → .cancelAutoHide (표시 유지)│
  └──────────────────────────────────────────────────────────┘

  스크러빙 중: .scrubBegan에서 .cancelAutoHide → 드래그가 아무리 길어도 안 사라짐  ← 브리프 요구
  detach / deinit: .detached → .cancelAutoHide, hideTask.cancel(), 토큰 전량 cancel
```

### 6.3 플레이어 → 컨트롤 이벤트 매핑

| `ABPlayerEvent` | 컨트롤 반응 |
|---|---|
| `.periodicTime(t)` | 스크러빙 중이면 무시(도달하지 않음). 아니면 시크바 progress/buffered/라벨 갱신 |
| `.timeControlStatusChanged(s)` | 재생/일시정지 아이콘 교체 + `machine.handle(.playbackStateChanged)` |
| `.rateChanged(r)` | 배속 라벨/메뉴 체크마크 갱신 |
| `.gradeChanged(_, to)` | `to != .current`면 전 컨트롤 비활성(`disabledTintColor`), 시크바 0으로 리셋 |
| `.itemDetached`, `.sourceChanged` | 시크바/라벨 리셋, duration 미상 상태로 |
| `.itemStatusChanged(.readyToPlay)` | duration 재조회 → 총 시간 라벨 확정, 컨트롤 활성 |
| `.failed` | 전 컨트롤 비활성. 에러 UI는 소비자 책임(컨트롤은 표시하지 않는다) |
| `.playedToEnd` | 재생 아이콘으로 복귀 + 컨트롤 강제 표시(`setVisible(true)`) |
| `.seekCompleted(t)` | 스크러빙이 아닌 경로(스킵 버튼 등)에서만 progress 즉시 반영 |
| `.playbackRejected` | 무시(로그 없음 — 코어 §6 원칙 4) |

### 6.4 라이브/미확정 duration 처리

`duration == nil`(indefinite)이면: 시크바는 **표시하되 드래그 비활성**, progress는 0으로 고정, 버퍼 바만 그린다. 총 시간 라벨 자리에 `ABTimeFormatter.liveMarker`("LIVE"). 스킵 버튼은 하한(0)만 클램프하고 유지한다.

---

## 7. MainActor · 수명 규칙 (프로젝트 규약 준수 확인)

| 항목 | 규칙 |
|---|---|
| `MainActor.assumeIsolated` | **0건.** `addPeriodicTimeObserver`의 큐 콜백도 값만 캡처해 `Task { @MainActor }`로 홉한다. |
| 타임스탬프 캡처 | 주기 이벤트는 TTFF가 아니므로 `CACurrentMediaTime()` 즉시 캡처 규칙 대상 아님. 다만 홉 후 **아이템 동일성 재검증**(`avPlayerItem === capturedItem`)은 §3 규칙대로 수행한다. |
| 주기 관찰자 해제 | `detachItem`/`releasePlayer`/등급 강등/`periodicTimeInterval = nil`/`deinit` 5경로 전부에서 `removeTimeObserver`. AVPlayer 폐기 전 제거 보장(T3). |
| 컨트롤 뷰 토큰 | `player` didSet에서 이전 토큰 cancel → 새로 등록(ABPlayerView와 동일 순서). `deinit`에서 전량 cancel + hideTask cancel. |
| 컨트롤 → 플레이어 참조 | `weak` 아님(뷰가 플레이어를 소유하지 않지만 강참조는 소비자 기대에 맞음 — `ABPlayerView.player`와 동일 규약). 관찰 클로저 내부는 `[weak self, weak player]` + 동일성 가드. |
| `print`/`NSLog` | 0건. |
| 순수 타입 격리 | `ABSeekCoalescer`, `ABControlsVisibilityMachine`, `ABSeekBarGeometry`, `ABTimeFormatter`, `ABPlaybackTime`, `ABSeekTolerance`, `ABPlaybackRate` — 전부 `nonisolated` + `Sendable`(가능한 범위). |

---

## 8. 테스트 계획

PLANNING §7 규약: `@Suite`는 **시나리오 단위**, 테스트 이름은 Given-When-Then 서술.

### 8.1 `ABPlayerKitTests` — 신규/확장 스위트

**`@Suite("Playback rate survives pause, resume, and grade round-trips")`**
- 정지 중 `setRate(1.5)`는 target에 play를 발행하지 않는다
- 재생 중 `setRate(2.0)`는 즉시 target rate에 반영된다
- `play()`는 `configuration.playbackRate`로 재생을 시작한다 (T4)
- `pause()` → `play()` 후 rate가 유지된다 (T5)
- `.current` → `.preloaded` → `.current` 왕복 후 rate가 유지된다 (T5)
- 범위 밖 값(0, -1, 99)은 `ABPlaybackRate.allowedRange`로 클램프되고 클램프된 값이 `.rateChanged`에 실린다
- 같은 값 재설정은 `.rateChanged`를 방송하지 않는다
- `grade != .current`에서 `setRate`는 `.playbackRejected`를 방송하지 않는다
- `configuration.playbackRate` 직접 대입도 `setRate`와 동일 경로를 탄다

**`@Suite("Skip clamps to the playable range")`**
- `skip(by: +10)`은 `currentTime + 10`으로 이동한다
- 끝에서 `skip(by: +10)`은 `duration`으로 클램프된다 (T6)
- 시작에서 `skip(by: -10)`은 `.zero`로 클램프된다 (T6)
- `duration == nil`(라이브)에서 전진 스킵은 상한 클램프 없이 발행된다
- `duration == nil`에서 후진 스킵은 0 하한만 적용된다
- `grade != .current`에서 스킵은 `.playbackRejected` 후 seek을 발행하지 않는다
- 스킵 연타 5회는 target seek을 5회 큐잉하지 않는다(코얼레싱 경유)

**`@Suite("Scrubbing coalesces seeks and never issues a stale target")`**
- `request` 3연타 → 발행 1회 + pending 1개(가장 최근), 중간 목표는 소멸 (T2)
- `completed()`는 pending을 발행하고 pending을 비운다
- pending 없는 `completed()`는 `.hold`를 반환한다
- `flush(.precise)`는 마지막 목표를 precise로 발행한다
- `flush` 시 진행 중 seek이 있으면 완료 후 최종 seek이 이어진다
- `reset()` 후 늦게 도착한 `completed()`는 아무것도 발행하지 않는다
- `beginScrubbing` 없이 `scrub(to:)`를 부르면 단발 coarse seek으로 동작한다
- `beginScrubbing` 중복 호출은 no-op이며 `.scrubbingChanged`를 두 번 방송하지 않는다

**`@Suite("Periodic time observation is opt-in and pauses during scrubbing")`**
- `periodicTimeInterval == nil`이면 관찰자가 설치되지 않는다 (v0.1 동작 유지)
- 간격을 설정하고 `.current`로 승격하면 관찰자가 설치된다
- `beginScrubbing`~`endScrubbing` 사이 tick은 `.periodicTime`을 방송하지 않는다 (T1)
- `endScrubbing` 후 즉시 1틱이 방송되고 순서는 `.seekCompleted` → `.scrubbingChanged(false)` → `.periodicTime` (T7)
- `.current` → `.preloaded` 강등 시 관찰자가 제거된다 (T3)
- `release()` 시 관찰자가 AVPlayer 폐기 **전에** 제거된다 (T3)
- `periodicTimeInterval`을 nil로 바꾸면 관찰자가 즉시 제거된다
- 소스 교체 시 관찰자가 새 아이템 기준으로 재설치된다

**`@Suite("ABPlaybackTime derives progress safely")`** (순수)
- `duration == nil` → `progress == nil`, `bufferedProgress == nil`
- `duration == .zero` → `progress == nil` (0 나눗셈 방어)
- `currentTime > duration` → progress는 1.0으로 클램프
- `bufferedUntil`이 `currentTime`보다 작으면 `bufferedProgress`는 progress 미만이 아니라 그대로 노출(가공하지 않음)
- indefinite duration은 `nil`로 정규화된다

**`@Suite("Seek tolerance maps to AVFoundation tolerances")`**
- `.precise` → before/after == `.zero`
- `.coarse(a, b)` → 그대로 전달
- `.nearest` → `.positiveInfinity`

**`@Suite("Seek bar geometry maps touches to progress")`** (순수 — Q9 수정안으로 코어 이관)
- 트랙 왼쪽 끝 터치 → 0.0, 오른쪽 끝 → 1.0 (썸 반폭 보정 포함)
- 트랙 밖 터치는 0...1로 클램프된다
- `trackWidth == 0`, `trackWidth == thumbWidth`에서 0 나눗셈이 나지 않는다
- `thumbWidth == 0`(숏폼 슬림 시크바)에서도 양 끝이 0/1에 정확히 도달한다
- progress ↔ thumbCenterX 왕복이 항등이다
- `horizontalInset`이 있어도 좌우 끝이 0/1에 도달한다
- `duration == nil` / `.zero` / indefinite면 `time(forProgress:)`가 nil이다
- `time(forProgress:)` ↔ `progress(forTime:)` 왕복이 항등이다
- `currentTime > duration`이면 `progress(forTime:)`가 1.0으로 클램프된다

**`@Suite("Time labels format every duration shape")`** (순수 — Q9 수정안으로 코어 이관)
- 0 → "0:00", 59 → "0:59", 60 → "1:00", 3599 → "59:59", 3600 → "1:00:00"
- 음수 → "0:00"
- NaN / infinity → "--:--"
- `CMTime` 오버로드: invalid / indefinite → "--:--"
- remaining: current 12 / duration 225 → "-3:33"
- remaining에서 current > duration → "-0:00"
- remaining에서 duration == nil → "--:--"

### 8.2 `ABPlayerKitControlsTests` — 신규 타겟

**`@Suite("Controls auto-hide follows playback and scrubbing state")`** (순수 머신, 시간 의존 0)
- §5.2 규칙표 13행을 1:1 케이스로 전수
- 스크러빙 중 도착한 `.autoHideFired`는 무시된다
- 일시정지 중 `staysVisibleWhilePaused == true`면 자동 숨김이 걸리지 않는다
- `staysVisibleWhilePaused == false`면 일시정지 중에도 숨김 타이머가 걸린다
- `autoHideDelay == nil`이면 어떤 입력에도 `.scheduleAutoHide`가 나오지 않는다
- `.setVisible(현재값)`은 빈 이펙트를 반환한다(중복 notify 없음)
- `.detached`는 항상 `.cancelAutoHide`를 포함한다

> `ABSeekBarGeometry`·`ABTimeFormatter` 스위트는 Q9 수정안에 따라 **`ABPlayerKitTests`(§8.1)로 이관**했다. 컨트롤 타겟은 이 둘을 `import ABPlayerKit`으로 쓰고 별도로 테스트하지 않는다.

**`@Suite("Style changes apply without recreating the view")`** (MainActor 뷰 테스트)
- 색상만 바꾸면 `setNeedsLayout`이 호출되지 않는다
- `trackHeight` 변경은 레이아웃을 무효화한다
- 아이콘을 `.image(_)`로 바꾸면 버튼 이미지가 교체된다
- `.none` 아이콘은 해당 버튼을 숨긴다
- `skipInterval = 15` + `synchronizesSkipIconWithInterval` → `goforward.15`가 선택된다
- `skipInterval = 7`(심볼 없음) → 기본 10 심볼로 폴백하고 크래시하지 않는다
- style에서 스킵 아이콘을 명시하면 자동 동기화보다 우선한다

**`@Suite("Controls attach and detach without leaking observation")`**
- 부착 시 플레이어의 `periodicTimeInterval`이 config 값으로 설정된다
- 해제 시 **부착 이전 값으로 복원**된다
- 플레이어 교체 시 이전 플레이어에 이벤트를 보내도 UI가 반응하지 않는다
- 뷰 deinit 후 플레이어 이벤트 방송이 크래시하지 않는다(토큰 전량 해제)
- `accessoryViews` 교체가 기존 제약을 남기지 않는다

**`@Suite("Controls reflect engine events")`**
- `.timeControlStatusChanged(.playing)` → pause 아이콘 표시
- `.gradeChanged(to: .preloaded)` → 전 컨트롤 비활성 + 시크바 리셋
- `.rateChanged(1.5)` → 배속 라벨 "1.5×"
- `.playedToEnd` → play 아이콘 + 컨트롤 강제 표시
- duration indefinite → 시크바 드래그 비활성 + "LIVE" 라벨

### 8.3 데모 앱 검증 (수동/XCUITest — 유닛으로 못 잡는 것)

| 항목 | 확인 |
|---|---|
| 스크럽 추종성 | 120Hz 드래그에서 썸이 손가락을 벗어나지 않음, 놓는 순간 스냅백 없음 |
| 배속 | 1.5× 재생 → 일시정지 → 재생 시 배속 유지, HLS/MP4 양쪽 |
| 버퍼 바 | 셀룰러 스로틀 조건에서 버퍼 구간이 실제로 자란다 |
| 자동 숨김 | 3초 후 숨김, 드래그 5초 동안 유지, 일시정지 중 유지 |
| 접근성 | VoiceOver로 시크바 조정(Adjustable), Dynamic Type에서 라벨 잘림 없음, Reduce Motion에서 페이드 없음 |
| 배터리 | `periodicTimeInterval = 0.25`에서 유휴 CPU 증가가 무시 가능한 수준인지 Instruments 확인 |

---

## 9. 접근성 (구현 필수, 별도 감사 대상)

- 모든 버튼: `accessibilityLabel`(현지화 문자열, en/ko), `accessibilityTraits = .button`, 히트 영역 ≥ 44×44
- 재생/일시정지 버튼: 상태에 따라 label 교체("재생"/"일시정지")
- 시크바: `accessibilityTraits = .adjustable`, `accessibilityValue = "3분 45초 중 1분 12초"`, `accessibilityIncrement/Decrement`가 `skipInterval`만큼 이동
- 배속 버튼: `accessibilityValue = "1.5배"`
- 자동 숨김: VoiceOver 실행 중이면 **자동 숨김을 하지 않는다**(`UIAccessibility.isVoiceOverRunning`) — 사라진 컨트롤을 VoiceOver로 되찾을 방법이 없다
- `style.respectsReduceMotion == true`이면 `UIAccessibility.isReduceMotionEnabled`일 때 전이 duration 0
- Dynamic Type: 시간 라벨 폰트는 `UIFontMetrics`로 스케일(기본 style은 고정 크기 — 프리셋 `.default`는 고정, 소비자가 스케일 폰트를 주입 가능)

---

## 10. 구현 태스크 분해 (순서 있는 커밋)

각 커밋은 **빌드 성공 + 경고 0 + 기존 테스트 전량 통과**를 만족해야 한다. 커밋 메시지는 영어 Conventional Commits.

### Phase A — 엔진 (코어 타겟)

| # | 커밋 | 내용 | 테스트 |
|---|---|---|---|
| A1 | `feat: add ABSeekTolerance and ABPlaybackRate value types` | 순수 타입 2개 + 프리셋 | 톨러런스 매핑, 클램프 |
| A2 | `feat: add ABPlaybackTime with safe progress derivation` | 순수 타입 + progress/bufferedProgress | `ABPlaybackTime` 스위트 |
| A3 | `feat: add ABSeekCoalescer state machine` | 순수 코얼레서(아직 미사용, internal) | 코얼레서 스위트 전수 |
| **A4** | **`feat: add public ABSeekBarGeometry and ABTimeFormatter`** | **코어 `Presentation/` 신규 디렉터리 + 두 public 순수 타입 (Q9 수정안). 컨트롤/ABShortsKit 공용 기반이므로 컨트롤 타겟보다 먼저 만든다** | **지오메트리·포맷터 스위트 (`ABPlayerKitTests`)** |
| A5 | `feat: expose playback rate on ABPlayer` | config `playbackRate` + `setRate` + `.rateChanged` + target `setRate`/`play` 수정 + fake 확장 | 배속 스위트 |
| A6 | `feat: add tolerance-aware seek and skip(by:)` | `seek(to:tolerance:)`, `skip(by:)`, target seek 시그니처 변경 | 스킵 스위트 |
| A7 | `feat: add scrubbing API backed by seek coalescing` | `beginScrubbing`/`scrub`/`endScrubbing`/`isScrubbing` + `.scrubbingChanged`/`.seekCompleted` | 스크러빙 스위트 |
| A8 | `feat: add opt-in periodic time observation` | config `periodicTimeInterval`, target 주기 관찰, `bufferedUntil`, `.periodicTime`, 스크럽 중 게이팅, 전 해제 경로 | 주기 스위트 (T1/T3/T7) |
| A9 | `docs: document v0.2 engine additions` | DocC 심볼 주석 + `ABPlayerKit.md` Topics에 신규 타입 추가(`ABPlaybackTime`, `ABSeekTolerance`, `ABPlaybackRate`, **`ABSeekBarGeometry`, `ABTimeFormatter`**) + Scrubbing 섹션 | — |

### Phase B — 컨트롤 타겟 골격

| # | 커밋 | 내용 | 테스트 |
|---|---|---|---|
| B1 | `feat: add ABPlayerKitControls target scaffold` | Package.swift 타겟/프로덕트/테스트타겟, 빈 DocC | 빈 스위트 1개(링크 확인) |
| B2 | `feat: add ABPlayerControlsStyle and ABControlIcon` | 스타일 구조체 전 필드 + 프리셋 3종 | 기본값 스냅샷, 프리셋 동등성 |
| B3 | `feat: add ABPlayerControlsConfiguration and ABControlsEvent` | 동작 설정 + 이벤트 enum | 기본값 검증 |
| B4 | `feat: add ABControlsVisibilityMachine` | 순수 자동 숨김 머신 | 규칙표 전수 |

> 초안의 `B5: feat: add seek bar geometry and time formatter`는 **A4로 이동**했다(Q9 수정안 — 코어 public).

### Phase C — 컨트롤 뷰

| # | 커밋 | 내용 | 테스트 |
|---|---|---|---|
| C1 | `feat: add ABControlButton with style-driven icons` | 아이콘 해석(심볼/이미지/none), 히트 영역 확장, 하이라이트 | 아이콘 스위트 |
| C2 | `feat: add ABSeekBar with buffered track and draggable thumb` | 트랙/버퍼/진행/썸 레이어, 드래그 제스처, 트랙 탭, 스크럽 확대 | 지오메트리 연동, 드래그 시뮬레이션 |
| C3 | `feat: add ABPlayerControlsView layout and engine binding` | 스택 레이아웃, 플레이어 관찰 배선, 이벤트 매핑(§6.3), 컨트롤 활성/비활성 | 부착/해제, 이벤트 반영 스위트 |
| C4 | `feat: wire auto-hide and scrubbing into ABPlayerControlsView` | 머신 연결, hideTask 수명, 배경 탭 | 자동 숨김 통합 |
| C5 | `feat: add playback rate menu and cycle interactions` | UIMenu / 순환 / hidden 3모드, 라벨 갱신 | 배속 상호작용 |
| C6 | `feat: add controls background styles` | none/color/gradient/blur + 교체 시 서브뷰 정리 | 배경 교체 |
| C7 | `feat: apply style changes live without view recreation` | didSet 차분 적용(§4.1 표) | 라이브 갱신 스위트 |
| C8 | `feat: add accessibility support to controls` | §9 전 항목 + VoiceOver 자동숨김 억제 | 라벨/값/트레잇 |

### Phase D — SwiftUI · 문서 · 데모

| # | 커밋 | 내용 |
|---|---|---|
| D1 | `feat: add ABPlayerControls SwiftUI wrapper` | `UIViewRepresentable` + 차분 업데이트 |
| D2 | `feat: add ABVideoPlayerWithControls convenience view` | ZStack 조립 |
| D3 | `docs: add ABPlayerKitControls DocC catalog` | Overview + Topics + 커스터마이징 가이드 |
| D4 | `docs: document controls layer in README (en/ko)` | 설치(타겟 선택), 최소 예제, 스타일 커스터마이징 예제, 타겟 분리 근거 |
| D5 | `feat: showcase controls in the demo app` | 데모에 컨트롤 화면 + 스타일 프리셋 토글 + 배속/스크럽 시연 |
| D6 | `chore: release v0.2.0` | CHANGELOG(신규 enum 케이스 주의 문구 + 신규 public 타입 2종 포함), 태그 |

**의존 관계.**
- A1·A2·A3·A4는 서로 독립(전부 순수 타입) — 병렬 가능
- A5~A8은 순차 (각각 `ABPlaybackTarget` 프로토콜과 fake를 건드림)
- B1~B4는 A와 병렬 가능 (B는 순수 타입/설정만)
- **C2(`ABSeekBar`)는 A4에 의존** — 지오메트리 없이는 만들 수 없다
- **C3은 A4·A8에 의존** — 시간 라벨(포맷터)과 주기 이벤트가 필요하다
- C1·C2 병렬, C3부터 순차
- D는 C 완료 후

**총 27커밋** — A(엔진) 9 · B(컨트롤 골격) 4 · C(컨트롤 뷰) 8 · D(SwiftUI·문서·데모) 6.

---

## 11. 내가 직접 결정한 사항과 근거

| 결정 | 근거 |
|---|---|
| 컨트롤을 별도 타겟 `ABPlayerKitControls`로 | 코어 설계서가 컨트롤 UI를 명시적 비목표로 선언했고, 숏폼 소비자는 이 코드를 링크할 이유가 없다(§2.1) |
| `ABSeekBarGeometry`·`ABTimeFormatter`만 코어 public으로 승격 (사용자 수정안) | ABShortsKit v0.2가 숏폼 제스처 UI에서 재사용한다. 컨트롤 타겟에 두면 숏폼이 안 쓰는 시크바 뷰·배속 메뉴까지 링크하게 되어, 타겟을 분리한 이유가 반대 방향으로 재발한다(§2.3) |
| SwiftUI 래퍼는 컨트롤 타겟 안에 | §2 "래퍼는 자기 코어와 같은 타겟" 방침 일관 적용 |
| `rate`를 `configuration.playbackRate`에 | `isMuted`/`isLooping`이 이미 그 경로를 쓴다. 새 상태 채널을 만들면 `applyConfigurationChange`와 이중 진실이 생긴다 |
| `play()`가 배속을 복원 | AVPlayer `play()`의 rate=1.0 강제를 그대로 노출하면 소비자가 매번 재설정해야 한다 |
| `setRate`를 등급 게이트에서 제외 | 배속은 재생 명령이 아니라 설정값. 프리로드 셀에 미리 걸 수 있어야 한다 |
| 스크럽 코얼레싱을 **엔진**에 | 컨트롤에 두면 UIKit/SwiftUI 두 벌 중복 + 테스트가 UI에 묶인다. 코어 소비자(자체 UI 제작)도 혜택 |
| 스크럽 중 `.periodicTime` **방송만** 게이팅(관찰자 유지) | 관찰자를 떼면 재개 시 interval만큼 공백이 생겨 놓는 순간 썸이 멈춰 보인다 |
| 버퍼 구간을 별도 이벤트가 아닌 `ABPlaybackTime` 필드로 | 버퍼 바와 진행 바는 항상 같은 프레임에 그려진다. 이벤트를 쪼개면 소비자가 두 값을 직접 동기화해야 한다 |
| `seek(to:tolerance:)` 오버로드(기본 인자 아님) | `seek(to:precise: Bool = true)`는 기존 `seek(to:)`와 호출부 모호성/의도 불명확을 만든다. 별도 시그니처가 additive하고 읽힌다 |
| 자동 숨김을 순수 머신 + 뷰 소유 타이머로 분리 | 시간 의존 없는 결정적 테스트. 브리프의 "가능하면 순수 타입으로" 요구 충족 |
| 낙관적 시크바 UI (드래그 중 UI가 진실) | seek 왕복을 기다리면 썸이 손가락에 지연된다. 전환점 글리치는 T1/T7로 방어 |
| 스타일(외형)과 설정(동작)을 두 구조체로 분리 | 테마는 디자인 시스템이 주입하고 동작은 화면이 정한다 — 수명이 다르다. 하나로 합치면 테마 교체가 동작까지 덮어쓴다 |
| 아이콘을 `ABControlIcon` enum으로 | SF Symbol 이름 문자열만 받으면 커스텀 이미지가 불가능, `UIImage`만 받으면 심볼 설정(pointSize/weight)이 죽는다 |
| VoiceOver 실행 중 자동 숨김 억제 | 사라진 컨트롤을 VoiceOver로 되찾을 수단이 없다. 접근성 회귀를 코드로 봉쇄 |
| 에러 UI를 컨트롤이 그리지 않음 | 코어 §6 원칙(실패는 이벤트) 유지. 재시도 UX는 앱마다 다르다 |
| `accessoryViews` 슬롯만 제공(전체화면/PiP 버튼 미구현) | v0.2 범위 밖이지만 확장 지점을 막지 않기 위한 최소 장치 |

---

## 12. 쟁점 Q9~Q15 — ✅ 전부 확정 (사용자 승인, 2026-08-04)

| # | 쟁점 | 확정 | 비고 |
|---|---|---|---|
| Q9 | 컨트롤 타겟 분리 | **A** — 신규 `ABPlayerKitControls` 타겟 | 추천안 채택 + **수정안 1건**: `ABSeekBarGeometry`·`ABTimeFormatter`는 코어 `ABPlayerKit`의 public API로 승격 (§2.3) |
| Q10 | `ABPlayerEvent` 케이스 추가 | **A** — 그대로 추가, 비전수(non-exhaustive) 취급 규약을 README·DocC·CHANGELOG 3곳에 명시 | 추천안 채택 |
| Q11 | 주기 관찰 활성화 주체 | **A** — 컨트롤 뷰가 부착 시 설정, 해제 시 이전 값 복원 | 추천안 채택 |
| Q12 | 배속 ≠ 1일 때 preroll rate | **A** — `prerollRate`를 문자 그대로 유지, 배속 비연동 | 추천안 채택 |
| Q13 | 스타일의 `Sendable` | **A** — 채택 시도 후 Swift 6 경고 시 `Equatable`만 유지. `@unchecked Sendable` 금지 | 추천안 채택 |
| Q14 | 컨트롤 구현 스택 | **A** — UIKit 코어 + SwiftUI 래퍼 | 추천안 채택 |
| Q15 | 기본 `periodicTimeInterval` | **A** — 0.25초 | 추천안 채택 |

### 확정이 설계에 미치는 영향
- **Q9 수정안**: 코어에 `Presentation/` 디렉터리 신설, public 타입 2개 추가(§2.2·§2.3·§5.3·§5.4). 테스트는 `ABPlayerKitTests`로 이관(§8.1). 태스크 B5 → A4로 이동, C2·C3이 A4에 의존(§10). 코어 DocC Topics에 두 타입 추가.
- **Q10**: `CHANGELOG.md`에 breaking-ish 주의 문구 필수. DocC `ABPlayerEvent` 심볼 주석에 "새 케이스가 마이너 버전에서 추가될 수 있으므로 `default`를 두라" 명시.
- **Q11**: `ABPlayerControlsView`가 `previousPeriodicTimeInterval`을 보관. 테스트 `부착 이전 값으로 복원된다`가 게이트.
- **Q15**: `ABPlayerControlsConfiguration.periodicTimeInterval` 기본값 0.25. Phase 5에서 Instruments 실측치를 README에 기재.

<details>
<summary>원본 쟁점 서술 (선택지·근거 — 결정 이력 보존용)</summary>

> `DESIGN-OPEN-QUESTIONS.md`의 Q1~Q8에 이어 번호를 매긴다.

### Q9. 컨트롤 타겟 분리를 확정하는가

| 선택지 | 내용 | 비용/위험 |
|---|---|---|
| **A** | 신규 타겟 `ABPlayerKitControls` | import 1개 추가. 타겟 4개 |
| B | 코어 `ABPlayerKit`에 포함 | import 1개로 끝. 대신 숏폼 소비자가 UI 코드를 강제 링크하고, 코어 설계서 §1의 비목표 선언을 뒤집어야 함 |
| C | 별도 레포 `ABPlayerKitControls` | 독립 스타/버전. 대신 코어와 버전 동기화 부담 + 데모 앱이 레포 2개를 의존 |

**추천: A.** 근거 — (1) 코어 설계서가 이미 공개 문서로 컨트롤을 비목표라 선언했고 이를 뒤집으면 문서 신뢰도가 깎인다, (2) Metrics/Cache 분리와 같은 축(옵트인 링크)이라 포트폴리오 서사가 일관된다, (3) C는 v0.2 규모에 비해 릴리스 오버헤드가 과하다.

### Q10. `ABPlayerEvent`에 케이스 4개 추가 — 소스 호환 파괴를 감수하는가

전수 `switch`하는 소비자는 재컴파일 시 에러가 난다(바이너리 호환 문제는 없음).

| 선택지 | 내용 |
|---|---|
| **A** | 그대로 추가. CHANGELOG와 README에 "`ABPlayerEvent`는 비전수(non-exhaustive)로 취급하고 `default`를 두라"고 명시. 0.x semver 범위 |
| B | 신규 이벤트를 별도 enum(`ABPlaybackProgressEvent`)으로 분리하고 별도 등록 메서드 제공 | 기존 switch 무사. 대신 이벤트 채널이 2개가 되어 §5.4의 "단일 이벤트 스트림" 설계가 깨짐 |
| C | `.periodicTime`만 별도 채널, 나머지 3개는 기존 enum에 | 절충안이지만 분리 기준이 자의적 |

**추천: A.** 근거 — 0.1.0 공개 후 며칠 된 라이브러리이고 외부 소비자가 사실상 데모뿐이다. 지금 문서로 규약(비전수 취급)을 못 박는 비용이, 영구히 이벤트 채널 2개를 유지하는 비용보다 훨씬 싸다. 다만 **README/DocC/CHANGELOG 세 곳에 명시**하는 것을 조건으로 한다.

### Q11. 주기 시간 관찰을 누가 켜는가

| 선택지 | 내용 |
|---|---|
| **A** | `configuration.periodicTimeInterval`이 스위치. 컨트롤 뷰가 부착 시 자기 값으로 덮어쓰고 해제 시 이전 값 복원 | 설정 소유권이 1곳. 단 컨트롤이 소비자 설정을 잠시 바꾼다(복원은 보장) |
| B | 엔진에 참조 카운트 API 추가: `player.addPeriodicTimeObserver(interval:) -> ABObservationToken` | 소비자 설정을 건드리지 않음. 대신 관찰 API가 2종(설정 기반 + 토큰 기반)이 되고, 서로 다른 interval 요청의 병합 규칙(최소값 채택?)을 정의해야 함 |
| C | 컨트롤이 켜지 않는다 — 소비자가 직접 `periodicTimeInterval`을 설정해야 시크바가 움직인다 | 가장 정직. 대신 "시크바가 안 움직여요" 이슈가 확정적으로 발생 |

**추천: A.** 근거 — 브리프가 "기존 옵저버 시스템으로 전달"을 명시했고, B는 사실상 두 번째 관찰 채널을 만든다(Q10에서 피하려는 것과 같은 문제). A의 유일한 위험인 "복원 실패"는 테스트 1개(`부착 이전 값으로 복원된다`)로 봉쇄된다.

### Q12. 배속 ≠ 1일 때 preroll rate

| 선택지 | 내용 |
|---|---|
| **A** | `configuration.prerollRate`를 문자 그대로 사용(현행 유지). 배속과 무관 |
| B | `prerollRate == 1.0`(기본값)이면 `playbackRate`를 따라간다 | 2× 재생 중 프리로드 셀 승격 시 재프리롤 비용 절감. 대신 "기본값일 때만 자동"이라는 조건부 규칙이 API 주석 없이는 이해 불가 |
| C | `prerollRate`에 `.matchesPlaybackRate` 센티널 케이스 추가 | 명시적이고 선택 가능. 대신 `Float?`를 enum으로 바꾸는 **파괴적 변경** |

**추천: A.** 근거 — 배속 재생은 소수 사용 경로이고, 재프리롤 비용은 측정된 적이 없다. 측정 없이 API를 복잡하게 만들지 않는다(§6 "측정 근거 없이는 정하지 않는다"). Phase 5 벤치마크에서 2× 승격 지연이 실제로 관측되면 v0.3에서 C를 고려한다.

### Q13. `ABPlayerControlsStyle`의 `Sendable` 채택

| 선택지 | 내용 |
|---|---|
| **A** | `Sendable` 채택을 시도하고, Swift 6에서 경고가 나면 떼고 `Equatable`만 유지 | 정직. 타입은 MainActor에서만 읽히므로 실질 손실 없음 |
| B | `@unchecked Sendable` 고정 | 항상 컴파일됨. 대신 검증되지 않은 주장을 코드에 박는 것 — 프로젝트가 `MainActor.assumeIsolated`를 금지한 것과 같은 이유로 부적절 |
| C | 색을 `UIColor` 대신 자체 `ABColor`(RGBA 값 타입)로 | 완전 Sendable + 플랫폼 중립. 대신 소비자가 `UIColor`를 매번 변환해야 하고 다이나믹 컬러(다크모드 자동 대응)를 잃는다 |

**추천: A.** C는 다이나믹 컬러 손실이 치명적이다(라이트/다크 자동 대응이 안 됨). B는 프로젝트 규약 위반.

### Q14. 컨트롤을 SwiftUI 네이티브로 다시 쓸 것인가

| 선택지 | 내용 |
|---|---|
| **A** | UIKit 코어 + SwiftUI 래퍼 (기획 확정 방식) | PLANNING §2 기술 스택과 일치. UIKit 소비자도 그대로 사용 |
| B | SwiftUI 네이티브 구현 + UIKit `UIHostingController` 래핑 | 선언적 스타일링이 자연스러움. 대신 기획 스택 역전 + UIKit 소비자가 호스팅 오버헤드를 짐 |
| C | 두 벌 구현 | 각 스택에 최적. 유지보수 2배 — 기각 |

**추천: A.** 브리프가 "UIKit 코어 + SwiftUI 래퍼, 기존 라이브러리 컨벤션"을 명시했으므로 확인 목적의 질문이다. 다만 **드래그 제스처 정밀도**(UIPanGestureRecognizer vs SwiftUI DragGesture)에서 A가 유리하다는 점도 근거에 추가한다.

### Q15. 기본 `periodicTimeInterval` 값

| 선택지 | 내용 |
|---|---|
| **A** | 0.25초 | 3pt 트랙에서 계단 거의 안 보임. 배터리 영향 무시 가능 |
| B | 1/30초(0.033) | 완전히 매끄러움. 초당 30회 MainActor 방송 — 숏폼 피드에서 플레이어 3개면 90회/초 |
| C | 1.0초 | 배터리 최적. 진행바가 눈에 띄게 튄다 |

**추천: A(0.25).** 다만 컨트롤 설정으로 노출되어 있으므로 소비자가 조절 가능하고, Phase 5에서 Instruments로 실측해 README에 수치를 싣는다.

</details>

---

## 13. 문서 산출물 체크리스트

- [ ] `Sources/ABPlayerKit/ABPlayerKit.docc/ABPlayerKit.md` — Topics에 `ABPlaybackTime`, `ABSeekTolerance`, `ABPlaybackRate` 추가 + **"Building Custom UI" 섹션에 `ABSeekBarGeometry`, `ABTimeFormatter`** + "Scrubbing" 섹션
- [ ] `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/ABPlayerKitControls.md` — Overview / Getting Started / Customizing Appearance / Auto-Hide Behavior
- [ ] `README.md` / `README.ko.md` — 타겟 4개 표 갱신, 컨트롤 최소 예제(UIKit·SwiftUI 각 1개), 스타일 커스터마이징 예제(뒷편색/앞편색/썸 크기·색/아이콘 교체), 타겟 분리 근거 1문단
- [ ] `CHANGELOG.md` — v0.2.0: 엔진 추가 API, 신규 타겟, 신규 public 타입 2종, **`ABPlayerEvent` 비전수 취급 주의**
- [x] `docs/DESIGN-OPEN-QUESTIONS.md` — Q9~Q15 확정 결정 기록 완료 (2026-08-04)
- [ ] `Examples/` 데모 — 컨트롤 화면 + 스타일 프리셋 토글

---

## 14. Bottom-Bar Rework & 리뷰 라운드 2 결정 기록 (2026-08-04)

> `FINAL-VERDICT APPROVE` 이후 `docs/BRIEF-bottombar.md` 요청분(레이아웃 개편·시간 포맷·프로모션 동작)과 그에 대한 리뷰 라운드 2(`FIX-REQUIRED`, B1/M1/M2/M3 + m1/m5)에서 확정된 사항. §12(Q9~Q15)와 동일한 형식으로 남긴다 — 이번 라운드에 이 문서가 갱신되지 않은 것 자체가 리뷰의 지적 사항(§B, 프로세스)이었다.

| # | 결정 | 내용 | 근거 |
|---|---|---|---|
| R1 | 하단 클러스터 레이아웃 전면 개편 | 시크바가 오버레이 전체 폭을 균등 여백으로 채우고, 그 바로 아래(시각적 트랙 기준 10pt) 압축된 행에 경과/전체 시간 라벨(좌)과 배속 버튼(우)을 배치한다. 44pt 접근성 터치 영역은 유지하되 시각 요소보다 위/아래로 넓게 확장되며, 겹치는 영역에서는 `hitTest(_:with:)`의 명시적 우선순위 목록(구체적 컨트롤 → `accessoryViews` → 시크바 순)이 항상 더 구체적인 컨트롤을 우선한다 | 사용자 피드백: 이전 레이아웃은 시크바가 중앙에 붕 떠 보이고 시간 라벨/시크바 사이 간격이 과했다 |
| R2 | `ABPlayerControlsConfiguration.timeFormat: TimeLabelFormat` 추가 | `.automatic`(MM:SS/HH:MM:SS 자동 전환), `.fixedHours`(항상 HH:MM:SS — **기본값**, 기존 동작 유지), `.custom((TimeInterval, TimeInterval?) -> String)`. 기본값을 `.fixedHours`로 둔 것은 기존 v0.2 릴리스의 시각적 동작을 하위 호환으로 보존하기 위함 | 사용자 피드백: 시간 포맷을 소비자가 고를 수 있어야 함 |
| R3 | `ABPlayerControlsConfiguration.skipInterval` 클램프 규칙 확정 | 5초 단위, `5...60` 범위로 클램프(반올림 후 clamp). SF Symbol이 있는 값(5/10/15/30/45/60)은 `gobackward.N`/`goforward.N`을 직접 쓰고, 없는 값(20/25/35/40/50/55)은 일반 화살표 아이콘 위에 숫자를 합성해(`ABControlButton.applySkip`) 렌더한다 | 사용자 피드백: 스킵 간격이 가변인데 아이콘 숫자가 항상 10으로 고정되어 있었음 |
| R4 | `ABPlayerControlsConfiguration.promotesToCurrentOnPlay: Bool = true` 추가 | 플레이어가 소스는 있지만 `.current`가 아닐 때 재생/일시정지 버튼만 예외적으로 탭 가능 상태를 유지하고, 탭 시 `player.promote(to: .current)`를 `play()` 앞에 호출한다. 탐색/스킵/배속은 여전히 `.current`가 될 때까지 비활성 상태를 유지한다 — §6.3이 규정한 "`grade != .current` → 컨트롤 비활성" 규칙에 대한 **유일한 예외**다 | 사용자 피드백: 프리로드 상태로 시작한 플레이어의 오버레이가 첫 실행 시 완전히 죽어 있었고, 데모 앱이 자체적으로 우회 구현하고 있던 동작을 라이브러리가 직접 제공해야 함 |
| R5 | `ABTimeFormatter.string(from:)`는 §5.4 계약을 그대로 유지 | 릴리스 준비 중 한 커밋(`2406589`)이 이 API를 항상-`HH:MM:SS`로 바꿨다가, 리뷰 라운드 2(M3)에서 설계서 계약(최소 `M:SS`/`H:MM:SS`, 예: `0` → `"0:00"`)으로 **되돌렸다**. `ABPlayerControlsConfiguration.TimeLabelFormat.fixedHours`(R2)가 항상-패딩 형태를 원하는 소비자를 위한 전용 경로이며, 컨트롤 레이어 자체 포매터(`fixedHoursString(from:)`)로 구현되어 이 API에 위임하지 않는다 | 리뷰 지적(M3): `ABTimeFormatter`는 ABShortsKit 숏폼 재사용을 위해 코어 public으로 승격됐는데(Q9 수정안), 항상-`HH:MM:SS`는 15초 클립에 부적절한 기본값이었다 |
| R6 | 하단 행 간격 산술은 실측 폰트 메트릭 기반, 경험적 상수 최소화 | `rootStackSpacing`이 시크바 트랙과 하단 행 사이의 슬랙(터치 영역 vs 시각 요소)을 양쪽 모두 보정한다. 시크바 쪽은 `trackHeight` 기반 정확한 산술, 하단 행 쪽(시간 라벨/배속 타이틀)은 폰트의 `lineHeight`/`ascender`/`capHeight`로 유도한 근사치를 쓴다 — Dynamic Type 접근성 크기(예: AX3)에서 스케일된 폰트를 반영해야 트랙과 라벨이 겹치지 않는다. `UITraitPreferredContentSizeCategory` 변경 시 `registerForTraitChanges`로 간격을 재계산한다 | 리뷰 지적(M1/m1): 간격 산술이 미스케일 폰트·하드코딩된 행 높이를 썼다 |

### R1~R6가 설계에 미치는 영향
- §3.3 설정 표에 `timeFormat`(R2), `skipInterval` 클램프 규칙(R3), `promotesToCurrentOnPlay`(R4)를 반영해야 한다(현재 §3.3 코드 블록은 릴리스 이전 스냅샷이며 최신화되지 않음 — 알려진 문서 부채로 남긴다).
- §5.4는 원래 계약대로 유지, 변경 없음(R5) — 단 컨트롤 레이어가 별도 `.fixedHours` 경로를 갖는다는 점을 §3.3에 함께 기록해야 한다.
- §6.3의 "grade != .current → 컨트롤 비활성" 규칙에 R4의 예외(재생/일시정지만 프로모션 자격)를 각주로 추가해야 한다.
- §4.1(라이브 갱신 규칙)에 R1의 히트테스트 우선순위 목록과 R6의 트레잇 변경 재계산 훅을 반영해야 한다.
- 위 항목들은 **알려진 문서 부채**로 남겨둔다 — 코드·테스트·`IMPL-v0.2-RESULT.md`가 이 결정들의 1차 소스이며, §3.3/§4.1/§6.3 본문 자체의 상세 재작성은 후속 문서화 커밋으로 분리한다(리뷰가 지적한 "문서화 없이 결정만 반복되는" 패턴을 반복하지 않기 위해, 최소한 이 표를 결정의 근거로 지금 남긴다).
