# DESIGN: 라운드6 트랙 S — SwiftUI 간편 API (S-0 설계 게이트)

기준 커밋 995bb6d. 입력: `ROADMAP-round6.md` §0·§2(트랙 S)·§6, `REVIEW-round6-portfolio-audit.md` C-1~C-3, 실소스.
산출 대상 WP: S-1w(URL 편의 생성자), S-2w(Environment modifier), S-3w(README Quick Start).

**파일 경계 준수**: 본 설계는 `ABPlayer.swift` / `ABAVPlaybackTarget.swift` / `ABPlayerControlsView.swift`를 **한 줄도 수정하지 않는다.** 이 파일들에 요구할 사항은 §9에 기록만 한다.

---

## 0. 결정 요약

| # | 결정 | 선택 |
|---|---|---|
| 1 | 소유권 모델 | **SwiftUI 저장소 수명에 묶인 내부 소유** — `ABVideoPlayer`는 `Coordinator`+`dismantleUIView`, `ABVideoPlayerWithControls`는 `@State` 박스. **`onAppear`/`onDisappear`/`task`를 일절 쓰지 않는다.** |
| 2 | autoplay 기본값 | `true` (두 뷰 모두). 등급은 autoplay와 무관하게 항상 `.current` |
| 2b | 라벨 | `videoGravity:` (로드맵의 `gravity:` 축약 대신 기존 표면과 통일), 플레이어 설정은 코어 `configuration:` / Controls `playerConfiguration:` |
| 3 | Environment 전파 | `EnvironmentKey` 값 타입을 **Optional**(`nil` = 미지정)로. 우선순위 = **이니셜라이저 인자 > Environment > 타입 기본값**. 기존 이니셜라이저의 `style:`/`configuration:` 파라미터 타입을 Optional로 완화(호출부 100% 소스 호환) |
| 4 | README | 첫 예제 = `ABVideoPlayerWithControls(url:)` 원라이너, `kind:` 전면 제거(확장자 없는 URL 주의만 고급 절에 존치), grade는 "고급 — 피드와 프리로드"로 강등. `README.ko.md` 동시 개정 |

전부 additive. deprecated 신규 추가 없음, 제거 없음.

---

## 1. 결정 1 — URL 편의 API의 소유권 모델 (C-1)

### 1.1 선택안

> **소유권은 SwiftUI 뷰 **identity**의 수명에 묶는다. "보이지 않게 됨(disappear)"은 어떤 경우에도 해제 트리거로 쓰지 않는다.**

구현 매체는 뷰 종류별로 그 뷰의 네이티브 저장소를 쓴다. 정책은 하나, 매체는 둘이다.

| 뷰 | 저장소 | 생성 시점 | 해제 시점 |
|---|---|---|---|
| `ABVideoPlayer` (`UIViewRepresentable`) | `Coordinator` | `makeUIView(context:)` 첫 호출 | `dismantleUIView(_:coordinator:)` (동기) → 미호출 시 `Coordinator.deinit`(MainActor 홉) |
| `ABVideoPlayerWithControls` (`View`) | `@State private var owner = ABOwnedPlayerBox()` | `body` 첫 평가에서 지연 생성 | `@State` 저장소 파기 → `ABOwnedPlayerBox.deinit`(MainActor 홉) |

두 경로가 공유하는 **불변식 4개**(S-4 게이트의 검증 대상):

1. **I-1 생성 1회**: 소유 플레이어는 identity당 정확히 1개 생성된다. 뷰 구조체 재생성(부모 body 재평가)은 생성을 유발하지 않는다.
2. **I-2 해제는 identity 소멸 시에만**: `onDisappear`를 쓰지 않으므로 "화면 밖으로 스크롤됐지만 저장소는 살아있는" 상태에서 해제가 일어날 수 없다.
3. **I-3 남의 것은 건드리지 않는다**: 명시 소유(`player:` 이니셜라이저) 경로에서는 `ownsPlayer == false`이며, `dismantleUIView`/`deinit`이 `release()`를 **호출하지 않는다**.
4. **I-4 이중 해제 무해**: `release()`는 `set(source: nil, grade: .released)`이고 `ABPlayer.swift:217`의 `guard previousGrade != resolvedGrade || sourceChanged else { return }`가 두 번째 호출을 no-op으로 만든다. 따라서 `dismantleUIView` + `deinit` 이중 경로는 안전하다(방어적 플래그 불필요 — 다만 구현은 `didRelease` 플래그로 홉 자체를 생략해 불필요한 Task 생성을 피한다).

### 1.2 왜 `onDisappear` 자동 release를 기각했는가 (핵심 논거)

로드맵 §2가 제시한 원안은 "내부 `@State` ABPlayer 자동 생성 + `onDisappear` 자동 release"다. `onDisappear`는 **"identity가 죽었다"가 아니라 "지금 보이지 않는다"**는 신호이며, 둘은 SwiftUI에서 일치하지 않는다.

- `List`/`LazyVStack` 셀이 화면 밖으로 스크롤되면 `onDisappear`가 발생하지만 저장소가 유지되는 경우가 있다. 이때 `release()`하면 `AVPlayerItem`이 파기되고, 되돌아왔을 때 `onAppear`가 다시 attach → **아이템 재생성 + TTFF 재지불 + 재생 위치 리셋**(`rewindOnDemotion` 여부와 무관하게 새 아이템은 0초에서 시작). 이것이 브리프가 지목한 "재생 끊김" 시나리오의 실체다.
- 반대로 `NavigationStack` push, `TabView` 전환에서도 `onDisappear`가 발생한다. 여기서는 해제가 맞다 — 하지만 그 경우에도 identity가 살아있으므로(뒤로 가면 상태가 복원돼야 한다) 해제하면 안 된다.
- 결론: `onDisappear`는 **해제 트리거로 신뢰할 수 없다.** 반면 저장소(`Coordinator`/`@State`)의 파기는 정확히 "이 뷰 identity는 다시 오지 않는다"와 동치이며, SwiftUI가 보장한다.

