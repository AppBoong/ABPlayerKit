# DESIGN: 라운드6 트랙 G — NowPlaying · PiP · AirPlay (G-0 설계 게이트)

기준 브랜치 `AppBoong/round6-nowplaying`, base `main` = `d29e231`.
입력: `ROADMAP-round6.md` §0·§3(트랙 G)·§6·§7, `REVIEW-round6-portfolio-audit.md` §G, `DESIGN-round6-core.md` §3.2·§5.5(동결 표면), `DESIGN-round6-swiftui.md` §1.1~§1.5·§3.2·§9-4, `DESIGN-round6-metrics.md` §12, `HANDOFF-round6-wave2.md`, 실소스.

산출 대상 WP: G-1w(NowPlaying 타깃), G-2w(PiP + AirPlay), G-3w(`.continueAudioOnly`), G-4w(문서). G-5 최종 게이트가 §7·§9를 체크리스트로 쓴다.

**본 문서는 설계만 담는다. 이 단계에서 코드는 한 줄도 바뀌지 않았다.**

---

## 0. 전역 제약 (모든 결정에 선행)

| 제약 | 내용 | 근거 |
|---|---|---|
| additive-only | 공개 타입/프로퍼티/케이스는 **추가만**. 기존 시그니처 변경·이름 변경·삭제 금지. 유일한 예외가 `ABBackgroundPolicy` 케이스 추가이며, 그 영향은 결정 3에서 별도로 논증한다 | `POLICY-api-stability.md` "Adding `enum` cases", ROADMAP §0 |
| deprecated 신규 부착 금지 | 신규 표면이 기존 것을 대체해도 `@available(*, deprecated)`를 붙이지 않는다. 라이브러리 내부가 그 심볼을 계속 쓰므로 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`에서 자기 경고가 난다 | `POLICY-api-stability.md` §"Worked example" 마지막 항목, `ABVideoPlayerWithControls.swift:9-21`의 회피 구조 |
| 프로세스 전역 자원은 명시 opt-in + 스냅숏/복원 | NowPlaying(`MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`)은 `AVAudioSession`과 동일 등급의 프로세스 전역 자원이다. 아무도 붙지 않았으면 **한 바이트도 쓰지 않는다** | README `:247-258`, `ABPlayerConfiguration.swift:51`(`audioSessionPolicy` 기본 `.unmanaged`), `ABPlayer.swift:170-176`(`ABAudioSessionCoordinator` 선례) |
| `AVPlayerLayer`는 계속 private | `ABPlayerView`의 백킹 레이어는 외부에 노출하지 않는다. `playerLayer.player`를 쓰는 주체는 `rebindPlayerLayer()` 하나로 유지 | `ABPlayerView.swift:9,11-15,99-105` |
| `@unchecked Sendable` / `MainActor.assumeIsolated` 금지 | 코드베이스 확립된 금지 | `DESIGN-OPEN-QUESTIONS.md` Q13, `ABPlayerControls.swift:191-216`(금지 사유를 명시한 `deinit` 홉 주석) |
| 코어 이벤트 표면은 **소비만** | 트랙 G는 `ABPlayerEvent`에 케이스를 **추가하지 않는다**. 필요한 것이 없으면 §8로 전달 | core §5.5 동결, HANDOFF §4-1b(이벤트 1개 추가가 Controls 특성화 테스트를 깼던 실제 사고) |
| 새 주석에 리뷰/설계 ID 인용 금지 | 불변식만 서술한다. 본 문서의 ID(G-1, I-G3, R-2 등)를 **소스 주석에 적지 말 것**. 제출 전 diff 추가 라인을 ID 패턴(`G-\d`, `I-G\d`, `WP\d`, `round\d`)으로 직접 재스캔할 것 | ROADMAP §0, HANDOFF §4-8, H-2 재발 방지 |
| 커밋 금지 / 시뮬레이터 신규 부팅 금지 / `sleep` 금지 | 이미 부팅된 기기는 재사용한다(전체 스킴 실행은 필수) | ROADMAP §0, HANDOFF §4-1b·§4-2 |

### 0.1 파일 경계 (트랙 G가 잡는 것)

**신규**
- `Sources/ABPlayerKitNowPlaying/**` (신규 타깃)
- `Sources/ABPlayerKit/View/ABPictureInPictureSession.swift`
- `Tests/ABPlayerKitNowPlayingTests/**`
- `Tests/ABPlayerKitTests/ABPictureInPictureSessionTests.swift`, `ABContinueAudioOnlyTests.swift`, `ABExternalPlaybackConfigurationTests.swift`

**수정 허용** (이번 Wave에 다른 트랙이 잡고 있지 않음)
- `Sources/ABPlayerKit/View/ABPlayerView.swift`
- `Sources/ABPlayerKit/Engine/ABPlayer.swift`, `ABPlaybackTarget.swift`, `ABAVPlaybackTarget.swift`
- `Sources/ABPlayerKit/Policy/ABBackgroundPolicy.swift`, `ABBackgroundPolicyMachine.swift`
- `Sources/ABPlayerKit/Model/ABPlayerConfiguration.swift`
- `Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift`
- `Sources/ABPlayerKit/ABPlayerKit.docc/**`
- `Package.swift`
- `Tests/ABPlayerKitTests/ABBackgroundPolicyMachineTests.swift`, `Fakes/ABFakePlaybackTarget.swift` (§6.4의 사전 승인 범위 내에서만)
- `README.md`, `README.ko.md`, `CHANGELOG.md`
- `Examples/ABPlayerKitDemo/**`의 **재생/PiP/NowPlaying 영역만**

**수정 금지 (위반 시 G-5 REQUEST-CHANGES)**
- `Sources/ABPlayerKitControls/**` 전체 — 트랙 C가 동시 작업 중
- 그중에서도 `Sources/ABPlayerKitControls/SwiftUI/` 4파일(`ABPlayerControls.swift`, `ABVideoPlayerWithControls.swift`, `ABPlayerControlsEnvironment.swift`, `ABOwnedPlayerBox.swift`) — 트랙 C도 diff 0줄로 묶여 있다. **읽고 사용하는 것은 허용, 수정은 금지**
- `Sources/ABPlayerKitMetrics/**`, `Examples/.../MetricsScreen.swift`, `DemoModel.swift`의 **메트릭 관련 멤버** — 트랙 F 소유(metrics §12). G는 별도 프로퍼티로 추가하고 병합 순서(F → G)에 따라 리베이스한다
- `Sources/ABPlayerKitCache/**`
- `Tests/ABPlayerKitControlsTests/**` 전체

### 0.2 소비하는 코어 확정 표면 (core §5.5 동결분 중 G가 쓰는 것)

| 심볼 | 용도 | WP |
|---|---|---|
| `player.isPlaying` (저장·관찰, 명령 직후 동기) | NowPlaying `PlaybackRate`, `togglePlayPause` 라우팅 | G-1w |
| `player.duration` / `durationAvailable(CMTime)` | `PlaybackDuration`, `changePlaybackPosition` 활성 여부 | G-1w |
| `player.currentTime` | `ElapsedPlaybackTime` (발행 시점 스냅숏) | G-1w |
| `player.isBuffering` / `bufferingChanged(Bool)` | 레이트 0 반영(스톨 중 진행바 정지) | G-1w |
| `player.grade` / `gradeChanged(from:to:)` | NowPlaying 소유권 자격(R1) 판정 | G-1w |
| `itemAttached(source:)` / `itemDetached(reason:)` | 세션 경계, 메타데이터 무효화 | G-1w |
| `seekCompleted(to:)` / `scrubbingChanged(isScrubbing:)` | 위치 재발행 시점 | G-1w |
| `rateChanged(Float)` / `playedToEnd` | 레이트·종료 반영 | G-1w |
| `presentationSizeChanged(CGSize)` | (참고용, 이번 라운드 미사용) | — |
| `ABErrorOrigin` | PiP 시작 실패의 `(domain, code)` 환원 | G-2w |
| `ABObservationToken` (공개 `init(onCancel:)`) | NowPlaying 등록 토큰의 기반 타입 | G-1w |

`ABPlayerEvent`는 non-exhaustive 계약이므로(`ABPlayerEvent.swift`의 타입 주석) NowPlaying 브리지의 `switch`에는 `default`를 둔다.

---

## 1. 결정 요약

| # | 결정 | 선택 |
|---|---|---|
| 1 | NowPlaying 타깃 API | **`ABPlayerKitNowPlaying` 신규 타깃 + 프로세스 전역 `ABNowPlayingCenter.shared` + 참가자 LIFO 스택.** 명시 `attach(_:metadata:)` 전에는 전역 상태 무접촉, 첫 획득 시 스냅숏 / 마지막 반납 시 복원. 순수 리듀서 3종 + `MediaPlayer` 어댑터 1종 |
| 2 | PiP 노출 형태 | **`ABPictureInPictureSession`(코어 신규 공개 타입) + `ABPlayerView.pictureInPictureSession` 바인딩 + `ABVideoPlayer.init(player:videoGravity:pictureInPicture:)`.** 맨 팩토리·레이어 접근자 모두 기각 |
| 3 | `.continueAudioOnly` | **`pauseAndDetachLayer`에서 `.pause`만 뺀 정책.** 레이어는 **뗀다**(그것이 iOS에서 배경 오디오가 계속되는 조건). 케이스 추가는 소스 호환 위험을 인정하고 non-exhaustive 주석 + Migration 노트로 처리 |
| 4 | PiP × 편의 API 자동 해제 | **v0.4.0에서는 억제 수단 불필요 — 편의 API에 PiP 파라미터를 넣지 않으므로 억제할 대상 자체가 없다.** 필요해지는 조건과 그때의 확정 형태를 §5에 기록하고, **v0.5.0 additive 옵션으로 이월 권고** |
| 5 | AirPlay 노브 | **`ABPlayerConfiguration`에 3개 값 프로퍼티**(`allowsExternalPlayback`=`true`, `usesExternalPlaybackWhileExternalScreenIsActive`=`false`, `externalPlaybackVideoGravity`=`.resizeAspect`) + **읽기 전용 computed `player.isExternalPlaybackActive`**. 런타임 setter 신설 없음, 신규 이벤트 없음 |
| 6 | 문서 범위 | 자막/오디오 트랙 선택은 **non-goal 유지 + escape hatch 경로 문서화**. 추가로 **현재 README에 전무한 `backgroundPolicy` 절을 신설**하고, PiP/AirPlay/배경 오디오의 전제조건 표를 넣는다 |

---

## 2. 결정 1 — `ABPlayerKitNowPlaying` 신규 타깃 API (감사 G-3)

### 2.1 왜 별도 타깃인가

코어에 넣지 않는다. `MediaPlayer.framework` 링크는 프로세스 전역 리모트 커맨드 표면을 끌고 들어오고, 이 리포는 이미 **"쓰지 않는 기능은 링크하지 않는다"**를 4모듈 분리로 관철하고 있다(`Package.swift`의 4개 product, README `:218-224`의 타깃 표). 캐시/메트릭이 별도 타깃인 것과 정확히 같은 이유다.

`Package.swift`에 추가:

```swift
.library(name: "ABPlayerKitNowPlaying", targets: ["ABPlayerKitNowPlaying"]),
...
.target(name: "ABPlayerKitNowPlaying", dependencies: ["ABPlayerKit"]),
.testTarget(
    name: "ABPlayerKitNowPlayingTests",
    dependencies: ["ABPlayerKitNowPlaying", "ABPlayerKit", "ABTestSupport"]
)
```

### 2.2 공개 표면

```swift
// ABNowPlayingMetadata.swift
/// 소비자만 알 수 있는 정보. 코어는 URL 외에 아무것도 모르므로 브리지가 추론하지 않는다.
public struct ABNowPlayingMetadata: Sendable, Equatable {
    public enum MediaType: Sendable, Equatable { case video, audio }

    public var title: String
    public var artist: String?
    public var albumTitle: String?
    public var mediaType: MediaType
    /// `true`이거나 아이템 duration이 유한하지 않으면 라이브로 발행한다.
    public var isLiveStream: Bool
    public var externalContentIdentifier: String?

    public init(
        title: String,
        artist: String? = nil,
        albumTitle: String? = nil,
        mediaType: MediaType = .video,
        isLiveStream: Bool = false,
        externalContentIdentifier: String? = nil
    )
}

// ABRemoteCommandSet.swift
public struct ABRemoteCommandSet: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int)

    public static let play: ABRemoteCommandSet
    public static let pause: ABRemoteCommandSet
    public static let togglePlayPause: ABRemoteCommandSet
    public static let skipForward: ABRemoteCommandSet
    public static let skipBackward: ABRemoteCommandSet
    public static let changePlaybackPosition: ABRemoteCommandSet
    public static let changePlaybackRate: ABRemoteCommandSet
    public static let nextTrack: ABRemoteCommandSet
    public static let previousTrack: ABRemoteCommandSet

    /// 대응 동작이 항상 존재하는 6종만. `nextTrack`/`previousTrack`은
    /// 라이브러리에 큐 개념이 없어 제외, `changePlaybackRate`는 지원 레이트
    /// 목록이 있어야 의미가 있어 제외.
    public static let `default`: ABRemoteCommandSet
}

// ABNowPlayingConfiguration.swift
public struct ABNowPlayingConfiguration: Sendable, Equatable {
    public var commands: ABRemoteCommandSet          // 기본 .default
    public var skipInterval: TimeInterval            // 기본 15
    /// `.changePlaybackRate`를 켰을 때만 의미. 값은 `ABPlaybackRate.clamped`를 거친다.
    public var supportedPlaybackRates: [Float]       // 기본 []
    public init(...)
}

// ABNowPlayingArtworkProviding.swift
/// `MPMediaItemArtwork`의 requestHandler는 임의 크기로 **여러 번, 임의 스레드에서
/// 동기 호출**된다. 그래서 이 프로토콜은 원본 이미지를 **한 번** 비동기로 해석하는
/// 책임만 지고, 크기별 리사이즈는 브리지가 캐시된 원본에서 동기 수행한다.
@MainActor
public protocol ABNowPlayingArtworkProviding: AnyObject {
    /// `nil` 반환 또는 취소는 "아트워크 없음"이며, 그 경우 브리지는
    /// `MPMediaItemPropertyArtwork` 키를 **넣지 않는다**(자체 플레이스홀더 금지).
    func artwork(for metadata: ABNowPlayingMetadata) async -> UIImage?
}

/// 이미 이미지를 들고 있는 소비자용 기본 구현.
@MainActor
public final class ABStaticArtworkProvider: ABNowPlayingArtworkProviding {
    public init(image: UIImage?)
    public func artwork(for metadata: ABNowPlayingMetadata) async -> UIImage?
}

// ABNowPlayingCenter.swift
@MainActor
public final class ABNowPlayingCenter {
    /// 프로세스 전역 단일 자원의 단일 소유자.
    public static let shared: ABNowPlayingCenter

    /// 테스트 심 — `ABNowPlayingSurface`(internal 프로토콜) 주입.
    /// 프로덕션 경로는 `.shared`만 쓴다.
    init(surface: any ABNowPlayingSurface)

    /// 현재 NowPlaying 표면을 소유한 플레이어. 아무도 없으면 `nil`이며,
    /// 그 상태에서 이 타입은 전역 상태를 한 바이트도 건드리지 않는다.
    public private(set) var owner: ABPlayerID?

    /// 참가자로 등록한다. 토큰이 해제(`cancel()` 또는 `deinit`)되면 반납한다.
    /// 반환값을 버리면 즉시 반납되므로 `@discardableResult`가 **아니다**.
    public func attach(
        _ player: ABPlayer,
        metadata: ABNowPlayingMetadata,
        configuration: ABNowPlayingConfiguration = ABNowPlayingConfiguration(),
        artwork: (any ABNowPlayingArtworkProviding)? = nil
    ) -> ABObservationToken

    /// 같은 플레이어의 메타데이터 갱신. 소유 중이면 즉시 재발행,
    /// 아니면 다음 획득 시 반영된다.
    public func update(_ metadata: ABNowPlayingMetadata, for player: ABPlayer)

    /// `nextTrack`/`previousTrack`을 켰을 때 필요한 소비자 동작.
    /// 핸들러 없이 커맨드만 켜면 그 커맨드는 **활성화되지 않는다**.
    public func setTrackNavigationHandlers(
        next: (@MainActor () -> Void)?,
        previous: (@MainActor () -> Void)?,
        for player: ABPlayer
    )
}
```

`ABObservationToken`을 재사용하는 근거: 이 타입은 `public init(onCancel:)`을 갖고 있고 그 doc 주석이 **"Extension targets can use this initializer to expose observation APIs with the same lifetime contract as ABPlayerKit"**라고 명시한다(`ABObservationToken.swift:19-21`). `deinit`에서 자동 `cancel()`까지 이미 보장한다(`:47-49`). 신규 토큰 타입을 만들 이유가 없다.

### 2.3 다중 플레이어 중 "현재" 선정 규칙 (프로세스 전역 자원 조정)

`ABPlayer`는 인스턴스마다 독립적인 grade를 갖고, 동시에 여러 인스턴스가 `.current`일 수 있다(피드 시나리오 — `ABPlaybackGrade.swift`에 전역 유일성 제약 없음). NowPlaying은 프로세스 전역 단일 자원이므로 조정자가 필요하다. `ABAudioSessionCoordinator`가 이미 같은 문제를 refcount + 스냅숏/복원으로 풀었고(`ABPlayer.swift:170-176`, `:1066-1069`, `:1088-1092`), NowPlaying도 **동형이되 배타적**(refcount가 아니라 단일 소유)이다.

확정 규칙:

| # | 규칙 | 정의 |
|---|---|---|
| **R1 자격** | `grade == .current`인 참가자만 소유할 수 있다 | NowPlaying은 "지금 재생 중인 것"을 기술한다. `.preloaded` 피드 셀은 자격이 없다. `attach`는 grade와 무관하게 성공하지만(참가자 등록), 소유는 `.current` 진입 시점에 일어난다 |
| **R2 획득** | 자격을 얻은 참가자가 **스택 최상단**으로 올라가고 소유권을 가져간다(last-eligible-wins) | 피드에서 다음 셀을 `.current`로 승격하면 NowPlaying이 그리로 넘어간다 — iOS 자체의 "마지막에 쓴 앱이 이긴다"와 같은 방향 |
| **R3 반납** | 소유자가 `.current`를 벗어나거나(`gradeChanged(to: < .current)`), `itemDetached`를 받거나, 토큰이 해제되거나, 인스턴스가 소멸(weak → nil)하면 반납한다 | 반납 시 스택에서 제거하고, 남은 참가자 중 **자격 있는 최상단**이 즉시 승계한다 |
| **R4 경합** | 두 참가자가 동시에 `.current`이면 **나중에 자격을 얻은 쪽**이 소유, 먼저 있던 쪽은 스택에 남는다. 나중 것이 반납하면 먼저 것이 자동 복귀한다 | LIFO. 싸우지 않고 결정적이다 |
| **R5 위생** | 스택이 비면 첫 획득 시 찍어 둔 스냅숏을 복원한다: `nowPlayingInfo`를 스냅숏 값으로 되돌리고, 이 브리지가 `addTarget`한 모든 핸들러를 `removeTarget`하고, 각 커맨드의 `isEnabled`를 스냅숏 값으로 되돌린다 | `MPNowPlayingInfoCenter.nowPlayingInfo`는 **읽을 수 있으므로** 스냅숏이 실제로 가능하다. 오디오 세션과 달리 "이미 활성이었는지 알 수 없음" 문제가 없다 |
| **R6 무접촉** | 참가자가 0명인 동안 이 타입은 `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`에 **읽기조차 하지 않는다**(스냅숏은 첫 `attach`가 소유를 획득하는 순간 1회) | 프로젝트의 확립된 입장(README `:247-249`) |

이 6개 규칙 전체가 순수 리듀서 `ABNowPlayingOwnership`(internal, 값 타입)로 표현되며 `MediaPlayer` 없이 테이블 테스트된다 — `ABGradePlanner`/`ABBackgroundPolicyMachine`과 같은 형태다.

```swift
struct ABNowPlayingOwnership: Equatable {
    enum Effect: Equatable {
        case acquire(ABPlayerID)      // 소유 이전(발행 + 커맨드 활성)
        case relinquishAll            // 마지막 반납(스냅숏 복원)
        case none
    }
    mutating func register(_ id: ABPlayerID, isEligible: Bool) -> Effect
    mutating func setEligible(_ id: ABPlayerID, _ eligible: Bool) -> Effect
    mutating func unregister(_ id: ABPlayerID) -> Effect
    var owner: ABPlayerID? { get }
}
```

### 2.4 리모트 커맨드 선택 — "빈 핸들러 금지" 불변식

**불변식 I-G1: 활성화된 커맨드는 반드시 관측 가능한 동작을 낸다.** 대응 동작이 없는 커맨드는 활성화하지 않는다. 컨트롤 센터에 눌리는데 아무 일도 안 하는 버튼이 뜨는 것이 최악이라는 브리프의 지적을 규칙으로 고정한다.

| 커맨드 | 기본 | 매핑 | 활성화 조건 |
|---|---|---|---|
| `playCommand` | **ON** | `player.play()` | 소유자는 R1에 의해 항상 `.current`이므로 항상 유효 |
| `pauseCommand` | **ON** | `player.pause()` | 〃 |
| `togglePlayPauseCommand` | **ON** | `player.isPlaying ? pause() : play()` | 헤드셋 버튼의 실제 경로. `isPlaying`이 명령 직후 동기라는 코어 불변식(core §5.1 I-1)에 의존 |
| `skipForwardCommand` | **ON** | `Task { await player.skip(by: +interval) }` | `preferredIntervals = [configuration.skipInterval]`. `skip(by:)`가 `pendingSeekTime` 기반 누적이므로 연타가 정확히 합산된다(`ABPlayer.swift:416-439`) |
| `skipBackwardCommand` | **ON** | `skip(by: -interval)` | 〃 |
| `changePlaybackPositionCommand` | **ON (조건부)** | `Task { await player.seek(to: CMTime(seconds: event.positionTime, ...)) }` | **`player.duration`이 유한할 때만 활성.** 라이브/불명이면 비활성 → 진행바가 잡히는데 안 움직이는 상태를 만들지 않는다. `durationAvailable`/`itemDetached`에서 재평가 |
| `changePlaybackRateCommand` | OFF | `player.setRate(_:)` | `supportedPlaybackRates`가 비어 있지 않을 때만. 값은 `ABPlaybackRate.clamped`를 거치므로 `supportedPlaybackRates`도 클램프된 값으로 발행 |
| `nextTrackCommand` | OFF | 소비자 핸들러 | 라이브러리에 큐 개념이 없다. **핸들러가 없으면 켜도 활성화하지 않는다**(I-G1) |
| `previousTrackCommand` | OFF | 소비자 핸들러 | 〃 |
| `seekForward`/`seekBackward`(연속) | OFF·범위 밖 | — | begin/end 단계가 있는 연속 탐색은 코어에 대응 모델이 없다. `ABPlayer.setRate` 조작으로 흉내 내면 사용자가 놓았을 때 원래 배속 복원 책임이 생기고, 그것은 별도 설계 항목이다 |
| `stop`, `changeRepeatMode`, `changeShuffleMode`, `like`/`dislike`/`bookmark`/`rating` | 범위 밖 | — | 대응 개념 없음 |

커맨드 라우팅도 순수 리듀서로 분리한다(테스트에서 `MPRemoteCommandEvent`를 만들 수 없으므로 이것이 유일한 검증 경로다):

```swift
enum ABRemoteCommandIntent: Equatable {
    case play, pause, togglePlayPause
    case skip(TimeInterval)
    case seek(seconds: Double)
    case setRate(Float)
    case nextTrack, previousTrack
}

enum ABRemoteCommandOutcome: Equatable {
    case perform(ABRemoteCommandIntent)
    case rejectNoOwner          // MPRemoteCommandHandlerStatus.noActionableNowPlayingItem
    case rejectNotSeekable      // .commandFailed
    case rejectNoHandler
}

struct ABRemoteCommandRouter {
    func outcome(
        for intent: ABRemoteCommandIntent,
        ownerExists: Bool,
        isSeekable: Bool,
        hasTrackHandlers: (next: Bool, previous: Bool)
    ) -> ABRemoteCommandOutcome
}
```

### 2.5 NowPlaying 정보 발행 — 키 매핑과 **발행 시점**

```swift
struct ABNowPlayingInfo: Equatable {          // internal, 골든 테스트 대상
    var title: String
    var artist: String?
    var albumTitle: String?
    var duration: Double?                     // 유한할 때만
    var elapsed: Double
    var rate: Double
    var defaultRate: Double
    var isLiveStream: Bool
    var mediaType: ABNowPlayingMetadata.MediaType
    var externalContentIdentifier: String?
    var hasArtwork: Bool
    /// MPNowPlayingInfoCenter에 넘길 최종 딕셔너리.
    func dictionary(artwork: MPMediaItemArtwork?) -> [String: Any]
}

struct ABNowPlayingInfoBuilder {
    /// 순수 함수. `ABPlayer`를 받지 않고 스냅숏만 받는다 → MediaPlayer/AVFoundation 없이 테스트 가능.
    func info(metadata: ABNowPlayingMetadata, snapshot: ABNowPlayingPlayerSnapshot) -> ABNowPlayingInfo
}

struct ABNowPlayingPlayerSnapshot: Equatable {
    var currentTimeSeconds: Double
    var durationSeconds: Double?              // 유한하지 않으면 nil
    var isPlaying: Bool
    var isBuffering: Bool
    var rate: Float
}
```

| MediaPlayer 키 | 소스 |
|---|---|
| `MPMediaItemPropertyTitle` / `Artist` / `AlbumTitle` | `metadata` |
| `MPMediaItemPropertyPlaybackDuration` | `player.duration`이 `isNumeric && seconds.isFinite && > 0`일 때만. 아니면 키 자체를 넣지 않는다 |
| `MPNowPlayingInfoPropertyElapsedPlaybackTime` | 발행 시점의 `player.currentTime` |
| `MPNowPlayingInfoPropertyPlaybackRate` | `isPlaying && !isBuffering ? Double(rate) : 0` — 스톨 중 잠금화면 진행바가 계속 전진하는 오차를 없앤다 |
| `MPNowPlayingInfoPropertyDefaultPlaybackRate` | `Double(player.rate)` (= `configuration.playbackRate`, `ABPlayer.swift:69`) |
| `MPNowPlayingInfoPropertyIsLiveStream` | `metadata.isLiveStream || duration == nil` |
| `MPNowPlayingInfoPropertyMediaType` | `metadata.mediaType` |
| `MPMediaItemPropertyArtwork` | 아트워크 해석 성공 시에만 |
| `MPNowPlayingInfoPropertyExternalContentIdentifier` | `metadata` |

**발행 시점 = 이산 전이만. `.periodicTime`은 구독하지 않는다.** NowPlaying은 (위치, 레이트) 쌍을 주면 시스템이 외삽하므로 틱마다 쓰는 것은 낭비이자 진동의 원인이다.

발행 트리거(정확히 이 목록):
`소유권 획득` / `update(_:for:)` 호출 / `timeControlStatusChanged` / `bufferingChanged` / `rateChanged` / `seekCompleted` / `scrubbingChanged(isScrubbing: false)` / `durationAvailable` / `playedToEnd` / `itemAttached` / 아트워크 해석 완료.

명시적 비구독: `.periodicTime`, `.presentationSizeChanged`, `.tuningApplied`, `.failed`/`.failureReported`(실패는 NowPlaying 표면의 개념이 아니다 — 소비자가 `lastFailure`로 처리한다).

### 2.6 아트워크 공급자 — 동기/비동기, 취소, 폴백

`MPMediaItemArtwork(boundsSize:requestHandler:)`의 requestHandler는 **동기**이고, 임의 크기로 여러 번, 임의 스레드에서 호출된다. 따라서:

1. 브리지가 `provider.artwork(for:)`를 **1회** `Task`로 호출해 원본 `UIImage`를 얻는다(비동기 I/O는 전부 여기서 끝난다).
2. 얻은 원본으로 `MPMediaItemArtwork(boundsSize: image.size) { requested in /* 캐시된 원본을 requested 크기로 동기 리사이즈 */ }`를 만든다. **requestHandler 안에서 I/O·await·락 대기 금지**가 구현 규칙이다.
3. **취소/세대 가드**: 각 해석 `Task`에 `artworkGeneration` 정수를 캡처시키고, `update(_:)`·소유권 이전·`itemDetached`가 세대를 증가시키며 이전 `Task`를 `cancel()`한다. 늦게 도착한 결과는 세대 불일치로 버린다. 이 관용구는 코어가 이미 두 곳에서 쓴다 — `seekGeneration`(`ABPlayer.swift:1163-1181`)과 stale-item 가드(`ABAVPlaybackTarget.swift:475,489,540`).
4. **실패 폴백**: `nil` 반환·취소·throw(프로토콜이 throws가 아니므로 provider 내부에서 삼킨다) → `MPMediaItemPropertyArtwork` 키를 **넣지 않고** 나머지 정보만 발행한다. 라이브러리가 만든 플레이스홀더 이미지를 넣지 않는다(소비자의 브랜드 자산을 라이브러리가 대신 발명하지 않는다).
5. `provider == nil`이면 3·4 전체를 건너뛴다.

### 2.7 MediaPlayer 어댑터 심

```swift
/// `ABPlaybackTarget`과 같은 역할의 단일 심. 프로덕션 구현 1개 +
/// 테스트 페이크 1개. 이 프로토콜 덕분에 위 리듀서 3종과
/// 소유권/발행 로직 전체가 MediaPlayer 없이 검증된다.
@MainActor
protocol ABNowPlayingSurface: AnyObject {
    func snapshotInfo() -> [String: Any]?
    func setInfo(_ info: [String: Any]?)
    func snapshotCommandEnablement() -> [ABRemoteCommandKey: Bool]
    func setCommand(_ key: ABRemoteCommandKey, enabled: Bool, handler: (@MainActor (ABRemoteCommandIntent) -> ABRemoteCommandOutcome)?)
    func restoreCommandEnablement(_ snapshot: [ABRemoteCommandKey: Bool])
}
```

### 2.8 기각안

| 기각안 | 사유 |
|---|---|
| 코어 `ABPlayer`에 `nowPlayingMetadata` 프로퍼티 추가 | 코어가 `MediaPlayer`를 링크하게 되고, 메타데이터(제목/아티스트)는 코어가 알 수 없는 소비자 도메인 정보다. `ABMediaSource`는 URL·kind·헤더만 갖는다(`ABMediaSource.swift:11-19`) |
| 자동 opt-in(플레이어가 `.current`가 되면 알아서 NowPlaying 점유) | §0의 "프로세스 전역 무접촉" 원칙 정면 위배. `audioSessionPolicy` 기본값이 `.unmanaged`인 것과 같은 이유(`ABPlayerConfiguration.swift:51`) |
| 소유권을 refcount로(오디오 세션과 동일하게) | NowPlaying은 배타적 자원이다. refcount는 "여러 참가자가 동시에 유효"를 전제하는데, 여기서는 마지막 쓰기만 살아남는다 → LIFO 스택이 맞는 모델 |
| 플레이어를 강하게 보유 | 브리지가 플레이어 수명을 연장하면 `release()` 후에도 `AVPlayer`가 살아남는다. `weak var player: ABPlayer?`로 보유하고 `nil` 관측 시 R3 반납 |
| `.periodicTime` 구독으로 elapsed 실시간 갱신 | 시스템이 (위치, 레이트)로 외삽한다. 틱마다 전역 딕셔너리를 쓰면 비용만 들고, 스크럽 중에는 진동한다 |
| `MPRemoteCommandEvent`를 테스트에서 직접 생성 | 공개 이니셜라이저가 없다. 그래서 §2.4의 순수 라우터 분리가 **선택이 아니라 필수**다 |
| 아트워크를 requestHandler 안에서 비동기 로드 | requestHandler는 동기 계약이다. 안에서 세마포어로 기다리면 임의 스레드를 블로킹한다 |

---

## 3. 결정 2 — PiP 노출 형태 (감사 G-1)

### 3.1 문제의 실제 형태

`AVPlayerLayer`가 완전 private이다:

```swift
public override class var layerClass: AnyClass { AVPlayerLayer.self }   // ABPlayerView.swift:9

