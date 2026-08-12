# DESIGN: 라운드6 트랙 C — Controls UX (C-0 설계 게이트)

기준 커밋 995bb6d. 입력: `DESIGN-round6-core.md` §3·§3.5·§5.5(확정 계약), `DESIGN-round6-swiftui.md` §9-3, `ROADMAP-round6.md` §0·§3 트랙 C, `REVIEW-round6-portfolio-audit.md` §D(D-1~D-11), 실소스 `Sources/ABPlayerKitControls/` 전체.

산출 대상 WP: C-1w ~ C-7w. 본 문서의 "확정" 시그니처는 구현 브리프가 그대로 인용한다.

**파일 경계**: 본 트랙은 `Sources/ABPlayerKitControls/` 안에서만 작업한다. `Sources/ABPlayerKit/`(특히 `ABTimeFormatter.swift`)는 **한 줄도 수정하지 않는다**. 또한 트랙 S가 Wave 1에서 점유하는 `Sources/ABPlayerKitControls/SwiftUI/` 3파일(`ABPlayerControls.swift`, `ABVideoPlayerWithControls.swift`, `ABPlayerControlsEnvironment.swift`)과 `ABOwnedPlayerBox.swift`도 **수정하지 않는다**(§6-3 근거). 요구가 생기면 §6에 기록만 한다.

---

## 0. 전역 제약 (모든 결정에 선행)

| 제약 | 내용 | 근거 |
|---|---|---|
| additive-only | 공개 타입/프로퍼티/케이스는 **추가만**. 기존 프로퍼티 타입 변경·이름 변경·삭제 금지 | `POLICY-api-stability.md`, ROADMAP §0 |
| deprecated 신규 부착 금지 | 슬롯 API가 `accessoryViews`를 대체해도 `@available(*, deprecated)`를 붙이지 않는다. 라이브러리 내부(`ABPlayerControls.update`)가 그 심볼을 계속 쓰므로 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`에서 자기 경고가 난다 | `ABPlayerControls.swift:31-51`이 그 함정을 이미 한 번 우회한 구조 |
| 기본값 = 현행 동작 | 신규 옵션(`touchPassthrough`, `doubleTapSeek`, 슬롯)의 기본값은 **현재 렌더링·히트테스트 결과가 바이트 동일**하게 유지되는 값이어야 한다 | §5.1 I-C2/I-C3 |
| `@unchecked Sendable` / `MainActor.assumeIsolated` 금지 | 코드베이스 확립된 금지(`DESIGN-OPEN-QUESTIONS.md` Q13, `ABPlayerControls.swift:168-193` 주석) | D-10 해결 방식을 제약함 |
| 코어 표면은 소비만 | `ABPlayerEvent`/`ABPlayer` 프로퍼티는 읽기만 한다. 필요한 것이 없으면 §6로 전달 | ROADMAP §6 "유일한 공유 파일 위험은 `ABPlayerEvent.swift`(A 전용)" |
| Controls는 시크 델타를 스스로 합산하지 않는다 | 누적의 진실원은 코어 `pendingSeekTime` | core §3.5 |
| 새 주석에 리뷰 ID 인용 금지 | 불변식만 서술. 본 문서의 ID(D-2, I-C1 등)를 소스 주석에 적지 말 것 | ROADMAP §0, H-2 재발 방지 |

### 소비하는 코어 확정 표면 (core §5.5 동결분 중 C가 쓰는 것)

| 심볼 | 용도 | WP |
|---|---|---|
| `player.isBuffering` / `bufferingChanged(Bool)` | 스피너, 아이콘 역전 해소, auto-hide 억제 | C-1w |
| `player.isPlaying`(저장·관찰) | 탭 분기의 라이브 값 | C-1w |
| `player.pendingSeekTime` / `seekTargetChanged(CMTime?)` | 누적 skip 표시, 낙관적 타임라인 렌더 | C-2w, C-3w |
| `durationAvailable(CMTime)` | 스크러버 활성화(폴링 제거) | C-2w |
| `callRejected(ABRejectedCall, grade:)` | 거부 진단(데모/문서용, UI 동작 변경 없음) | C-7w(문서만) |
| `mutedChanged(Bool)` | (이번 라운드 미사용 — Controls에 음소거 UI가 없음) | — |

---

## 결정 1 — 버퍼링 시각 상태 (D-2, D-3)

### 1.1 선택안: **아이콘 유지 + 글리프 자리에 스피너 오버레이**, 컨트롤 가시성과 독립

세 가지를 동시에 만족해야 한다: (a) 스톨 중에도 **일시정지할 수 있어야** 하고, (b) 스톨 중 **레이아웃이 흔들리면 안 되며**, (c) 컨트롤이 자동으로 숨겨진 상태에서도 **스피너는 보여야** 한다.

```
transport row (레이아웃 불변)          컨트롤 숨김 + 버퍼링
 ⏪   [ ◌ ]   ⏩                              ◌
      ↑ playPauseButton은 그 자리에         (스피너만 표시)
        그대로 있고 enabled·hitTest 우선,
        글리프만 억제되고 스피너가 겹침
```

- **스피너 위치**: `controlsContentView`의 **형제**(자기 자신의 직접 subview)로 두고 `controlsContentView.centerX/centerY`에 고정한다. `buttonStack`이 같은 앵커에 고정돼 있으므로(`ABPlayerControlsView.swift:282-283`) 스피너 중심 == play/pause 중심이며, 스킵 버튼이 숨겨져도(`showsSkipButtons == false`) 흔들리지 않는다. 형제로 두는 이유는 `applyControlsVisibility`가 `controlsContentView.alpha`를 0으로 만들 때(`:860-880`) 스피너까지 사라지면 (c)가 깨지기 때문이다.
- **비상호작용**: `isUserInteractionEnabled = false`, `priorityControls`(`:176-183`)에 넣지 않는다. → hitTest 결과 불변(I-C1).
- **글리프 억제**: 버퍼링 중 `playPauseButton`은 `isHidden`도 `alpha`도 건드리지 않는다. `isHidden = true`는 `buttonStack`을 재배치하고, `alpha = 0`은 **UIKit이 `alpha <= 0.01`인 뷰를 히트테스트에서 제외**하므로 (a)가 깨진다. 대신 `ABControlButton`에 글리프 억제 상태를 두고 `setImage(nil, for: .normal)`만 적용한다 — 44×44 고정 제약(`:291-292`)이 있으므로 크기 변화 0.
- **접근성**: `accessibilityLabel`은 계속 "일시 정지"(의도가 재생이므로). VoiceOver 사용자도 스톨을 중단할 수 있다.
- **Reduce Motion**: 스피너는 계속 회전한다. 정지한 로딩 인디케이터는 아무 정보도 전달하지 못하며, `UIActivityIndicatorView`/`ProgressView`는 시스템 자체도 Reduce Motion에서 멈추지 않는다. `style.respectsReduceMotion`은 **가시성 페이드와 바운스에만** 적용된다는 기존 계약(`:868-871`, `:708-713`)을 넓히지 않는다. DocC에 명시.

### 1.2 아이콘 역전(D-2)의 해소 축: `isPlaying || isBuffering`

현재 아이콘은 `.timeControlStatusChanged(status)` → `isPlaying = status == .playing`(`ABControlsPresenter.swift:174-176`) 하나로만 결정된다. 리버퍼에서 `.waitingToPlay`가 오면 ▶︎로 뒤집힌다.

코어 §3.5는 `isPlaying && isBuffering`을 "재생을 원하지만 멈춰 있음"으로 규정한다. 그러나 그것만으로는 부족하다 — `automaticallyWaitsToMinimizeStalling == false` 튜닝(코어 `ABBufferingEvaluator`의 `.paused` 분기)에서는 스톨 시 rate가 0이 되어 `isPlaying == false`, `isBuffering == true`가 된다. 이 경우까지 덮는 축은 **논리합**이다.

```
showsPauseIcon = isPlaying || isBuffering
```

`isBuffering`은 코어 평가기의 `guard hasItem, intendsToPlay, !isWaitingWithNoItem`에 의해 **재생 의도가 있을 때만** 참이므로, 논리합은 정확히 "사용자가 재생을 원하는 상태"를 의미한다.

| 상황 | `isPlaying` | `isBuffering` | 아이콘 | 스피너 |
|---|---|---|---|---|
| 정상 재생 | true | false | ⏸ | ✗ |
| 리버퍼(기본 튜닝, `.waitingToPlay`) | true | true | ⏸ | ✓ |
| 리버퍼(`automaticallyWaits == false`, `.paused`) | false | true | ⏸ | ✓ |
| 사용자 일시정지 | false | false | ▶︎ | ✗ |
| 재생 종료 | false | false | ▶︎ | ✗ |
| 아이템 없음 / 미준비 | false | false | ▶︎ | ✗ |

### 1.3 프리젠터 배선 — 기존 케이스 시그니처를 하나도 바꾸지 않는다

`ABControlsPresenter.isPlaying`의 **의미를 유지**한다(`.timeControlStatusChanged(.playing)`만 참으로 만든다). 새 상태를 옆에 둔다.

```swift
struct ABControlsPresenter: Equatable {
    private(set) var isPlaying = false        // 기존, 의미 불변
    private(set) var isBuffering = false      // 신규
    private(set) var hasPlayedToEnd = false   // 신규 (결정 6 / D-5)

    /// play/pause 버튼이 표시해야 할 상태이자, 탭이 수행해야 할 동작의 축.
    var showsPauseIcon: Bool { isPlaying || isBuffering }

    enum Effect: Equatable {
        // 기존 6종 그대로
        case setBuffering(Bool)               // 신규
    }
}
```

`handlePlayerEvent`의 변경은 **두 곳뿐**이다.

```swift
case .timeControlStatusChanged(let status):
    isPlaying = status == .playing
    return [.setPlaybackIcon(isPlaying: showsPauseIcon)]

case .bufferingChanged(let buffering):
    guard buffering != isBuffering else { return [] }
    isBuffering = buffering
    // 아이콘도 함께 갱신한다 — .playedToEnd 와 .bufferingChanged(false) 의
    // 도착 순서는 계약되어 있지 않으므로, 어느 쪽이 나중에 와도 최종 상태가
    // 옳도록 양쪽 모두가 아이콘을 다시 낸다.
    return [.setBuffering(buffering), .setPlaybackIcon(isPlaying: showsPauseIcon)]