`onDisappear`를 제거하면서 잃는 것은 **화면 이탈 시 자동 일시정지**다. 이는 §1.5에 알려진 한계로 명시하고 escape hatch를 문서화한다.

### 1.3 왜 "명시 소유 유지"(현행)만으로는 부족한가

C-1이 지적한 최소 경로는 4단계(플레이어 생성 → 소스 생성 → `set(source:grade:)` → `play()`) + `onDisappear { release() }`이고, README의 SwiftUI 예제(`README.md:130-154`)가 그 5줄을 그대로 노출한다. 제품 목표 1번("URL로 간편 재생")과 로드맵 §7의 완료 정의("`ABVideoPlayerWithControls(url:)` 한 줄로 재생되는 README 첫 예제")를 명시 소유만으로는 만족시킬 수 없다. **명시 소유는 제거하지 않고 그대로 둔다**(피드·프리로드·다중 플레이어의 정답 경로) — 편의 API는 그 위에 additive로 얹는다.

### 1.4 기각안과 기각 사유

| 기각안 | 사유 |
|---|---|
| `@State` + `onDisappear { release() }` (로드맵 원안) | §1.2. 지연 컨테이너에서 살아있는 identity의 플레이어를 죽인다 |
| `@State` + `onDisappear { pause() }` + `onAppear { resume() }` | 일시정지는 해제보다 안전하지만, ① `ABVideoPlayer`는 `UIViewRepresentable`이라 내부에서 `onAppear`를 붙일 수 없어 두 뷰의 동작이 비대칭이 되고 ② 지연 컨테이너의 오탐 시 "보이는데 멈춤"이 발생한다. v0.4.0 범위에서 제외하고 §9-4로 이월 |
| `ABVideoPlayer`를 `View`로 전환해 body에서 생명주기 modifier 사용 | `UIViewRepresentable` 준수 제거 = 공개 API 표면 축소. additive-only 위반 |
| `ABPlayer`에 `deinit` 기반 자동 해제 추가 | `ABPlayer.swift` 수정 금지(파일 경계). 게다가 `ABPlayer.deinit`은 이미 태스크 취소 + 오디오 세션 leave를 수행한다(`ABPlayer.swift:187-191`) — 최종 안전망은 이미 존재 |
| 소유 플레이어를 `configuration` 변경 시 재동기화 | **거부. 실패 시나리오 있음**: Controls의 배속 메뉴가 `player.setRate(_:)`를 호출하면 `configuration.playbackRate`가 바뀐다(`ABPlayer.swift:296`). 이후 부모 body가 재평가될 때 뷰가 들고 있던 원본 `configuration`으로 되쓰면 **사용자가 고른 배속이 1.0으로 리셋**된다. 따라서 `configuration`은 **생성 시 1회만** 적용한다(§3.2) |
| 코어에 공개 소유 컨테이너 타입(`ABManagedPlayer<Content>`) 신설 | 모듈 경계를 넘는 재사용은 해결되지만 검증되지 않은 추상화에 영구 공개 표면을 부여한다(§6 범위 방어). 내부 클래스 2벌(각 ~30줄, 각각 테스트됨)을 택하고, 제3의 소비자가 생기면 그때 승격 |

### 1.5 알려진 한계 (문서화 대상)

1. **화면 이탈 시 자동 일시정지 없음.** 앱 백그라운드 진입은 코어 `backgroundPolicy`(기본 `.pause`, `ABPlayerConfiguration.swift:50`)가 처리하지만, 앱 내 화면 전환에서는 소리가 계속 난다. 회피: `configuration:`으로 정책을 조정하거나 명시 소유 API를 사용.
2. **오디오 세션은 여전히 `.unmanaged` 기본**(`ABPlayerConfiguration.swift:51`). 편의 API가 프로세스 전역 세션을 몰래 건드리는 것은 이 프로젝트의 확립된 설계 입장("opt-in이 아니면 손대지 않는다", README §Audio Session)에 정면으로 위배되므로 유지한다. 무음/무시 스위치 이슈는 `configuration:` 인자로 `audioSessionPolicy = .playback(...)`을 넘기는 원라이너를 README에 함께 제시한다.
3. **동일 URL을 두 뷰가 쓰면 플레이어도 2개**다(각자 다운로드). 공유가 필요하면 명시 소유.
4. **identity 교체 순간의 짧은 오디오 중첩**: `@State` 경로의 해제는 `deinit` → `Task { @MainActor }` 홉이라 1 MainActor 턴 지연된다. 그 사이 새 identity의 `play()`가 먼저 실행될 수 있다(수 ms). `isolated deinit`(SE-0371, swift-tools 6.1 필요)로 제거 가능 — §9-5로 전달.

---

## 2. 결정 2 — autoplay 기본값과 등급

### 2.1 `autoplay` 기본값 = `true`

- 로드맵 §7 완료 정의가 "한 줄로 **재생되는**" 예제를 요구한다. 기본값 `false`면 원라이너가 정지 화면이 되고 제품 목표 1번이 미달이다.
- 두 뷰에서 동일하게 `true`. `ABVideoPlayer(url:)`은 컨트롤이 없어 소비자가 시작시킬 수단 자체가 없으므로(플레이어 핸들 비노출) `false` 기본은 사실상 dead view다.
- 대가: 무음 자동재생 옵션(HIG상 흔한 피드 패턴)이 시그니처에 없다. `configuration:`으로 `isMuted = true`를 넘기면 해결되며 README에 그 형태를 적는다.

