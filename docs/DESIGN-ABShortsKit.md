# 설계서 — ABShortsKit (Phase 1)

> 대상: `github.com/AppBoong/ABShortsKit` · iOS 17+ · Swift 6 언어 모드 · MIT (Q7 확정 반영)
> 의존: `ABPlayerKit` (SPM, `.upToNextMinor(from: "1.0.0")`)
> 참조 구현: `ohdasiyoung-ios` Shorts feature (ManageVideoPlayersUseCase / ShortsFeedView / ShortsReducer)

## 1. 목표와 비목표

| | 내용 |
|---|---|
| 목표 | 수직 페이징 숏폼 피드의 **재생 자원 관리**를 라이브러리화. 데이터·오버레이·네트워킹은 전부 소비자 책임 |
| 목표 | 원본의 이중 슬라이딩 윈도우를 **주입 가능한 순수 엔진**으로 일반화하고, 등급 전이를 커맨드로 명시화 |
| 목표 | 소비자의 앱 아키텍처(TCA/MVVM/MVC)에 중립. `ABShortsKit`은 어떤 상태관리도 강제하지 않는다 |
| 비목표 | 데이터 페칭, 이미지 로딩, 좋아요/공유 등 도메인 UI, 무한 스크롤 정책 자체(콜백만 제공) |
| 비목표 | 수평 피드, 그리드, 챕터/시리즈 네비게이션 |

## 2. 타겟 구조

```
ABShortsKit/
├─ Package.swift
├─ Sources/
│  ├─ ABShortsEngine/                # 순수. Foundation만 import. UIKit/AVFoundation 미의존
│  │  ├─ ABWindowConfiguration.swift
│  │  ├─ ABWindowPlanner.swift       # index → ABPlaybackGrade 총함수
│  │  ├─ ABWindowDiff.swift          # plan 간 차분 → [ABFeedCommand]
│  │  ├─ ABScrollIntent.swift        # (velocity, targetOffset) → 착지 인덱스 / fling 판정
│  │  └─ ABFeedItemStore.swift       # items 갱신/트림/시프트 diff (원본 약점 #3,#4)
│  └─ ABShortsKit/                   # → ABShortsEngine, ABPlayerKit
│     ├─ ABShortsFeedController.swift
│     ├─ ABShortsCell.swift          # internal
│     ├─ ABPlayerPool.swift          # internal — 플레이어는 셀 밖에서 소유
│     ├─ ABProMotionBooster.swift    # internal
│     └─ SwiftUI/ABShortsFeed.swift
├─ Tests/ABShortsEngineTests/        # 대부분의 테스트가 여기 (UIKit 불필요, 빠름)
├─ Tests/ABShortsKitTests/           # fake 플레이어/스크롤 이벤트 기반
└─ Examples/ABShortsKitDemo/
```

**결정 — 순수 엔진을 별도 타겟으로 분리.** ABPlayerKit에서는 플래너가 작아서 코어에 뒀지만, 여기서는 윈도우/차분/스크롤 의도/아이템 스토어가 라이브러리 가치의 절반이고 전부 UIKit 없이 검증 가능하다. 분리하면 테스트가 빠르고, "무엇이 순수 로직인가"가 디렉터리로 드러난다. `ABShortsEngine`은 `ABPlaybackGrade`만 필요하므로 `ABPlayerKit`에 의존한다(값 enum 하나 때문에 의존을 만드는 것이 등급 타입을 중복 정의하는 것보다 낫다).

## 3. 아키텍처

```
소비자 (DataSource / Delegate / Overlay UIView)
        │
┌───────▼─────────────────────────────────────────────┐
│ ABShortsFeedController : UIViewController            │  @MainActor
│  ├ UICollectionView (isPagingEnabled, vertical)      │
│  ├ UICollectionViewDiffableDataSource<Int, ABItemID> │
│  ├ ABPlayerPool  ─ 플레이어 소유 (셀 아님)             │
│  └ ABProMotionBooster                                │
└───────┬──────────────────────────────────────────────┘
        │ (currentIndex, itemCount, existing) / scroll events
┌───────▼──────────────┐
│ ABShortsEngine (순수) │  ABWindowPlanner → ABWindowPlan → ABWindowDiff → [ABFeedCommand]
└───────┬──────────────┘
        │ [ABFeedCommand]
┌───────▼──────────────────────────┐
│ ABPlayerPool → ABPlayer.set(source:grade:) / release() / startPreroll()
└──────────────────────────────────┘
```