private var playerLayer: AVPlayerLayer {                                 // :11-15
    layer as! AVPlayerLayer
}
```

그리고 `playerLayer.player`를 쓰는 주체는 정확히 두 곳뿐이다 — `attach(_:)`의 초기화(`ABPlayerView.swift:69`)와 `rebindPlayerLayer()`(`:99-105`). 후자는 `isLayerAttachmentEnabled` 게이트를 통해 배경 정책의 detach를 구현한다:

```swift
let attachedPlayer = player?.isLayerAttachmentEnabled == true ? player : nil   // :101
playerLayer.player = attachedPlayer?.avPlayer
detector.observe(layer: playerLayer, item: attachedPlayer?.avPlayerItem)       // :103
```

즉 `playerLayer.player`는 **배경 정책과 TTFF 검출(`ABFirstFrameDetector`)의 공유 진실원**이다.

### 3.2 선택안: `ABPictureInPictureSession` (세션 객체) + 뷰 바인딩

```
Sources/ABPlayerKit/View/ABPictureInPictureSession.swift   (신규, ~150줄)
Sources/ABPlayerKit/View/ABPlayerView.swift                (프로퍼티 1개 + 바인딩 로직 추가)
Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift            (이니셜라이저 파라미터 1개 추가)
```

세션이 `AVPictureInPictureController`를 소유하고, `ABPlayerView`가 자기 백킹 레이어를 세션에 넘긴다. 레이어는 여전히 public 표면에 나타나지 않는다.

### 3.3 기각안과 기각 사유

| 기각안 | 사유 |
|---|---|
| **`AVPlayerLayer` 접근자 노출** (`public var playerLayer: AVPlayerLayer`) | `playerLayer.player`를 소비자가 직접 쓸 수 있게 되는 순간 ① `pauseAndDetachLayer`가 조용히 무력화되고 ② `ABFirstFrameDetector`가 관측하는 레이어와 실제 재생 레이어가 갈라져 TTFF 정의(레이어 ready AND 아이템 ready)가 깨진다(`ABPlayerView.swift:99-105`). 감사가 "강점 — 건드리지 말 것"에 TTFF 정의를 올려 뒀다(audit §강점) |
| **맨 팩토리** `ABPlayerView.makePictureInPictureController() -> AVPictureInPictureController?` (감사·로드맵의 문자 그대로의 안) | ① **SwiftUI에서 도달 불가.** `ABVideoPlayer`는 `makeUIView(context:)` 안에서 `ABPlayerView`를 만들고(`ABVideoPlayer.swift:59-71`) 밖으로 내보내는 접근자가 없다. `ABVideoPlayerWithControls`도 마찬가지다(`ABVideoPlayerWithControls.swift:190`이 내부에서만 씀). 제품 목표 1번의 주 통합 경로에서 못 쓰는 기능은 출하된 기능이 아니다. ② PiP 버튼은 `isPictureInPicturePossible`로 활성/비활성, `isPictureInPictureActive`로 글리프를 바꾼다. 둘 다 KVO 전용이라 SwiftUI가 소비하려면 `@Observable` 미러가 필요한데, 그 미러의 소유자가 없다. ③ 라이브러리가 "PiP가 켜져 있다"를 알 수 없어 §4의 상호작용 매트릭스를 **정의할 수 없다** — 기본 `backgroundPolicy`가 `.pause`(`ABPlayerConfiguration.swift:50`)이므로 PiP는 기본 설정에서 깨진 채 출하된다 |
| 세션을 `ABPlayer`에 붙이기(`player.makePictureInPictureController()`) | `ABPlayer`는 레이어를 모른다. 내부에 별도 `AVPlayerLayer`를 만들면 화면에 없는 레이어라 `isReadyForDisplay`에 도달하지 못한다 |
| `AVPictureInPictureVideoCallViewController` 계열(콘텐츠 소스 API) | 영상 통화용 표면이다. `AVPlayerLayer` 기반 PiP가 이 라이브러리의 케이스다 |
| `AVPlayerViewController` 채택 | UI 전체를 애플 것으로 교체하는 것이고, 이 라이브러리의 Controls 타깃 존재 이유와 충돌한다 |

**선택안이 감사 G-1의 의도를 만족시키는가**: 만족시킨다. G-1의 요구는 "PiP를 가능하게 하라"이고 제안 형태는 예시였다. 선택안은 팩토리의 본질(뷰가 자기 레이어에 대해 컨트롤러를 만든다, 레이어는 계속 private)을 유지하면서, 맨 팩토리가 구조적으로 풀 수 없는 세 가지(SwiftUI 도달성·관찰성·정책 상호작용)를 해결한다. `session.controller`로 `AVPictureInPictureController` 원본을 그대로 내주므로 escape hatch도 닫히지 않는다(`ABPlayer.avPlayer`/`avPlayerItem`이 이미 세운 선례, `ABPlayer.swift:55-58`).

### 3.4 확정 시그니처

```swift
// Sources/ABPlayerKit/View/ABPictureInPictureSession.swift
@preconcurrency import AVKit