### 2.2 등급은 autoplay와 무관하게 항상 `.current`

- `autoplay: false`에서 `.preloaded`로 두면 `play()`가 `.playbackRejected`로 거부되고(`ABPlayer.swift:273`), Controls의 재생 버튼도 `promotesToCurrentOnPlay`(`ABPlayerControlsConfiguration.swift:80`)에 의존하게 되어 두 뷰의 동작이 갈린다.
- `.current` + 미재생 = "첫 프레임을 띄운 채 정지" — 포스터 프레임 용도로도 자연스럽다.
- `autoplay`는 **상태가 아니라 1회성 시작 동작**이다. `autoplay` 값만 바뀌는 업데이트는 아무 동작도 하지 않는다(재생 중인 영상을 멈추거나 되살리지 않는다). URL이 바뀌면 새 소스에 대해 다시 1회 평가한다.

### 2.3 라벨 결정 (로드맵 표기와의 의도적 차이)

로드맵 WP 표기는 `ABVideoPlayer(url:gravity:autoplay:)`이지만, 확정 시그니처는 **`videoGravity:`**를 쓴다. 같은 타입 안에 `init(player:videoGravity:)`와 `init(url:gravity:)`가 공존하면 표면이 갈라진다(기존 `ABVideoPlayerWithControls`, `ABPlayerControlsView`, `ABPlayerConfiguration.videoGravity` 전부 `videoGravity`). 로드맵 표기는 축약으로 간주한다.

---

## 3. 확정 API 시그니처

### 3.1 `ABPlayerKit` — `Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift` (기존 파일 수정)

```swift
public struct ABVideoPlayer: UIViewRepresentable {
    // 기존 — 변경 없음
    public init(player: ABPlayer, videoGravity: AVLayerVideoGravity = .resizeAspectFill)

    // 신규 — SwiftUI가 플레이어를 소유
    public init(
        url: URL,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        configuration: ABPlayerConfiguration = ABPlayerConfiguration()
    )

    // 신규 — httpHeaders / 확장자 없는 URL의 명시 kind 용
    public init(
        source: ABMediaSource,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        configuration: ABPlayerConfiguration = ABPlayerConfiguration()
    )

    public func makeCoordinator() -> Coordinator
    public func makeUIView(context: Context) -> ABPlayerView          // 기존
    public func updateUIView(_ uiView: ABPlayerView, context: Context) // 기존
    public static func dismantleUIView(_ uiView: ABPlayerView, coordinator: Coordinator)

    /// 구현 상세. 공개 멤버 없음 — `UIViewRepresentable`이 연관 타입을 요구해 public일 뿐.
    @MainActor public final class Coordinator { }
}
```

- `Coordinator` 연관 타입이 `Void` → 신규 클래스로 바뀐다. 공개 타입 별칭 변화이지만 `ABVideoPlayer.Coordinator`를 직접 참조하는 소비자 코드는 현실적으로 없다(리포 내 0건). CHANGELOG `### Changed`에 한 줄 기록.
- 소유 경로에서 `videoGravity` 인자는 생성 시 `configuration.videoGravity`에 **덮어써서** 단일 진실원을 만든다. `ABPlayerView.attach(_:)`가 플레이어 부착 시 `configuration.videoGravity`로 되돌리기 때문이다(`ABPlayerView.swift:83`).

### 3.2 소유 저장소의 계약 (두 타깃 공통 — 각 타깃 내부 타입)

```swift
@MainActor
final class ABOwnedPlayerBox {          // Controls 타깃: 신규 파일
                                        // 코어: 동일 필드를 ABVideoPlayer.Coordinator가 보유
    private var owned: ABPlayer?
    private var appliedSource: ABMediaSource?
    private var didRelease = false

    /// I-1. `configuration`은 이 최초 1회에만 적용된다(이후 재동기화 금지 — §1.4).
    func player(configuration: ABPlayerConfiguration, videoGravity: AVLayerVideoGravity) -> ABPlayer

    /// `source`가 직전 적용분과 다를 때만 `set(source:grade:.current)`.
    /// 이어서 `autoplay`이면 `play()`. 같은 소스의 반복 호출은 완전한 no-op이다
    /// (사용자가 누른 일시정지를 body 재평가가 되살리지 않는다).
    func apply(source: ABMediaSource, autoplay: Bool)

    /// I-3/I-4. 소유하지 않았거나 이미 해제했으면 no-op.
    func releaseIfOwned()

    deinit { /* releaseIfOwned()를 MainActor로 홉 — ABPlayerControls.swift:168-193 선례 */ }
}
```

`deinit`에서의 MainActor 홉은 이 코드베이스의 확립된 패턴이다(`ABPlayerControls.Coordinator.deinit`, `ABPlayerControls.swift:168-193`: `MainActor.assumeIsolated` 금지, `isolated deinit`은 tools 6.1 필요라 `Task { @MainActor in ... }` 사용). **구현 시 주의**: `ABPlayer`(비-Sendable, `@MainActor`)를 nonisolated `deinit`에서 `Task { @MainActor in }`로 캡처하는 것이 Swift 6 모드에서 거부되면, 홉을 포기하고 `dismantleUIView`(코어) / `ABPlayer.deinit`(`ABPlayer.swift:187-191`, 태스크 취소 + 오디오 세션 leave)에만 의존한다. 그 경우 `@State` 경로는 "즉시 해제"가 아니라 "인스턴스 소멸과 함께 정리"가 되며, 이는 여전히 누수가 아니다. 어느 쪽을 택했는지 `RESULT-round6-swiftui.md`에 명시할 것.