```

**기존 프리젠터 테스트가 그대로 통과하는 이유**: `isBuffering`이 거짓인 동안 `showsPauseIcon == isPlaying`이므로 `ABControlsPresenterTests.swift:56/66/144`(`.playing`→`[.setPlaybackIcon(true)]`, `.paused`→`[false]`, `.playedToEnd`→`[false]` **정확히 1개**)의 배열 동등 비교가 유지된다. `.bufferingChanged`는 기존 테스트가 한 번도 넣지 않는 신규 입력이다.

### 1.4 탭 분기도 같은 축을 쓴다 — 단, `Input` 케이스는 건드리지 않는다

`ABPlayerControlsView.togglePlayback()`(`:686-700`)이 넘기는 값을 라이브 논리합으로 바꾼다.

```swift
presenter.handle(.playPauseTapped(
    isPlaying: player.isPlaying || player.isBuffering,   // ← 여기만 바뀐다
    allowsPromotionTap: canPromoteToCurrentOnPlayTap
))
```

`Input.playPauseTapped(isPlaying:allowsPromotionTap:)`의 **라벨과 시그니처는 유지**한다. 라벨을 `intendsToPlay:`로 고치면 `ABControlsPresenterTests.swift:166/177/186/204` 네 곳이 기계적으로 깨지는데, 그 파일은 MJ-3 회귀(라이브 값이 캐시를 이긴다)를 고정하는 파일이라 무수정 통과가 곧 증명이다. 대신 호출부에 불변식 주석을 남긴다. MJ-3의 논거(`ABControlsPresenter.swift:113-131`)는 그대로 유효하며, 논리합은 그 논거를 `automaticallyWaits == false` 경로까지 **확장**할 뿐이다.

### 1.5 스톨 중 auto-hide 정책: **억제하되 강제 표시는 하지 않는다**

`ABControlsVisibilityMachine`에 `isScrubbing`(`:31`, `:56-66`, `:105-111`)과 **동형**으로 `isBuffering`을 추가한다.

```swift
enum Input: Equatable {
    // 기존 10종 그대로
    case bufferingChanged(Bool)          // 신규
}

private(set) var isBuffering = false     // 신규

case .bufferingChanged(let buffering):
    isBuffering = buffering
    return buffering ? [.cancelAutoHide] : scheduleEffectsIfNeeded()

// scheduleEffectsIfNeeded()  : guard 에 `!isBuffering` 추가
// .autoHideFired             : guard 에 `!isBuffering` 추가
// .detached                  : isBuffering = false (isScrubbing 과 같은 줄)
```

- **억제하는 이유**: 스톨 중에는 화면이 정지 프레임이다. 이때 오버레이를 숨기면 사용자가 "중단하고 나가기"(일시정지·스크럽)에 접근할 수단이 사라진다. 스크럽 중 억제와 같은 논리다.
- **강제 표시하지 않는 이유**: 300ms짜리 순간 리버퍼마다 오버레이 전체가 튀어나오면 긴 영상에서 매우 거슬린다. 신호는 이미 스피너가 전달하며(§1.1의 (c) 덕분에 컨트롤이 숨어 있어도 보인다), 그것으로 충분하다.
- **`playbackStateChanged` 피드는 건드리지 않는다**(`ABPlayerControlsView.swift:422-423`의 `status == .playing`). 그 경로를 논리합으로 바꾸면 `ABPlayerControlsAutoHideTests`/`playbackEndShowsPlayAndControls`가 의존하는 전이가 달라진다. `isBuffering` 축은 **직교로 추가**하는 것이 최소 diff다.

### 1.6 기각안

| 기각안 | 사유 |
|---|---|
| play/pause 버튼을 스피너로 **교체**(버튼 제거 후 인디케이터 삽입) | (a) 긴 리버퍼를 사용자가 중단할 수 없다. (b) `buttonStack`의 arranged subview가 바뀌어 transport 클러스터 폭이 변하고, `renderedTransportControlsFrame`에 의존하는 `bottomClusterOverlapFavorsButtonsOverSeekBar`(`ABPlayerControlsViewTests.swift:507-534`)의 겹침 전제가 무너진다 |
| 스피너를 `controlsContentView` **안**에 넣기 | auto-hide로 컨트롤이 숨으면 스피너도 같이 사라진다. 스톨의 유일한 신호가 소멸 |
| `playPauseButton.alpha = 0`으로 글리프 숨기기 | `UIView.hitTest`가 `alpha <= 0.01`인 뷰를 제외한다 → 스톨 중 일시정지 불가. `ABPlayerControlsView.hitTest`가 `control.hitTest(...)`를 직접 호출하므로(`:186`) 우회 불가 |
| 아이콘 축을 `isPlaying && isBuffering`으로만 판정 | `automaticallyWaits == false` 스톨(코어 평가기 `.paused` 분기)에서 `isPlaying == false`라 D-2가 그대로 남는다 |
| `.playbackStalled` 이벤트로 스피너 그리기 | 코어 §3.4가 명시 기각 — 기본 튜닝에서 아예 발생하지 않는 경우가 흔하다 |
| `.waitingToPlay` 추론 | core §3.5 명시 금지. 레이트 평가 대기와 실제 리버퍼가 구분되지 않는다 |
| `isBuffering`을 프리젠터 대신 뷰가 직접 `player.isBuffering`으로 폴링 | D-9가 지적한 미러 패턴의 반복. 이벤트 스트림이 이미 진실원 |
| 스톨 시 컨트롤 강제 표시(`.setVisible(true)`) | §1.5. 짧은 리버퍼마다 오버레이가 깜빡인다 |

---

## 결정 2 — 더블탭 시크 UX (D-4)

### 2.1 영역 분할: 좌 30% / 중앙 40%(불감대) / 우 30%

순수 값 타입으로 분리해 제스처 없이 표 테스트한다 — `ABSeekBarGeometry`/`ABControlsLayout`과 같은 방식.

```swift
// Layout/ABDoubleTapSeekZone.swift (신규, internal)
enum ABDoubleTapSeekZone: Equatable {
    case backward, neutral, forward

    /// `edgeFraction` 은 0.1...0.5 로 클램프된다. `width <= 0` 이면 `.neutral`.
    /// 레이아웃 방향(RTL)은 호출부가 `effectiveUserInterfaceLayoutDirection` 으로
    /// 해석해 뒤집으므로 이 함수는 항상 물리 좌표 기준이다.
    static func zone(forX x: CGFloat, width: CGFloat, edgeFraction: Double) -> Self
}
```

- **중앙 불감대가 필요한 이유**: 컨트롤이 표시 중이면 transport 버튼이 hitTest 우선순위(`:176-183`)로 자기 터치를 가져가므로 문제가 없다. 그러나 컨트롤이 숨겨지면 `controlsContentView.isUserInteractionEnabled == false`가 되어(`:865`) 버튼이 터치를 받지 못하고 **오버레이 전체가 제스처를 받는다**. 이때 중앙 불감대가 없으면 "화면 중앙 더블탭 = 재생 위치 점프"가 되어, 오버레이를 부르려던 탭이 시크로 오인된다.
- **RTL**: `.backward`/`.forward`는 의미(시간축) 기준이다. `traitCollection.layoutDirection == .rightToLeft`면 호출부에서 좌/우를 뒤집는다. 순수 함수는 물리 좌표만 다룬다.

### 2.2 옵션 형태 — 기본값 `.disabled`

```swift
public enum ABDoubleTapSeek: Sendable, Equatable {
    /// 더블탭 제스처를 설치하지 않는다(기본값).
    case disabled
    /// 좌우 가장자리 대역에서 더블탭이 ``skipInterval`` 만큼 시크한다.
    /// `edgeWidthFraction` 은 오버레이 폭에 대한 한쪽 대역의 비율로, 0.1...0.5 로 클램프된다.
    case edges(edgeWidthFraction: Double = 0.3)
}

extension ABPlayerControlsConfiguration {
    public var doubleTapSeek: ABDoubleTapSeek { get set }   // = .disabled
}
```

**기본값이 `.disabled`인 결정적 이유**: 더블탭을 인식하려면 기존 배경 탭 인식기가 `singleTap.require(toFail: doubleTap)`으로 **더블탭 실패를 기다려야** 한다. 그러면 모든 단일 탭의 show/hide 토글이 ~300ms 지연된다 — 기존 모든 소비자가 체감하는 실질 회귀다. 따라서 더블탭 인식기와 `require(toFail:)`는 **`doubleTapSeek != .disabled`일 때만 설치**하고, 기본값은 옵트인이어야 한다. 데모 앱과 DocC/README에서 켜는 것을 권장 설정으로 제시한다.

### 2.3 연속 탭 누적 표시 — 코어 `pendingSeekTime`만 읽는다

```
seekTargetChanged(t) 수신
  ├─ t != nil 이고 직전이 nil 이었다면: anchor = presenter.currentPlaybackTime.currentTime  (1회 스냅샷)
  ├─ t != nil: delta = t - anchor          → 배지에 "+20초" / "+40초"
  │            낙관적 렌더 render(ABPlaybackTime(currentTime: t, duration: …))
  └─ t == nil: anchor = nil, 배지 페이드 아웃
```

- **자체 누적기가 아니다**: 합산은 전적으로 코어 `pendingSeekTime`(`base = pendingSeekTime ?? currentTime`)이 수행한다. Controls는 "이번 연타가 시작된 지점"이라는 **기준점 1개**만 보관해 절대값을 상대 표기로 환산한다. 기준점은 `nil → non-nil` 전이에서만 갱신되고 `nil`에서 폐기되므로 상태가 누적되지 않는다.
- **스크럽 중에는 배지가 뜨지 않는다**: 코어가 스크럽 세션 중 `pendingSeekTime`을 갱신하지 않는다(core 결정 4). 시크바가 위치의 주인이라는 계약과 일치.
- **한 경로가 세 소비자를 덮는다**: 스킵 버튼(D-1 잔여), 더블탭(D-4), VoiceOver 조정이 전부 코어 시크를 거치므로 배지·낙관적 렌더가 **한 벌**로 통일된다. 이것이 C-2w와 C-3w가 같은 메커니즘을 공유하는 근거다.

### 2.4 배지 뷰

```
Sources/ABPlayerKitControls/View/ABSeekFeedbackView.swift (신규, internal)
```
- `controlsContentView`의 **형제**(스피너와 같은 이유 — 컨트롤이 숨겨진 상태의 더블탭이 주 사용 시나리오다).
- `isUserInteractionEnabled = false`, `priorityControls` 미포함 → hitTest 불변.
- 배치: 해당 대역의 수평 중앙, 오버레이 수직 중앙.
- 애니메이션: 등장 페이드 + 소멸 페이드. `style.respectsReduceMotion && isReduceMotionEnabledProvider()`면 duration 0으로 즉시 전환(`applyControlsVisibility`의 기존 규약 `:868-871`과 동일). 테스트 노출용 `private(set) var lastSeekFeedbackAnimationDuration: TimeInterval?`.

### 2.5 햅틱

```swift
extension ABPlayerControlsConfiguration {
    public var providesHapticFeedback: Bool { get set }   // = true
}
```
- 발화 지점은 **더블탭 시크 수용 시 1회**로 한정한다. 스킵 버튼/배속/스크럽에는 붙이지 않는다 — 그쪽은 기존 동작이고, 기기 동작을 조용히 바꾸는 것은 옵트인 없이 할 일이 아니다(더블탭은 옵트인 제스처이므로 예외).
- 테스트 시임은 기존 관례를 따른다(`isVoiceOverRunningProvider` `:59`와 동형):
```swift
var performHapticFeedback: @MainActor (UIImpactFeedbackGenerator.FeedbackStyle) -> Void =
    { UIImpactFeedbackGenerator(style: $0).impactOccurred() }