/// PiP 실패의 출처. `ABErrorOrigin`(코어 기존 타입)을 재사용한다.
public struct ABPictureInPictureFailure: Sendable, Equatable {
    public let description: String
    public let origin: ABErrorOrigin?
}

/// 하나의 `ABPlayerView`에 바인딩되는 PiP 세션.
///
/// 활성 상태(`isActive == true`) 동안 바인딩된 뷰를 **강하게 보유**한다 —
/// PiP는 소스 뷰가 화면에서 사라진 뒤에도 렌더링을 계속해야 하고, 그
/// 렌더 소스가 바로 그 뷰의 백킹 `AVPlayerLayer`이기 때문이다. 비활성으로
/// 돌아오면 보유를 놓는다.
@MainActor
@Observable
public final class ABPictureInPictureSession {
    public init()

    /// 기기/OS가 PiP를 지원하는가. 시뮬레이터에서는 대체로 `false`다.
    public static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// `AVPictureInPictureController.isPictureInPicturePossible`의 재계산 미러.
    /// 레이어가 `readyForDisplay`가 되기 전에는 `false`다.
    public private(set) var isPossible: Bool
    /// `isPictureInPictureActive`의 재계산 미러.
    public private(set) var isActive: Bool
    /// 마지막 시작 실패. 다음 `start()` 시도에서 `nil`로 리셋된다.
    public private(set) var lastFailure: ABPictureInPictureFailure?

    /// `canStartPictureInPictureAutomaticallyFromInline` 프록시.
    /// **기본 `false`.** 켜면 §4.4의 경합 경로에 들어간다.
    public var startsAutomaticallyFromInline: Bool
    public var requiresLinearPlayback: Bool

    /// PiP가 끝나고 원래 UI를 복원해야 할 때 호출된다. 복원에 성공했으면
    /// `true`를 반환한다. 미지정이면 `true`를 반환한 것으로 간주한다.
    public var restoreUserInterfaceHandler: (@MainActor () async -> Bool)?

    /// Escape hatch — delegate/추가 knob 접근용. `delegate`를 재지정하면
    /// `lastFailure`와 `restoreUserInterfaceHandler`가 동작을 멈춘다
    /// (`isPossible`/`isActive`는 KVO 기반이라 영향 없음).
    public var controller: AVPictureInPictureController? { get }

    public func start()
    public func stop()
}

// Sources/ABPlayerKit/View/ABPlayerView.swift (추가)
extension ABPlayerView {
    /// 세션을 바인딩하면 이 뷰의 백킹 `AVPlayerLayer`에 대해
    /// `AVPictureInPictureController`가 1회 생성된다. `nil` 대입은
    /// 언바인딩이며, 세션이 활성이면 **정지 시점까지 지연**된다.
    public var pictureInPictureSession: ABPictureInPictureSession? { get set }
}

// Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift (추가 — 명시 소유 경로 전용)
extension ABVideoPlayer {
    public init(
        player: ABPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        pictureInPicture: ABPictureInPictureSession
    )
}
```

`AVKit` import가 새로 필요하다(`AVPictureInPictureController`는 AVKit). 코어 타깃에 AVKit 링크가 추가되는 것은 iOS 17+에서 실질 비용이 없고, `ABVideoPlayer`가 SwiftUI를 같은 이유로 코어에 두고 있다(`ABVideoPlayer.swift:4-8`).

### 3.5 상태 미러링 방식

`isPossible`/`isActive`는 **KVO**로 관측한다(delegate가 아니라). 이유: `session.controller.delegate`를 소비자가 재지정해도 상태 추적과 §4의 정책 억제가 살아남아야 한다. delegate는 `lastFailure`(`failedToStartPictureInPictureWithError:`)와 `restoreUserInterfaceHandler`(`restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:`)에만 쓴다.

미러 갱신은 코어의 확립된 패턴을 따른다 — **값이 실제로 바뀔 때만 대입**(`ABPlayer.swift:608-638`의 `refreshPlaybackMirrors()`). `@Observable`은 동일 값 재대입에도 `withMutation`을 다시 발화시켜 SwiftUI를 무효화하기 때문이다.

`isActive`가 바뀌면 세션은 `boundView?.player?.setPictureInPictureActive(_:)`(코어 internal 메서드)를 호출한다. `reportFirstFrameDisplayed(at:)`가 이미 같은 방향의 internal 콜백이다(`ABPlayer.swift:551-558`).

---

## 4. PiP × 레이어 detach 정책 상호작용 매트릭스 (결정 2의 핵심 산출물)

### 4.1 충돌의 정체

`pauseAndDetachLayer`는 배경 진입 시 다음을 수행한다:

```swift
case .pauseAndDetachLayer:
    return (grade == .current ? [.pause] : []) + [.setLayerAttachment(false)]   // ABBackgroundPolicyMachine.swift:73-75