### 3.3 `ABPlayerKitControls` — 신규 이니셜라이저

`Sources/ABPlayerKitControls/SwiftUI/ABVideoPlayerWithControls.swift` (기존 파일 수정)

```swift
public struct ABVideoPlayerWithControls: View {
    // 신규 — 원라이너
    public init(
        url: URL,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        playerConfiguration: ABPlayerConfiguration = ABPlayerConfiguration()
    )

    public init(
        source: ABMediaSource,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        playerConfiguration: ABPlayerConfiguration = ABPlayerConfiguration()
    )

    // 신규 — 액세서리 오버레이 동반형 (url/source 각각)
    public init<Accessories: View>(
        url: URL,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        autoplay: Bool = true,
        playerConfiguration: ABPlayerConfiguration = ABPlayerConfiguration(),
        @ViewBuilder accessories: @escaping () -> Accessories
    )
    // (source: 버전 동일)
}
```

- **URL 계열에는 `style:`/`configuration:`(Controls용) 파라미터를 두지 않는다.** 커스터마이즈는 결정 3의 modifier로 한다. 이유: ① 파라미터 7개짜리 시그니처를 피하고 ② `configuration:` 라벨이 `ABPlayerConfiguration`과 `ABPlayerControlsConfiguration` 두 의미로 쓰이는 혼란을 없애며 ③ 신규 modifier API에 "하나의 명백한 사용법"을 부여한다.
- 라벨이 `playerConfiguration:`인 이유는 이 타입 안에 이미 `configuration:`(=Controls 설정)이 있기 때문이다. 코어 `ABVideoPlayer`에는 설정 종류가 하나뿐이라 `configuration:`을 유지한다(사용 지점의 명확성 우선).
- 오버로드 충돌 없음: 첫 라벨(`player:`/`url:`/`source:`)이 다르고, 액세서리 유무는 후행 클로저 존재로 갈린다. 그래도 `ABPlayerControlsInitializerAmbiguityTests`에 신규 호출 형태를 추가해 기계로 고정한다(§8).

### 3.4 결정 3의 Environment 표면 — `Sources/ABPlayerKitControls/SwiftUI/ABPlayerControlsEnvironment.swift` (신규)

```swift
private struct ABPlayerControlsStyleKey: EnvironmentKey {
    // `static let`이 아니라 computed `static var`여야 한다 — §4.3
    static var defaultValue: ABPlayerControlsStyle? { nil }
}

private struct ABPlayerControlsConfigurationKey: EnvironmentKey {
    static var defaultValue: ABPlayerControlsConfiguration? { nil }
}

extension EnvironmentValues {
    /// 조상 뷰가 `.playerControlsStyle(_:)`로 지정한 스타일. `nil`은 "미지정"이며,
    /// 이니셜라이저 인자 → 이 값 → `ABPlayerControlsStyle.default` 순으로 해석된다.
    public var playerControlsStyle: ABPlayerControlsStyle? { get set }
    public var playerControlsConfiguration: ABPlayerControlsConfiguration? { get set }
}

extension View {
    public func playerControlsStyle(_ style: ABPlayerControlsStyle) -> some View
    public func playerControlsConfiguration(_ configuration: ABPlayerControlsConfiguration) -> some View
}
```

### 3.5 기존 이니셜라이저의 파라미터 타입 완화 (결정 3 실행에 필수)

`ABPlayerControls`와 `ABVideoPlayerWithControls`의 `style:`/`configuration:` 파라미터를 다음과 같이 바꾼다.

```swift
- style: ABPlayerControlsStyle = .default,
- configuration: ABPlayerControlsConfiguration = .init(),
+ style: ABPlayerControlsStyle? = nil,
+ configuration: ABPlayerControlsConfiguration? = nil,
```

- **소스 호환**: 값을 넘기던 호출부는 옵셔널 승격으로 그대로 컴파일된다. 생략하던 호출부도 그대로다. 깨지는 것은 이니셜라이저를 함수값으로 참조하는 경우뿐이며 리포 내 0건, 현실 소비자에게도 사실상 없다. SPM 소스 배포라 ABI 문제 없음.
- **동작 호환**: 신규 modifier를 쓰지 않으면 Environment 값은 항상 `nil`이므로 해석 결과가 종전과 **바이트 동일**하다(`nil ?? nil ?? .default == .default`). `POLICY-api-stability`의 "Behavior changes" 규칙에 따라 CHANGELOG `### Changed`에 한 줄 + 마이그레이션 노트("신규 modifier를 쓰지 않는 코드는 영향 없음")를 적는다.
- 이 변경은 `ABPlayerControlsView.style`/`configuration`(비옵셔널, `ABPlayerControlsView.swift:15-21`)에는 손대지 않는다. 해석은 SwiftUI 레이어에서 끝내고 UIKit 뷰에는 항상 확정값만 넘긴다 — 트랙 C와의 파일 충돌 0.

---

## 4. 결정 3 — modifier API의 Environment 전파 범위 (C-2)

### 4.1 우선순위 규칙

```
resolvedStyle         = 이니셜라이저 인자 ?? environment.playerControlsStyle ?? .default
resolvedConfiguration = 이니셜라이저 인자 ?? environment.playerControlsConfiguration ?? .init()
```

**이니셜라이저 인자가 이긴다.** 근거: 지역적·명시적 선언이 주변 환경보다 구체적이라는 SwiftUI 관례(`.font` 대 `Text`의 직접 지정과 동형)이고, `ABVideoPlayerWithControls(player:style:.minimal){}.playerControlsStyle(.tinted)`를 읽었을 때 사람이 기대하는 결과와 일치한다.