```

### 2.6 VoiceOver 실행 중에는 더블탭 시크를 수행하지 않는다

VoiceOver의 더블탭은 **포커스된 요소의 활성화 제스처**다. 여기에 시크를 겹치면 "재생 버튼을 활성화하려 했는데 20초 점프"가 된다. 따라서 제스처 핸들러 진입부에서 `guard !isVoiceOverRunningProvider() else { return }`. VoiceOver 사용자의 시크 경로는 이미 두 개 있다 — 조절 가능(`.adjustable`) 시크바(`ABSeekBar.swift:68-69`)와 스킵 버튼.

### 2.7 기각안

| 기각안 | 사유 |
|---|---|
| 좌/우 50:50 분할(중앙 불감대 없음) | §2.1. 컨트롤 숨김 상태에서 중앙 더블탭이 시크가 된다 |
| 기본값 `.edges(0.3)`(켜짐) | §2.2. 모든 기존 소비자의 단일 탭이 ~300ms 지연된다 |
| `require(toFail:)` 없이 단일 탭도 즉시 발화 | 더블탭 1회가 "토글 + 토글 + 시크"를 만든다. 사용자가 본 결과와 조작이 어긋난다 |
| Controls가 `accumulatedDelta`를 직접 합산 | core §3.5 명시 금지. `ABPlayer`를 직접 쓰는 소비자와 동작이 갈린다 |
| 배지에 절대 시각("01:20")을 표시 | 연타 피드백의 요점은 "얼마나 더"다. 절대 시각은 시크바와 시간 라벨이 이미 낙관적으로 보여준다 |
| 더블탭 인식기를 `seekBar`/버튼에도 부착 | 스크럽 중 오인식. 오버레이 자신에만 부착하고 대역 판정으로 거른다 |
| Reduce Motion에서 배지 자체를 숨김 | Reduce Motion은 "움직임을 줄여라"이지 "정보를 숨겨라"가 아니다. 페이드만 제거 |

---

## 결정 3 — passthrough 터치 옵션 (D-4)

### 3.1 확정 형태

```swift
public enum ABControlsTouchPassthrough: Sendable, Equatable {
    /// 오버레이 영역의 모든 터치를 소비한다(현행 동작, 기본값).
    case never
    /// 컨트롤이 숨겨져 있는 동안에만, 어떤 컨트롤에도 닿지 않은 터치를 뒤로 통과시킨다.
    case whenControlsHidden
    /// 어떤 컨트롤에도 닿지 않은 터치를 항상 뒤로 통과시킨다.
    case always
}

extension ABPlayerControlsConfiguration {
    public var touchPassthrough: ABControlsTouchPassthrough { get set }   // = .never
}
```

### 3.2 hitTest와의 상호작용 — **우선순위 루프 뒤, 마지막 한 줄만 추가**

```swift
public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
    if controlsContentView.isUserInteractionEnabled, … {
        for control in priorityControls { … return hitView }      // ← 기존 그대로, 순서 불변
    }
    let hit = super.hitTest(point, with: event)
    // 패스스루가 포기하는 것은 오직 "자기 자신"뿐이다. 실제 자손 뷰(컨트롤,
    // 액세서리, 소비자가 넣은 subview)가 잡히면 언제나 그 뷰가 이긴다.
    if hit === self, isPassthroughActive { return nil }
    return hit
}

private var isPassthroughActive: Bool {
    switch configuration.touchPassthrough {
    case .never:              false
    case .whenControlsHidden: !isControlsVisible
    case .always:             true
    }
}
```

핵심 성질: **패스스루는 우선순위 판정에 개입하지 않는다.** `super.hitTest`가 `self`를 돌려준 경우 — 즉 어떤 자손도 잡히지 않은 경우 — 에만 `nil`로 바꾼다. 따라서 §5.1 I-C1(구체적 컨트롤 → 액세서리 → 시크바)의 순서 계약은 정의상 영향받지 않으며, `.never` 기본값에서는 `hit`을 그대로 돌려주므로 **현재 코드와 완전히 동일**하다.

### 3.3 알려진 상호작용 (문서화 필수)

패스스루가 활성인 터치에 대해 이 뷰는 응답자 체인에서 빠지므로, **`backgroundTapRecognizer`(`:270-272`, `handlesBackgroundTap`)가 그 터치를 받지 못한다.** 결과:

| 조합 | 결과 |
|---|---|
| `.never`(기본) + `handlesBackgroundTap = true` | 현행 그대로 |
| `.whenControlsHidden` + `handlesBackgroundTap = true` | **탭으로 컨트롤을 다시 부를 수 없다.** 숨김 = 패스스루이므로 |
| `.whenControlsHidden` + `handlesBackgroundTap = false` | 의도된 조합. 호스트가 `setControlsVisible(_:)`로 가시성을 주도하고, 숨김 중 터치는 아래 뷰(피드 셀 등)로 간다 |
| `.always` + `handlesBackgroundTap = false` | 의도된 조합. 오버레이는 컨트롤 히트박스만 점유 |

DocC `CustomizingControls.md`에 이 표를 그대로 싣는다. API로 강제하지 않는 이유: `handlesBackgroundTap`을 자동으로 끄면 소비자가 설정한 값을 라이브러리가 덮어쓰는 것이고, 두 값이 모두 `configuration`에 있어 어느 쪽이 나중에 대입될지 정해져 있지 않다.

### 3.4 기각안

| 기각안 | 사유 |
|---|---|
| `Bool passthroughTouches` | "언제"가 표현되지 않는다. 실사용의 대부분은 "숨겨져 있을 때만"이다 |
| 소비자 제공 술어(`(CGPoint) -> Bool`) | `ABPlayerControlsConfiguration`의 `Sendable, Equatable`이 깨진다(`TimeLabelFormat.custom`이 이미 지불한 대가 — `:85-105`). 세 케이스로 충분 |
| 기본값을 `.whenControlsHidden`으로 | `interactiveControlHitTesting`(`ABPlayerControlsViewTests.swift:664-668`)이 숨김 상태에서 `hitTest(center) === view`를 단언한다. 기본값 변경은 곧 그 테스트의 파괴이자 무언의 동작 변경 |
| `isUserInteractionEnabled = false`로 통째 비활성화 | 컨트롤까지 죽는다 |
| `super.hitTest` 앞에서 패스스루 판정 | 소비자가 오버레이에 직접 추가한 subview(문서화된 확장 경로가 아니지만 가능)까지 무시된다. `hit === self` 검사가 그 경우를 정확히 배제 |

---

## 결정 4 — 레이아웃 슬롯 API (D-7)

### 4.1 확정 표면

```swift
// Model/ABControlsSlot.swift (신규)
/// 액세서리 뷰를 배치할 수 있는 오버레이 내 위치.
public enum ABControlsSlot: Sendable, Hashable, CaseIterable {
    /// 오버레이 상단 후행 모서리(상단바).
    case topTrailing
    /// 중앙 transport 클러스터의 후행. 클러스터 자체의 중앙 정렬은 유지된다.
    case transportTrailing
    /// 하단 행에서 시간 라벨과 배속 컨트롤 사이. ``accessoryViews`` 와 같은 자리.
    case bottomTrailing
}

extension ABPlayerControlsView {
    /// `slot` 에 배치된 뷰들. 선행→후행 순서.
    public func accessoryViews(in slot: ABControlsSlot) -> [UIView]
    public func setAccessoryViews(_ views: [UIView], in slot: ABControlsSlot)