```

`.setLayerAttachment(false)` → `ABPlayer.setLayerAttachmentEnabled(false)`(`ABPlayer.swift:1222-1226`) → 레이어 부착 옵저버 방송 → `ABPlayerView.rebindPlayerLayer()` → **`playerLayer.player = nil`**(`ABPlayerView.swift:101-102`).

`AVPictureInPictureController`는 자신이 붙은 `AVPlayerLayer`의 `player`에서 렌더링한다. **PiP가 존재하는 이유가 "배경으로 가도 영상이 계속 보인다"인데, 배경 진입이 정확히 그 렌더 소스를 끊는다.** 정면 충돌이다. `.pause`/`.demoteToInstance`도 각각 재생 정지·아이템 detach(`ABPlayer.swift:693-708`)로 같은 결과를 만든다.

### 4.2 확정 규칙

> **PiP 세션이 활성인 동안 `backgroundPolicy`는 전 정책 공통으로 완전히 억제된다.**

논거:
1. `pauseAndDetachLayer`의 **목적**은 "영상이 보이지 않을 때 디코더를 놓는다"이다. PiP 중에는 영상이 **보인다**. 정책의 전제가 거짓이므로, 억제는 소비자 의도를 뒤엎는 것이 아니라 올바로 해석하는 것이다.
2. 반대(정책이 이긴다)를 택하면, 사용자가 PiP를 켠 바로 그 순간 PiP 창이 죽는다 — 정책이 아니라 고장이다.
3. 억제 범위는 `isActive`인 동안으로 한정된다. PiP가 끝나면 다음 생명주기 신호부터 정책이 정상 적용된다.
4. 한 문장 규칙이라 전 정책에 대해 테이블 테스트로 전수 고정할 수 있다.

구현 형태 — `ABBackgroundPolicyMachine`에 **기본값 있는** 파라미터 1개 추가(기존 호출부·테스트 6곳이 무수정 컴파일된다):

```swift
func actions(
    for signal: ABAppLifecycleSignal,
    policy: ABBackgroundPolicy,
    grade: ABPlaybackGrade,
    wasPlayingBeforeBackground: Bool,
    hasCapturedGrade: Bool,
    isPictureInPictureActive: Bool = false
) -> [ABBackgroundAction] {
    guard !isPictureInPictureActive else {
        switch signal {
        case .willResignActive, .didEnterBackground:
            return []
        case .willEnterForeground:
            return [.markAudioSessionDirty, .clearCapture]
        }
    }
    // 이하 기존 로직 그대로
}
```

`.markAudioSessionDirty`는 PiP 중에도 유지한다 — 배경 체류 중 시스템이 세션을 비활성화했을 가능성은 정책과 무관하며, 다음 `play()`가 재활성화하도록 두는 편이 안전하다(`ABBackgroundPolicyMachine.swift:86-90`의 기존 논거와 동일). `.clearCapture`는 `willResignActive`에서 아무것도 캡처하지 않았으므로 남은 잔재를 지우는 위생 조치다.

### 4.3 매트릭스 A — 앱 생명주기 × 정책 × PiP

`isActive == false`인 열은 **현행 동작과 바이트 동일**해야 한다(무회귀 불변식 I-G4).

| 정책 | PiP | willResignActive | didEnterBackground | willEnterForeground | 관찰 결과 |
|---|---|---|---|---|---|
| `.ignore` | 비활성 | `[]` | `[]` | `[.markAudioSessionDirty]` | 현행 |
| `.ignore` | **활성** | `[]` | `[]` | `[.markAudioSessionDirty, .clearCapture]` | PiP 계속. `.ignore`는 원래 PiP와 유일하게 양립하던 정책 |
| `.pause` (기본값) | 비활성 | `[.capturePlaying]` | `[.pause]`(`.current`일 때) | `[…, .resumePlay?, .clearCapture]` | 현행 |
| `.pause` | **활성** | `[]` | `[]` | `[.markAudioSessionDirty, .clearCapture]` | **PiP 계속 재생.** 기본 설정에서 PiP가 동작한다 |
| `.pauseAndDetachLayer` | 비활성 | `[.capturePlaying]` | `[.pause, .setLayerAttachment(false)]` | `[…, .setLayerAttachment(true), .resumePlay?, .clearCapture]` | 현행 |
| `.pauseAndDetachLayer` | **활성** | `[]` | `[]` | `[.markAudioSessionDirty, .clearCapture]` | **레이어 유지 + 재생 유지.** PiP 창이 살아 있다 |
| `.demoteToInstance` | 비활성 | `[]` | `[.demoteToInstance]` | `[…, .restoreCapturedGrade?]` | 현행 |
| `.demoteToInstance` | **활성** | `[]` | `[]` | `[.markAudioSessionDirty, .clearCapture]` | 아이템 유지 → PiP 계속. `gradeBeforeBackground`가 캡처되지 않으므로 복귀 시 복원할 것도 없다 |
| `.continueAudioOnly` (신규) | 비활성 | `[.capturePlaying]` | `[.setLayerAttachment(false)]` | `[…, .setLayerAttachment(true), .resumePlay?, .clearCapture]` | 결정 3 |
| `.continueAudioOnly` | **활성** | `[]` | `[]` | `[.markAudioSessionDirty, .clearCapture]` | **레이어를 떼지 않는다.** PiP 중에는 오디오만이 아니라 영상도 계속되어야 하므로 detach가 목적에 반한다 |

### 4.4 매트릭스 B — 레이어/아이템을 끊는 그 밖의 경로 × PiP 활성

억제는 **배경 정책의 자동 부작용에만** 적용된다. 소비자가 명시적으로 내린 명령은 억제하지 않는다 — 그것이 이 라이브러리가 "정책은 명시적, 마법 없음"을 지키는 방식이다.

| # | 트리거 | 코드 경로 | PiP 활성 시 확정 동작 |
|---|---|---|---|
| B-1 | `player.release()` | `ABPlayer.swift:353-355` → `.detachItem`(`:693-708`) → `.releasePlayer` | **PiP 종료.** 억제하지 않는다. 세션은 `isActive → false`를 관측하고 뷰 보유를 놓는다. 문서화 대상 |
| B-2 | `promote(to:)`로 `.current` 미만 강등 | `:347-349` → planner → `.detachItem` | **PiP 종료.** 억제하지 않는다 |
| B-3 | 소스 교체(같은 인스턴스, URL 변경) | `set(source:grade:)` → detach → attach | **PiP는 종료된다고 간주한다.** `replaceCurrentItem`이 개입하는 동안 PiP가 살아남는지는 플랫폼 보장이 없다(§10-4). 세션은 어느 쪽이든 KVO로 실제 상태를 따라간다 |
| B-4 | `ABPlayerView.player`에 다른 플레이어 대입 | `ABPlayerView.swift:63-97`(`:69`에서 `playerLayer.player = nil`) | **PiP 종료.** 세션은 뷰에 바인딩돼 있으므로 계속 바인딩된 채 남고, 새 플레이어가 붙은 뒤 `isPossible`이 다시 참이 되면 재시작 가능 |
| B-5 | `ABPlayerView` 자체 파기(SwiftUI `dismantleUIView` / UIKit dealloc) | `ABVideoPlayer.swift:85-87` | **PiP 활성이면 세션이 뷰를 강하게 보유하므로 뷰와 레이어가 살아남아 PiP가 계속된다.** 언바인딩은 `isActive == false`가 될 때까지 지연. 단 **`ABPlayer`가 별도로 살아 있어야** 한다 → §5의 결론으로 이어진다 |
| B-6 | `configuration.backgroundPolicy` 런타임 변경 | `ABPlayer.swift:797-803` | 정책 자체가 억제 중이므로 무해. 단 §5.3의 `detachesLayer` 수정이 없으면 `.continueAudioOnly → .ignore` 전환 시 레이어가 영구 detach 상태로 남는다(결정 3의 필수 수정) |
| B-7 | 오디오 인터럽션(`interruptionPolicy == .pauseAndResume`) | `:993-1036` | **억제하지 않는다.** 전화가 왔으면 PiP 창도 멈추는 것이 옳다. 인터럽션 종료 시 기존 규칙대로 재개 |
| B-8 | 라우트 변경 device unavailable | `:1038-1044` | **억제하지 않는다.** 이어폰이 빠지면 멈추는 것이 HIG 기대다(`ABPlayerConfiguration.swift:28-34`) |
| B-9 | `.playedToEnd` | `:577-580` | PiP 창이 종료 프레임에서 멈춘다. 라이브러리는 개입하지 않는다(리플레이는 Controls/소비자 몫 — 트랙 C의 D-5) |
| B-10 | 같은 세션 인스턴스를 두 번째 뷰에 바인딩 | 신규 코드 | **거부하지 않고 이전 뷰에서 언바인딩 후 재바인딩**한다. 단 활성 중이면 이전 뷰 언바인딩이 지연되므로, 그동안의 두 번째 바인딩 요청은 **무시하고 `lastFailure`에 사유를 기록**한다. 세션 1개 ↔ 뷰 1개 불변식(I-G3) |
| B-11 | PiP 활성 중 앱이 종료/스와이프 킬 | — | 플랫폼 소관. 라이브러리 동작 없음 |

### 4.5 배경 체류 중 PiP가 시작되는 경합 (`startsAutomaticallyFromInline`)

`canStartPictureInPictureAutomaticallyFromInline == true`이면 PiP는 **배경 전환 시점에** 시작된다. `UIApplication.didEnterBackgroundNotification` 처리(`ABPlayer.swift:893-901`)와 PiP 활성화 KVO 중 어느 쪽이 먼저인지는 **플랫폼이 보장하지 않는다**(§10-3, 확인 불가). 정책이 먼저 돌면 이미 pause/detach된 상태에서 PiP가 켜져 검은 창 또는 정지 프레임이 뜬다.

확정 동작 — **활성화 시 복구(repair) 경로**를 둔다. `ABPlayer.setPictureInPictureActive(true)`가 호출되면:

1. `!isLayerAttachmentEnabled`이면 `setLayerAttachmentEnabled(true)` — 레이어를 되붙인다.
2. `grade == .current && wasPlayingBeforeBackground && !isPlaying`이면 `play()`.
3. `wasPlayingBeforeBackground = false`(중복 재개 방지 — 이후 `willEnterForeground`의 `.clearCapture`와 멱등).
4. `grade < .current`(= `.demoteToInstance`가 이미 강등)면 아이템이 없으므로 PiP 활성화 자체가 성립하지 않는다. 복구하지 않는다.

기본값은 `startsAutomaticallyFromInline = false`이며, 이 경합 경로는 **"켤 수는 있으나 관측 가능한 결과가 한 번의 짧은 일시정지→재개를 포함할 수 있다"**로 문서화한다. 기본 지원 경로는 **포그라운드에서 사용자가 시작한 PiP**다.

### 4.6 PiP의 플랫폼 전제조건 (라이브러리가 대신 해 줄 수 없는 것)

| 전제 | 누가 하는가 | 확인 방법 |
|---|---|---|
| `UIBackgroundModes`에 `audio` | **호스트 앱 Info.plist.** 라이브러리 불가 | 없으면 배경 진입과 동시에 PiP가 멈춘다 |
| `AVAudioSession` 카테고리 `.playback` 활성 | 소비자가 `audioSessionPolicy = .playback(mixWithOthers:)`로 opt-in(기본 `.unmanaged`, `ABPlayerConfiguration.swift:51`) | 없으면 배경 오디오 불가 → PiP도 사실상 불가 |
| 기기가 PiP 지원 | `ABPictureInPictureSession.isSupported` | 시뮬레이터는 대체로 미지원(§10-5) |
| 레이어가 `readyForDisplay` | 자동 | `session.isPossible` |

이 표가 그대로 README/DocC로 간다(결정 6).

---

## 5. 결정 4 — [필수] PiP × SwiftUI 편의 API 자동 해제의 상호작용

트랙 S가 `DESIGN-round6-swiftui.md` §9-4로 넘긴 판단이다.

### 5.1 사실관계 재확인 (실코드)

- 편의 API의 해제 트리거는 **저장소 파기**다. `ABOwnedPlayerBox`는 `@State`로 보유되고(`ABVideoPlayerWithControls.swift:42`), `deinit`에서 `Task { @MainActor in owned.release() }`로 1턴 지연 해제한다(`ABOwnedPlayerBox.swift:59-64`). 코어 쪽 대응물은 `ABVideoPlayer.Coordinator`이며 `dismantleUIView`에서 동기 해제한다(`ABVideoPlayer.swift:85-87,138-149`).
- `onDisappear`는 명시적으로 기각됐다(swiftui §1.2).
- PiP 세션은 뷰 파기보다 오래 살아야 한다.

### 5.2 판정: **v0.4.0에서 억제 수단은 필요하지 않다**

근거는 "해제해도 안전해서"가 **아니라**, **편의 API 경로에서 PiP에 도달할 수단 자체를 만들지 않기 때문**이다.

1. **구조적 도달 불가.** §3.4의 PiP 파라미터는 `ABVideoPlayer.init(player:videoGravity:pictureInPicture:)` — **명시 소유 이니셜라이저에만** 붙는다. `init(url:)`/`init(source:)`(`ABVideoPlayer.swift:29-53`)와 `ABVideoPlayerWithControls`의 URL 계열(`ABVideoPlayerWithControls.swift:102-164`)에는 붙이지 않는다. 소유 플레이어 핸들도 소유 뷰 핸들도 외부에 노출되지 않는다(`ABOwnedPlayerBox`의 전 필드가 private, `:18-20`; `Coordinator`의 전 필드가 private, `ABVideoPlayer.swift:102-104`). 따라서 편의 API 사용자는 `ABPictureInPictureSession`을 바인딩할 지점이 없다 — **억제할 대상이 존재하지 않는다.**
2. **`init(url:)`에만 파라미터를 붙이는 절충안도 기각.** `ABVideoPlayer.swift`는 코어 파일이라 트랙 G가 수정할 수 있으므로 기술적으로는 가능하다. 그러나 그렇게 하면 **정의상의 사용 사례에서 조용히 깨지는 기능**을 출하하게 된다: 사용자가 PiP를 켜고 화면을 나가면 뷰 identity가 죽고 → `Coordinator`/`@State` 파기 → `release()` → `AVPlayer` 소멸 → PiP 종료. "PiP를 켰는데 화면을 나가니 꺼진다"는 기능 부재보다 나쁘다. 더구나 `ABVideoPlayerWithControls`(동결 파일)에는 같은 파라미터를 넣을 수 없으므로, 컨트롤 있는 원라이너만 PiP가 안 되는 비대칭이 남는다.
3. **1턴 지연(swiftui §1.5-4)은 이 판정과 무관하다.** 억제 대상이 없으므로 홉 지연이 PiP에 영향을 줄 경로가 없다.

### 5.3 "억제하면 되지 않나"에 대한 정직한 검토 — 왜 토큰 하나로는 부족한가

PiP가 뷰 파기를 넘어 살아남으려면 **두 개의 수명**이 동시에 연장되어야 한다:

| 수명 | 소유자 | §3의 설계에서 |
|---|---|---|
| (a) `AVPlayerLayer` (= `ABPlayerView`) | SwiftUI `UIViewRepresentable` 기계 | **해결됨.** 세션이 `isActive` 동안 뷰를 강하게 보유하고 언바인딩을 지연한다(B-5) |
| (b) `AVPlayer` (= `ABPlayer`) | 명시 소유면 소비자, 편의 API면 `ABOwnedPlayerBox`/`Coordinator` | **미해결.** 편의 API에서는 저장소 파기와 함께 `release()`된다 |

즉 릴리스 억제 토큰은 (b)만 푼다. (a)는 세션이 이미 풀었으므로, **토큰을 도입하면 원리적으로는 편의 API + PiP가 성립한다.** 그럼에도 v0.4.0에 넣지 않는 이유:

- `ABOwnedPlayerBox.swift`와 `ABVideoPlayerWithControls.swift` 수정이 필요한데, 이 두 파일은 이번 라운드에 **트랙 C도 diff 0줄로 묶인 동결 파일**이다(§0.1, HANDOFF §2).
- "해제 지연(deferred release)"은 이 코드베이스에 없던 새 수명 개념이다. 특히 `ABAudioSessionCoordinator`의 참가자 refcount(`ABPlayer.swift:170-176`, `:1088-1092`)와 맞물린다 — 뷰가 사라진 뒤에도 오디오 세션 참가자로 남아 있는 상태가 생기고, 그 상태에서 호스트 앱이 세션을 되찾을 수 있어야 한다. 이 분석은 트랙 G의 파일 경계 밖이며 자체 설계 게이트를 받을 값어치가 있다.
- PiP의 올바른 집은 어차피 명시 소유다. v0.4.0은 그 경로를 완성해 출하하고, 편의 경로는 검증된 뒤에 얹는 것이 순서다.

### 5.4 트랙 S 4파일 관련 요구사항 (직접 수정하지 않음 — 요구사항으로만 기록)

**v0.5.0(또는 편의 API + PiP를 결정하는 라운드)의 확정 요구사항.** 아래 4개가 한 묶음이며, 부분 도입은 금지한다(부분 도입 시 §5.3의 (a)/(b) 중 하나만 풀려 조용히 깨진다).

| # | 대상 파일 | 요구사항 |
|---|---|---|
| S-PiP-1 | `Sources/ABPlayerKit/Engine/ABPlayer.swift` (코어) | `public var isRetainedByPictureInPicture: Bool` 읽기 전용 추가. 바인딩된 세션이 활성인 동안 `true`. 코어 내부 신호이므로 이벤트 방송은 하지 않는다 |
| S-PiP-2 | `Sources/ABPlayerKitControls/SwiftUI/ABOwnedPlayerBox.swift` **(동결)** | `releaseIfOwned()`가 `owned.isRetainedByPictureInPicture == true`이면 해제를 **연기**하고, 세션 정지 콜백에서 실행한다. `didRelease` 플래그 의미를 "해제됨"과 "해제 예약됨"으로 분리해야 한다 |
| S-PiP-3 | `Sources/ABPlayerKitControls/SwiftUI/ABVideoPlayerWithControls.swift` **(동결)** | URL/source 계열 이니셜라이저에 `pictureInPicture: ABPictureInPictureSession? = nil` 추가(additive, 기본 `nil`이면 현행 동작 바이트 동일) |
| S-PiP-4 | `Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift` (코어) | `Coordinator.releaseIfOwned()`에 S-PiP-2와 동일한 연기 규칙 + `init(url:)`/`init(source:)`에 `pictureInPicture:` 추가 |

**권고: v0.4.0 범위에 넣지 말고 v0.5.0 additive 옵션으로 이월한다.** 사유는 §5.3 세 항목. 대신 v0.4.0의 문서(G-4w)에 **"PiP는 명시 소유 경로에서 지원된다"**를 한계로 명시해, 소비자가 편의 API로 PiP를 시도하다 원인을 찾아 헤매는 일이 없게 한다.

---

## 6. 결정 3 — `ABBackgroundPolicy.continueAudioOnly` (감사 G-4)

### 6.1 detach/유지 시맨틱: **레이어는 뗀다**

직관과 반대로 보이지만 이것이 정답이다. iOS에서 배경 오디오를 계속하려면 **`AVPlayerLayer`가 `AVPlayer`에 붙어 있으면 안 된다** — 화면에 붙은 레이어를 가진 플레이어는 배경 진입 시 시스템이 재생을 멈춘다. 배경 오디오 계속의 표준 기법이 정확히 "배경 진입 시 `playerLayer.player = nil`, 복귀 시 되붙이기"다.

즉 `.continueAudioOnly`는 **`pauseAndDetachLayer`에서 `.pause`만 뺀 것**이며, 기존 detach 기계를 그대로 재사용한다.

```swift
// ABBackgroundPolicyMachine.swift
private func willResignActiveActions(policy:) -> [ABBackgroundAction] {
    case .pause, .pauseAndDetachLayer, .continueAudioOnly:  return [.capturePlaying]
    case .ignore, .demoteToInstance:                        return []
}