이 규칙이 **의미를 가지려면** "인자를 안 넘김"과 "인자로 `.default`를 넘김"이 구분돼야 한다 → §3.5의 Optional 완화가 전제다. 센티널 값(`ABPlayerControlsStyle.unspecified`)이나 옵셔널 오버로드 추가는 각각 취약성·모호성(기존 `ABPlayerControlsInitializerAmbiguityTests`가 존재하는 이유) 때문에 기각.

### 4.2 전파 범위

- 표준 Environment 상속: modifier가 적용된 뷰와 그 **하위 트리 전체**. `ABVideoPlayerWithControls(...)` 자신에게 붙여도 그 `body`가 만드는 `ABPlayerControls`까지 도달한다.
- 값을 읽는 지점은 **`ABPlayerControls`(UIViewRepresentable) 한 곳뿐**이며 `context.environment`로 읽는다(`@Environment` 저장 프로퍼티를 추가하지 않는다 — 커스텀 이니셜라이저가 여럿이라 저장 프로퍼티가 늘수록 초기화 부담이 커진다).
- `ABVideoPlayerWithControls`는 스스로 Environment를 읽지 않는다. 자신이 받은 옵셔널을 그대로 아래로 넘기면, `nil`인 경우 중첩된 `ABPlayerControls`가 **같은 Environment 하위 트리에서** 해석하므로 결과가 동일하다. 해석 코드는 한 벌만 존재한다.
- `ABPlayerControlsView`를 UIKit에서 직접 쓰는 소비자에게는 아무 영향이 없다(Environment는 SwiftUI 개념).
- 컨테이너에 modifier를 걸어 **여러 플레이어에 일괄 적용**하는 것이 이 API의 주 용도다(`VStack { ... }.playerControlsStyle(.minimal)`). 개별 뷰에서 인자로 예외를 두는 조합이 자연스럽게 성립한다.

### 4.3 구현 함정 (반드시 지킬 것)

1. `ABPlayerControlsStyle`은 현재 **비-Sendable**(D-10)이고 `.default`/`.minimal`/`.tinted`는 `@MainActor static let`이다(`ABPlayerControlsStyle.swift:92,94,110`). 따라서 `EnvironmentKey.defaultValue`를 `static let ... = .default`로 쓰면 nonisolated 정적 저장 프로퍼티 + MainActor 격리 위반으로 Swift 6에서 실패한다. **`static var defaultValue: ABPlayerControlsStyle? { nil }`(computed, 저장 없음)**만 사용한다. 트랙 C가 D-10(Style Sendable화)을 끝내면 `static let`으로 단순화 가능하지만 v0.4.0에서는 필요 없다.
2. `@Entry` 매크로는 쓰지 않는다. iOS 17 하한에서의 가용성 리스크를 감수할 이유가 없고, 명시적 `EnvironmentKey`가 문서화(DocC)에도 유리하다.
3. `ABPlayerControls.update(_:coordinator:)`는 현재 테스트가 직접 호출한다(`ABPlayerControlsSwiftUITests.swift:16-22` 등). 시그니처를 `update(_ view:, coordinator:, environment: EnvironmentValues = EnvironmentValues())`로 확장하면 기존 테스트가 그대로 컴파일되고 새 테스트는 환경을 주입할 수 있다.

---

## 5. identity 재생성 시나리오 분석 (안전성 논증)

`P` = 소유 플레이어. 각 행은 S-4 게이트가 검증할 항목이며 §8에 대응 테스트가 있다.

| # | 시나리오 | SwiftUI 동작 | 본 설계의 결과 | 위험 |
|---|---|---|---|---|
| 1 | 최초 표시 | `makeCoordinator` → `makeUIView` / `body` 첫 평가 | `P` 1회 생성, 소스 1회 적용, autoplay면 `play()` | 없음 |
| 2 | 부모 body 재평가 (뷰 구조체만 재생성, identity 동일) | `updateUIView`만 반복 | `appliedSource` 동일 → **완전 no-op**. 사용자가 누른 일시정지가 되살아나지 않는다 | 없음 (I-1) |
| 3 | `url` 변경, identity 동일 | `updateUIView` | 같은 `P`에 `set(source:grade:.current)` → 코어 planner가 detach→attach 수행, autoplay면 `play()`. 인스턴스 재사용이므로 **누수 0, release 0회** | 없음 |
| 4 | 지연 컨테이너 스크롤 아웃 (저장소 유지) | `onDisappear`만 발생 | 우리는 `onDisappear`를 구독하지 않음 → **아무 일도 없음**. 복귀 시 재생 지속 | 화면 밖 오디오 지속(§1.5-1) |
| 5 | 지연 컨테이너 셀 파기 (저장소 파기) | `dismantleUIView` / `@State` 파기 | `release()` 1회. 복귀 시 새 identity가 새 `P` 생성 | 없음 |
| 6 | `.id(x)` 변경 / if-else 분기 전환 | 옛 identity 파기 + 새 identity 생성 | 옛 `P` 해제, 새 `P` 생성. **이중 release 아님**(각 저장소가 자기 것만 해제, I-3/I-4) | 해제 홉 지연으로 수 ms 오디오 중첩 가능(§1.5-4) |
| 7 | 명시 소유(`player:`) 뷰의 파기 | `dismantleUIView` 호출됨 | `ownsPlayer == false` → **release 하지 않음**. 소비자 플레이어 생존 | 없음 (I-3) — 회귀 시 가장 파괴적, 전용 테스트 필수 |
| 8 | 화면 전체 종료(호스팅 컨트롤러 해제) | `dismantleUIView`가 호출되지 않을 수 있음 | `Coordinator`/`Box`의 `deinit` → 홉 → release. 그마저 실패해도 `ABPlayer.deinit`(`ABPlayer.swift:187-191`)이 태스크 취소 + 오디오 세션 leave | 없음 (3중 안전망) |
| 9 | `release()`가 두 경로로 두 번 | — | `ABPlayer.swift:217` guard가 두 번째를 no-op 처리 | 없음 (I-4) |
| 10 | 소유 `P`를 관찰하는 SwiftUI 뷰 존재 | — | **구조적으로 불가능**: 소유 `P`의 핸들은 외부에 노출되지 않는다. 우리 뷰들도 `player.grade`/`source` 같은 `@Observable` 프로퍼티를 body/update에서 읽지 않는다 | 없음 → `makeUIView`/`body` 안에서 `set(source:)`를 동기 호출해도 "Modifying state during view update"류 문제가 발생할 수 없다 |