    /// 기존 프로퍼티는 `.bottomTrailing` 슬롯의 별칭으로 남는다(동작 100% 동일).
    public var accessoryViews: [UIView] { get set }
}
```

- `accessoryViews`는 **정확히** `accessoryViews(in: .bottomTrailing)` / `setAccessoryViews(_:in: .bottomTrailing)`로 재정의한다. 같은 스택, 같은 위치, 같은 hitTest 우선순위 → `accessoryViewsWinHitTestingOverAnEnabledSeekBar`(`:536-576`)와 `swiftUIHostedAccessoryWinsHitTestingOverAnEnabledSeekBar`(`:578-612`), `ABPlayerControlsSwiftUITests`의 SwiftUI 액세서리 경로가 전부 무수정 통과.
- **deprecated 붙이지 않는다**(§0). `ABPlayerControls.update(_:coordinator:)`(`ABPlayerControls.swift:119-129`)가 계속 `view.accessoryViews`를 쓰며, 그 파일은 트랙 S 소유라 손댈 수 없다.
- `.topLeading`은 **의도적 이월**. 브리프가 명시한 3종만 넣는다. 상단 선행 슬롯(제목 등)은 나중에 케이스 추가만으로 additive하게 붙는다.

### 4.2 각 슬롯의 컨테이너와 레이아웃 안전성

| 슬롯 | 컨테이너 | 제약 | 비어 있을 때 |
|---|---|---|---|
| `.topTrailing` | 신규 `topStack`(horizontal, `.center`), `controlsContentView`의 자식 | `top == layoutMarginsGuide.top`, `trailing == layoutMarginsGuide.trailing` | 크기 0. `rootStack`(하단 고정, `top >= layoutMarginsGuide.top` `:286`)과 `buttonStack`(중앙 고정 `:282-283`)에 **영향 없음** |
| `.transportTrailing` | 신규 `transportTrailingStack`, `controlsContentView`의 자식. **`buttonStack`의 arranged subview가 아니다** | `leading == buttonStack.trailing + style.buttonSpacing`, `centerY == buttonStack.centerY`, `trailing <= layoutMarginsGuide.trailing`(priority `.defaultHigh`) | 폭 0 |
| `.bottomTrailing` | 기존 `accessoryStack`(`:247-249`, `:256`) | 변경 없음 | 변경 없음 |

**`.transportTrailing`을 `buttonStack`에 넣지 않는 이유**가 이 결정의 핵심이다. `buttonStack`은 `centerX`로 고정돼 있으므로(`:282`) 자식을 하나 더 추가하면 스택 전체가 넓어지면서 **play/pause 버튼이 오버레이 중앙에서 밀려난다.** 별도 스택을 `buttonStack.trailingAnchor`에 붙이면 클러스터의 중앙 정렬이 보존되고, `renderedTransportControlsFrame`에 의존하는 `bottomClusterOverlapFavorsButtonsOverSeekBar`와 `releaseLayoutGeometry`(`:379`)의 기하 전제가 그대로 유지된다.

**비어 있는 슬롯이 기하를 바꾸지 않는다**는 것이 I-C3이며, `ABControlsLayoutTests`가 고정한 리터럴 값(`rootStackSpacing == -27.96142578125` 등, `:16`·`:24`)이 그 기계적 증거다. 두 신규 스택은 모두 `rootStack`/`buttonStack`의 제약에 참여하지 않으므로 리터럴은 산술적으로 변할 수 없다.

### 4.3 hitTest 우선순위 확장

```swift
var priorityControls: [UIView] = [playPauseButton, skipForwardButton, skipBackwardButton, rateButton]
priorityControls.append(contentsOf: transportTrailingStack.arrangedSubviews)
priorityControls.append(contentsOf: topStack.arrangedSubviews)
priorityControls.append(contentsOf: accessoryStack.arrangedSubviews)   // 기존 위치 유지
priorityControls.append(seekBar)                                       // 언제나 마지막
```
- 4개 transport 버튼이 선두라는 것과 `seekBar`가 최후라는 것은 불변(I-C1).
- `.transportTrailing`이 `accessoryStack`보다 앞인 이유: transport 행은 짧은 오버레이에서 시크바 터치 행과 실제로 겹친다(`:507-534`가 그 겹침이 실재함을 단언한다). 겹치지 않는 `.topTrailing`은 순서가 무관하지만 결정적 순서를 위해 고정한다.

### 4.4 `showsPlayPauseButton` / `showsSeekBar`

```swift
extension ABPlayerControlsConfiguration {
    public var showsPlayPauseButton: Bool { get set }   // = true
    public var showsSeekBar: Bool { get set }           // = true
}
```
- 적용 관례는 `showsSkipButtons`(`:500-501`, `:572-575`)를 그대로 따른다: 아이콘/렌더 갱신 메서드 **마지막**에 `if !configuration.showsPlayPauseButton { playPauseButton.isHidden = true }`를 두어, `updatePlaybackIcon()`이 나중에 다시 켜지 못하게 한다.
- `showsSeekBar = false` → `seekBar.isHidden = true`. `rootStack`의 arranged subview이므로 자연 붕괴되고, `UIView.hitTest`가 숨김 뷰에 대해 `nil`을 돌려주므로 우선순위 루프도 자동으로 건너뛴다(추가 분기 불필요).
- 두 값이 모두 `false`이고 `showsTimeLabels`/`showsSkipButtons`/`rateInteraction == .hidden`이면 오버레이는 배경 스크림 + 슬롯만 남는다 — 커스텀 UI를 위한 정당한 구성이며, 의도적으로 허용한다.

### 4.5 기각안

| 기각안 | 사유 |
|---|---|
| `accessoryViews`에 `deprecated` 부착 후 슬롯 API로 이관 | §0. 라이브러리 내부(트랙 S 소유 파일)가 계속 호출하므로 zero-warning CI에서 자기 경고 |
| 슬롯별 개별 프로퍼티(`topTrailingAccessoryViews` 등) | 슬롯이 늘 때마다 공개 프로퍼티가 늘고, `ABControlsSlot`로 순회하는 코드(hitTest, 스타일 적용)를 못 쓴다 |
| `.transportTrailing`을 `buttonStack`의 arranged subview로 | §4.2. play/pause가 중앙에서 이탈 |
| 대칭용 투명 스페이서를 선행에 자동 삽입해 중앙 정렬 유지 | 존재하지 않는 기하를 발명한다. `.transportLeading`이 추가되면 스페이서와 실제 뷰가 충돌 |
| `showsPlayPauseButton`을 `style.playIcon = .none`으로 대체 | 이미 가능하지만 배속·시간 라벨과 표현 축이 갈린다(`shows*`는 configuration, 아이콘은 style). D-7이 요구한 것은 configuration 축의 일관성 |

---

## 결정 5 — 스타일 diff 단일화(D-8) + `Sendable`화(D-10)

### 5.1 단일 facet 레지스트리

현재 diff 목록은 3벌이다 — `iconsDiffer`(`ABPlayerControlsView.swift:924-933`), `requiresControlsLayout`(`:935-956`), `requiresSeekBarLayout`(`ABSeekBar.swift:257-269`). 프로퍼티를 추가하고 목록에 넣는 것을 잊으면 **조용히** 갱신이 누락된다.

```swift
// Model/ABPlayerControlsStyleFacets.swift (신규, internal)
extension ABPlayerControlsStyle {
    struct ChangeImpact: OptionSet, Sendable {
        let rawValue: Int
        static let iconRebuild    = ChangeImpact(rawValue: 1 << 0)
        static let controlsLayout = ChangeImpact(rawValue: 1 << 1)
        static let seekBarLayout  = ChangeImpact(rawValue: 1 << 2)
        /// 색·불투명도처럼 다시 칠하기만 하면 되는 값.
        static let paintOnly: ChangeImpact = []
    }

    struct Facet {
        /// 저장 프로퍼티 이름과 **정확히 일치**해야 한다. 소진성 테스트가 이 값을
        /// `Mirror` 로 얻은 라벨 집합과 대조한다.
        let name: String
        let impact: ChangeImpact
        let isEqual: (ABPlayerControlsStyle, ABPlayerControlsStyle) -> Bool
    }

    /// 유일한 진실원. 모든 저장 프로퍼티가 정확히 한 번 등장한다.
    static let facets: [Facet]

    /// 달라진 facet들의 impact 합집합.
    func changeImpact(comparedTo previous: Self) -> ChangeImpact
}
```

소비 지점 3곳이 전부 이 하나를 읽는다.

```swift
// ABPlayerControlsView.applyStyle(previous:)  (:484-493)
guard let previous else { return }
let impact = style.changeImpact(comparedTo: previous)
if impact.contains(.iconRebuild) { … invalidateIntrinsicContentSize() … }
if replacedBackground || impact.contains(.controlsLayout) { styleLayoutInvalidationCount += 1; setNeedsLayout() }

// ABSeekBar.style.didSet  (:14-21)
if style.changeImpact(comparedTo: oldValue).contains(.seekBarLayout) { setNeedsLayout() }
```

`backgroundStyle`은 facet에서 `paintOnly`다 — 레이아웃 무효화 여부는 `controlsBackgroundView.apply(_:)`의 반환값(`replacedBackground`, `ABControlsBackgroundView.swift:11-52`)이 결정하며 그 경로는 그대로 둔다.

**현재 분류를 한 항목도 바꾸지 않는다**(이것이 `ABPlayerControlsLiveStyleTests`의 `styleLayoutInvalidationCount` 단언 2건 — 색상 변경 시 증가 없음(`:24`), 치수 변경 시 정확히 1(`:40`) — 을 보존하는 조건이다):

| impact | 프로퍼티 |
|---|---|
| `.iconRebuild` (8) | `playIcon`, `pauseIcon`, `skipBackwardIcon`, `skipForwardIcon`, `iconPointSize`, `iconWeight`, `iconRenderingMode`, `rateLabelStyle` |
| `.controlsLayout` 단독 (9) | `playPauseButtonSize`, `skipButtonSize`, `buttonSpacing`, `timeLabelFont`, `usesFixedWidthTimeLabels`, `rateButtonSize`, `contentInsets`, `containerCornerRadius`, `seekBarBottomSpacing` |
| `[.controlsLayout, .seekBarLayout]` (11) | `trackHeight`, `trackHeightWhileScrubbing`, `trackCornerRadius`, `seekBarHorizontalInset`, `thumbSize`, `thumbSizeWhileScrubbing`, `thumbBorderWidth`, `thumbCornerRadius`, `thumbShadowRadius`, `thumbImage`, `isThumbHidden` |
| `.paintOnly` (14 + 신규) | `buttonHighlightedAlpha`, `tintColor`, `disabledTintColor`, `timeLabelColor`, `trackColor`, `progressColor`, `bufferedColor`, `thumbColor`, `thumbBorderColor`, `thumbShadowOpacity`, `thumbTouchInflation`, `backgroundStyle`, `visibilityAnimationDuration`, `respectsReduceMotion` + 본 라운드 신규 4종(§5.3) |

**소진성 강제**: `Mirror(reflecting: ABPlayerControlsStyle()).children`의 라벨 집합과 `facets.map(\.name)` 집합이 같음을 단언하는 테스트를 둔다. 프로퍼티를 추가하고 레지스트리에 넣지 않으면 **빨간불**이 된다 — 이것이 D-8이 실제로 요구한 기계적 가드다.

### 5.2 `Sendable`화 (D-10)

`ABPlayerControlsStyle`의 구성 요소는 SDK에서 이미 전부 `Sendable`이다: `UIColor`/`UIFont`/`UIImage`가 `NS_SWIFT_SENDABLE`(iOS 18 SDK / UIKit 헤더 확인), 나머지는 `CGFloat`/`CGSize`/`NSDirectionalEdgeInsets`/`TimeInterval`/`Bool`과 UIKit `NS_ENUM`들이다.

```swift
public enum ABControlIcon: Sendable, Equatable { … }
public enum ABControlsBackgroundStyle: Sendable, Equatable { … }
public enum ABTrackCornerRadius: Sendable, Equatable { … }
public enum ABRateLabelStyle: Sendable, Equatable { … }
public struct ABPlayerControlsStyle: Sendable, Equatable { … }
```

**두 개의 독립 서브아이템으로 쪼개고 위험한 쪽을 뒤에 둔다**(코어 A-7w의 `defaultRate` 처리와 같은 패턴):

1. **(안전)** 위 5개 타입에 `Sendable` 부착. 순수 additive.
2. **(되돌림 가능)** 프리셋 3종의 `@MainActor` 제거: `@MainActor public static let default/minimal/tinted`(`ABPlayerControlsStyle.swift:92,94,110`) → `public static let`. 이 표기는 타입이 비-Sendable이라 Swift 6에서 전역 저장이 불가능했기 때문에 붙은 것이므로, 1번이 끝나면 불필요해진다.

**검증 우선 절차 (구현자 필수)**: C-7w 착수 시 CI 툴체인(`Xcode 16.4`, `.github/workflows/ci.yml:19`)에서 1번만 먼저 컴파일해 본다. 실패하면(해당 SDK에서 UIKit 타입 중 하나가 Sendable이 아니라면) **D-10은 이월하고 §6-5에 사유를 기록**한다. `@unchecked Sendable`은 §0에 의해 선택지가 아니다. 실패는 컴파일 에러로 즉시 드러나므로 조용한 위험은 없다.

2번의 부작용: 다른 액터에서 `await ABPlayerControlsStyle.default`를 쓰던 소비자 코드에 "no async operations occur within 'await'" **경고**가 뜬다(소비자 측 경고이지 소스 비호환이 아니다). CHANGELOG `### Changed` 한 줄 + 마이그레이션 노트.