private func didEnterBackgroundActions(policy:grade:) -> [ABBackgroundAction] {
    case .continueAudioOnly:  return [.setLayerAttachment(false)]      // .pause 없음
    // 나머지 현행
}

private func willEnterForegroundActions(...) -> [ABBackgroundAction] {
    case .continueAudioOnly:
        actions.append(.setLayerAttachment(true))
        if grade == .current && wasPlayingBeforeBackground { actions.append(.resumePlay) }
        actions.append(.clearCapture)
}
```

`.capturePlaying` + 포그라운드 `.resumePlay`를 유지하는 이유: 전제조건(§6.2)이 갖춰지지 않은 앱에서는 시스템이 배경에서 재생을 멈춘다. 그때 이 정책이 **조용히 `.ignore`처럼 죽는 대신 `.pause`처럼 복구**되도록 하는 안전망이다. 오디오가 실제로 계속됐다면 `resumePlay`의 `play()`는 이미 재생 중인 플레이어에 대한 사실상 무해한 재호출이다(`ABPlayer.swift:359-375` — `desiresPlayback = true` 재설정 + `target.play()` + 미러 갱신).

### 6.2 `audioSessionPolicy`와의 관계 — 소비자가 해야 할 일

기본값 `.unmanaged`(`ABPlayerConfiguration.swift:51`)에서는 이 정책이 **동작하지 않는다.** 성립 조건 3개:

| # | 조건 | 주체 | 미충족 시 |
|---|---|---|---|
| 1 | Info.plist `UIBackgroundModes`에 `audio` | **호스트 앱만 가능** | 배경 진입 시 앱이 서스펜드 → 재생 중단 |
| 2 | `configuration.audioSessionPolicy = .playback(mixWithOthers: false)` | 소비자 | 카테고리가 재생용이 아니라 배경 오디오 불가 |
| 3 | `configuration.backgroundPolicy = .continueAudioOnly` | 소비자 | — |

3개가 모두 갖춰졌을 때만 실제로 배경 오디오가 계속된다. 셋 중 하나라도 빠지면 §6.1의 안전망에 의해 `.pause`와 유사하게 동작한다(복귀 시 재개).

**진단 API는 만들지 않는다.** `Bundle.main`에서 `UIBackgroundModes`를 읽어 "준비됨/안 됨"을 알려 주는 헬퍼를 검토했으나 기각한다: (a) SPM 테스트 번들에서 `Bundle.main`은 테스트 러너를 가리켜 그 경로가 테스트 불가이고, (b) 부분 진단(2번만 확인)은 가장 흔한 실패 원인인 1번을 놓친 채 "정상"이라고 답해 **오히려 오도한다**. 대신 세 조건을 문서의 표로 못 박는다(결정 6). 완전한 진단은 v0.5.0 후보로 §8에 남긴다.

### 6.3 케이스 추가의 소스 호환 영향 — 정직한 논증

`ABBackgroundPolicy`는 공개 enum이고(`ABBackgroundPolicy.swift:2`), `ABPlayerEvent`와 달리 **non-exhaustive 계약 주석이 없다.** library evolution을 쓰지 않는 SPM 소스 배포이므로, 소비자 모듈의 `switch`는 exhaustive를 요구하고 **케이스 추가는 그 `switch`를 컴파일 에러로 만든다.**

그럼에도 추가하는 근거:

1. `ABBackgroundPolicy`는 **입력**이다. 소비자는 이 값을 `configuration.backgroundPolicy = .pause`처럼 **설정**하지, 라이브러리가 방송하는 것을 받아 `switch`하지 않는다. `ABPlayerEvent`(출력, 반드시 `switch`됨)와 위험 프로파일이 다르다.
2. 리포 내 영향 조사 결과: `Examples/`·`Sources/ABPlayerKitControls/`·`Sources/ABPlayerKitMetrics/`·`Sources/ABPlayerKitCache/`에서 이 타입은 **생성 인자로만** 쓰이고(`ABPlayerConfiguration(backgroundPolicy: .ignore)` 형태) `switch`는 한 건도 없다. 프로덕션 `switch`는 `ABBackgroundPolicyMachine.swift:56,68,91` 3곳(라이브러리 내부)뿐이며, 이는 **컴파일러가 새 케이스의 동작을 3개 지점 전부에서 결정하도록 강제**하는 바람직한 성질이다. 테스트 쪽 `switch` 2곳(`ABBackgroundPolicyMachineTests.swift:25,46`)은 §12.3의 사전 승인 범위로 처리한다.
3. `POLICY-api-stability.md`의 "Adding `enum` cases — 기존 관례 계속: non-exhaustive 선언, `default` 필요, 타입 doc과 DocC 양쪽에 문서화"가 정확히 이 상황의 절차다.

수반 조치(전부 필수):
- `ABBackgroundPolicy`에 non-exhaustive 계약 주석 추가(`ABPlayerEvent`의 타입 주석과 같은 문구 형태).
- DocC `ABPlayerKit.md`의 "Events and Policy" 토픽에 이미 `ABBackgroundPolicy`가 큐레이션돼 있으므로(`:63`) 심볼 문서만 갱신.
- CHANGELOG `### Added` + **Migration 노트 1줄**: "`ABBackgroundPolicy`를 `switch`하는 코드는 `default` 분기를 추가해야 합니다. 이 타입은 non-exhaustive입니다."
- **`ABPlayerConfiguration`의 기본값은 `.pause` 유지**(`:50`) — 동작 변경 0.

### 6.4 필수 수반 수정 — 놓치면 조용히 깨지는 곳

`applyConfigurationChange`가 detach 정책에서 벗어날 때 레이어를 되붙이는 조건이 `.pauseAndDetachLayer` 문자열 비교로 되어 있다:

```swift
if previousConfiguration.backgroundPolicy == .pauseAndDetachLayer,
   configuration.backgroundPolicy != .pauseAndDetachLayer {
    setLayerAttachmentEnabled(true)          // ABPlayer.swift:797-801
}
```

`.continueAudioOnly`도 레이어를 떼므로, 이 조건은 **정책의 성질**로 일반화해야 한다. 그러지 않으면 배경 체류 중 `.continueAudioOnly → .ignore` 전환 시 레이어가 영구 detach로 남는다(검은 화면).

```swift
// ABBackgroundPolicy.swift (internal)
extension ABBackgroundPolicy {
    var detachesLayerInBackground: Bool {
        switch self {
        case .pauseAndDetachLayer, .continueAudioOnly: true
        case .ignore, .pause, .demoteToInstance:       false
        }
    }
}
// ABPlayer.swift:797-801
if previousConfiguration.backgroundPolicy.detachesLayerInBackground,
   !configuration.backgroundPolicy.detachesLayerInBackground {
    setLayerAttachmentEnabled(true)
}
```

`reconcileBackgroundObserver()`의 `!= .ignore` 가드(`ABPlayer.swift:859`)는 새 케이스에 대해 이미 올바르다(옵저버가 설치된다).

### 6.5 기각안

| 기각안 | 사유 |
|---|---|
| 레이어를 **유지**하는 시맨틱 | 배경 오디오가 계속되지 않는다(§6.1). 정책 이름이 약속한 것을 못 지킨다 |
| `ABPlayerConfiguration`에 `continuesAudioInBackground: Bool` 추가(케이스 추가 회피) | `pauseAndDetachLayer` + `true` 같은 무의미 조합이 타입으로 표현 가능해진다. 정책은 상호배타적 4(→5)지선이므로 enum이 맞는 모델 |
| `ABBackgroundPolicy`를 struct + static 멤버로 전환(소스 호환 확보) | 생성 호환은 되지만 `switch`는 어차피 깨진다. 공개 타입 전면 교체 대가만 남는다 |
| 비디오 트랙 비활성화(`AVPlayerItem.tracks`의 video track `isEnabled = false`) 방식 | detach보다 침습적이고, 복귀 시 복원 책임이 생기며, HLS에서 트랙 조작은 신뢰도가 낮다. 기존 detach 기계 재사용이 회귀 위험이 낮다 |
| 새 정책 전용 이벤트 방송 | §0의 "이벤트 표면 소비만" 제약. `setLayerAttachment`는 이미 레이어 부착 옵저버로 관측 가능하다(`ABPlayer.swift:1222-1226`) |

---

## 7. 결정 5 — AirPlay 노브 (감사 G-2)

### 7.1 계층: **configuration**

```swift
// ABPlayerConfiguration.swift (추가)
/// `AVPlayer.allowsExternalPlayback`. 기본 `true` — `AVPlayer`의 기본값과
/// 일치하므로 기존 소비자의 관찰 가능한 동작이 바뀌지 않는다. 피드처럼
/// 여러 플레이어가 동시에 사는 화면에서는 현재 셀 외에는 `false`가 옳다.
public var allowsExternalPlayback: Bool                       // 기본 true
/// `AVPlayer.usesExternalPlaybackWhileExternalScreenIsActive`.
public var usesExternalPlaybackWhileExternalScreenIsActive: Bool   // 기본 false
/// `AVPlayer.externalPlaybackVideoGravity`.
public var externalPlaybackVideoGravity: AVLayerVideoGravity  // 기본 .resizeAspect

// ABPlayer.swift (추가) — 읽기 전용
/// 외부 재생(AirPlay)이 활성인지. **`@Observable` 추적 대상이 아니다** —
/// 대상을 매번 다시 읽는 computed 프로퍼티이므로 SwiftUI가 자동으로
/// 재렌더하지 않는다. 반응형이 필요하면 `avPlayer`를 직접 KVO하거나
/// `AVRoutePickerView`가 자체 관리하는 상태를 쓴다.
public var isExternalPlaybackActive: Bool { target.isExternalPlaybackActive }
```

**런타임 setter를 따로 두지 않는 근거**: `isMuted`/`isLooping`/`playbackRate`가 전부 configuration에 있고 `applyConfigurationChange`가 대상에 반영한다(`ABPlayer.swift:804-815`). 별도 setter를 두면 진실원이 둘이 되어, 다음 `player.configuration = ...` 대입이 사용자가 setter로 정한 값을 조용히 덮어쓴다. 이 함정은 swiftui §1.4가 이미 배속에서 실증했다(`ABOwnedPlayerBox.swift:22-27`의 "configuration은 생성 시 1회만" 규칙이 그 대응책).

`setMuted(_:)`(`ABPlayer.swift:507-509`)처럼 configuration을 갱신하는 얇은 편의 setter는 가능하나 **이번 라운드에는 만들지 않는다**(표면 절약, 필요성 미검증).

### 7.2 적용 시점

`allowsExternalPlayback` 계열은 `AVPlayer`의 프로퍼티이므로 **아이템이 아니라 플레이어 생성 시점**에 적용해야 한다.

- `interpret(_:source:detachReason:)`의 `.createPlayer` 분기(`ABPlayer.swift:657-658`)에서 `target.applyExternalPlayback(...)` 호출 추가.
- `applyConfigurationChange`에 세 값의 변경 감지 분기 추가(기존 `isMuted`/`isLooping` 분기와 같은 형태, `:804-810`).
- `ABPlaybackTarget`에 `func applyExternalPlayback(_ settings: ABExternalPlaybackSettings)` + `var isExternalPlaybackActive: Bool` 추가 → `ABAVPlaybackTarget`과 `ABFakePlaybackTarget` 양쪽 구현.