핵심: **컨트롤러는 커맨드를 실행할 뿐 자원 결정을 하지 않는다.** 모든 자원 결정은 순수 엔진에서 나오고, 따라서 전부 테스트 가능하다.

## 4. 윈도우 엔진 (원본 `ManageVideoPlayersUseCase` 일반화)

### 4.1 설정

```swift
public struct ABRingSpan: Sendable, Equatable {
  public var backward: Int      // >= 0
  public var forward: Int       // >= 0
  public init(backward: Int, forward: Int)
  public static func symmetric(_ n: Int) -> ABRingSpan
}

public struct ABWindowConfiguration: Sendable, Equatable {
  /// AVPlayer 인스턴스를 유지할 범위. 기본 (-2, +3) — 원본과 동일한 전방 편향
  public var instanceRing: ABRingSpan
  /// AVPlayerItem을 세팅(=네트워크 로드)할 범위. 기본 (-1, +2)
  public var loadRing: ABRingSpan

  public static let `default` = ABWindowConfiguration(
    instanceRing: .init(backward: 2, forward: 3),
    loadRing: .init(backward: 1, forward: 2))

  /// 프리로드 없음 — A/B 대조군 및 저사양/셀룰러 프리셋. 원본의 A/B 플래그 2개(약점 #16)를 이 하나로 대체
  public static let disabled = ABWindowConfiguration(
    instanceRing: .init(backward: 1, forward: 1),
    loadRing: .init(backward: 0, forward: 0))

  /// 정규화: loadRing ⊆ instanceRing 을 강제로 보장 (throw 없이 클램프)
  public func normalized() -> ABWindowConfiguration
}
```

### 4.2 플래너 — 3개 집합이 아니라 등급 사전

```swift
public struct ABWindowPlan: Sendable, Equatable {
  /// 인덱스 → 목표 등급. .released는 키에 포함되지 않는다.
  public let grades: [Int: ABPlaybackGrade]
  public let currentIndex: Int
  public subscript(index: Int) -> ABPlaybackGrade { get }   // 없으면 .released
}

public struct ABWindowPlanner: Sendable {
  public var configuration: ABWindowConfiguration
  public init(configuration: ABWindowConfiguration = .default)

  public func plan(currentIndex: Int, itemCount: Int) -> ABWindowPlan
}
```

원본과의 차이(설계 의도):

| 원본 | ABShortsKit |
|---|---|
| `playerIndices` / `activeIndices` / `indicesToRemove` 3집합 + 호출부의 `index == currentIndex` 비교 | 인덱스당 등급 1개. "어느 집합에 속하는가"를 해석하는 코드가 사라짐 (감사 A-1 해소) |
| 링 크기 하드코딩 매직넘버 | `ABWindowConfiguration` 주입 |
| 제거 대상은 호출부가 `existing - playerIndices`로 계산 | `ABWindowDiff`가 이전 plan과 비교해 커맨드로 산출 |

### 4.3 차분 → 커맨드

```swift
public enum ABFeedCommand: Sendable, Equatable {
  /// 등급 전이 (승격·강등 모두). ABPlayer.set(source:grade:)로 실행된다.
  case setGrade(index: Int, grade: ABPlaybackGrade)
  /// 풀에서 플레이어를 반납 (release() → detachItem 보장)
  case release(index: Int, reason: ABReleaseReason)
  /// 프리로드 취소 (등급은 유지) — 빠른 스와이프 대응
  case cancelPreload(index: Int)
  /// 보류된 preroll 실행
  case startPreroll(index: Int)
  /// 인덱스 시프트 (데이터 트림/prepend 시 플레이어 재키잉)
  case rekey(from: Int, to: Int)
  /// 페이지네이션 요청
  case requestMoreItems(currentIndex: Int)
}

public enum ABReleaseReason: Sendable, Equatable {
  case leftInstanceRing, itemRemoved, reload, deactivated, trimmed
}

public struct ABWindowDiff: Sendable {
  /// 이전 plan → 새 plan 에 필요한 커맨드를 순서 보장하여 생성한다.
  /// 순서 규칙: release/cancel(자원 회수) → 강등 → 승격 → preroll
  /// (회수를 먼저 해야 승격 시점에 대역폭·디코더가 확보된다 — 원본에는 없던 순서 보장)
  public static func commands(
    from previous: ABWindowPlan,
    to next: ABWindowPlan,
    prerollTiming: ABPrerollTiming,
    isScrollSettled: Bool
  ) -> [ABFeedCommand]
}

public enum ABPrerollTiming: Sendable, Equatable {
  case immediate          // 아이템 부착 즉시 preroll
  case onScrollSettled    // 감속 종료까지 보류 (원본 deferPreroll의 의도 — 약점 #8 실제 배선)
}
```