### 5.3 본 라운드가 추가하는 스타일 프로퍼티 (전부 `paintOnly` facet)

```swift
/// 버퍼링 인디케이터의 색. `nil` 이면 ``tintColor`` 를 따른다.
public var bufferingIndicatorColor: UIColor?                  // = nil
public var seekFeedbackTextColor: UIColor                      // = .white
public var seekFeedbackBackgroundColor: UIColor                // = UIColor.black.withAlphaComponent(0.45)
public var seekFeedbackFont: UIFont                            // = .systemFont(ofSize: 15, weight: .semibold)
```
전부 기본값이 있으므로 `ABPlayerControlsStyle() == .default`(`ABPlayerControlsStyleTests.swift:10`)는 그대로 성립한다.

### 5.4 기각안

| 기각안 | 사유 |
|---|---|
| `Mirror` 기반 **런타임** diff(프로퍼티 순회로 자동 비교) | 값 타입 비교가 `Any` 언박싱을 타며 `Equatable`을 잃는다(`UIImage` 두 인스턴스). 성능도 `applyStyle` 호출마다 지불. 무엇보다 impact **분류**는 반사로 알 수 없다 |
| 키패스 배열 + `Equatable` 존재 타입 | `KeyPath<Style, some Equatable>`를 이종 배열에 담을 수 없다. 클로저 비교자가 가장 단순한 표현 |
| `iconsDiffer`/`requiresControlsLayout`을 남긴 채 seekBar만 통합 | 3벌 중 2벌만 줄이는 것으로는 "프로퍼티 추가 시 조용한 버그"가 그대로 남는다 |
| 소진성 검사를 컴파일 타임 매크로로 | 매크로 타깃 신설 = 패키지 구조 변경. 테스트 한 개가 같은 보장을 준다 |
| `Sendable` 대신 `ABPlayerControlsStyle`을 클래스화 | 값 의미론 상실. `style` 대입 diff 전체가 무의미해진다 |

---

## 결정 6 — 나머지 WP의 확정 사항

### 6.1 D-5 리플레이 (C-4w)

`.playedToEnd` 후 play 탭이 `player.play()`만 호출하면 AVPlayer는 끝에서 rate가 0으로 묶여 있어 아무 일도 일어나지 않는다(`ABControlsPresenter.swift:208-210`).

```swift
enum PlayerCommand: Equatable {
    // 기존 5종 그대로
    case restartFromStart          // 신규
}
```
- 프리젠터: `hasPlayedToEnd`를 `.playedToEnd`에서 `true`, `.seekCompleted`/`.itemDetached`/`.sourceChanged`/`.timeControlStatusChanged(.playing)`/`.detached`/`.gradeChanged(to: != .current)`에서 `false`로 둔다. `.playPauseTapped`에서 `hasPlayedToEnd && !isPlaying`이면 `[.send(.restartFromStart)]`(승격이 필요하면 그 앞에 `.send(.promoteToCurrent)`).
- 뷰의 해석 — **시크 후 재생** 순서를 지킨다:
```swift
case .restartFromStart:
    guard let targetPlayer else { return }
    Task { [weak targetPlayer] in
        await targetPlayer?.seek(to: .zero, tolerance: .precise)
        targetPlayer?.play()
    }
```
  먼저 `play()`를 부르면 끝 지점에서 rate가 다시 0으로 눌릴 수 있어 순서를 뒤집을 수 없다. 완전히 버퍼된 아이템의 0초 정밀 시크는 사실상 즉시 완료된다.
- **기존 테스트 보호**: `.playedToEnd`의 반환 effect는 `[.setPlaybackIcon(isPlaying: false)]` **정확히 1개**로 유지된다(`ABControlsPresenterTests.swift:149`가 배열 동등 비교). 플래그는 상태일 뿐 effect가 아니다. `.seekCompleted`도 `[]` 유지(`:120`).

### 6.2 D-1 잔여 — VoiceOver 라벨/커맨드 일치 (C-2w)

코어 A-5w가 `base = pendingSeekTime ?? currentTime`으로 바뀌면, 프리젠터의 낙관적 절대 렌더(`ABControlsPresenter.swift:150-164`)와 코어의 상대 커맨드가 **수렴한다**:

- 1회차: `pendingSeekTime == nil` → 코어 base == `currentTime` == 프리젠터 base. 일치.
- 2회차(정착 전): 프리젠터의 `currentPlaybackTime`은 1회차 목표로 갱신돼 있고(`:163`), 코어의 `pendingSeekTime`도 같은 값이다. 일치.

C-2w의 일은 (1) 이 수렴을 테스트로 고정하고, (2) `seekTargetChanged(t)` 수신 시 **스킵 버튼 경로에도** 같은 낙관적 렌더를 적용해 세 경로를 한 벌로 만드는 것이다.

```swift
case .seekTargetChanged(let target):
    guard player?.isScrubbing != true else { return }
    guard let target else { seekFeedback.dismiss(); seekAnchor = nil; return }
    if seekAnchor == nil { seekAnchor = presenter.currentPlaybackTime.currentTime }
    let snapshot = ABPlaybackTime(currentTime: target,
                                  duration: presenter.currentPlaybackTime.duration ?? player?.duration,
                                  bufferedUntil: presenter.currentPlaybackTime.bufferedUntil)
    render(snapshot)                      // render 가 presenter.syncPlaybackTime 을 겸한다(§6.5)
    seekFeedback.show(delta: target - seekAnchor!, …)
```
`.accessibilityAdjusted` 경로는 프리젠터가 이미 같은 값을 렌더하므로 멱등이다.

접근성 보강(D-11 일부): 신규 localized hint 키 5종(`controls.hint.playPause`, `.skipBackward`, `.skipForward`, `.rate`, `.timeline`)을 `accessibilityHint`에 부착한다. **기존 `accessibilityLabel` 문자열은 바꾸지 않는다** — `ABPlayerControlsAccessibilityTests.swift:12-15,22,26`이 키를 직접 비교한다.

### 6.3 D-6 배속 로케일 + 타이틀 훅 (C-5w)

```swift
// Model/ABRateFormatter.swift (신규, internal, 순수)
struct ABRateFormatter {
    let locale: Locale
    /// 0.5 → "0.5"(en) / "0,5"(de). 정수는 소수부 없이("1"), 최대 2자리, 그룹 구분자 없음.
    func string(from rate: Float) -> String
}
```
`String(format: "%g", rate)`(`ABPlayerControlsView.swift:599`, `:742`)를 전부 대체한다. 뷰는 `Locale.autoupdatingCurrent`를 넘기고, 테스트는 명시 로케일을 주입한다.

```swift
extension ABPlayerControlsConfiguration {
    /// 배속 값을 문자열로 만드는 방식.
    public enum RateLabelFormat: Sendable {
        /// 로케일을 따르는 기본 표기. ``ABPlayerControlsStyle/rateLabelStyle`` 의
        /// `format` 템플릿이 그 결과를 감싼다("%@×" → "1.5×").
        case automatic
        /// 소비자 포맷터. 반환값이 **라벨 전체**로 쓰이며 `rateLabelStyle` 의
        /// `format` 템플릿은 적용되지 않는다.
        case custom(@Sendable (Float) -> String)
    }
    public var rateLabelFormat: RateLabelFormat { get set }   // = .automatic
}
```
`Equatable` 수기 구현은 `TimeLabelFormat`(`ABPlayerControlsConfiguration.swift:85-105`)을 **그대로** 따른다: `.automatic == .automatic`, `.custom`은 항상 불일치. 그로 인한 SwiftUI 재대입 churn이 `UIMenu`를 재생성하지 않는다는 보장은 이미 존재하는 `rateMenuContentsChanged` 가드(`:512-514`)가 제공한다 — 그 가드에 `rateLabelFormat`을 **추가하지 않는다**(추가하면 `.custom`에서 매 패스 메뉴가 재생성된다).

메뉴 항목 타이틀(`:742`의 `"\(String(format: "%g", option))×"`)도 버튼 타이틀과 같은 경로를 쓰도록 통일한다 — 지금은 버튼만 `style.rateLabelStyle`의 format을 존중하고 메뉴는 "×"를 하드코딩하는 불일치가 있다. 기존 테스트는 메뉴 **개수**만 단언하므로(`ABPlayerControlsRateTests.swift:17,95`) 안전하다.

### 6.4 D-11 하드코딩 문자열 (C-5w)

| 항목 | 현재 | 확정 |
|---|---|---|
| 가시 LIVE 라벨 | `ABTimeFormatter.liveMarker`(코어, `"LIVE"`) — `ABControlsTimeLabelFormatter.swift:38` | Controls 로컬라이즈 키 `controls.liveMarker` 신설. **en = `"LIVE"`**(현행 렌더 바이트 동일), ko = `"실시간"`. 코어 심볼은 손대지 않는다(파일 경계) |
| 시간 라벨 구분자 | `"/"` 하드코딩(`:49`) | `configuration.timeLabelSeparator: String = "/"`. 기본값 동일 → 동작 변화 0 |
| 접근성 힌트 | 없음 | §6.2의 5개 키 |
| 햅틱 | 없음 | 결정 2.5 |

