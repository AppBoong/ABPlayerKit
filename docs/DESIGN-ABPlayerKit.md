# 설계서 — ABPlayerKit (Phase 1)

> 대상: `github.com/AppBoong/ABPlayerKit` · iOS 16+ · Swift 5.9+ · MIT
> 기준 문서: `docs/PLANNING.md` §6 설계 기본 스탠스
> 참조 구현: `ohdasiyoung-ios` (ShortsPlayerView / ShortsReducer / 감사문서 §3 16개 발견)

## 1. 목표와 비목표

| | 내용 |
|---|---|
| 목표 | AVPlayer 재생 파이프라인을 **얇게** 감싸면서, 원본 구현이 암묵적으로 갖고 있던 "재생 등급"을 1급 개념으로 승격하고, 승격/강등을 **대칭**으로 처리하며, 모든 해제 경로가 반드시 `replaceCurrentItem(nil)`을 지나도록 보장한다 |
| 목표 | 첫 프레임(TTFF) 종점을 `isReadyForDisplay ∧ status == .readyToPlay`로 정의해 라이브러리 수준에서 제공 |
| 목표 | 전역 상태·전역 옵저버·`print` 없이 릴리스 빌드에 안전하게 링크되는 것 |
| 비목표 | 커스텀 컨트롤 UI(시크바/타임라인), DRM/FairPlay, 라이브 스트림 특화, 광고, 오프라인 라이선스 |
| 비목표 | AVFoundation을 완전히 은폐하는 추상화. `avPlayer` / `avPlayerItem` 접근자를 공개 유지한다 (스터디 목적 + 소비자 탈출구) |

## 2. 타겟 구조

```
ABPlayerKit/
├─ Package.swift
├─ Sources/
│  ├─ ABPlayerKit/                 # 코어 (UIKit + AVFoundation + SwiftUI 래퍼 포함)
│  │  ├─ Model/                    # ABMediaSource, ABPlaybackGrade, ABPlaybackTuning, ABPlayerConfiguration
│  │  ├─ StateMachine/             # ABGradePlanner, ABGradeAction  (순수, AVFoundation 미의존)
│  │  ├─ Engine/                   # ABPlayer, ABPlaybackTarget(internal), ABAVPlaybackTarget
│  │  ├─ View/                     # ABPlayerView(UIView), ABFirstFrameDetector
│  │  ├─ Policy/                   # ABAudioSessionPolicy, ABBackgroundPolicy, ABApplicationStateObserver
│  │  ├─ Observation/              # ABPlayerEvent, ABPlayerObserver, ABObservationToken, ABObservationBag
│  │  └─ SwiftUI/                  # ABVideoPlayer (UIViewRepresentable)
│  ├─ ABPlayerKitMetrics/          # → ABPlayerKit
│  └─ ABPlayerKitCache/            # → ABPlayerKit
├─ Tests/
│  ├─ ABPlayerKitTests/            # 순수 로직 + fake target
│  ├─ ABPlayerKitMetricsTests/
│  └─ ABPlayerKitCacheTests/
└─ Examples/ABPlayerKitDemo/       # 별도 Package (products 아님)
```

```swift
// Package.swift (요지)
let package = Package(
  name: "ABPlayerKit",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "ABPlayerKit", targets: ["ABPlayerKit"]),
    .library(name: "ABPlayerKitMetrics", targets: ["ABPlayerKitMetrics"]),
    .library(name: "ABPlayerKitCache", targets: ["ABPlayerKitCache"]),
  ],
  targets: [
    .target(name: "ABPlayerKit", swiftSettings: strict),
    .target(name: "ABPlayerKitMetrics", dependencies: ["ABPlayerKit"], swiftSettings: strict),
    .target(name: "ABPlayerKitCache", dependencies: ["ABPlayerKit"], swiftSettings: strict),
    .testTarget(name: "ABPlayerKitTests", dependencies: ["ABPlayerKit"]),
    // ...
  ]
)
// strict = [.enableExperimentalFeature("StrictConcurrency"), .enableUpcomingFeature("InferSendableFromCaptures")]
```

**결정 — SwiftUI 래퍼는 코어와 같은 타겟.** `UIViewRepresentable` 구현은 40줄 미만이고 SwiftUI는 iOS 16에서 링크 비용이 사실상 없다. 별도 타겟으로 쪼개면 소비자가 두 모듈을 import해야 하는 비용이 이득보다 크다. (숏츠 쪽도 동일 방침 — 일관성)