10번이 이 설계에서 `.task`/`onAppear` 없이 **동기적으로** 소스를 적용할 수 있는 근거다. 구현 규칙으로 고정한다: **소유 경로의 `makeUIView`/`updateUIView`/`body`는 `ABPlayer`의 `@Observable` 프로퍼티를 읽지 않는다.** 멱등성 판단은 전부 저장소(`appliedSource`)로 한다.

---

## 6. 결정 4 — README Quick Start 개편안 (C-3)

### 6.1 방침

- 첫 예제 = **컨트롤 포함 URL 원라이너**. `import` 2줄 + 뷰 1줄.
- `kind:` **전면 제거**. 확장자 추론이 이미 있다(`ABMediaSource.swift:24` 파라미터 기본값 `nil`, `:30-32` `inferredKind`). 다만 "확장자 없는 서명 URL은 `kind:`를 명시" 한 줄은 고급 절에 존치한다(제거하면 실제 함정이 문서에서 사라진다).
- grade 4단계 표와 `set(source:grade:)` 설명은 **"고급 — 피드와 프리로드"**로 강등. 삭제가 아니라 이동이다(이 프로젝트의 차별점이므로).
- `.onDisappear { player.release() }`는 편의 API 예제에서 사라진다. 명시 소유 예제에서는 유지(그쪽은 여전히 소비자 책임).
- `README.ko.md`(`:78` 이하)도 동일 구조로 개정. 두 파일의 절 구성이 어긋나지 않게 한다.

### 6.2 새 Quick Start 초안 (README.md)

````markdown
## Quick Start

Play a URL with the standard controls — this is the whole integration:

```swift
import ABPlayerKit
import ABPlayerKitControls
import SwiftUI

struct VideoScreen: View {
    var body: some View {
        ABVideoPlayerWithControls(url: URL(string: "https://example.com/video.m3u8")!)
            .aspectRatio(16 / 9, contentMode: .fit)
    }
}
```

The view creates its own `ABPlayer`, starts playback, and releases every
playback resource when SwiftUI discards the view. Media type is inferred from
the URL (`.m3u8` → HLS, anything else → progressive).

Without the controls overlay, use the core target alone:

```swift
import ABPlayerKit
import SwiftUI

ABVideoPlayer(url: url, videoGravity: .resizeAspect)
```

### Customizing

Controls appearance and behavior are set with view modifiers, so one modifier
can cover a whole screen of players:

```swift
var style = ABPlayerControlsStyle.default
style.progressColor = .systemPink

var controls = ABPlayerControlsConfiguration()
controls.skipInterval = 15

ABVideoPlayerWithControls(url: url)
    .playerControlsStyle(style)
    .playerControlsConfiguration(controls)
```

Player-level settings (mute, loop, audio session, rate) go through
`ABPlayerConfiguration` at creation time:

```swift
var configuration = ABPlayerConfiguration()
configuration.isMuted = true
configuration.audioSessionPolicy = .playback(mixWithOthers: false)

ABVideoPlayerWithControls(url: url, playerConfiguration: configuration)
```

> Playback keeps running while the view stays alive but off-screen. Screens
> that need visibility-driven pausing should own the player explicitly (below).

### Owning the player yourself

Own an `ABPlayer` when several views share it, when playback must outlive one
view, or when you drive preloading across a feed:

```swift
struct VideoScreen: View {
    @State private var player = ABPlayer()

    var body: some View {
        ABVideoPlayerWithControls(player: player, videoGravity: .resizeAspect) {}
            .aspectRatio(16 / 9, contentMode: .fit)
            .task {
                player.set(source: ABMediaSource(url: url), grade: .current)
                player.play()
            }
            .onDisappear { player.release() }
    }
}
```

### Advanced — grades and preloading

(기존 grade 표 + `set(source:grade:)` 설명 + `.preloaded`/`.instanceOnly` 전이 예제를 여기로 이동.
`kind:`는 이 절의 "URL에 확장자가 없을 때만 명시" 문단에서만 언급.)
````

UIKit 예제(`ABPlayerView`)는 위치만 "Advanced" 앞으로 유지하고 `kind:` 인자만 제거한다.

---

## 7. WP별 구현 지침

공통(로드맵 §0): Swift 6 zero-warning, 시뮬레이터 신규 부팅 금지, `sleep` 금지(`ABWaitUntil`), 커밋 금지, additive-only, **새 주석에 리뷰 ID 인용 금지**(불변식만 서술 — H-2 재발 방지). 본 문서의 ID(C-1, I-3 등)를 소스 주석에 적지 말 것.

### S-1w — URL 편의 생성자

수정: `Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift`, `Sources/ABPlayerKitControls/SwiftUI/ABVideoPlayerWithControls.swift`
신규: `Sources/ABPlayerKitControls/SwiftUI/ABOwnedPlayerBox.swift`