### 4.4 스크롤 의도 (선제 윈도우 이동 + 빠른 스와이프)

```swift
public struct ABScrollIntent: Sendable, Equatable {
  public let targetIndex: Int
  public let delta: Int            // targetIndex - currentIndex
  public let isFling: Bool         // |delta| > flingThreshold 또는 속도 > velocityThreshold

  /// willEndDragging의 (velocity, targetContentOffset, pageHeight)에서 순수 계산.
  /// 원본이 실측으로 확인한 ~300ms 선점의 근거 지점.
  public static func make(targetOffsetY: CGFloat, pageHeight: CGFloat,
                          velocityY: CGFloat, currentIndex: Int, itemCount: Int,
                          flingThreshold: Int, velocityThreshold: CGFloat) -> ABScrollIntent
}
```

`isFling == true`일 때의 정책(순수 규칙, 테스트 대상):
- 착지 인덱스 기준으로 plan을 다시 만들되, **경유 인덱스에는 아이템을 붙이지 않는다** (`.setGrade(.instanceOnly)`).
- 이전 plan에서 `.preloaded`였으나 새 plan에 없는 인덱스는 `.cancelPreload` 후 `.release`.
- `prerollTiming`을 강제로 `.onScrollSettled`로 승격시켜 감속 중 디코드 경합을 피한다.

### 4.5 아이템 스토어 (원본 약점 #3, #4)

```swift
public struct ABItemID: Hashable, Sendable { public init(_ value: AnyHashable) }

public struct ABFeedMutation: Sendable, Equatable {
  public enum Kind: Sendable, Equatable { case reload, append, prependTrim(count: Int) }
  public let kind: Kind
}

public struct ABFeedItemStore: Sendable {
  public private(set) var ids: [ABItemID]
  /// 새 id 목록을 적용하고, 살아남은 인덱스 매핑/사라진 인덱스를 커맨드로 산출한다.
  /// 트림·중복 제거·전체 교체 어느 경로에서도 사라지는 플레이어가 반드시 .release 커맨드를 받는다.
  public mutating func apply(_ newIDs: [ABItemID],
                             activeIndices: Set<Int>) -> [ABFeedCommand]
}
```

## 5. 공개 API — 피드

### 5.1 아이템 / 데이터소스 / 델리게이트

```swift
public struct ABShortsItem: Sendable, Hashable, Identifiable {
  public let id: ABItemID
  public let source: ABMediaSource          // ABPlayerKit
  /// 첫 프레임 전에 보여줄 포스터. 라이브러리는 네트워킹을 하지 않는다 — 아래 posterProvider로 소비자가 공급.
  public var posterURL: URL?
  public init(id: AnyHashable, source: ABMediaSource, posterURL: URL? = nil)
}

@MainActor
public protocol ABShortsFeedDataSource: AnyObject {
  func numberOfItems(in feed: ABShortsFeedController) -> Int
  func feed(_ feed: ABShortsFeedController, itemAt index: Int) -> ABShortsItem
  /// 셀당 오버레이 뷰 생성. 셀이 재사용되면 configure로만 갱신되고 재생성되지 않는다.
  /// nil 반환 시 오버레이 없음.
  func feed(_ feed: ABShortsFeedController, makeOverlayAt index: Int) -> UIView?
  func feed(_ feed: ABShortsFeedController, configure overlay: UIView,
            with item: ABShortsItem, at index: Int, isCurrent: Bool)
}

@MainActor
public protocol ABShortsFeedDelegate: AnyObject {
  func feed(_ feed: ABShortsFeedController, didChangeCurrentIndexTo index: Int)
  func feed(_ feed: ABShortsFeedController, didDisplayFirstFrameAt index: Int,
            latency: TimeInterval?)
  func feed(_ feed: ABShortsFeedController, didChangePlaybackAt index: Int, isPlaying: Bool)
  func feed(_ feed: ABShortsFeedController, didFail error: ABPlayerError, at index: Int)
  /// 페이지네이션 — paginationThreshold 이내로 접근하면 1회 호출 (중복 억제는 라이브러리가 담당)
  func feedNeedsMoreItems(_ feed: ABShortsFeedController, from index: Int)
  func feed(_ feed: ABShortsFeedController, didSelectItemAt index: Int)
}
public extension ABShortsFeedDelegate { /* 전 메서드 기본 구현 = no-op */ }
```