**놓치기 쉬운 곳**: `ABPlayerConfiguration`은 `assetFactory` 때문에 `==`를 수기로 구현한다(`:75-91`). 신규 3개 프로퍼티를 이 목록에 **반드시 추가**해야 한다. 누락 시 타입의 동등성이 이 값들을 무시한다(`ABPlayer` 내부는 필드별 비교라 동작은 유지되지만 공개 타입의 계약이 깨진다).

### 7.3 기본값 결정

| 노브 | 선택 | 근거 |
|---|---|---|
| `allowsExternalPlayback` | **`true`** | `AVPlayer`의 기본값과 동일. `false`로 두면 **기존 소비자의 AirPlay가 이번 릴리스에서 조용히 꺼진다** — POLICY의 "Behavior changes" 관점에서 가장 나쁜 종류의 변경이다. 피드 시나리오의 권장 설정(`.current` 외 `false`)은 문서로 안내한다 |
| `usesExternalPlaybackWhileExternalScreenIsActive` | **`false`** | `AVPlayer` 기본값과 동일 |
| `externalPlaybackVideoGravity` | **`.resizeAspect`** | `AVPlayer` 기본값으로 알려진 값. §10-8에서 구현 시 확인 항목으로 남긴다 |

### 7.4 기각안

| 기각안 | 사유 |
|---|---|
| `isExternalPlaybackActive`를 `@Observable` 저장 미러 + `externalPlaybackChanged(Bool)` 이벤트로 | 신규 `ABPlayerEvent` 케이스는 §0 제약 위반이고, HANDOFF §4-1b가 **이벤트 1건 추가가 Controls 특성화 테스트(시퀀스 배열 `==`)를 깬 실제 사고**를 기록했다. 트랙 C가 동시 진행 중인 이번 Wave에 같은 위험을 재현할 이유가 없다 |
| `AVRoutePickerView` 래퍼 제공 | 스톡 UIKit 뷰이고 SwiftUI에서 3줄 `UIViewRepresentable`로 끝난다. 라이브러리 표면에 넣을 값어치 없음. README에 예제만 싣는다 |
| 라우트 변경 이벤트를 새로 방송 | `audioRouteChangedDeviceUnavailable`가 이미 있다(`ABPlayerEvent.swift`) |

---

## 8. 결정 6 — 문서 범위 (감사 G-6, G-4w 확정 범위)

### 8.1 자막/오디오 트랙 선택 — non-goal 유지 + escape hatch 문서화

README에 신설할 절의 내용(요지):

- 이 라이브러리는 자막/오디오 트랙 선택 UI와 상태 관리를 **제공하지 않는다**(선언된 non-goal).
- escape hatch: `player.avPlayerItem`(`ABPlayer.swift:58`)으로 `AVMediaSelectionGroup`에 직접 접근한다.
- **정직하게 함께 적을 제약 3가지**(이걸 빼면 문서가 함정이 된다):
  1. `avPlayerItem`은 `grade >= .preloaded`에서만 non-nil이다(`ABPlaybackGrade.holdsItem`).
  2. 소스 교체·강등·release마다 아이템이 **새로 만들어진다**(`ABAVPlaybackTarget.swift:95-104`). 선택은 아이템에 붙으므로 **매 attach마다 다시 적용**해야 한다 → `.itemAttached(source:)`를 훅으로 쓴다.
  3. 라이브러리는 선택 상태를 기억하지 않는다. 재적용 책임은 소비자에게 있다.

### 8.2 G-4w의 확정 문서 범위

| 문서 | 추가/개정 |
|---|---|
| `README.md` | ① **`Background Policy` 절 신설** — 현재 README에 `backgroundPolicy` 언급이 **0건**이다(공개 정책 4종이 문서 없이 존재). 5종 정책 표 + `.continueAudioOnly`의 3조건 표(§6.2). ② `Picture in Picture` 절 — 세션 사용법, 전제조건 표(§4.6), 매트릭스 요약, **"명시 소유 경로에서 지원"** 한계 명시(§5.4). ③ `AirPlay` 절 — 3개 노브 + `AVRoutePickerView` 예제 + 피드 권장 설정. ④ `Now Playing and Remote Commands` 절 — opt-in 사용법, 소유권 규칙 R1~R6 요약, 커맨드 표. ⑤ `Subtitles and Audio Tracks` 절(§8.1) |
| `README.ko.md` | 위와 **동일 절 구성**. 트랙 S가 세운 규약(swiftui §6.1 "두 파일의 절 구성이 어긋나지 않게 한다") 준수 |
| `Sources/ABPlayerKit/ABPlayerKit.docc/ABPlayerKit.md` | Topics에 `ABPictureInPictureSession`(새 그룹 "Picture in Picture"), `ABPictureInPictureFailure` 큐레이션. "Events and Policy"의 `ABBackgroundPolicy` 심볼 문서 갱신 |
| `Sources/ABPlayerKit/ABPlayerKit.docc/BackgroundAndPictureInPicture.md` (신규 article) | §4 매트릭스 A/B 전문 + §4.6 전제조건 + §4.5 경합 |
| `Sources/ABPlayerKitNowPlaying/ABPlayerKitNowPlaying.docc/` (신규 카탈로그) | Overview + Topics(전 공개 심볼) + `RemoteCommands.md` article(커맨드 표, "빈 핸들러 금지" 불변식, 소유권 규칙) |
| `CHANGELOG.md` | `### Added`(NowPlaying 타깃, PiP 세션, `.continueAudioOnly`, AirPlay 3노브, `isExternalPlaybackActive`) + `### Changed`(없음 예상) + **Migration 노트 2건**: ① `ABBackgroundPolicy` non-exhaustive, ② `ABPlaybackTarget`은 internal이므로 소비자 영향 없음을 명시 |

**CHANGELOG는 초안이 아니라 실제 파일에 반영한다**(HANDOFF §4-8의 재발 방지 항목).

---

## 9. 확정 API 시그니처 (한자리 모음)

### 9.1 `ABPlayerKit` (코어) — 추가분

```swift
// Policy/ABBackgroundPolicy.swift
/// 이 열거형은 non-exhaustive로 취급한다. 마이너 릴리스가 케이스를 추가할 수 있으므로
/// 소비자 switch는 `default` 분기를 포함해야 한다.
public enum ABBackgroundPolicy: Sendable, Equatable {
    case ignore
    case pause
    case pauseAndDetachLayer
    case demoteToInstance
    /// 배경에서 오디오만 계속한다. 레이어는 뗀다(그것이 iOS에서 배경 오디오가
    /// 이어지는 조건). 성립하려면 호스트 앱의 `UIBackgroundModes: audio`와
    /// `audioSessionPolicy != .unmanaged`가 함께 필요하다.
    case continueAudioOnly
}

// Model/ABPlayerConfiguration.swift
public var allowsExternalPlayback: Bool                             // 기본 true
public var usesExternalPlaybackWhileExternalScreenIsActive: Bool    // 기본 false
public var externalPlaybackVideoGravity: AVLayerVideoGravity        // 기본 .resizeAspect

// Engine/ABPlayer.swift
public var isExternalPlaybackActive: Bool { get }                   // computed, 비추적

// View/ABPictureInPictureSession.swift  (신규 파일)
public struct ABPictureInPictureFailure: Sendable, Equatable {
    public let description: String
    public let origin: ABErrorOrigin?
}

@MainActor
@Observable
public final class ABPictureInPictureSession {
    public init()
    public static var isSupported: Bool { get }
    public private(set) var isPossible: Bool
    public private(set) var isActive: Bool
    public private(set) var lastFailure: ABPictureInPictureFailure?
    public var startsAutomaticallyFromInline: Bool                  // 기본 false
    public var requiresLinearPlayback: Bool                         // 기본 false
    public var restoreUserInterfaceHandler: (@MainActor () async -> Bool)?
    public var controller: AVPictureInPictureController? { get }
    public func start()
    public func stop()
}

// View/ABPlayerView.swift
public var pictureInPictureSession: ABPictureInPictureSession? { get set }

// SwiftUI/ABVideoPlayer.swift  (명시 소유 경로에만)
public init(
    player: ABPlayer,
    videoGravity: AVLayerVideoGravity = .resizeAspectFill,
    pictureInPicture: ABPictureInPictureSession
)
```

### 9.2 `ABPlayerKitNowPlaying` (신규 타깃) — 전체 공개 표면

```swift
public struct ABNowPlayingMetadata: Sendable, Equatable { … }        // §2.2
public struct ABRemoteCommandSet: OptionSet, Sendable, Equatable { … }
public struct ABNowPlayingConfiguration: Sendable, Equatable { … }
@MainActor public protocol ABNowPlayingArtworkProviding: AnyObject { … }
@MainActor public final class ABStaticArtworkProvider: ABNowPlayingArtworkProviding { … }

@MainActor
public final class ABNowPlayingCenter {
    public static let shared: ABNowPlayingCenter
    public private(set) var owner: ABPlayerID?
    public func attach(_:metadata:configuration:artwork:) -> ABObservationToken
    public func update(_:for:)
    public func setTrackNavigationHandlers(next:previous:for:)
}
```

internal(테스트 대상 순수 리듀서): `ABNowPlayingOwnership`, `ABNowPlayingInfoBuilder`, `ABNowPlayingInfo`, `ABNowPlayingPlayerSnapshot`, `ABRemoteCommandRouter`, `ABRemoteCommandIntent`, `ABRemoteCommandOutcome`, `ABRemoteCommandKey`, `ABNowPlayingSurface`.

### 9.3 internal 변경분

```swift
// Policy/ABBackgroundPolicy.swift
extension ABBackgroundPolicy { var detachesLayerInBackground: Bool { … } }

// Policy/ABBackgroundPolicyMachine.swift
func actions(for:policy:grade:wasPlayingBeforeBackground:hasCapturedGrade:
             isPictureInPictureActive: Bool = false) -> [ABBackgroundAction]

// Engine/ABPlayer.swift
func setPictureInPictureActive(_ isActive: Bool)          // 세션 → 플레이어 (§4.5 복구 포함)
var isPictureInPictureActive: Bool { get }

// Engine/ABPlaybackTarget.swift
var isExternalPlaybackActive: Bool { get }
func applyExternalPlayback(_ settings: ABExternalPlaybackSettings)
```

**`ABPlaybackTarget` 변경이 공개 표면에 미치는 영향은 없다** — 이 프로토콜은 internal이며 그렇게 유지되도록 명시돼 있다(`ABPlaybackTarget.swift:31-35`).

---

## 10. 확인 불가 / 구현 시 검증 항목 (정직 보고)

정적 코드 읽기만으로 확정할 수 없었던 것들이다. **추측으로 설계를 굳히지 않고, 각 항목의 검증 방법과 실패 시 대안을 함께 적는다.**

| # | 항목 | 상태 | 검증 방법 / 대안 |
|---|---|---|---|
| 10-1 | `AVPictureInPictureController`가 `playerLayer`를 **강하게** 보유하는가 | **확인 불가** (AVKit 내부) | 검증: 컨트롤러 생성 후 로컬 레이어 참조를 버리고 `weak` 참조 생존 확인(단위 테스트 가능). 강한 보유가 아니면 §3.4의 "세션이 뷰를 보유" 설계가 **레이어까지 보유**하도록 명시 필드를 추가한다(설계 변경 아님, 필드 1개 추가) |
| 10-2 | `UIView`가 해제된 뒤 그 백킹 `AVPlayerLayer`가 PiP로 계속 렌더링되는가 | **확인 불가** | 본 설계는 이 질문에 **의존하지 않도록** 세션이 활성 중 **뷰 자체**를 보유하게 했다(B-5). 우회 설계이므로 검증 실패해도 재설계가 필요 없다 |
| 10-3 | `didEnterBackgroundNotification` 처리와 PiP 자동 활성화 KVO의 순서 | **플랫폼 미보장** | §4.5의 복구 경로가 양쪽 순서 모두에서 수렴하도록 설계됨. 기기 수동 확인 항목 |
| 10-4 | `playerLayer.player = nil` 또는 `replaceCurrentItem(nil)`이 PiP를 **종료**시키는가 **정지**시키는가 | **확인 불가** | 매트릭스 B는 "종료"로 확정 동작을 정의하되, 세션의 `isActive`는 KVO 기반이라 실제 결과를 따라간다. 즉 문서와 실동작이 어긋나도 상태는 정확하다. 기기 확인 후 문서 문구만 조정 |
| 10-5 | 시뮬레이터의 PiP 지원 여부 | **대체로 미지원(경험칙)** | `ABPictureInPictureSession.isSupported`가 `false`인 환경에서 **`start()`가 안전한 no-op**임을 단위 테스트로 고정. PiP 실동작 검증은 **기기 수동 확인**으로만 가능하며 CI 대상이 아니다(§11.5에 명시) |
| 10-6 | `MPRemoteCommandEvent`를 테스트에서 생성 가능한가 | **불가(공개 이니셜라이저 없음)** | 그래서 §2.4의 순수 라우터 분리가 필수. 라우터는 100% 테스트, `MPRemoteCommand.addTarget` 배선은 페이크 `ABNowPlayingSurface`로 "어떤 커맨드를 어떤 enabled 값으로 설정했는가"까지만 검증 |
| 10-7 | 데모 앱에 배경 오디오 모드를 켜는 정확한 빌드 설정 키 | **미검증** | `INFOPLIST_KEY_UIBackgroundModes = audio`를 시도하고, 인식되지 않으면 명시 `Info.plist` 파일로 전환(`GENERATE_INFOPLIST_FILE = YES`, `project.pbxproj:166-169`) |
| 10-8 | `AVPlayer.externalPlaybackVideoGravity`의 실제 기본값 | **미검증(`.resizeAspect`로 상정)** | 구현 시 런타임 확인 후 그 값을 기본값으로 채택. 값이 다르면 **AVPlayer 기본값 쪽을 따른다**(동작 변경 0 원칙) |
| 10-9 | `.continueAudioOnly`가 레이어 detach만으로 실제 배경 오디오를 이어 가는가 | **플랫폼 기법에 근거한 설계 판단, 리포 코드로는 검증 불가** | §6.2의 3조건을 갖춘 데모에서 **기기 수동 확인**. 실패하면 §6.5의 "비디오 트랙 비활성화" 대안을 재검토 |
| 10-10 | `MPNowPlayingInfoCenter.nowPlayingInfo`의 스냅숏/복원이 실제로 왕복하는가 | 읽기 가능하므로 **원리상 가능**, 실동작 미검증 | 페이크 surface로 왕복 단위 테스트 + 데모에서 수동 확인 |

---