**결정 — 메트릭/캐시는 별도 타겟.** 메트릭은 릴리스 바이너리에 들어갈 이유가 없어야 하고(원본 약점 #13), 캐시는 `AVAssetDownloadURLSession`·디스크 I/O라는 전혀 다른 책임/실패 모드를 갖는다. 옵트인 링크가 맞다.

## 3. 레이어링과 스레딩 모델

```
   소비자
     │
 ┌───▼──────────────┐   ┌──────────────────────┐
 │ ABPlayerView     │   │ ABVideoPlayer (SwiftUI)│   View 레이어  @MainActor
 │ (AVPlayerLayer)  │   └──────────┬────────────┘
 └───┬──────────────┘              │
     │ isReadyForDisplay            │
 ┌───▼──────────────────────────────▼───────────┐
 │ ABPlayer  — 등급 소유, 이벤트 방송, 자원 해제  │   Engine 레이어  @MainActor
 └───┬───────────────────────┬──────────────────┘
     │ actions               │ AVFoundation 호출
 ┌───▼─────────────┐   ┌─────▼────────────────┐
 │ ABGradePlanner  │   │ ABPlaybackTarget      │   Policy / Seam
 │ (순수 함수)      │   │ (internal protocol)   │
 └─────────────────┘   └───┬──────────────┬────┘
                    ABAVPlaybackTarget  ABFakePlaybackTarget(Tests)
```

### @MainActor 경계

| 타입 | 격리 |
|---|---|
| `ABPlayer`, `ABPlayerView`, `ABVideoPlayer`, `ABPlayerObserver`, `ABApplicationStateObserver` | `@MainActor` |
| `ABPlaybackGrade`, `ABGradeAction`, `ABGradePlanner`, `ABMediaSource`, `ABPlaybackTuning`, `ABPlayerConfiguration`, `ABPlayerEvent`, `ABPlayerError` | `nonisolated` + `Sendable` (전부 값 타입/enum) |
| `ABObservationBag` | `final class`, 내부 락, `@unchecked Sendable` — **deinit에서 어느 스레드에서든 invalidate 가능해야 하므로 격리하지 않는다** |
| `ABMediaCache`, `ABHLSPrefetcher` (Cache 타겟) | `actor` 백엔드 + `Sendable` 파사드 |

**콜백 규칙 (원본에서 그대로 가져오는 교훈):**
KVO/`NotificationCenter` 콜백은 임의 스레드로 온다. `MainActor.assumeIsolated`는 **쓰지 않는다** (원본 `ShortsPlayerView:144,153`은 사실상 검증되지 않은 가정). 대신:

1. 콜백 스레드에서 **즉시** `CACurrentMediaTime()`을 캡처한다 (큐 호핑 지연이 TTFF에 섞이는 것을 방지 — 원본이 실측으로 확립한 규칙).
2. 캡처한 타임스탬프를 값으로 넘겨 `MainActor`로 홉한다.
3. 홉 후 재검증: `player.currentItem === capturedItem` 확인 후에만 이벤트 발행.

```swift
// 패턴 (내부)
observation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
  guard layer.isReadyForDisplay else { return }
  let t = CACurrentMediaTime()                 // ← 콜백 스레드에서 즉시
  Task { @MainActor [weak self] in self?.layerBecameReady(at: t) }
}
```

## 4. 재생 등급 상태 머신

### 4.1 등급 정의

```swift
/// 플레이어가 자원을 얼마나 점유하고 있는지를 나타내는 유일한 진실.
/// 원본의 `Set<Int>` 멤버십 + `index == currentIndex` 비교(감사 A-1)를 대체한다.
public enum ABPlaybackGrade: Int, Sendable, CaseIterable, Comparable {
  /// AVPlayer 인스턴스 없음. 모든 자원 반납 완료.
  case released     = 0
  /// AVPlayer 인스턴스만 존재. currentItem == nil → 네트워크 0.
  case instanceOnly = 1
  /// AVPlayerItem 세팅됨. 프리로드 튜닝(상한) 적용, 정지 상태, preroll 대상.
  case preloaded    = 2
  /// AVPlayerItem 세팅됨. 재생 튜닝(상한 해제) 적용, play() 허용.
  case current      = 3

  public var holdsItem: Bool { self >= .preloaded }
  public var holdsInstance: Bool { self >= .instanceOnly }
  public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}
```

### 4.2 전이표 (전이 16쌍 전부 정의된 전역 함수)

`source`가 바뀌는 경우를 별도 축으로 둔다 (같은 등급이라도 URL이 바뀌면 재부착).

| from \ to | released | instanceOnly | preloaded | current |
|---|---|---|---|---|
| **released** | – | createPlayer | createPlayer, attachItem, applyTuning(.preload), armPreroll | createPlayer, attachItem, applyTuning(.current) |
| **instanceOnly** | releasePlayer | – (source만 갱신) | attachItem, applyTuning(.preload), armPreroll | attachItem, applyTuning(.current) |
| **preloaded** | cancelPreload, pause, **detachItem**, teardownObservers, releasePlayer | cancelPreload, pause, **detachItem** | – (source 변경 시 detachItem→attachItem) | cancelPreload, **applyTuning(.current)** ← 승격 |
| **current** | pause, **detachItem**, teardownObservers, releasePlayer | pause, **detachItem** | pause, **applyTuning(.preload)**, (선택)armPreroll ← **강등: 승격의 정확한 역연산** |

**불변식 (테스트로 고정):**
- I1. `from.holdsItem && !to.holdsItem` ⇔ 액션 목록에 `.detachItem` 정확히 1회 포함. (원본 약점 #2·#3·#4 봉쇄)
- I2. `.applyTuning`은 등급이 바뀔 때마다 반드시 1회 이상 실행되며, `.preloaded`↔`.current` 왕복은 항등이다. (원본 약점 #1)
- I3. `to < .preloaded` ⇒ `.cancelPreload` 포함. (원본 약점 #9)
- I4. `.attachItem` 앞에는 항상 해당 등급의 `.applyTuning`이 오거나 같은 배치에 온다 — 아이템 생성 직후 상한이 걸리기 전 세그먼트가 새어나가지 않도록 **`replaceCurrentItem` 호출 전에** 튜닝을 적용한다.
- I5. 액션 목록은 멱등이다. 같은 (from,to,source)로 두 번 실행해도 관찰 가능한 상태가 같다.

```swift
public enum ABGradeAction: Sendable, Equatable {
  case createPlayer
  case cancelPreload
  case pause
  case applyTuning(ABTuningRole)       // .preload | .current
  case attachItem(ABMediaSource)       // AVPlayerItem 생성 + replaceCurrentItem(item)
  case detachItem                      // replaceCurrentItem(nil)
  case armPreroll                      // status .readyToPlay 대기 후 preroll(atRate:)
  case seekToStart
  case teardownObservers
  case releasePlayer
}

public enum ABTuningRole: Sendable, Equatable { case preload, current }

/// AVFoundation을 import하지 않는 순수 플래너. 테스트 100% 대상.
public struct ABGradePlanner: Sendable {
  public init() {}
  public func actions(
    from: ABPlaybackGrade,
    to: ABPlaybackGrade,
    sourceChanged: Bool,
    rewindOnDemotion: Bool = false
  ) -> [ABGradeAction]
}
```

## 5. 공개 API — ABPlayerKit (core)

### 5.1 소스와 설정

```swift
public struct ABMediaSource: Sendable, Hashable {
  public enum Kind: Sendable, Hashable { case hls, progressive }

  public let url: URL
  public let kind: Kind
  public var httpHeaders: [String: String]

  /// 확장자 기반 추론: .m3u8 → .hls, 그 외 → .progressive
  public init(url: URL, kind: Kind? = nil, httpHeaders: [String: String] = [:])
}

/// AVPlayerItem/AVPlayer에 걸리는 튜닝 노브 묶음. 승격/강등 모두 이 한 타입으로 적용된다.
public struct ABPlaybackTuning: Sendable, Equatable {
  /// bps. 0 = 무제한 (AVFoundation 규약 그대로)
  public var preferredPeakBitRate: Double
  /// 초. 0 = 자동
  public var preferredForwardBufferDuration: TimeInterval
  /// .zero = 제한 없음
  public var preferredMaximumResolution: CGSize
  public var automaticallyWaitsToMinimizeStalling: Bool

  /// 상한 없음 — 착지 셀 기본값
  public static let unrestricted = ABPlaybackTuning(
    preferredPeakBitRate: 0, preferredForwardBufferDuration: 0,
    preferredMaximumResolution: .zero, automaticallyWaitsToMinimizeStalling: true)

  /// 원본 구현이 실측으로 사용하던 프리로드 상한 (2Mbps / 5s).
  /// forwardBufferDuration은 세그먼트 ≥6s 스트림에서 soft hint임이 원본 실측으로 확인됨 — 문서화된 한계.
  public static let conservativePreload = ABPlaybackTuning(
    preferredPeakBitRate: 2_000_000, preferredForwardBufferDuration: 5,
    preferredMaximumResolution: .zero, automaticallyWaitsToMinimizeStalling: true)

  /// 대역폭 상한을 렌디션 선택으로 거는 대안 프리셋 (셀룰러 지향)
  public static let resolutionCapped = ABPlaybackTuning(
    preferredPeakBitRate: 2_000_000, preferredForwardBufferDuration: 5,
    preferredMaximumResolution: CGSize(width: 960, height: 540),
    automaticallyWaitsToMinimizeStalling: true)
}

public struct ABPlayerConfiguration: Sendable, Equatable {
  public var preloadTuning: ABPlaybackTuning       // 기본 .conservativePreload
  public var currentTuning: ABPlaybackTuning       // 기본 .unrestricted
  public var isLooping: Bool                       // 기본 false
  public var isMuted: Bool                         // 기본 false
  public var prerollRate: Float?                   // 기본 1.0. nil이면 preroll 안 함
  public var prerollTimeout: TimeInterval          // 기본 10초 (원본 하드코딩 → 설정화)
  public var rewindOnDemotion: Bool                // 기본 false. true면 강등 시 seek(.zero)
  public var backgroundPolicy: ABBackgroundPolicy  // 기본 .pause
  public var audioSessionPolicy: ABAudioSessionPolicy // 기본 .unmanaged
  public var videoGravity: AVLayerVideoGravity     // 기본 .resizeAspectFill
  public var assetFactory: any ABAssetFactory      // 기본 ABDefaultAssetFactory()

  public init(...)  // 전 필드 기본값 있는 memberwise
}
```

### 5.2 정책

```swift
public enum ABBackgroundPolicy: Sendable, Equatable {
  /// 아무 것도 하지 않는다 (원본의 현행 동작 — 명시적으로 선택할 수 있게만 남긴다)
  case ignore
  /// 백그라운드 진입 시 pause, 포그라운드 복귀 시 직전 재생 상태 복원
  case pause
  /// pause + AVPlayerLayer.player = nil (디코더 해제). 복귀 시 재부착.
  case pauseAndDetachLayer
  /// pause + 등급을 .instanceOnly로 강등 (네트워크 완전 차단). 복귀 시 직전 등급 복원.
  case demoteToInstance
}

/// 라이브러리는 기본적으로 AVAudioSession을 건드리지 않는다 (앱 전역 자원이므로).
public enum ABAudioSessionPolicy: Sendable, Equatable {
  case unmanaged                                     // 기본값. 호출 0건
  case playback(mixWithOthers: Bool)
  case ambient                                        // 무음 스위치 존중, 다른 앱 오디오 유지
}

/// 명시 호출로만 동작하는 파사드. ABPlayer가 자동으로 부르지 않는다.
public enum ABAudioSession {
  @MainActor public static func activate(_ policy: ABAudioSessionPolicy) throws
  @MainActor public static func deactivate() throws
}
```

### 5.3 ABPlayer

```swift
public struct ABPlayerID: Hashable, Sendable { /* UUID wrapper */ }

@MainActor
public final class ABPlayer {

  public let id: ABPlayerID
  public var configuration: ABPlayerConfiguration { didSet }  // 현재 등급 튜닝 즉시 재적용
  public private(set) var grade: ABPlaybackGrade              // 기본 .released
  public private(set) var source: ABMediaSource?
  public private(set) var lastError: ABPlayerError?
  /// 첫 프레임이 화면에 표시 가능해졌는가 (isReadyForDisplay ∧ status == .readyToPlay)
  public private(set) var hasDisplayedFirstFrame: Bool

  /// 탈출구 — 스터디 목적상 AVFoundation 가시성 유지. 등급 관련 프로퍼티 직접 변경은 미지원.
  public var avPlayer: AVPlayer? { get }
  public var avPlayerItem: AVPlayerItem? { get }

  public init(configuration: ABPlayerConfiguration = .init())

  // MARK: 등급 — 유일한 상태 변경 진입점
  /// (source, grade)를 원자적으로 설정한다. 불법 조합(grade >= .preloaded && source == nil)은
  /// .instanceOnly로 클램프되고 .invalidGradeForSource 이벤트를 발행한다 (throw/crash 없음).
  public func set(source: ABMediaSource?, grade: ABPlaybackGrade)
  public func promote(to grade: ABPlaybackGrade)   // set(source: source, grade:) 편의
  /// 전 자원 반납. 어느 등급에서 호출해도 replaceCurrentItem(nil) → 옵저버 해제 → 플레이어 폐기.
  public func release()

  // MARK: 재생 제어 (grade == .current 에서만 유효, 아니면 무시 + .playbackRejected 이벤트)
  public func play()
  public func pause()
  public func seek(to time: CMTime) async
  public func setMuted(_ muted: Bool)
  public var isPlaying: Bool { get }
  public var currentTime: CMTime { get }
  public var duration: CMTime? { get }

  // MARK: 프리로드 제어
  /// preroll을 지금 실행 (ABShortsKit의 .onScrollSettled 타이밍용)
  public func startPreroll()
  /// 진행 중인 preroll/status 대기 Task 취소. 네트워크 요청 자체를 끊으려면 등급을 낮춘다.
  public func cancelPreload()

  // MARK: 관찰
  public func addObserver(_ observer: some ABPlayerObserver) -> ABObservationToken
  public func addObserver(_ handler: @escaping @MainActor (ABPlayerEvent) -> Void) -> ABObservationToken
}
```

**의도적으로 넣지 않은 것 (YAGNI):** `rate` 세터, `isSeeking`, 자막/오디오 트랙 선택, 재생 큐, `AVQueuePlayer` 기반 루프. 루프는 `isLooping` 설정 하나로만 제공한다.

### 5.4 이벤트

```swift
public enum ABPlayerEvent: Sendable, Equatable {
  case gradeChanged(from: ABPlaybackGrade, to: ABPlaybackGrade)
  case sourceChanged(ABMediaSource?)
  case itemStatusChanged(ABItemStatus)                 // .unknown/.readyToPlay/.failed
  /// TTFF 종점. t = 콜백 스레드에서 캡처한 CACurrentMediaTime()
  case firstFrameDisplayed(at: CFTimeInterval)
  case prerollCompleted(success: Bool)
  case preloadCancelled
  case playbackStalled
  case playedToEnd
  case timeControlStatusChanged(ABTimeControlStatus)
  case failed(ABPlayerError)
  case tuningApplied(ABTuningRole, ABPlaybackTuning)   // 원본 약점 #10 대응 (승격/강등 가시화)
  case itemDetached(reason: ABDetachReason)            // 원본 약점 #11 대응
}

public enum ABDetachReason: Sendable, Equatable { case demotion, release, sourceChanged, backgroundPolicy }

@MainActor public protocol ABPlayerObserver: AnyObject {
  func player(_ player: ABPlayer, didEmit event: ABPlayerEvent)
}

/// 해제 보장 토큰. deinit 시 자동 등록 해제 — 원본의 "영구 등록된 stall 옵저버"(약점 #12) 봉쇄.
public final class ABObservationToken: Sendable {
  public func cancel()
  /// 소비자가 보관을 잊었을 때 즉시 해제되지 않도록 명시 저장 API 제공
  public func store(in set: inout Set<ABObservationToken>)
}
```

**결정 — delegate가 아니라 다중 옵저버 + 토큰.** 메트릭 타겟이 소비자의 delegate 슬롯을 뺏지 않고 붙을 수 있어야 한다. `AsyncStream`은 이벤트 순서/역압 문제와 `for await` 수명 관리 부담이 있어 v1에서는 제외하되, 필요하면 `events` 프로퍼티를 추가하는 것은 소스 호환 변경이다. (→ OPEN-QUESTIONS Q3)

### 5.5 뷰

```swift
@MainActor
public final class ABPlayerView: UIView {
  public override class var layerClass: AnyClass { AVPlayerLayer.self }

  /// 플레이어 부착. 교체 시 이전 플레이어의 첫프레임 관찰을 먼저 끊고 새로 건다 (순서 고정).
  public var player: ABPlayer? { get set }
  public var videoGravity: AVLayerVideoGravity { get set }   // CATransaction 암시 애니메이션 차단하여 적용
  public var isReadyForDisplay: Bool { get }

  /// 영상 비율에 따라 gravity 자동 적용 (기본 false — 릴스 관례는 항상 resizeAspectFill).
  /// 원본의 applyVideoGravity가 호출부 0건이었던 문제(약점 #15)를 "설정 1개"로 대체.
  public var adaptsGravityToAspectRatio: Bool
}

// SwiftUI
public struct ABVideoPlayer: UIViewRepresentable {
  public init(player: ABPlayer, videoGravity: AVLayerVideoGravity = .resizeAspectFill)
}
```

**첫 프레임 감지 (ABFirstFrameDetector, internal)** — 원본의 핵심 자산을 그대로 승계:
- `AVPlayerLayer.isReadyForDisplay` KVO(`.initial` 포함)와 `AVPlayerItem.status` KVO를 **AND**로 묶고 늦게 오는 쪽을 종점으로 삼는다.
- `reportedItem` 아이덴티티 가드로 아이템당 1회만 발행 (이전 프레임 때문에 layer.ready가 먼저 true가 되는 실측 사례 방어).
- 관찰자는 전부 `ABObservationBag`에 담겨 `release()`/`deinit`에서 명시 invalidate (약점 #14).
- `NotificationCenter` 전역 방송은 쓰지 않는다. 이벤트는 해당 `ABPlayer`의 옵저버에게만 간다.

### 5.6 에셋 팩토리 (캐시 타겟과의 유일한 이음매)

```swift
public protocol ABAssetFactory: Sendable {
  func makeAsset(for source: ABMediaSource) -> AVURLAsset
}
public struct ABDefaultAssetFactory: ABAssetFactory, Sendable {
  public init()
  // AVURLAssetHTTPHeaderFieldsKey(비공식 키 대신 AVURLAsset options의 공식 경로만 사용)
}
```

## 6. 에러 처리

```swift
public enum ABPlayerError: Error, Sendable, Equatable {
  case itemFailed(description: String)          // AVPlayerItem.error 문자열화 (Equatable/Sendable 보장)
  case assetNotPlayable
  case prerollTimedOut(after: TimeInterval)
  case prerollFailed
  case invalidGradeForSource(requested: ABPlaybackGrade)
  case cacheUnavailable(description: String)    // Cache 타겟이 사용
}
```

원칙:
1. **throw하지 않는다.** 재생 실패는 비동기 사건이므로 전부 `.failed` 이벤트 + `lastError` 프로퍼티. 동기 API에서 throw를 쓰면 소비자가 잡을 수 없는 지점이 생긴다.
2. **자동 강등하지 않는다.** 실패해도 등급은 유지된다 — 소비자가 `set(source:grade:)`로 재시도하거나 다른 소스로 교체할 수 있어야 한다.
3. **fatalError / precondition / assert 0건.** 불법 인자는 클램프 + 이벤트.
4. **print / NSLog 0건.** 로깅은 Metrics 타겟의 sink를 통해서만.
5. 소스 URL은 에러 메시지에 포함하지 않는다 (서명 URL 유출 방지).

## 7. 테스트 전략

| 계층 | 방법 | 커버리지 목표 |
|---|---|---|
| `ABGradePlanner` | swift-testing 순수 유닛. 16개 전이쌍 × sourceChanged 2 = 32 케이스 전수 + 불변식 I1~I5 프로퍼티 테스트 | 100% |
| `ABPlaybackTuning` 대칭 | `promote→demote` 왕복 후 튜닝 동등성 (`#expect(applied == .conservativePreload)`) | 100% |
| `ABPlayer` 엔진 | **internal `ABPlaybackTarget` 프로토콜 + `ABFakePlaybackTarget`**. 호출 시퀀스를 기록해 "모든 해제 경로에 detachItem이 정확히 1회" 를 어서션 | 주요 경로 100% |
| `ABObservationToken` 수명 | fake 옵저버 해제 후 이벤트 미수신 확인, `weak` 참조 nil 확인 | – |
| `ABFirstFrameDetector` | KVO는 fake 불가 → **AND 판정 로직을 순수 함수 `shouldReport(layerReady:itemStatus:reportedItem:currentItem:)`로 분리**해 유닛 테스트. KVO 배선은 데모 앱 검증 | 판정 로직 100% |
| 메트릭 집계 | 순수 (`percentile`, `hitRate`, LRU) — 고정 표본으로 검증 | 100% |
| 캐시 | `ABCacheIndex` LRU/용량 초과 축출, 범위 요청 파싱, 키 유도 = 순수. 디스크 I/O는 임시 디렉터리 통합 테스트 | 순수 100% |
| AVPlayer 실동작 | **데모 앱 벤치마크**: HLS/MP4 각각 TTFF p50/p95, 첫프레임 미표시율, 승격/강등 시 `accessLog.indicatedBitrate` 변화, 백그라운드 왕복 후 재생 지속 | 수동/XCUITest |

```swift
// 테스트 이음매 (internal, @testable로 접근)
@MainActor protocol ABPlaybackTarget: AnyObject {
  func makePlayer()
  func releasePlayer()
  func attachItem(_ source: ABMediaSource, tuning: ABPlaybackTuning)
  func detachItem()
  func applyTuning(_ tuning: ABPlaybackTuning)
  func play(); func pause(); func preroll(rate: Float) async -> Bool
  func seekToStart() async
}
```
> 프로토콜은 이 하나(+`ABAssetFactory`, `ABPlayerObserver`, 메트릭 `ABMetricsSink`, `ABClock`)로 제한한다. PLANNING §6 "테스트 경계에만 protocol" 원칙 준수.

## 8. ABPlayerKitMetrics

```swift
public struct ABMetricSample: Sendable, Equatable {
  public enum Outcome: Sendable, Equatable { case hit, waited(ms: Double), abandoned }
  public let playerID: ABPlayerID
  public let startedAt: CFTimeInterval
  public let outcome: Outcome
}

public enum ABMetricEvent: Sendable, Equatable {
  case ttff(ABMetricSample)
  case stall(playerID: ABPlayerID, at: CFTimeInterval)
  case preloadStarted(playerID: ABPlayerID, at: CFTimeInterval)     // 원본 약점 #10
  case itemDetached(playerID: ABPlayerID, reason: ABDetachReason,
                    access: ABAccessSnapshot?)                      // 원본 약점 #11
  case tuning(playerID: ABPlayerID, role: ABTuningRole)
}

/// AVPlayerItem.accessLog에서 뽑은 스냅샷 — 프리로드 낭비/과잉 수신 정량화용
public struct ABAccessSnapshot: Sendable, Equatable {
  public let numberOfBytesTransferred: Int64
  public let indicatedBitrate: Double
  public let observedBitrate: Double
  public let startupTime: Double
  public let stallCount: Int
}

public protocol ABMetricsSink: Sendable {
  func record(_ event: ABMetricEvent)
}
public final class ABInMemoryMetricsSink: ABMetricsSink { public var events: [ABMetricEvent] { get } }
public final class ABJSONLinesMetricsSink: ABMetricsSink { public init(fileURL: URL) }
public struct ABOSLogMetricsSink: ABMetricsSink { public init(subsystem: String, category: String) }

public protocol ABClock: Sendable { var now: CFTimeInterval { get } }
public struct ABMonotonicClock: ABClock { }   // CACurrentMediaTime()

@MainActor
public final class ABMetricsRecorder {
  public init(sink: any ABMetricsSink, clock: any ABClock = ABMonotonicClock())
  /// 플레이어에 붙는다. 토큰을 버리면 즉시 관찰이 끊긴다 (전역 상태 0).
  public func attach(to player: ABPlayer) -> ABObservationToken
  /// TTFF 시작점 — "사용자가 그 셀을 보기 시작한 순간"을 소비자가 지정한다.
  /// (원본이 실측으로 확립한 정의: 로드 시점 기준으로 재면 프리로드 유무를 비교할 수 없다)
  public func beginTTFF(for player: ABPlayer, at time: CFTimeInterval? = nil)
  /// 첫 프레임 전에 다음 항목으로 넘어간 경우 — abandoned(블랙스크린)로 확정
  public func abandonTTFF(for player: ABPlayer)
}

/// 순수 집계 — 테스트 100% 대상
public struct ABPlaybackStatistics: Sendable, Equatable {
  public let sampleCount: Int, hitCount: Int, abandonedCount: Int
  public let p50: Double, p95: Double, max: Double
  public var hitRate: Double        // 분모 = 전체 샘플 (abandoned 포함) — 원본 문서의 정직한 분모 규칙
  public var abandonRate: Double
  public static func aggregate(_ samples: [ABMetricSample]) -> ABPlaybackStatistics
}
```

설계 규칙:
- `static var` 상태 **0건**. 레코더 인스턴스가 소유.
- `#if DEBUG` 게이팅에 의존하지 않는다 — **타겟 분리 자체가 게이팅**이다. 릴리스 앱은 `ABPlayerKitMetrics`를 링크하지 않으면 된다.
- 모든 옵저버는 토큰 기반. `deinit`에서 전량 해제.
- sink 호출은 항상 MainActor에서 발생하고, sink 구현이 I/O를 하면 자기 큐로 넘기는 책임을 진다 (`ABJSONLinesMetricsSink`는 내부 직렬 큐 사용).

## 9. ABPlayerKitCache — v1 범위 정밀화

### 9.1 무엇을 하고 무엇을 안 하나

| 항목 | v1 | 비고 |
|---|---|---|
| **Progressive(MP4) 투명 캐싱** | **포함** | `AVAssetResourceLoader` + 커스텀 스킴(`ab-cache://`) 리다이렉트. Range 요청 처리, 순차 채움, 디스크 LRU |
| MP4 부분 수신 재개(cross-launch) | 포함 (파일 끝에서 이어받기 수준) | 조각난 구간 병합/병렬 범위는 v2 |
| **HLS 명시 프리페치** | **포함** | `AVAssetDownloadURLSession` 기반 `ABHLSPrefetcher.prefetch(_:)`. 완료된 자산만 로컬 재생 |
| HLS 투명 세그먼트 캐싱 | **제외 (v2)** | `AVAssetResourceLoader`는 HTTP(S) HLS 마스터/미디어 재생목록에 사용할 수 없다(키 요청 제외). 하려면 로컬 리버스 프록시가 필요하며 실패 모드가 전혀 다르다 → 별도 설계 필요 |
| HLS 부분(첫 세그먼트) 캐싱 | 제외 (v2) | 위와 동일 이유 |
| DRM / FairPlay / persistent key | 제외 | PLANNING v1 제외 항목 |
| 캐시 암호화 | 제외 | 파일 보호 속성(`.completeUntilFirstUserAuthentication`)만 설정 |
| 프리워밍 정책(스크롤 예측 다운로드) | 제외 | ABShortsKit의 윈도우가 담당 |

### 9.2 API

```swift
public struct ABCacheConfiguration: Sendable, Equatable {
  public var directory: URL            // 기본 Caches/ABPlayerKitCache
  public var maximumDiskSize: Int64    // 기본 512MB. LRU 축출
  public var maximumEntrySize: Int64   // 기본 64MB. 초과 자산은 캐싱 우회(패스스루)
  public init(...)
}

public final class ABMediaCache: Sendable {
  public init(configuration: ABCacheConfiguration = .init()) throws
  /// 코어에 주입할 팩토리. progressive만 가로채고 HLS는 그대로 통과시킨다.
  public func makeAssetFactory(hlsPrefetcher: ABHLSPrefetcher? = nil) -> any ABAssetFactory
  public func totalSize() async -> Int64
  public func remove(_ source: ABMediaSource) async
  public func removeAll() async
}

public struct ABHLSPrefetchHandle: Sendable, Hashable { public func cancel() }

public final class ABHLSPrefetcher: Sendable {
  public init(configuration: ABCacheConfiguration = .init())
  /// minimumRequiredMediaBitrate: nil이면 시스템 기본(최저 렌디션 근처)
  @discardableResult
  public func prefetch(_ source: ABMediaSource,
                       minimumRequiredMediaBitrate: Double? = nil) -> ABHLSPrefetchHandle
  public func cancelAll()
  public func localAsset(for source: ABMediaSource) -> AVURLAsset?
  public func remove(_ source: ABMediaSource) async
}
```

### 9.3 순수 테스트 대상 분리
- `ABCacheKey.derive(from:)` — URL 정규화(쿼리 토큰 제거 규칙 포함) 순수 함수
- `ABCacheIndex` — Codable 인덱스, `evictLRU(to:)` 순수 함수
- `ABByteRange.parse(_:)` / `merge(_:)` — Range 헤더 파싱·병합 순수 함수
- `AVAssetResourceLoaderDelegate` 배선 자체는 데모 앱에서 검증 (MP4 반복 재생 시 2회차 네트워크 0 확인)

## 10. 원본 약점 → 설계 대응 매핑

감사 문서 `숏폼-생명주기-현황감사.md` §3의 16개 발견(그중 12개가 재사용 가능한 동작 결함) 전부를 매핑한다. `[P]`=ABPlayerKit, `[S]`=ABShortsKit.

| # | 원본 약점 | 대응 설계 요소 |
|---|---|---|
| 1 | 강등 시 파라미터 복원 코드 부재 | `[P]` `ABGradePlanner` 전이표 `current→preloaded`에 `.applyTuning(.preload)` 강제 + 불변식 I2 테스트. 승격/강등이 **같은 타입(`ABPlaybackTuning`)의 같은 적용 경로**를 쓰므로 비대칭이 구조적으로 불가능 |
| 2 | `indicesToRemove` 경로에 `replaceCurrentItem(nil)` 없음 | `[P]` 불변식 I1(등급이 `.preloaded` 아래로 내려가면 `.detachItem` 필수) + `[S]` `ABWindowDiff`가 `.release(index:reason:)` 커맨드를 명시 생성 |
| 3 | 데이터 트림 경로에 해제 없음 | `[S]` `ABFeedItemStore.apply(_:)`가 제거/시프트되는 인덱스를 전부 커맨드로 뱉고, 커맨드 실행이 `player.release()`를 호출. 순수 diff 테스트 대상 |
| 4 | 데이터 초기 로드 경로에 해제 없음 | `[S]` 동일 (reload = 전체 diff, 기존 전부 release) |
| 5 | 앱 상태 전환 처리 전무 | `[P]` `ABBackgroundPolicy` + `ABApplicationStateObserver` (플레이어 인스턴스별 구독, 토큰 해제) `[S]` 피드가 정책을 전 플레이어에 전파 |
| 6 | `prepareForReuse`에 `pause()` 없음 | `[S]` 플레이어를 **셀 밖(`ABPlayerPool`)에서 소유**하고, 셀의 `unbind()`가 `player.pause()`를 항상 호출. `prepareForReuse`→`unbind()` 단일 경로 + fake 테스트 |
| 7 | 화면 이탈 시 아이템 유지(pause만) | `[S]` `ABDeactivationPolicy { .pauseOnly, .demoteToInstance, .releaseAll }` — 원본 동작(.pauseOnly)도 선택 가능하게 두되 **선택을 명시화** |
| 8 | `deferPreroll` 경로가 실질적으로 죽어 있음 | `[S]` `ABPrerollTiming { .immediate, .onScrollSettled }`를 피드가 실제로 분기하고, `.onScrollSettled` 경로를 fake 스크롤 이벤트로 테스트. `[P]` `startPreroll()` 공개 |
| 9 | 프리로드 취소 경로 부재 | `[P]` `cancelPreload()` + 등급 하락 시 자동 취소(I3) `[S]` 빠른 스와이프 감지(`ABScrollIntent.isFling`) 시 중간 인덱스 프리로드 취소 |
| 10 | 프리로드 시작 로그 부재 | `[P]/[M]` `ABMetricEvent.preloadStarted` |
| 11 | 인스턴스 링 이탈 로그 부재 | `[P]/[M]` `ABPlayerEvent.itemDetached(reason:)` + `ABMetricEvent.itemDetached(access:)` (accessLog 바이트 포함) |
| 12 | stall 옵저버 2개 영구 등록 | `[P]` 모든 관찰은 `ABObservationToken`/`ABObservationBag` 경유, `static` 옵저버 0건 |
| 13 | 릴리스 빌드에 `print`·계측 동작 | `[P]` 코어에 `print` 0건 (린트 규칙으로 고정) + 계측은 **별도 타겟**이라 링크 안 하면 코드가 존재하지 않음 |
| 14 | PlayerView KVO 3종 명시 해제 부재 | `[P]` `ABObservationBag`을 `release()`와 `deinit` 양쪽에서 invalidate. Bag은 비격리 클래스라 deinit에서 안전 |
| 15 | `applyVideoGravity` 호출부 0건(죽은 코드) | `[P]` gravity를 `ABPlayerConfiguration.videoGravity` + `adaptsGravityToAspectRatio` 설정으로 승격, 적용 경로 1개 |
| 16 | A/B 플래그 2개 공존 | `[S]` 프리로드 on/off는 `ABWindowConfiguration` 하나(프리셋 `.disabled`)로만 표현. 별도 플래그 없음 |

## 11. 내가 직접 결정한 사항과 근거

| 결정 | 근거 |
|---|---|
| SwiftUI 래퍼를 코어 타겟에 포함 | 코드 40줄, 링크 비용 0, 소비자 import 1개 |
| 이벤트 = 다중 옵저버 + 토큰 (delegate/AsyncStream 아님) | 메트릭 타겟이 소비자 슬롯을 뺏으면 안 됨. 토큰이 약점 #12를 구조적으로 봉쇄 |
| `ABPlaybackTarget`을 internal로 | 공개 API 최소화(YAGNI). `@testable import`로 테스트 목적 달성 |
| 실패를 throw가 아닌 이벤트로 | 재생 실패는 비동기 사건. 동기 throw는 잡을 수 없는 지점을 만든다 |
| 등급 API를 `set(source:grade:)` 단일 진입점으로 | (source, grade) 불법 조합을 타입 경계에서 방어 |
| `AVAudioSession` 기본 `.unmanaged` | 앱 전역 자원을 라이브러리가 몰래 바꾸면 안 된다. 명시 호출만 허용 |
| 프리로드 기본값 = 원본 실측값(2Mbps/5s) | 근거 있는 유일한 값. 단 forwardBuffer가 soft hint임을 API 주석에 명시 (→ Q2에서 재확인) |
| HLS 투명 캐싱 v1 제외 | `AVAssetResourceLoader`가 HTTP(S) HLS에 사용 불가. 리버스 프록시는 별도 프로젝트 규모 (→ Q1) |
| `NotificationCenter` 전역 방송 폐지 | 원본의 `.shortsPlayerFirstFrameDisplayed`는 전역 결합. 플레이어별 이벤트로 대체 |