### 5.2 설정

```swift
public enum ABDeactivationPolicy: Sendable, Equatable {
  case pauseOnly            // 원본 동작 — 탭 복귀 시 재로드 없음, 대신 버퍼/메모리 유지
  case demoteToInstance     // 기본값. 아이템 해제로 네트워크 차단, 인스턴스는 유지
  case releaseAll           // 전량 반납
}

/// Q8 확정 — 되돌아가기 이어보기 정책
public enum ABResumePolicy: Sendable, Equatable {
  /// 위치 기억 안 함. 강등 시 위치 유지, 윈도우 이탈 후 복귀는 0초부터
  case none
  /// 최근 capacity개 인덱스의 재생 위치를 기억하고 복귀 시 복원 (LRU). 기본값
  case rememberWindow(capacity: Int)
}

public struct ABShortsFeedConfiguration: Sendable {
  public var window: ABWindowConfiguration          // .default
  public var player: ABPlayerConfiguration          // ABPlayerKit. isLooping 기본 true로 오버라이드
  public var prerollTiming: ABPrerollTiming         // .onScrollSettled
  public var preemptiveWindowShift: Bool            // true — willEndDragging에서 선제 이동
  public var flingIndexThreshold: Int               // 2
  public var flingVelocityThreshold: CGFloat        // 2.0 (pt/ms)
  public var proMotionBoost: Bool                   // false (Info.plist 요구사항 있으므로 옵트인)
  public var deactivationPolicy: ABDeactivationPolicy
  /// Q8 확정: 인덱스별 재생 위치 기억·복원. 기본 .rememberWindow — 강등/해제 직전 위치 저장,
  /// current 승격 시 첫 프레임 표시 전에 seek 복원. 복원된 재생은 메트릭에 resumed로 구분 집계된다.
  public var resumePolicy: ABResumePolicy           // .rememberWindow(capacity: 50)
  public var paginationThreshold: Int               // 3
  public var poolCapacity: Int?                     // nil = instanceRing 크기와 동일
  /// 포스터 이미지 공급 — 라이브러리는 URLSession을 쓰지 않는다
  public var posterProvider: (@Sendable (URL) async -> UIImage?)?
  public var backgroundColor: UIColor               // .black
  public init(...)
}
```

### 5.3 컨트롤러

```swift
@MainActor
public final class ABShortsFeedController: UIViewController {

  public init(configuration: ABShortsFeedConfiguration = .init())

  public weak var dataSource: (any ABShortsFeedDataSource)?
  public weak var delegate: (any ABShortsFeedDelegate)?
  /// 런타임 변경 가능. 링 크기를 줄이면 즉시 초과 플레이어가 release된다.
  public var configuration: ABShortsFeedConfiguration { get set }

  public private(set) var currentIndex: Int

  // 데이터
  public func reloadData()
  /// 페이지네이션 응답 반영. 기존 인덱스는 유지되고 새 항목만 append된다.
  public func appendItems()
  /// 앞부분 트림(무한 피드 상한). 인덱스 시프트와 플레이어 rekey/release를 라이브러리가 처리한다.
  public func trimLeadingItems(count: Int)

  // 제어
  public func scroll(to index: Int, animated: Bool)
  public func play()
  public func pause()
  /// 화면 이탈/복귀. deactivationPolicy가 적용된다. (탭 전환·네비게이션 push 시 소비자가 호출)
  public func setActive(_ isActive: Bool)

  // 진단 (메트릭 타겟 연결용)
  public func player(at index: Int) -> ABPlayer?
  public var activePlayers: [Int: ABPlayer] { get }
}
```

### 5.4 SwiftUI 래퍼