`controls.live`(음성용 "Live"/"실시간")와 `controls.liveMarker`(가시용 "LIVE"/"실시간")는 **별개 키**다. 전자는 VoiceOver가 읽는 문장이고 후자는 축약 배지다.

### 6.5 D-9 프리젠터 미러 제거 (C-7w) — 범위를 명시적으로 좁힌다

감사가 지목한 3중 미러는 `ABPlayerControlsView.isPlayingState`/`currentPlaybackTime`(`:54-55`), `ABControlsPresenter.isPlaying`/`currentPlaybackTime`(`:73-75`), 그리고 `ABPlayer`다.

**하는 것**:
1. `ABPlayerControlsView.isPlayingState` **삭제**. `presenter.showsPauseIcon`을 읽는다. 테스트 접근자 `isShowingPauseIcon`(`:84`)은 이름을 유지하고 그 값을 돌려준다 → `ABControlsPlayPauseReentrancyCharacterizationTests.swift:71,95` 무수정 통과.
2. `ABPlayerControlsView.currentPlaybackTime` **삭제**하고 `presenter.currentPlaybackTime`을 유일한 사본으로 만든다. `render(_:)`가 진입부에서 `presenter.syncPlaybackTime(time)`을 호출하도록 바꾸면, 지금 `syncPlaybackTime`을 별도로 부르던 두 지점(`:435`, `:450`)이 자연히 사라진다. `scrubChanged`/`setControlsEnabled`/`applyConfiguration`의 읽기는 그대로 컴파일된다.
3. `replacePlayer()`의 `presenter.seed(...)`(`:365`)는 유지하되 `isPlaying:` 인자에 §1.4의 논리합을 넘긴다.

**하지 않는 것 (명시적 비범위 — C-8이 이것으로 REQUEST-CHANGES 하지 않도록)**:
- `ABPlayerControlsView`가 `withObservationTracking`으로 `player.isPlaying`/`isBuffering`을 직접 구독하는 것. 코어 문서가 못박은 이중 체계 원칙(core §0 "관찰 이중 체계 유지")상 UIKit 소비자의 채널은 이벤트 스트림이다. 관찰 추적은 매 발화마다 재등록이 필요해 `handlePlayerEvent`와 중복 갱신 경로를 만든다.
- `ABControlsPresenter`에서 상태를 제거해 완전 무상태로 만드는 것. 28개 프리젠터 테스트가 그 상태를 검증한다.
- 스크럽 세션의 `scrubbingPlayer` 고정(`:53`, `:776-813`) 제거. 감사 "강점" 목록 등재 항목.

---

## 3. 확정 API 시그니처 (한자리 모음)

```swift
// ── 신규 공개 타입 ────────────────────────────────────────────────
public enum ABControlsSlot: Sendable, Hashable, CaseIterable {
    case topTrailing, transportTrailing, bottomTrailing
}

public enum ABControlsTouchPassthrough: Sendable, Equatable {
    case never, whenControlsHidden, always
}

public enum ABDoubleTapSeek: Sendable, Equatable {
    case disabled
    case edges(edgeWidthFraction: Double = 0.3)
}

// ── ABPlayerControlsView (추가만) ─────────────────────────────────
extension ABPlayerControlsView {
    public func accessoryViews(in slot: ABControlsSlot) -> [UIView]
    public func setAccessoryViews(_ views: [UIView], in slot: ABControlsSlot)
    // 기존 `accessoryViews`, `style`, `configuration` 은 시그니처·옵셔널성 모두 불변
}

// ── ABPlayerControlsConfiguration (추가만, 전부 기본값 = 현행 동작) ──
extension ABPlayerControlsConfiguration {
    public enum RateLabelFormat: Sendable, Equatable {
        case automatic
        case custom(@Sendable (Float) -> String)
    }
    public var showsPlayPauseButton: Bool          // = true
    public var showsSeekBar: Bool                  // = true
    public var showsBufferingIndicator: Bool       // = true
    public var touchPassthrough: ABControlsTouchPassthrough   // = .never
    public var doubleTapSeek: ABDoubleTapSeek      // = .disabled
    public var providesHapticFeedback: Bool        // = true
    public var rateLabelFormat: RateLabelFormat    // = .automatic
    public var timeLabelSeparator: String          // = "/"
}

// ── ABPlayerControlsStyle (추가만) ───────────────────────────────
extension ABPlayerControlsStyle {
    public var bufferingIndicatorColor: UIColor?   // = nil (→ tintColor)
    public var seekFeedbackTextColor: UIColor      // = .white
    public var seekFeedbackBackgroundColor: UIColor
    public var seekFeedbackFont: UIFont
}

// ── Sendable 부착 (C-7w, 검증 후) ────────────────────────────────
// ABPlayerControlsStyle, ABControlIcon, ABControlsBackgroundStyle,
// ABTrackCornerRadius, ABRateLabelStyle : + Sendable
// ABPlayerControlsStyle.default/.minimal/.tinted : @MainActor 제거
```

기존 공개 심볼 중 **바뀌는 것은 하나도 없다.** `ABControlsEvent`도 이번 라운드에 케이스를 추가하지 않는다(더블탭 시크는 `.seekCommitted`가 아니라 코어가 정착 시 내는 `.seekCompleted`로 관측되며, 스킵 배지는 UI 내부 상태다).

### 신규 파일

```
Sources/ABPlayerKitControls/
  Model/ABControlsSlot.swift
  Model/ABRateFormatter.swift
  Model/ABPlayerControlsStyleFacets.swift
  Layout/ABDoubleTapSeekZone.swift
  View/ABBufferingIndicatorView.swift
  View/ABSeekFeedbackView.swift
  Resources/{en,ko}.lproj/Localizable.strings   (키 추가)
```

---

## 4. WP별 구현 지침과 테스트 전략

전 WP 공통(ROADMAP §0): Swift 6 zero-warning, 새 시뮬레이터 부팅 금지, `sleep` 금지(`Support/ABWaitUntil.swift`), 커밋 금지, 새 주석에 리뷰 ID 인용 금지. 각 WP는 독립 커밋 단위. 신규 공개 심볼은 전부 DocC 큐레이션(CI가 `DOCC_WARNINGS_AS_ERRORS=YES`).

### C-1w — 버퍼링 상태 (D-2, D-3)

**수정**: `StateMachine/ABControlsPresenter.swift`, `StateMachine/ABControlsVisibilityMachine.swift`, `View/ABPlayerControlsView.swift`, `View/ABControlButton.swift`, `Model/ABPlayerControlsStyle.swift`, `Model/ABPlayerControlsConfiguration.swift`
**신규**: `View/ABBufferingIndicatorView.swift`

1. 프리젠터에 `isBuffering`/`showsPauseIcon`/`Effect.setBuffering` 도입(§1.3).
2. 가시성 머신에 `isBuffering` + `.bufferingChanged` 입력(§1.5).
3. 뷰: 스피너를 `controlsContentView`의 형제로 추가하고 `controlsContentView.centerX/centerY`에 고정. `isUserInteractionEnabled = false`. `priorityControls` 미포함.
4. `ABControlButton`에 글리프 억제 상태 추가 — `applyBaseIcon`/`applySkip`의 `setImage` 지점에서만 분기하고, `isHidden` 계산은 `image == nil && !isGlyphSuppressed`로 바꾼다.
5. `togglePlayback()`의 `isPlaying:` 인자를 `player.isPlaying || player.isBuffering`으로(§1.4).
6. `handlePlayerEvent`에 `.bufferingChanged` 분기 추가 → 가시성 머신에 전달.
7. **`ABControlsPlayPauseReentrancyCharacterizationTests`의 기록 필터 갱신**(§5.3 허용 변경 — 사유는 §6-1 참조).

**테스트**
- 프리젠터 표 테스트: (`isPlaying` × `isBuffering`) 4조합 × 도착 순서 2가지 → `showsPauseIcon`과 방출 effect.
- 값이 안 바뀐 `.bufferingChanged` 중복 수신이 effect를 내지 않음.
- 뷰: `.bufferingChanged(true)` 후 ① 스피너 애니메이팅 ② `displayedPlayPauseImage == nil` ③ **`playPauseButton.isEnabled` 참** ④ `hitTest(play/pause 중심) === playPauseButton` ⑤ `renderedTransportControlsFrame`이 이전과 동일.
- `.bufferingChanged(true)` → `setControlsVisible(false)` → 스피너가 여전히 보임(`controlsContentAlpha == 0`인데도).
- auto-hide: 버퍼링 중 `hasScheduledAutoHide == false`, `.bufferingChanged(false)` 후 재무장. 버퍼링 시작이 숨은 컨트롤을 **표시하지 않음**.
- D-2 회귀 고정: `.timeControlStatusChanged(.waitingToPlay)` + `.bufferingChanged(true)` 후 `isShowingPauseIcon == true`이고, 탭이 `pause`를 보냄(가짜 관찰로 확인).
- `automaticallyWaits == false` 변형: `.timeControlStatusChanged(.paused)` + `.bufferingChanged(true)` → 동일 결과.
- `configuration.showsBufferingIndicator = false`면 스피너가 생성/표시되지 않고 글리프도 억제되지 않음.

### C-2w — skip UI + 누적 소비 (D-1 잔여)

**수정**: `View/ABPlayerControlsView.swift`, `StateMachine/ABControlsPresenter.swift`(읽기 전용 변화 없음), `Accessibility/`, `Resources/`
**신규**: `View/ABSeekFeedbackView.swift`

1. `.seekTargetChanged` 분기(§6.2). 앵커는 `nil → non-nil` 전이에서만 스냅샷.
2. `.durationAvailable` 소비 → `seekBar.isSeekEnabled` 재평가(현재는 `.periodicTime`/`.readyToPlay`를 기다린다).
3. 접근성 힌트 5종 부착. 기존 label 문자열은 불변.

**테스트**
- 앵커 규칙: `seekTargetChanged(t1)` → 배지 `+10s`; 정착 전 `seekTargetChanged(t2)` → `+20s`; `seekTargetChanged(nil)` → 배지 사라지고 앵커 폐기; 다시 `t3` → `+10s`(앵커 재스냅샷).
- 스크럽 세션 중 `seekTargetChanged` 수신 시 배지·렌더 모두 무시.
- 스킵 버튼 탭이 정착 전에 시크바 progress를 낙관적으로 이동시킴.
- VoiceOver 조정 2연타 후 표시 시간 == 프리젠터 계산값 == 배지 델타(라벨/커맨드 일치 고정).
- `.durationAvailable` 단독 수신으로 시크바가 활성화됨.