1. `ABVideoPlayer`에 `player`를 옵셔널 저장 프로퍼티 + `ownedInput`(URL/source + autoplay + configuration) 형태로 보관. 명시 소유와 자동 소유를 하나의 `enum Ownership { case explicit(ABPlayer), owned(ABMediaSource, autoplay: Bool, ABPlayerConfiguration) }`로 표현하면 분기가 한 곳에 모인다.
2. `makeUIView`: 소유 경로면 `context.coordinator`에서 `P`를 얻고 `apply(source:autoplay:)` → `view.player = P` → `view.videoGravity = videoGravity` **순서 고정**(플레이어 부착이 gravity를 덮어쓰므로, `ABPlayerView.swift:83`).
3. `updateUIView`: 기존 로직 유지 + 소유 경로면 `apply(source:autoplay:)` 재호출(멱등).
4. `dismantleUIView`: `coordinator.releaseIfOwned()`. **명시 소유에서는 절대 호출되지 않도록** 소유 여부를 코디네이터가 자체 보유.
5. `ABVideoPlayerWithControls`: `@State private var owner = ABOwnedPlayerBox()`. body에서 `let player = owner.player(configuration:videoGravity:)` → `owner.apply(source:autoplay:)` → 기존 body 구성 재사용. 명시 소유 이니셜라이저 경로에서는 박스를 **사용하지 않는다**(`owner`는 만들어지되 비어 있는 채로 남고 `deinit`이 no-op).
   - 주의: 기존 `controlsView: AnyView`는 이니셜라이저에서 즉시 만들어진다(`ABVideoPlayerWithControls.swift:22,34-42,60-62`). URL 계열은 플레이어가 body 시점에야 존재하므로 **이 프로퍼티를 그대로 쓸 수 없다.** URL 계열은 "액세서리 클로저 + 스타일 옵셔널"만 저장하고 body에서 `ABPlayerControls`를 구성하도록 분기한다. 기존 `player:` 경로의 `controlsView` 즉시 생성은 그대로 둔다(deprecated 경로의 경고 회피 구조가 거기에 묶여 있다).
6. 새 코드가 `ABPlayer.grade`/`source`/`isPlaying`을 body/update에서 읽지 않는지 확인(§5-10).

### S-2w — Environment modifier

신규: `Sources/ABPlayerKitControls/SwiftUI/ABPlayerControlsEnvironment.swift`
수정: `Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift`, `ABVideoPlayerWithControls.swift`

1. §3.4 그대로. `defaultValue`는 computed `static var`(§4.3-1).
2. §3.5의 파라미터 Optional 완화. `init(legacyPlayer:...)`(internal, `ABPlayerControls.swift:52-58`)도 함께 옵셔널화하되 `@available(*, deprecated ...)` 표기는 **그대로 유지**한다(제거하면 `ABVideoPlayerWithControls`의 경고 회피 구조가 깨진다).
3. `update(_:coordinator:environment:)`에서 해석 후 `ABPlayerControlsView`에는 확정값만 대입. 기존의 "변경된 것만 대입"(`ABPlayerControls.swift:107-115`) 구조를 유지해 불필요한 레이아웃 무효화를 막는다.
4. DocC: `ABPlayerKitControls.docc/ABPlayerKitControls.md`의 Topics에 새 modifier를 큐레이션하고, `CustomizingControls.md`에 modifier 절을 추가(CI가 `DOCC_WARNINGS_AS_ERRORS=YES`).

### S-3w — README 개편

수정: `README.md`, `README.ko.md`, (필요 최소) `Sources/ABPlayerKit/ABPlayerKit.docc/ABPlayerKit.md` Topics에 새 심볼 큐레이션.

1. §6.2 초안 반영. 두 언어판의 절 구성 동일하게.
2. 리포 전역 `kind:` 잔재 점검: `README.md`, `README.ko.md`, DocC, `Examples/`(데모는 `player:` 경로를 계속 쓰므로 코드 변경 불필요 — 문서 문구만).
3. CHANGELOG `### Added`(편의 생성자, modifier), `### Changed`(파라미터 타입 완화 + `Coordinator` 연관 타입) + 마이그레이션 노트 1줄.

---

## 8. 테스트 전략

새 시뮬레이터 부팅 없음. 기존 호스팅 패턴(`UIHostingController` + `UIWindow`, `ABVideoPlayerWithControlsTests.swift:16-36`) 재사용. 네트워크 대신 `Tests/ABPlayerKitTests/Resources`의 로컬 파일 URL 사용. 비동기 대기는 `ABWaitUntil`만.

### 코어 — `Tests/ABPlayerKitTests/ABVideoPlayerOwnershipTests.swift` (신규, `@testable`)

| # | 검증 | 대응 불변식 |
|---|---|---|
| 1 | `url:` 마운트 후 `ABPlayerView.player?.source?.url` 일치 + `grade == .current` | I-1 |
| 2 | `autoplay: true` → 재생 시작 / `autoplay: false` → `.current` & 미재생 | 결정 2 |
| 3 | `updateUIView` 2회 반복해도 플레이어 인스턴스 동일(`===`) | I-1 / 시나리오 2 |
| 4 | 소유 플레이어를 `pause()`시킨 뒤 `updateUIView` 재호출 → 재생 재개되지 않음 | 시나리오 2 (재생 끊김·되살아남 회귀) |
| 5 | `url` 변경 → 인스턴스 동일, `source.url` 갱신, autoplay 재적용 | 시나리오 3 |
| 6 | `dismantleUIView` → `grade == .released`, `source == nil` | 시나리오 5 |
| 7 | **`player:` 명시 소유에서 `dismantleUIView` 호출 → grade 불변** | I-3 (최우선) |
| 8 | `dismantleUIView` 2회 + `deinit` 중복 → 크래시 없음, 상태 `.released` 유지 | I-4 |
| 9 | 코디네이터를 스코프 밖으로 보낸 뒤 `ABWaitUntil { player.grade == .released }` | 시나리오 8 |
| 10 | `source:` 이니셜라이저가 `httpHeaders`/명시 `kind`를 보존 | §3.1 |