```swift
public struct ABShortsFeed: UIViewControllerRepresentable {
  public init(
    items: [ABShortsItem],
    currentIndex: Binding<Int>,
    configuration: ABShortsFeedConfiguration = .init(),
    onNeedMoreItems: @escaping () -> Void = {},
    /// Q6 확정: 오버레이는 UIView만. SwiftUI 오버레이가 필요하면 소비자가 직접 UIHostingController를 감싸 반환한다.
    overlayProvider: ((ABShortsItem, Int) -> UIView?)? = nil
  )
}
```

**Q6 확정 — 오버레이는 UIKit `UIView` 전용.** 원본이 실측으로 확인한 "SwiftUI 호스팅 계층이 스크롤 중 셀과 따로 움직이는" 문제의 재발 위험을 라이브러리가 떠안지 않는다. SwiftUI 소비자를 위한 `UIHostingController` 래핑 예제 코드를 README/데모에 제공한다(호스팅 시 `view.backgroundColor = .clear` + safe area 무시 필수 — 문서화). **영상 표면(`ABPlayerView`)은 항상 `contentView`의 최하단 UIKit 뷰로 고정한다.**

## 6. 셀 바인딩과 플레이어 소유권

```
ABPlayerPool  ──owns──▶ ABPlayer × N            (N = instanceRing 크기)
      │ bind(index:)
      ▼
ABShortsCell  ──weak──▶ ABPlayer                (셀은 표시만 담당, 소유하지 않음)
```

`ABShortsCell` (internal) 계약:

```swift
func bind(player: ABPlayer, item: ABShortsItem, isCurrent: Bool, overlay: UIView?)
func unbind()          // ① player.pause()  ② playerView.player = nil  ③ 오버레이 분리
override func prepareForReuse() { super.prepareForReuse(); unbind() }
```

- **`unbind()`는 반드시 `pause()`를 부른다** — 원본 약점 #6의 직접 대응. 소유가 셀 밖에 있으므로 pause 후에도 아이템/버퍼는 윈도우 정책이 결정한다.
- 원본의 `guard observedPlayer !== player else { return }` 조기 반환(감사 D-11의 미확인 위험)은 **채택하지 않는다.** 대신 `bind`는 항상 `unbind()`를 먼저 실행하고 재바인딩한다. 같은 플레이어가 다른 인덱스에 재바인딩되는 경로에서 관찰자가 낡을 여지를 없앤다.
- 셀은 `ABPlayer` 이벤트를 토큰으로 구독하고 `unbind()`에서 토큰을 버린다.

`ABPlayerPool` (internal):
```swift
func player(for index: Int) -> ABPlayer          // 없으면 재활용 or 신규
func release(index: Int, reason: ABReleaseReason)  // player.release() 후 재활용 큐로
func rekey(from: Int, to: Int)
func releaseAll(reason: ABReleaseReason)
```
플레이어 **인스턴스 재활용**이 핵심: 윈도우가 이동해도 `AVPlayer` 할당이 스크롤 수에 비례하지 않는다 (원본이 인스턴스 링을 둔 이유를 명시적 풀로 구현).

## 7. 상태 머신 — 피드 레벨

```
                 reloadData / appendItems / trimLeading
                              │
      ┌──────────┐  setActive(true)   ┌──────────┐
      │ inactive │ ─────────────────▶ │  idle    │
      │          │ ◀───────────────── │          │
      └──────────┘  setActive(false)  └────┬─────┘
        (deactivationPolicy 적용)          │ willBeginDragging
                                           ▼
                                     ┌───────────┐
                                     │ dragging  │  ProMotion boost ON
                                     └────┬──────┘
                          willEndDragging │ (ABScrollIntent 계산)
                                          ▼
                                  ┌────────────────┐
                                  │ transitioning  │ 선제 윈도우 이동 (~300ms 선점)
                                  │                │ preroll 보류 (.onScrollSettled)
                                  └────┬───────────┘
      didEndDecelerating / didEndDragging(willDecelerate:false)
                                       ▼
                                  ┌──────────┐
                                  │  idle    │ boost OFF, 보류 preroll 실행, 인덱스 보정
                                  └──────────┘
```

각 전이에서 실행되는 것:

| 이벤트 | 동작 |
|---|---|
| `scrollViewWillBeginDragging` | ProMotion boost 시작 (설정 시) |
| `scrollViewWillEndDragging` | `ABScrollIntent.make(...)` → 착지 인덱스 확정 → `plan` 재계산 → 커맨드 실행 (**아이템 부착·네트워크 요청은 여기서 시작**, preroll은 보류). fling이면 경유 인덱스 프리로드 취소 |
| `scrollViewDidEndDecelerating` / `didEndDragging(willDecelerate:false)` | 실제 정착 인덱스로 보정(터치 중단 대응) → 보류 preroll 실행 → boost 중지 → `didChangeCurrentIndexTo` 델리게이트 → 페이지네이션 임계 확인 |
| `willDisplay cell` | 최신 플레이어/등급 재바인딩 (윈도우가 이동한 뒤 생성된 셀 커버) |
| `didEndDisplaying cell` | `unbind()` 보장 (prepareForReuse가 늦게 오는 경우 대비) |
| 백그라운드 진입 | `ABPlayerConfiguration.backgroundPolicy`가 각 플레이어에서 처리. 피드는 추가로 `isPlaying` 스냅샷 보관 |
| `setActive(false)` | `deactivationPolicy`에 따른 커맨드 일괄 실행 |

## 8. 스레딩 모델

- `ABShortsFeedController`, `ABShortsCell`, `ABPlayerPool`, 데이터소스/델리게이트: 전부 `@MainActor`.
- `ABShortsEngine`의 모든 타입: `nonisolated` + `Sendable` 값 타입. 클래스 0개.
- `posterProvider`는 `@Sendable async` — 임의 액터에서 실행되고 결과만 MainActor로 홉.
- 커맨드 실행은 **동기 루프**다. 비동기 재정렬로 인해 "release 전에 promote"가 일어나면 대역폭 경합이 생기므로, 커맨드 배열의 순서를 그대로 지킨다.

## 9. 에러 처리

| 상황 | 처리 |
|---|---|
| `dataSource == nil` | 아이템 0개로 취급. 크래시 없음 |
| `itemAt(index)`가 범위 밖 인덱스로 호출되는 경합 | 컨트롤러가 `numberOfItems` 스냅샷으로 클램프. 델리게이트에 알리지 않음 |
| 중복 `ABItemID` | diffable data source 크래시를 막기 위해 **순서 보존 dedup 후 적용**하고, 조용히 처리(원본이 겪은 크래시 경로) |
| 재생 실패 | `ABPlayerEvent.failed` → `feed(_:didFail:at:)`. 자동 재시도 없음(정책은 소비자) |
| 아이템 0개 상태에서 `scroll(to:)` | no-op |

## 10. 테스트 전략

### ABShortsEngineTests (순수, 100% 목표)