### C-3w — 더블탭 시크 + passthrough + 햅틱 (D-4)

**수정**: `View/ABPlayerControlsView.swift`, `Model/ABPlayerControlsConfiguration.swift`
**신규**: `Layout/ABDoubleTapSeekZone.swift`

1. `ABDoubleTapSeekZone` 순수 함수(§2.1).
2. `doubleTapRecognizer`는 `configuration.doubleTapSeek != .disabled`일 때만 생성·부착하고, 그때만 `backgroundTapRecognizer.require(toFail: doubleTapRecognizer)`를 건다. `.disabled`로 되돌아가면 제거하고 요구 관계도 해제한다.
3. 핸들러: VoiceOver 가드(§2.6) → 대역 판정 → RTL 보정 → `presenter.handle(.skipTapped(±skipInterval))` **재사용**(스킵 버튼과 완전히 같은 경로) → 햅틱 → `handleVisibility(.controlInteracted)` → `observerRegistry.broadcast(.skipTapped(by:))`.
4. `hitTest`에 패스스루 마지막 한 줄(§3.2).

**테스트**
- `ABDoubleTapSeekZone` 표: `edgeFraction` 0.1/0.3/0.5, `x` 경계값, `width == 0`, 클램프 범위 밖 입력.
- `.disabled`(기본)에서 더블탭 인식기가 **존재하지 않고** `backgroundTapRecognizer`에 실패 요구가 걸려 있지 않음(단일 탭 지연 부재의 기계적 증거).
- 좌/우/중앙 더블탭 → 각각 `-interval`/`+interval`/무동작. `ABControlsEvent.skipTapped` 방송 확인.
- RTL 트레잇에서 좌우가 뒤집힘.
- VoiceOver 실행 중 더블탭이 무동작.
- 햅틱 시임이 정확히 1회 호출되고, `providesHapticFeedback = false`면 0회.
- 패스스루 매트릭스 3케이스 × (컨트롤 표시/숨김) × (컨트롤 위/빈 영역):
  - `.never` + 숨김 + 빈 영역 → `hitTest === view` (**기존 `interactiveControlHitTesting` 단언과 동일**)
  - `.whenControlsHidden` + 숨김 + 빈 영역 → `nil`
  - `.whenControlsHidden` + 표시 + 빈 영역 → `view`
  - `.always` + 표시 + **컨트롤 위** → 그 컨트롤 (패스스루가 우선순위를 이기지 못함)
  - `.always` + 액세서리 위(시크바와 겹침) → 액세서리

### C-4w — 리플레이 (D-5)

**수정**: `StateMachine/ABControlsPresenter.swift`, `View/ABPlayerControlsView.swift`

§6.1 그대로. `.playedToEnd`/`.seekCompleted`의 반환 effect 배열은 건드리지 않는다.

**테스트**
- `.playedToEnd` 후 play 탭 → `.send(.restartFromStart)` 1개(승격 불필요 시).
- 비-current + 승격 허용 + 종료 상태 → `[.send(.promoteToCurrent), .send(.restartFromStart)]`.
- 뷰 레벨: 실제 `ABPlayer`로 `.playedToEnd` 주입 후 탭 → `ABWaitUntil`로 `player.currentTime` 이 0 근처로 이동하고 `isPlaying`.
- 플래그 해제: `.seekCompleted` / `.sourceChanged` / `.itemDetached` / `.timeControlStatusChanged(.playing)` 각각 이후의 탭이 평범한 `.send(.play)`가 됨.
- `.playedToEnd` 반환 effect가 여전히 1개(`ABControlsPresenterTests.swift:149`와 같은 형태의 신규 단언).

### C-5w — 로케일·문자열 (D-6, D-11)

**수정**: `View/ABPlayerControlsView.swift`, `Model/ABControlsTimeLabelFormatter.swift`, `Model/ABPlayerControlsConfiguration.swift`, `Resources/{en,ko}.lproj/Localizable.strings`
**신규**: `Model/ABRateFormatter.swift`

§6.3, §6.4 그대로.

**테스트**
- `ABRateFormatter` 표: `en_US`/`de_DE`/`fr_FR`/`ko_KR` × `[0.5, 1, 1.25, 1.5, 2, 4]` → `"0.5"`/`"0,5"` 등.
- `.custom` 포맷이 `style.rateLabelStyle`의 템플릿을 무시하고 통째로 쓰임.
- `.custom` 설정이 `configuration != copy`를 만들고, 반복 재대입이 `UIMenu`를 재생성하지 않음(`repeatedCustomTimeFormatUpdatesDoNotRebuildTheRateMenu`와 같은 형태).
- 메뉴 항목 타이틀 == 버튼 타이틀의 포맷 경로(문자열 비교).
- `controls.liveMarker`가 en/ko 모두 존재하고 en == `"LIVE"`.
- `timeLabelSeparator` 기본값에서 라벨 문자열이 현행과 바이트 동일.
- 힌트 5종이 en/ko 모두 비어 있지 않음.

### C-6w — 레이아웃 슬롯 (D-7)

**수정**: `View/ABPlayerControlsView.swift`, `Model/ABPlayerControlsConfiguration.swift`
**신규**: `Model/ABControlsSlot.swift`

§4 그대로.

**테스트**
- **빈 슬롯 불변성**: 슬롯 API를 도입한 뒤에도 `ABControlsLayoutTests`의 리터럴(`-27.96142578125`, `-28.46142578125`)과 `releaseLayoutGeometry`의 10pt 간격이 그대로(기존 테스트 무수정 통과가 곧 증명).
- `accessoryViews` ↔ `accessoryViews(in: .bottomTrailing)` 동치(양방향 대입 후 상호 관찰).
- 슬롯별 배치: `.topTrailing` 뷰의 프레임이 `layoutMarginsGuide` 상단·후행에 접함; `.transportTrailing` 추가 후에도 `playPauseButton.center.x == controlsContentView.center.x`(중앙 이탈 없음 — 이 결정의 핵심 단언).
- hitTest 우선순위 매트릭스: 세 슬롯 각각의 뷰가 시크바와 겹치도록 배치한 뒤 셋 다 시크바를 이김.
- `showsPlayPauseButton = false` → 버튼 숨김이 `updatePlaybackIcon()` 이후에도 유지되고, `.bufferingChanged(true)`가 그것을 되살리지 않음.
- `showsSeekBar = false` → 시크바 숨김, hitTest가 시크바를 반환하지 않음, 하단 행이 위로 붙음.

### C-7w — 구조 정리 (D-8, D-9, D-10)

**수정**: `View/ABPlayerControlsView.swift`, `View/ABSeekBar.swift`, `Model/ABPlayerControlsStyle.swift`, `Model/ABControlIcon.swift`, `StateMachine/ABControlsPresenter.swift`
**신규**: `Model/ABPlayerControlsStyleFacets.swift`

순서 권고: (1) facet 레지스트리 + 소진성 테스트, (2) 3개 diff 목록을 레지스트리 소비로 교체, (3) D-9 미러 2건 제거, (4) `Sendable` 부착(검증 우선, §5.2), (5) 프리셋 `@MainActor` 제거.

**테스트**
- **소진성**: `Mirror` 라벨 집합 == `facets.map(\.name)` 집합.
- impact 분류 회귀: 위 §5.1 표의 4개 그룹 각각에 대해 대표 프로퍼티 1개씩 변경 → `changeImpact`가 기대 집합과 일치.
- `styleLayoutInvalidationCount` 2건(`ABPlayerControlsLiveStyleTests.swift:24,40`) 무수정 통과.
- `ABSeekBar`의 색상 전용 변경이 `setNeedsLayout`을 유발하지 않음.
- D-9: `isShowingPauseIcon`이 `presenter.showsPauseIcon`을 반영하고, 뷰에 별도 `isPlayingState`/`currentPlaybackTime` 저장 프로퍼티가 남아 있지 않음(컴파일이 증명).
- D-10: `ABPlayerControlsStyle`을 `Task.detached`로 넘겨 읽는 컴파일 테스트(`Sendable` 실증). 5개 타입 각각.

---

## 5. 리스크와 무회귀 가드

### 5.1 절대 불변식 (위반 시 C-8 게이트 REQUEST-CHANGES)

| # | 불변식 | 근거 |
|---|---|---|
| I-C1 | hitTest 우선순위는 **4개 transport 버튼 → 슬롯 3종 → `seekBar`** 순이며, 패스스루는 `super.hitTest`가 `self`를 돌려준 경우에만 개입한다 | `ABPlayerControlsView.swift:176-183`, `ABPlayerControlsViewTests.swift:507-612,634-669`, `CustomizingControls.md:18,77` |
| I-C2 | `touchPassthrough`의 기본값 `.never`에서, 컨트롤이 숨겨진 상태의 오버레이 중앙 히트테스트는 **`self`를 돌려준다** | `ABPlayerControlsViewTests.swift:664-668` |
| I-C3 | 모든 슬롯이 비어 있으면 오버레이 기하는 현행과 **수치적으로 동일**하다 | `ABControlsLayoutTests.swift:16,24`(고정 리터럴), `ABPlayerControlsViewTests.swift:379-462` |
| I-C4 | 버퍼링 중에도 play/pause 버튼은 `isEnabled == true`이고 히트테스트로 도달 가능하며 `accessibilityLabel`이 "일시 정지"다 | 결정 1의 (a). `alpha`/`isHidden`을 쓰면 깨진다 |
| I-C5 | `ABControlsPresenter.isPlaying`의 의미는 불변 — `.timeControlStatusChanged(.playing)`만 참으로 만든다. 새 축은 `showsPauseIcon` | `ABControlsPresenterTests.swift:56,66,144,190`(MJ-3) |
| I-C6 | play/pause 탭의 분기는 **라이브 값**(`player.isPlaying \|\| player.isBuffering`)을 쓰고 프리젠터 캐시를 쓰지 않는다 | MJ-3, `ABControlsPresenter.swift:113-131` |
| I-C7 | 스타일 변경의 무효화 분류(paintOnly / iconRebuild / controlsLayout / seekBarLayout)는 §5.1 표에서 **한 항목도 이동하지 않는다** | `ABPlayerControlsLiveStyleTests.swift:24,40` |
| I-C8 | 스크럽 세션의 `scrubbingPlayer` 고정과 `endScrubbing` 이후 세션 동일성 검사는 손대지 않는다 | `ABPlayerControlsView.swift:776-813`, `missingDurationStillEndsScrubbing` |
| I-C9 | Controls는 시크 델타를 합산하지 않는다. 표시는 `pendingSeekTime - anchor`이며 anchor는 `nil→non-nil` 1회 스냅샷 | core §3.5 |
| I-C10 | 더블탭 인식기와 `require(toFail:)`는 `doubleTapSeek != .disabled`일 때만 존재한다 | §2.2. 기본 구성의 단일 탭 지연 0 |
| I-C11 | `@unchecked Sendable` / `MainActor.assumeIsolated` 0건 | `DESIGN-OPEN-QUESTIONS.md` Q13 |
| I-C12 | 신규 오버레이 뷰(스피너·배지)는 `isUserInteractionEnabled == false`이고 `priorityControls`에 포함되지 않는다 | I-C1 보호 |