## 11. WP별 구현 지침과 테스트 전략

### 11.0 권장 구현 순서

로드맵의 WP ID는 유지하되, 착수 순서는 **G-3w → G-2w → G-1w → G-4w**를 권한다. 근거: `ABBackgroundPolicyMachine`을 건드리는 변경(새 케이스 / PiP 파라미터)이 두 WP에 걸쳐 있는데, 케이스 추가를 먼저 끝내면 G-2w의 PiP 억제 테이블을 **최종 5개 정책 전부에 대해 한 번에** 작성할 수 있다. G-1w는 두 WP와 파일 교집합이 없어 순서 자유.

### 11.1 공통 규칙 (전 WP)

- Swift 6 zero-warning. `@unchecked Sendable`·`MainActor.assumeIsolated`·신규 `@available(*, deprecated)` **0건**.
- **새 주석에 리뷰/설계 ID 인용 금지.** 불변식만 서술. 제출 전 diff 추가 라인을 `G-\d`, `I-G\d`, `WP\d`, `round\d`, `MJ-\d`, `N\d` 패턴으로 직접 재스캔할 것.
- `sleep` 금지 — `ABTestSupport`의 `ABWaitUntil` 사용.
- 테스트에서 **실제 원격 URL로 재생을 시작시키지 말 것**(HANDOFF §4-1b의 실제 사고: 도달 불가 URL + `autoplay` 기본 `true`가 스위트 전체를 굶겼다). 로컬 픽스처 또는 `ABFakePlaybackTarget` 사용.
- **전체 스킴 3회 연속 그린**이 검증 조건. `-only-testing`으로 좁힌 결과는 근거로 인정하지 않는다.
- 커밋 금지.

### 11.2 G-1w — `ABPlayerKitNowPlaying` 타깃 (감사 G-3)

**신규 파일**
```
Sources/ABPlayerKitNowPlaying/ABNowPlayingMetadata.swift
Sources/ABPlayerKitNowPlaying/ABRemoteCommandSet.swift
Sources/ABPlayerKitNowPlaying/ABNowPlayingConfiguration.swift
Sources/ABPlayerKitNowPlaying/ABNowPlayingArtworkProviding.swift
Sources/ABPlayerKitNowPlaying/ABNowPlayingOwnership.swift          // 순수
Sources/ABPlayerKitNowPlaying/ABNowPlayingInfoBuilder.swift        // 순수
Sources/ABPlayerKitNowPlaying/ABRemoteCommandRouter.swift          // 순수
Sources/ABPlayerKitNowPlaying/ABNowPlayingSurface.swift            // 심 + MediaPlayer 구현
Sources/ABPlayerKitNowPlaying/ABNowPlayingCenter.swift             // 조립
Sources/ABPlayerKitNowPlaying/ABPlayerKitNowPlaying.docc/…
```

**지침**
1. `Package.swift`에 product/target/testTarget 3개 추가(§2.1). `ABTestSupport` 의존은 테스트 타깃에만.
2. `MediaPlayer` import는 `ABNowPlayingSurface.swift`의 프로덕션 구현 **한 파일에만** 둔다. 나머지는 `MediaPlayer` 없이 컴파일되어야 한다 — 이것이 테스트 가능성의 전제다.
3. 플레이어는 `weak`로 보유한다. 참가자 레코드에 `ABObservationToken`(플레이어 이벤트 구독)을 함께 보유하고, 반납 시 `cancel()`한다.
4. 발행은 §2.5의 트리거 목록으로 한정. `.periodicTime`은 구독하지 않는다(리뷰 대상 불변식 I-G6).
5. 아트워크 세대 가드(§2.6-3)를 반드시 구현. requestHandler 안에 I/O·await 금지.
6. 스냅숏은 **첫 소유권 획득 시 1회**. 이후 획득·이전에서 다시 찍지 않는다(`ABAudioSessionCoordinator`와 같은 규칙, `ABPlayer.swift:1066-1069`).
7. 데모 연동: `DemoModel`에 `nowPlayingEnabled: Bool` + `nowPlayingToken: ABObservationToken?`를 **새 멤버로** 추가하고, `PlaybackScreen`에 `GroupBox("Now Playing")` + 토글을 추가한다. **`MetricsScreen.swift`와 `DemoModel`의 메트릭 멤버는 건드리지 않는다**(트랙 F 소유, metrics §12). 데모의 `ABPlayerEvent` 라벨 확장(`DemoModel.swift:446-479`)은 `default` 분기가 있어 수정 불필요.

**테스트 — 검증 가능한 것**

| # | 파일 | 검증 |
|---|---|---|
| 1 | `ABNowPlayingOwnershipTests` | R1~R4 전수: 등록/자격변경/해제 순열에 대한 `Effect` 테이블 |
| 2 | 〃 | 2참가자 LIFO: A획득 → B획득(A는 스택 유지) → B반납 → **A 자동 복귀** |
| 3 | 〃 | 자격 없는 참가자만 있을 때 `owner == nil` + `relinquishAll` |
| 4 | `ABNowPlayingInfoBuilderTests` | 골든: 유한 duration / 무한 duration(키 부재 + `isLiveStream == true`) / 스톨 중 `rate == 0` / 일시정지 `rate == 0` |
| 5 | `ABRemoteCommandRouterTests` | 커맨드 × (소유자 유무 × seekable 유무 × 핸들러 유무) 전수 → `Outcome` |
| 6 | 〃 | **I-G1 고정**: `.nextTrack`을 set에 넣되 핸들러 미제공 → `rejectNoHandler`, 그리고 surface가 그 커맨드를 `enabled: true`로 설정하지 **않았음** |
| 7 | `ABNowPlayingCenterTests` (페이크 surface) | `attach` 전 surface 호출 0건(R6) |
| 8 | 〃 | 마지막 토큰 해제 후 surface에 스냅숏 값이 되돌아옴(R5 왕복) |
| 9 | 〃 | 토큰을 버리면(`_ = center.attach(...)`) 즉시 반납됨 |
| 10 | 〃 | `ABFakePlaybackTarget` 기반 플레이어로 `.current` 승격 → 발행 1회, `.periodicTime` 100회 → **추가 발행 0회**(I-G6) |
| 11 | 〃 | 플레이어를 `nil`로 떨어뜨린 뒤 `ABWaitUntil { center.owner == nil }` |
| 12 | 〃 | duration이 무한 → `changePlaybackPosition`이 `enabled: false`로 설정됨 |

**테스트 — 검증 불가(정직 보고)**
- 실제 컨트롤 센터/잠금화면 표시, 헤드셋 버튼 이벤트, 실제 `MPRemoteCommandEvent` 전달 → **기기 수동 확인만 가능.** CI 대상 아님.
- `MPNowPlayingInfoCenter`의 실제 시스템 반영 → 수동.
- 다른 앱과의 NowPlaying 경합 → 수동.

### 11.3 G-2w — PiP 세션 + AirPlay 노브 (감사 G-1, G-2)

**지침**
1. `ABPictureInPictureSession`: `isPossible`/`isActive`는 **KVO**, 값이 실제로 바뀔 때만 대입(`ABPlayer.swift:608-638` 패턴). delegate는 `lastFailure`/`restoreUserInterfaceHandler` 전용.
2. `ABPlayerView.pictureInPictureSession` didSet에서 바인딩/언바인딩. **활성 중 언바인딩은 지연**(B-5, B-10).
3. 세션 → 코어 통보는 `player?.setPictureInPictureActive(_:)`. 뷰가 아니라 **플레이어**가 억제 상태를 들고 있어야 한다 — 배경 정책의 주체가 플레이어이기 때문(`ABPlayer.swift:883-911`).
4. `ABBackgroundPolicyMachine.actions(...)`에 기본값 `false`인 파라미터 추가(§4.2). `ABPlayer`의 3개 핸들러(`:883,893,903`)가 `isPictureInPictureActive`를 넘긴다.
5. §4.5 복구 경로를 `setPictureInPictureActive(true)`에 구현.
6. `ABVideoPlayer`: `Ownership` enum(`ABVideoPlayer.swift:10-13`)은 건드리지 않고 `pictureInPicture` 저장 프로퍼티를 별도로 둔다. `makeUIView`에서 바인딩, `dismantleUIView`에서 `uiView.pictureInPictureSession = nil`(지연은 세션이 처리).
7. AirPlay 3노브: §7.2의 3개 지점 + **`ABPlayerConfiguration.==`(`:75-91`)에 3줄 추가**.
8. `ABFakePlaybackTarget`에 `isExternalPlaybackActive`/`applyExternalPlayback` 구현 추가.

**테스트 — 검증 가능한 것**

| # | 파일 | 검증 |
|---|---|---|
| 13 | `ABBackgroundPolicyMachineTests`(확장) | **매트릭스 A 전수**: 5정책 × 4grade × 3신호 × PiP{false,true}. `isActive == false` 열이 현행과 동일함을 같은 테스트가 증명한다(I-G4) |
| 14 | 〃 | PiP 활성 시 `didEnterBackground`가 **모든 정책에서 `[]`** |
| 15 | `ABPictureInPictureSessionTests` | `isSupported == false` 환경에서 `start()`가 크래시 없이 no-op이고 `isActive == false` 유지 |
| 16 | 〃 | 세션을 뷰 A에 바인딩 → 뷰 B에 바인딩 → A의 바인딩이 끊어짐(I-G3) |
| 17 | 〃 | 미러 무발화: 동일 값 재대입이 `@Observable` 변경을 일으키지 않음 |
| 18 | `ABContinueAudioOnlyTests` / 코어 엔진 | PiP 활성 상태를 강제 주입한 플레이어에 배경 알림 → `isLayerAttachmentEnabled` 불변, `isPlaying` 불변 |
| 19 | 〃 | §4.5 복구: 레이어 detach된 상태에서 `setPictureInPictureActive(true)` → 재부착 + (조건 충족 시) 재생 재개 |
| 20 | `ABExternalPlaybackConfigurationTests` | 3노브가 `.createPlayer` 시점과 config 변경 시점에 대상으로 전달됨(페이크 대상 기록 검증) |
| 21 | 〃 | `ABPlayerConfiguration` 동등성이 3노브를 반영함(`==` 누락 회귀 고정) |
| 22 | 기존 `ABBackgroundLifecycleEngineTests` | **무수정 통과**(기본값 파라미터 덕분에 컴파일·동작 모두 불변) |

**테스트 — 검증 불가(정직 보고)**
- **PiP의 실제 시작/렌더링/창 조작은 시뮬레이터에서 검증할 수 없다**(§10-5). `isPossible`이 참이 되는 것조차 실제 디코딩된 레이어가 필요하다.
- `restoreUserInterfaceForPictureInPictureStop` 왕복 → 기기 수동.
- AirPlay 실제 라우팅·`isExternalPlaybackActive == true` 관측 → **Apple TV 등 실제 수신기 필요.** CI 불가, 기기 수동.
- 따라서 이 WP의 자동화 커버리지는 **"정책 리듀서 + 바인딩 수명 + 설정 전달"**까지이며, **"PiP가 실제로 뜬다"는 자동 검증되지 않는다.** `RESULT-round6-nowplaying.md`에 수동 확인 결과(기기 모델·OS·시나리오별 관측)를 반드시 남길 것.

### 11.4 G-3w — `.continueAudioOnly` (감사 G-4)

**지침**
1. `ABBackgroundPolicy`에 케이스 + non-exhaustive 계약 주석 추가.
2. `detachesLayerInBackground` internal 확장 추가, `ABPlayer.swift:797-801`을 그것으로 교체(§6.4). **이 수정이 이 WP의 진짜 함정이다.**
3. `ABBackgroundPolicyMachine`의 3개 private 메서드에 케이스 추가(§6.1).
4. **`ABBackgroundPolicyMachineTests` 수정은 사전 승인 범위**: `policies` 배열(`:11`)에 `.continueAudioOnly` 추가 + 3개 `switch policy` 블록(`:24-30`, `:47-56`, 그리고 foreground 블록)에 분기 추가. **기존 4정책의 기대값은 한 줄도 바꾸지 말 것** — 바꿔야 한다면 그 자체가 회귀 신호이므로 G-5에 보고한다.
5. CHANGELOG Migration 노트(§6.3).

**테스트 — 검증 가능한 것**

| # | 검증 |
|---|---|
| 23 | 리듀서 전수(테스트 13에 포함): `.continueAudioOnly`가 `didEnterBackground`에서 `.pause`를 **내지 않고** `.setLayerAttachment(false)`만 낸다 |
| 24 | 포그라운드 복귀에서 `.setLayerAttachment(true)` + (playing이었다면) `.resumePlay` |
| 25 | 엔진 레벨: `.continueAudioOnly`로 배경 진입 → `isPlaying`이 **참으로 유지**, `isLayerAttachmentEnabled == false` |
| 26 | **§6.4 회귀 고정**: 배경 상태에서 `.continueAudioOnly → .ignore` 전환 시 `isLayerAttachmentEnabled`가 `true`로 복구 |
| 27 | `.continueAudioOnly` + `audioSessionPolicy == .unmanaged`에서도 크래시·경고 없이 안전망 경로로 동작(복귀 시 재개) |

**테스트 — 검증 불가**
- **배경에서 오디오가 실제로 계속 나는지**는 시뮬레이터·단위 테스트로 검증할 수 없다(§10-9). 데모 앱 + 기기 수동 확인이 유일한 경로이며, `RESULT`에 결과를 남긴다.

### 11.5 G-4w — README/DocC (감사 G-6)

§8.2의 표가 그대로 작업 목록이다. 추가 지침:
1. `DOCC_WARNINGS_AS_ERRORS=YES`이므로 신규 공개 심볼 **전부** 큐레이션 + 링크 유효성 확인.
2. README/README.ko의 **절 구성 일치**(swiftui §6.1 규약).
3. 새 절에 §4.6·§6.2의 전제조건 표를 넣되, **"라이브러리가 해 줄 수 없는 것"**(Info.plist)을 표의 첫 행으로 둔다.
4. 자막 escape hatch 예제에 §8.1의 제약 3가지를 반드시 병기한다.
5. 트랙 F가 DocC 토픽 그룹 "QoE"를 신설하므로(metrics §12), 그룹명 충돌 없이 "Picture in Picture" / "Now Playing"을 쓴다.

---

## 12. 리스크와 무회귀 가드

### 12.1 절대 불변식 (위반 시 G-5 REQUEST-CHANGES)