| 스위트 | 내용 |
|---|---|
| `ABWindowPlannerTests` | 원본 테스트 승계 + 일반화: 중간/시작/끝 경계, itemCount < 윈도우, `loadRing ⊆ instanceRing` 프로퍼티, 설정 주입값별 파라미터라이즈 |
| `ABWindowDiffTests` | 1칸 전진/후진, 2칸 이상 점프, 되돌아가기. **불변식: 이전 plan에서 `.preloaded` 이상이었던 인덱스가 새 plan에서 사라지면 반드시 `.release`가 생성된다** (원본 약점 #2) |
| `ABWindowDiffOrderTests` | 커맨드 순서 = release/cancel → 강등 → 승격 → preroll |
| `ABScrollIntentTests` | 속도·오프셋 조합 표. fling 판정 경계, 인덱스 클램프, 마지막 페이지 |
| `ABFeedItemStoreTests` | reload/append/prependTrim에서 사라지는 인덱스 전부가 `.release` (약점 #3, #4), rekey 매핑 정확성, 중복 ID dedup |
| `ABPrerollTimingTests` | `.onScrollSettled`에서 감속 중에는 `.startPreroll`이 나오지 않고 정착 시 정확히 1회 나온다 (약점 #8) |

### ABShortsKitTests (fake 기반)

- `ABFakeFeedDataSource` + 스크롤 이벤트를 직접 주입하는 `ABShortsFeedController` 테스트:
  - `prepareForReuse` → `pause()` 호출 검증 (약점 #6)
  - `setActive(false)` 정책별 커맨드 검증 (약점 #7)
  - 페이지네이션 콜백 중복 억제
  - 링 크기 런타임 축소 시 초과 플레이어 release
- `ABPlayerKit`의 fake `ABPlaybackTarget`을 재사용해 실제 AVPlayer 없이 전 경로 검증.

### 데모 벤치마크 (Examples/ABShortsKitDemo)

원본의 측정 방법론을 그대로 이식한다:
- 시작점 = 착지 셀 확정 시각(`CACurrentMediaTime()` 즉시 캡처), 종점 = `firstFrameDisplayed`.
- `abandoned`(첫 프레임 전 다음 스와이프) 카운트를 분모에 포함한 블랙스크린율.
- A/B: `ABWindowConfiguration.default` vs `.disabled` 런타임 토글 (플래그 1개 — 약점 #16).
- 산출: TTFF p50/p95, 블랙스크린율, 미시청 프리로드 바이트(`ABMetricEvent.itemDetached`의 accessLog), 메모리.

## 11. 원본 약점 → 설계 대응 (ABShortsKit 담당분)

| # | 원본 약점 | 대응 |
|---|---|---|
| 2 | 인스턴스 링 이탈 시 아이템 미해제 | `ABWindowDiff`의 `.release` 커맨드 + 불변식 테스트 |
| 3 | 데이터 트림 시 플레이어 조용히 소실 | `ABFeedItemStore.apply` → `.release(reason: .trimmed)` / `.rekey` |
| 4 | 초기 로드 시 딕셔너리 통째 폐기 | `ABFeedItemStore.apply` → `.release(reason: .reload)` |
| 5 | 백그라운드 훅 부재 | `ABPlayerConfiguration.backgroundPolicy` 전파 + 재생 상태 스냅샷/복원 |
| 6 | `prepareForReuse`에 pause 없음 | `unbind()`가 `pause()` 보장, 셀 밖 소유 |
| 7 | 화면 이탈 시 아이템 유지 | `ABDeactivationPolicy` (기본 `.demoteToInstance`) |
| 8 | `deferPreroll` 죽은 경로 | `ABPrerollTiming.onScrollSettled` 실제 배선 + 전용 테스트 |
| 9 | 프리로드 취소 부재 | `ABScrollIntent.isFling` → `.cancelPreload` |
| 11 | 인스턴스 링 이탈 로그 부재 | `.release(reason:)`가 델리게이트/메트릭으로 전달 |
| 16 | A/B 플래그 2개 공존 | `ABWindowConfiguration` 단일 노브 |
| — | 셀에서 store 왕복하며 생긴 메인스레드 지터 | 셀은 상태관리 프레임워크를 경유하지 않는다. 진행률 등은 소비자 오버레이가 `ABPlayer`를 직접 관찰 |
| — | SwiftUI 호스팅 셀의 스크롤 어긋남 | 영상 표면은 항상 UIKit 최하단 고정, 오버레이만 호스팅 |

## 12. 내가 직접 결정한 사항과 근거

| 결정 | 근거 |
|---|---|
| 순수 엔진 타겟 분리 (`ABShortsEngine`) | 라이브러리 가치의 절반이 순수 로직. 테스트 속도 + 구조 가시성 |
| plan을 3집합이 아닌 `[Int: ABPlaybackGrade]`로 | 원본 감사 A-1의 근본 원인(암묵적 등급) 제거 |
| 커맨드 순서 보장(회수→강등→승격→preroll) | 원본 실측에서 "프리로드 실패 케이스가 오히려 더 느림(대역 경합)"이 관측됨. 회수 선행이 그 완화책 |
| 플레이어 풀을 internal로 | 공개하면 소비자가 등급 규칙을 우회할 수 있다. `player(at:)` 읽기 접근만 공개 |
| 포스터 이미지 로딩 미제공 (`posterProvider` 클로저) | 라이브러리에 URLSession/이미지 캐시 의존을 넣지 않는다. 소비자의 Kingfisher/Nuke를 그대로 씀 |
| 페이지네이션은 콜백만 | 데이터 계층은 소비자 책임 (PLANNING v1 범위) |
| `didEndDisplaying`에서도 `unbind()` | 원본은 주석만 있고 무동작. 재사용 타이밍이 기기/버전 의존이므로 이중 보장 |
| ProMotion boost 기본 off | `CADisableMinimumFrameDurationOnPhone=true`라는 앱 Info.plist 요구사항이 있어 라이브러리가 임의로 켜면 안 됨 |
| 되돌아가기 시 이어보기 미지원 | 윈도우 밖 이탈 시 아이템 해제가 설계의 핵심. 숏폼 표준 동작 (→ Q8) |