### 5.2 수정 금지 테스트 파일

- `Tests/ABPlayerKitControlsTests/ABControlsPresenterTests.swift` — 28건 전부. MJ-3와 effect 배열 동등성이 이 트랙 설계의 검증 조건이다
- `Tests/ABPlayerKitControlsTests/ABControlsLayoutTests.swift` — I-C3의 기계적 증거
- `Tests/ABPlayerKitControlsTests/ABPlayerControlsLiveStyleTests.swift` — I-C7
- `Tests/ABPlayerKitControlsTests/ABControlsVisibilityMachineTests.swift` — 기존 15건(신규 `isBuffering` 테스트는 파일 말미 추가만)
- `Tests/ABPlayerKitControlsTests/ABPlayerControlsInitializerAmbiguityTests.swift` — 트랙 S 소유
- `Tests/ABPlayerKitTests/` 전체 — 트랙 C는 코어 타깃을 건드리지 않는다

### 5.3 허용된 테스트 변경 (사전 승인, 그 외에는 C-8 문의)

| 파일:라인 | 변경 | WP |
|---|---|---|
| `ABPlayerControlsViewTests.swift:342` | `ABTimeFormatter.liveMarker` → Controls 로컬라이즈 마커 접근자. en 값이 `"LIVE"`로 동일하므로 **결과는 불변**이며, 비교 대상만 정직해진다 | C-5w |
| `ABControlsTimeLabelFormatterTests.swift:84` | 동일 | C-5w |
| `ABControlsPlayPauseReentrancyCharacterizationTests.swift:37-42` | `RecordedEvent.kind(of:)` 기록에서 버퍼링 미러 유래 이벤트를 제외. 이 스위트가 고정하는 것은 **탭→커맨드 순서**이지 엔진의 미러 트래픽이 아니다 | C-1w |

세 번째 항목은 **트랙 A 병합의 부수효과**이며 §6-1의 전달 사항과 짝을 이룬다.

### 5.4 리스크 등급

| 리스크 | 등급 | 완화 |
|---|---|---|
| A 병합만으로 `ABControlsPlayPauseReentrancyCharacterizationTests`가 붉어짐(§6-1) | **높음** | A-8 이전에 통지. 수정 권한은 C에 있다(코어 §5.2가 A의 Controls 테스트 수정을 금지) |
| 슬롯 도입이 기하를 흔들어 리터럴 고정 테스트 파괴 | **높음** | §4.2의 "제약 비참여" 설계 + I-C3. 신규 스택은 `rootStack`/`buttonStack` 제약에 일절 참여하지 않는다 |
| 패스스루가 hitTest 우선순위 회귀 유발 | 중 | §3.2의 `hit === self` 게이트 + 5×2×2 매트릭스 테스트 |
| 스피너/배지 뷰가 히트테스트에 끼어듦 | 중 | I-C12 + 각 WP의 hitTest 단언 |
| D-10 `Sendable`이 CI 툴체인(Xcode 16.4)에서 실패 | 중 | §5.2의 검증 우선 절차. 실패는 컴파일 에러로 즉시 드러나고 이월 경로가 준비돼 있다 |
| `NumberFormatter` 로케일이 CI 러너 로케일에 따라 기존 배속 단언(`"1.5×"`)을 깸 | 낮음 | `ABRateFormatter`가 로케일을 주입받고, 뷰만 `.autoupdatingCurrent`를 쓴다. 러너는 en_US이며 기존 테스트도 이미 en 로컬라이제이션을 전제한다 |
| 더블탭이 스크럽 시작과 경합 | 낮음 | 인식기는 오버레이 자신에만 부착. 시크바 위 터치는 hitTest 우선순위로 `seekBar`가 가져간다 |
| 신규 localized 키 누락으로 DocC/런타임 폴백 문자열 노출 | 낮음 | `ABControlsLocalization.string`이 키 자체를 폴백으로 돌려주므로 테스트에서 즉시 드러난다 |
| C 최대 diff로 인한 Wave 2 병합 충돌 | 낮음 | ROADMAP §3 병합 순서 F → G → C에서 C가 마지막. 파일 경계는 §0 |

---

## 6. 타 트랙 전달 사항

1. **트랙 A (A-8 게이트) — 즉시 확인 요망.** `Tests/ABPlayerKitControlsTests/ABControlsPlayPauseReentrancyCharacterizationTests.swift:63-68`은 한 번의 play 탭이 만드는 **이벤트 시퀀스 전체를 배열 `==`로 고정**한다. A-6w가 `play()` 직후 동기적으로 `refreshPlaybackMirrors()`를 돌리면, 실제 `AVPlayerItem`이 아직 `isPlaybackLikelyToKeepUp == false`인 그 시점에 `bufferingChanged(true)`가 **동기 방송**되어 이 배열에 새 원소가 끼어든다 → 트랙 A 단독 병합으로 Controls 스위트가 붉어진다. 코어 §5.2는 트랙 A의 Controls 테스트 수정을 금지하므로 선택지는 둘이다: (a) A-8이 이 한 파일에 한해 예외를 자기 화이트리스트에 추가, (b) A는 그대로 두고 C-1w가 §5.3의 허용 변경으로 처리 — 단 그러려면 **A 병합 시점에 CI가 붉어도 통과시키는 결정**이 필요하다. C-0의 권고는 (a)다(Wave 경계에서 그린을 유지하는 편이 안전).
2. **트랙 A** — `.itemDetached`/`sourceChanged` 이후 `pendingSeekTime`이 `nil`로 리셋되는지 확인 요망. C의 시크 배지는 `seekTargetChanged(nil)`을 소멸 신호로 쓴다. 코어 결정 4는 `resetSeeking()`에서 `nil`이 된다고 했으나, 소스 교체 경로가 `resetSeeking()`을 반드시 지나는지가 명시돼 있지 않다. 지나지 않는다면 배지가 남는다.
3. **트랙 S (Wave 1, 선행)** — S §9-3의 요청 3건 **전부 수용**: ① `ABPlayerControlsView.style`/`configuration`은 비옵셔널 유지(§3의 확정 표면에 반영), ② 본 라운드가 추가하는 스타일/설정 프로퍼티는 S의 Environment 표면에 자동 반영되므로 S 측 추가 작업 없음, ③ D-10이 성립하면 `EnvironmentKey.defaultValue`를 computed `static var`에서 `static let`으로 단순화할 수 있으나 **C는 그 파일을 수정하지 않는다**(파일 경계) — Wave 3 H-2w 또는 후속 라운드의 선택 항목으로 등록 요청.
4. **트랙 S** — C는 `Sources/ABPlayerKitControls/SwiftUI/` 4파일을 일절 수정하지 않는다. 반대로 S도 `View/`·`Model/`·`StateMachine/`·`Layout/`·`Accessibility/`·`Resources/`를 수정하지 않기를 요청한다(현 S 설계는 이미 그렇다). 교집합 0.
5. **Wave 3 / 리포 인프라** — (a) D-10 검증 실패 시 그 사유와 툴체인 버전을 `RESULT-round6-controls.md`에 남긴다. (b) `swift-tools-version` 6.1 상향(S §9-5)은 본 트랙과 무관하나, 성사되면 `ABControlsObserverRegistry`/`ABPeriodicIntervalLease`의 `deinit` 홉(`ABPeriodicIntervalLease.swift:29-33`)도 함께 정리 가능 — 별도 항목으로 등록 요청.
6. **Wave 3 H-2w** — README/DocC 최종화 시 `CustomizingControls.md`에 본 라운드가 추가하는 4개 절(버퍼링 인디케이터, 더블탭 시크, 패스스루 상호작용 표 §3.3, 레이아웃 슬롯)이 들어간다. 더블탭은 기본 꺼짐이므로 **"켜는 방법"을 Quick Start급으로 노출**할 것을 권고한다(제품 목표 4번의 가시성).
7. **코어 `ABTimeFormatter.liveMarker`** — Controls가 가시 라벨로 쓰던 것을 자체 로컬라이즈 키로 옮기므로, 코어의 그 심볼은 이번 라운드에 사용처가 줄어든다. **제거·deprecated 금지**(공개 API, POLICY). Wave 3에서 DocC 문구만 "축약 마커의 로케일 독립 기본값"으로 다듬을 것을 권고.

---

## 7. 완료 정의 (C-8 게이트 체크리스트)

- [ ] 기존 Controls 테스트 184건 중 §5.3의 3줄을 제외한 전부가 **무수정 통과**
- [ ] I-C1 ~ I-C12 각각에 대응 테스트 존재 (특히 I-C2·I-C3·I-C4·I-C7·I-C10)
- [ ] hitTest 우선순위 매트릭스(4버튼 × 슬롯 3종 × 시크바 × 패스스루 3케이스) 통과
- [ ] `Sources/ABPlayerKit/` diff **0줄**, `Sources/ABPlayerKitControls/SwiftUI/` diff **0줄**
- [ ] 신규 공개 심볼 전부 DocC 큐레이션 + `docbuild` 경고 0
- [ ] 신규 localized 키가 en/ko 양쪽에 존재
- [ ] 스타일 facet 소진성 테스트 존재 및 통과 (`Mirror` 라벨 집합 일치)
- [ ] `@unchecked Sendable` / `MainActor.assumeIsolated` / `@available(*, deprecated)` **신규 0건**
- [ ] Swift 6 zero-warning, 신규 주석에 리뷰 ID 인용 0건
- [ ] CHANGELOG `### Added`(슬롯·패스스루·더블탭·버퍼링 인디케이터·`shows*`·`rateLabelFormat`·`timeLabelSeparator`·햅틱) + `### Changed`(Sendable, 프리셋 격리 제거, LIVE 라벨의 로케일화) + 마이그레이션 노트
- [ ] D-10 이월 시 그 사유가 `RESULT-round6-controls.md`에 기록됨