| # | 불변식 | 근거 |
|---|---|---|
| **I-G1** | 활성화된 리모트 커맨드는 반드시 관측 가능한 동작을 낸다. 대응 동작·핸들러가 없으면 활성화하지 않는다 | §2.4 |
| **I-G2** | 참가자 0명인 동안 `ABNowPlayingCenter`는 `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`에 **읽기·쓰기 모두 하지 않는다.** 마지막 반납 시 스냅숏을 복원한다 | §2.3 R5·R6, README `:247-249` |
| **I-G3** | `ABPictureInPictureSession` 1개는 동시에 `ABPlayerView` 1개에만 바인딩된다. 활성 중 언바인딩은 정지 시점까지 지연된다 | §4.4 B-5·B-10 |
| **I-G4** | `isPictureInPictureActive == false`일 때 `ABBackgroundPolicyMachine`의 출력은 **기존 4정책에 대해 현행과 완전히 동일**하다 | §4.3, 테스트 13·22 |
| **I-G5** | `AVPlayerLayer`는 공개 표면에 노출되지 않는다. `playerLayer.player`를 쓰는 곳은 `ABPlayerView.attach(_:)`와 `rebindPlayerLayer()` 둘뿐이다 | `ABPlayerView.swift:69,99-105` |
| **I-G6** | NowPlaying 발행은 `.periodicTime`을 트리거로 쓰지 않는다 | §2.5 |
| **I-G7** | `ABPlayerEvent`에 케이스를 추가하지 않는다. 기존 이벤트의 방송 순서·시점을 바꾸지 않는다 | §0, core §3.3 순서 계약, HANDOFF §4-1b |
| **I-G8** | 브리지·세션 어느 쪽도 `ABPlayer`를 강하게 보유하지 않는다(세션이 활성 중 보유하는 것은 `ABPlayerView`이며 이는 §5.3에서 의도된 것) | §2.8, §5.3 |
| **I-G9** | 배경 정책의 **자동 부작용만** 억제된다. 소비자의 명시 명령(`release()`/강등/소스 교체)과 인터럽션·라우트 변경은 억제하지 않는다 | §4.4 |
| **I-G10** | 신규 기본값은 전부 **현행 동작 보존**: `backgroundPolicy` 기본 `.pause` 유지, `allowsExternalPlayback` 기본 `true`(AVPlayer 기본값), `startsAutomaticallyFromInline` 기본 `false` | §6.3, §7.3 |

### 12.2 수정 금지 테스트 파일

- `Tests/ABPlayerKitControlsTests/` **전체**
- `Tests/ABPlayerKitTests/ABSeekCoalescerTests.swift`, `ABScrubbingEngineTests.swift`, `ABPeriodicTimeEngineTests.swift`, `ABBackgroundLifecycleEngineTests.swift`
- `Tests/ABPlayerKitMetricsTests/`, `Tests/ABPlayerKitCacheTests/` 전체

### 12.3 허용된 테스트 변경 (사전 승인, 그 외에는 G-5 문의)

| 파일 | 변경 | WP |
|---|---|---|
| `ABBackgroundPolicyMachineTests.swift:11` | `policies` 배열에 `.continueAudioOnly` 추가 | G-3w |
| `ABBackgroundPolicyMachineTests.swift:25`·`:46`의 `switch policy` 블록 2곳 | 새 케이스 분기 추가. **기존 4정책 기대값 변경 금지** | G-3w |
| `ABBackgroundPolicyMachineTests.swift:78`의 정책 리터럴 배열 | `.continueAudioOnly` 추가(포그라운드 재개 + 레이어 재부착 기대가 `.pauseAndDetachLayer`와 동일). 기존 두 정책의 단언은 불변 | G-3w |
| `Fakes/ABFakePlaybackTarget.swift` | `isExternalPlaybackActive` / `applyExternalPlayback` 구현 추가 | G-2w |

### 12.4 리스크 등급

| 리스크 | 등급 | 완화 |
|---|---|---|
| PiP 실동작이 CI로 전혀 검증되지 않아, 그린인데 기능이 죽어 있을 수 있다 | **높음** | 자동 검증 범위를 정책 리듀서·바인딩 수명으로 명확히 한정(§11.3). **기기 수동 확인 결과를 `RESULT`에 필수 기재.** §10-1·10-2·10-4를 구현 초기에 먼저 확인해 설계 가정을 조기 검증 |
| `ABBackgroundPolicy` 케이스 추가가 소비자 `switch`를 깬다 | 중 | 리포 내 소비자 `switch` 0건 확인(§6.3-2). non-exhaustive 주석 + Migration 노트. 기본값 불변 |
| `ABPlayerConfiguration.==`에 신규 3필드 누락 | 중 | 테스트 21이 기계로 고정 |
| §6.4의 `detachesLayerInBackground` 일반화 누락 → 검은 화면 | 중 | 테스트 26이 기계로 고정 |
| 세션 ↔ 뷰의 의도된 상호 강참조가 PiP 정지 후에도 남아 누수 | 중 | 세션은 `isActive == false` 전이에서 **반드시** 뷰 참조를 놓는다. `ABWaitUntil` + `weak` 관측 테스트로 고정. 추가 안전망: 바인딩된 플레이어의 `avPlayer`가 `nil`이 되면 세션이 강제 `stop()` + 언바인딩 |
| 신규 KVO 4종(`isPossible`/`isActive` + AirPlay)이 detach 시 누수/크래시 | 중 | 코어 관례대로 `ABObservationBag` 수명 결속 + hop 후 stale 가드(`ABAVPlaybackTarget.swift:475,489,540`). TSan 잡(CI-2)이 2차 안전망 |
| 데모 파일이 트랙 F/C와 충돌 | 낮음 | 병합 순서 F → G → C. G는 `MetricsScreen`/메트릭 멤버 무접촉, C가 G 위로 리베이스 |
| 공개 표면이 한 라운드에 크게 늘어(신규 타깃 + 공개 타입 8종) | 중 | 순수 리듀서는 전부 internal. 신규 타깃은 별도 product라 쓰지 않으면 링크되지 않는다. DocC 토픽 그룹 2개 신설로 탐색성 확보 |
| `~150줄` 상정 대비 실제 규모 초과 | 낮음(인지 항목) | 브리지 코어는 상정대로지만, **소유권 조정 + 스냅숏/복원 + 순수 리듀서 3종**이 추가되어 타깃 전체는 350~450줄 규모가 된다. 그 증분이 곧 §2.3 R1~R6과 I-G1을 성립시키는 부분이며, 줄이면 정확성을 잃는다 |

---

## 13. 타 트랙 전달 사항

1. **트랙 S (Wave 1, 이미 병합됨) — §9-4 회신.** 질문 "PiP 사용 시 편의 API의 자동 해제를 억제할 수단이 필요한가"에 대한 답은 **"v0.4.0에서는 불필요"**이며, 근거는 §5.2다(편의 API에 PiP 파라미터를 넣지 않으므로 억제 대상이 없다). 다만 **"해제해도 안전하다"는 뜻이 아니다** — 억제 없이 편의 API에 PiP를 열면 정의상의 사용 사례에서 깨진다. §5.4의 요구사항 4개(S-PiP-1~4)가 그때 필요한 확정 형태이며, **v0.5.0 additive 이월을 권고**한다.
2. **트랙 C (Controls)** — ① 트랙 G는 `Sources/ABPlayerKitControls/**`를 **한 줄도 수정하지 않는다.** ② 반대로 요청: `Sources/ABPlayerKit/**`도 C가 수정하지 않기를 요청한다(C의 완료 정의가 이미 "`Sources/ABPlayerKit/` diff 0줄"을 선언하고 있어 교집합 0). ③ **PiP 버튼을 Controls에 넣지 않는다** — 세션 객체를 소비자가 소유하는 모델이라 Controls가 그것을 알 방법이 없고, 슬롯 API(C-6w)의 액세서리로 소비자가 직접 놓는 것이 정확한 조립이다. C-6w 문서에 그 예제를 넣을 것을 **권고**한다(필수 아님). ④ 병합 순서상 C가 G 위로 리베이스한다. G가 건드리는 데모 파일은 `PlaybackScreen.swift`(GroupBox 1개 추가)와 `DemoModel.swift`(비-메트릭 멤버 2개 추가)뿐이다.
3. **트랙 F (Metrics)** — ① metrics §12의 "`MetricsScreen.swift`/`DemoModel`의 메트릭 멤버는 F 소유"를 **수용**한다. G는 별도 프로퍼티만 추가하고 F 병합 후 리베이스한다. ② `.continueAudioOnly`가 도입되면 **배경에서 세션이 계속 살아 있는 새 시나리오**가 생긴다 — F-1w의 "스톨 미종결 세션 처리"와 watch time 누적이 배경 구간을 어떻게 다룰지는 F의 판단 사항이다. 코어는 배경 진입 시 `.itemDetached`를 방송하지 **않으므로**(`.continueAudioOnly`는 아이템을 유지) F의 세션 경계는 영향받지 않는다. **통지만, 요청 없음.**
4. **트랙 A (이미 병합됨) — 확인 요청 2건(비차단).** ① `.itemAttached(source:)` 방송 시점에 `player.avPlayerItem`이 non-nil인가(core §3.2 #4에서 도출). NowPlaying의 세션 시작이 여기 의존한다 — metrics §12-2와 **동일한 확인 요청**이므로 F의 확인 결과를 공유받으면 충분하다. ② `player.isPlaying`이 `play()` 직후 동기적으로 참(core §5.1 I-1)임에 `togglePlayPause` 라우팅이 의존한다.
5. **리포 인프라 / Wave 3** — ① 새 테스트 타깃 `ABPlayerKitNowPlayingTests`를 CI 전체 스킴과 **TSan 잡(CI-2)**에 포함할 것. 순수 리듀서 위주라 TSan에 안전하다. ② `swift-tools-version` 6.1 상향(swiftui §9-5, controls §6-5b)이 성사되면 `isolated deinit`으로 §5.4의 해제 지연 설계가 단순해진다 — 같은 항목에 **G의 관심사도 등록**해 달라. ③ 데모 앱의 배경 오디오 모드 설정(§10-7)은 G가 직접 넣지만, 실패 시 `Info.plist` 명시 파일 전환이 필요할 수 있다.
6. **Wave 3 H-1w(주석 위생)** — 트랙 G의 신규 코드는 처음부터 ID 인용 0건으로 작성하므로 H-1w의 회수 대상이 아니다. 단 §6.4에서 **수정하는** `ABPlayer.swift:797-801` 주변의 기존 주석에는 라운드3/4 ID가 남아 있을 수 있다 — G는 그것을 건드리지 않고 H-1w에 남긴다(범위 혼선 방지).
7. **Wave 3 H-2w(문서 최종화)** — §8.2에서 신설하는 README 4개 절(Background Policy / Picture in Picture / AirPlay / Now Playing)과 DocC article 2건이 H-2w의 최종 검수 대상이다. 특히 **§4.6·§6.2의 전제조건 표는 릴리스 노트에서도 한 번 더 강조**할 것을 권고한다(사용자가 가장 자주 막히는 지점).

---

## 14. 명시적 비범위 (G-5 게이트에서 위반 시 REQUEST-CHANGES)

- **`ABPlayerEvent` / `ABPlayerError` 케이스 추가**(§0, I-G7). AirPlay·PiP 어느 쪽도 새 이벤트를 만들지 않는다
- `Sources/ABPlayerKitControls/**` 수정 — 특히 SwiftUI 4파일
- `Sources/ABPlayerKitMetrics/**`, `Sources/ABPlayerKitCache/**` 수정
- **편의 API(`init(url:)`/`init(source:)`)에 PiP 파라미터 추가** — §5.2의 판정을 뒤집는 것이므로 재설계가 선행되어야 한다
- Controls에 PiP 버튼/AirPlay 버튼 UI 추가
- `AVPlayerLayer` 공개 노출, `AVPlayerViewController` 채택
- NowPlaying 큐/플레이리스트 모델(`nextTrack`/`previousTrack`의 라이브러리 구현)
- 연속 탐색 커맨드(`seekForward`/`seekBackward`), `changeRepeatMode`/`changeShuffleMode`/`like`/`rating`
- 자막·오디오 트랙 **선택 API**(문서화만 — 감사 G-6)
- tvOS/visionOS 지원(G-5, Wave 3 P-1의 선택 항목)
- `Bundle.main` 기반 배경 모드 진단 API(§6.2)
- `AVRoutePickerView` 래퍼 타입
- NowPlaying 정보의 원격 전송·로깅·샘플링
- `ABPlayer` 전면 분해, 시크/스크럽 로직 변경, 그 밖의 코어 리팩터링

---

## 15. 완료 정의 (G-5 게이트 체크리스트)

- [ ] `Sources/ABPlayerKitControls/` diff **0줄**, `Sources/ABPlayerKitMetrics/` diff **0줄**, `Sources/ABPlayerKitCache/` diff **0줄**
- [ ] `Examples/`의 메트릭 영역(`MetricsScreen.swift`, `DemoModel`의 메트릭 멤버) diff **0줄**
- [ ] `ABPlayerEvent`/`ABPlayerError` diff **0줄** (I-G7)
- [ ] 불변식 I-G1 ~ I-G10 각각에 대응 테스트 존재 (특히 I-G1·I-G2·I-G4·I-G6)
- [ ] 매트릭스 A(5정책 × 4grade × 3신호 × PiP 2상태) 전수 테이블 테스트 통과
- [ ] `isPictureInPictureActive == false` 열이 현행과 동일함이 테스트로 증명됨(I-G4)
- [ ] `ABBackgroundLifecycleEngineTests` **무수정 통과**
- [ ] `ABBackgroundPolicyMachineTests`의 기존 4정책 기대값 **무변경**(§12.3 범위 내 추가만)
- [ ] 기존 Controls 184개 테스트 무수정 통과 (전체 스킴 실행으로 확인)
- [ ] **전체 스킴 테스트 3회 연속 그린** (`-only-testing` 결과는 불인정)
- [ ] 신규 public 심볼 전부 DocC 큐레이션 + `docbuild` 경고 0
- [ ] README / README.ko의 신설 4개 절이 **동일 구성**으로 존재
- [ ] CHANGELOG **실제 파일에 반영** + Migration 노트 2건
- [ ] Swift 6 zero-warning, `@unchecked Sendable`·`MainActor.assumeIsolated`·신규 `deprecated` **0건**
- [ ] 신규 주석에 리뷰/설계 ID 인용 **0건** (diff 추가 라인 패턴 재스캔 결과를 `RESULT`에 기재)
- [ ] `RESULT-round6-nowplaying.md`에 **기기 수동 확인 결과** 기재: PiP 시작/배경 지속/복원, `.continueAudioOnly` 배경 오디오, NowPlaying 잠금화면 표시 및 커맨드 동작, AirPlay(수신기 없으면 "미확인"이라고 그대로 기재)
- [ ] §10의 확인 불가 항목 10건 각각에 대해 **확인됨/여전히 미확인** 상태를 `RESULT`에 기재