### Controls — `Tests/ABPlayerKitControlsTests/`

| # | 파일 | 검증 |
|---|---|---|
| 11 | `ABVideoPlayerWithControlsTests`(확장) | `url:` 마운트 시 `ABPlayerControlsView.player === ABPlayerView.player`(동일 인스턴스 공유) |
| 12 | 〃 | `url:` + `.playerControlsStyle(.minimal)` 호스팅 → 마운트된 컨트롤의 `style == .minimal` (modifier가 합성 뷰를 관통) |
| 13 | `ABPlayerControlsEnvironmentTests`(신규) | 해석 매트릭스 4종: 인자만 / 환경만 / 둘 다(인자 승) / 둘 다 없음(`.default`) — `update(_:coordinator:environment:)` 직접 호출 |
| 14 | 〃 | `configuration`도 동일 매트릭스(`skipInterval` 등으로 식별) |
| 15 | `ABOwnedPlayerBoxTests`(신규) | 생성 1회, `apply` 멱등, 같은 소스 재적용이 `play()`를 다시 부르지 않음, `releaseIfOwned` 멱등 |
| 16 | 〃 | 박스 소멸 후 `ABWaitUntil`로 해제 관측(홉 채택 시) |
| 17 | `ABPlayerControlsInitializerAmbiguityTests`(확장) | `url:` 4형태(기본 / 후행 클로저 / `playerConfiguration:` 지정 / modifier 체인) 컴파일 고정 |
| 18 | 기존 184개 Controls 테스트 | 파라미터 Optional 완화 후 **무수정 통과**(소스 호환 증명) |

18번이 §3.5의 소스 호환 주장을 기계로 증명하는 항목이다. **기존 테스트를 고쳐야 한다면 그 자체가 설계 위반 신호이므로 게이트에 보고할 것.**

---

## 9. 타 트랙 전달 사항 (본 트랙은 해당 파일을 수정하지 않음)

1. **트랙 A (`ABPlayer.swift`)** — B-5 `.playbackRejected` 페이로드: 편의 API는 `.current` 승격 직후 `play()`를 호출하며 소비자에게 플레이어 핸들이 없다. 거부가 발생하면 진단 경로가 전무하므로, 요청 동작과 당시 grade를 페이로드에 포함해 달라.
2. **트랙 A** — A-3(`lastError` 리셋)·A-4(`hasDisplayedFirstFrame` detach 리셋): URL 변경으로 같은 인스턴스를 재사용하는 것이 편의 API의 기본 경로다. 소스 교체 시 상태 리셋이 없으면 편의 API에서 오염이 곧바로 드러난다. 우선순위 상향 요청.
3. **트랙 C (`ABPlayerControlsView.swift` 등)** — ① D-10(Style `Sendable`화)이 끝나면 `EnvironmentKey.defaultValue`를 computed에서 `static let`으로 단순화 가능(필수 아님). ② `ABPlayerControlsView.style`/`configuration`은 **비옵셔널 유지** 요청 — 옵셔널 해석은 SwiftUI 레이어에서 끝난다. ③ 신규 스타일/설정 프로퍼티는 Environment 표면에 자동 반영되므로 별도 작업 불필요.
4. **다음 라운드(또는 트랙 G)** — 가시성 기반 자동 일시정지(`pausesWhenHidden`류): §1.5-1의 한계. 트랙 G의 `.continueAudioOnly`(G-4)·PiP(G-1)와 정면으로 상호작용하므로(PiP 세션은 뷰 파기보다 오래 살아야 한다) **G-0 설계에서 "PiP 사용 시 편의 API의 자동 해제를 억제할 수단이 필요한가"를 명시적으로 판단해 달라.** 필요하다면 v0.4.0 이후 additive 옵션으로 도입.
5. **리포 인프라(트랙 CI 또는 Wave 3)** — `swift-tools-version`을 6.1로 올리면 `isolated deinit`(SE-0371)이 열리고, ① 본 설계의 소유 박스 해제와 ② 기존 `ABPlayerControls.Coordinator.deinit`의 액세서리 detach가 모두 동기화된다(§1.5-4 해소). 별도 판단 항목으로 등록 요청.
6. **Wave 3 H-2w** — README/DocC 최종화 시 §6.2 구조(Quick Start → Customizing → Owning → Advanced)를 기준선으로 삼을 것.

---

## 10. 완료 정의 (S-4 게이트 체크리스트)

- [ ] `ABPlayer.swift` / `ABAVPlaybackTarget.swift` / `ABPlayerControlsView.swift` diff 0줄
- [ ] 불변식 I-1~I-4 각각에 대응 테스트 존재(§8의 1·3·7·8번)
- [ ] `onAppear`/`onDisappear`/`task`가 신규 코드에 0건
- [ ] 기존 Controls 테스트 184개 무수정 통과
- [ ] 신규 public 심볼 전부 DocC 큐레이션 + `docbuild` 경고 0
- [ ] README/README.ko의 첫 예제가 원라이너이며 `kind:` 부재
- [ ] Swift 6 zero-warning, 신규 주석에 리뷰 ID 인용 0건
