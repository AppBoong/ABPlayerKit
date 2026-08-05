# ROADMAP: 라운드4 — 라운드3 스코프 제외 2건의 실행 설계

라운드3(`BRIEF-fix-round3-phase4.md` "스코프 제외")에서 의도적으로 미룬 두 항목의 실행 로드맵이다.

- **(A)** `ABPlayerControlsView` 분해 — 현재 **1109줄**
- **(B)** `accessoryViews: [UIView]` SwiftUI API 정리 — `@ViewBuilder` 대체 + deprecation

**이 문서는 설계만이다. 코드 변경은 포함하지 않는다.** 각 WP는 구현 에이전트에게 그대로 넘길 수 있는 수준으로 작성했다.

## 현재 기준선 (실측)

| 항목 | 값 |
|---|---|
| `ABPlayerControlsView.swift` | 1109줄 |
| `ABPlayerKitControls` 타깃 전체 | 3725줄 (18파일) |
| 전체 테스트 | 373개 / 0 실패 / 0 경고 |
| `ABPlayerKitControlsTests` | **110개 `@Test`** / 14파일 / 1834줄 |
| `ABPlayerControlsView`의 internal 테스트 훅 | **31개** (프로퍼티 6 + 계산 접근자 21 + 메서드 4) |
| CI 스킴 | `ABPlayerKit-Package`만 (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`) — 데모 앱은 CI 미포함 |

> 지시서의 "302+개 테스트"는 이전 시점 수치로 보인다. 현재 전체 373개, 그중 이 작업이 건드리는 컨트롤 타깃이 110개다. 아래 리스크 산정은 110개 기준이다.

## 설계 원칙 — 이미 성공한 선례를 복제한다

이 레포에는 **동일한 분해가 이미 한 번 성공한 사례**가 있다: `StateMachine/ABControlsVisibilityMachine.swift`(112줄).

```swift
struct ABControlsVisibilityMachine: Equatable {
    enum Input: Equatable { case attached(initial:), tapped, scrubBegan, … }
    enum Effect: Equatable { case show, hide, scheduleAutoHide(after:), notifyVisibility(Bool) }
    mutating func handle(_ input: Input) -> [Effect]
}
```

- 순수 값 타입, `UIKit` 의존 없음, 뷰를 전혀 모름
- 뷰는 `Effect`를 **해석만** 한다 (`applyVisibilityEffects`, ABPlayerControlsView.swift:991)
- 전용 테스트 15개가 `UIView` 인스턴스 없이 돈다 (`ABControlsVisibilityMachineTests.swift`)

**라운드4의 세 추출물은 전부 이 형태를 그대로 따른다.** 새 아키텍처를 발명하지 않는다 — 이것이 "302개 테스트를 깨지 않는다"의 1차 보증이다.

---

# (A) ABPlayerControlsView 분해

## A-0. 목표 형태

| 신규 타입 | 성격 | 원본 위치 | 예상 |
|---|---|---|---|
| `Layout/ABControlsLayout.swift` | 순수 기하 계산 (`style` + `UITraitCollection` → CGFloat/UIFont) | :199–337 | ~150줄 |
| `Model/ABControlsTimeLabelFormatter.swift` | 순수 문자열 포매팅 | :691–768, :959–973 | ~110줄 |
| `StateMachine/ABControlsPresenter.swift` | Input/Effect 상태 기계 (플레이어 상태 ↔ 뷰 상태) | :470–510, :606–689, :770–821, :848–957 | ~260줄 |
| **`ABPlayerControlsView.swift` 잔존** | 뷰 계층 구축 + Effect 해석 + 제스처/히트테스트 | — | **~620줄** |

**정직한 규모 예측**: 프로덕션 총 LOC는 3725 → **약 4000줄로 증가한다**(타입 경계·문서 주석·생성자 비용). 줄어드는 것은 *한 파일의* 복잡도(1109 → ~620, **−44%**)와 뷰 인스턴스 없이 검증 가능한 로직의 비율이다. "LOC를 줄이는 작업"으로 보고하면 안 된다.

## A-1. WP 목록

### WP-A1 — 죽은 훅 제거 + 훅 예산 기준선 (리스크 없음)

**선행**: 없음. 단독 커밋.

1. `renderedBackgroundContentView`(ABPlayerControlsView.swift:88) 삭제 — 전 테스트 타깃에서 **사용 0회**다(`ABControlsBackgroundViewTests`는 `ABControlsBackgroundView.renderedContentView`를 직접 쓴다). 삭제 전 `grep -rn "renderedBackgroundContentView" Tests Sources Examples`로 0건을 재확인할 것.
2. 나머지 30개 훅에 대해 동일한 사용 횟수 census를 수행하고, 결과를 `docs/briefs/ROADMAP-round4-hook-census.md`로 남긴다. 이후 WP의 성과 측정 기준선이 된다.
3. **다른 훅은 이 WP에서 건드리지 말 것.** 삭제는 대응 커버리지가 다른 곳으로 옮겨간 뒤에만 가능하다(WP-A5).

**수용 기준**: 전체 373개 테스트 통과, `ABPlayerControlsView.swift` 1줄 감소, census 문서 존재.

---

### WP-A2 — `ABControlsLayout` 추출 (순수 기하)

**선행**: WP-A1. **가장 먼저 하는 실질 추출** — 세 후보 중 유일하게 플레이어 상태·가변 상태·부작용이 전혀 없다.

**대상 (ABPlayerControlsView.swift:199–337, 약 140줄)**

| 멤버 | 현재 위치 | 순수성 |
|---|---|---|
| `seekBarTouchRowHeight` (static let 44) | :202 | 상수 |
| `rootStackSpacing(for:)` | :215 | `style` + trait만 |
| `bottomRowVisibleContentSlack(for:)` | :267 | 동일 |
| `rateButtonBottomRowSlack(for:rowHeight:)` | :281 | `style`만 |
| `frameTopToInkTop(font:centeredIn:)` (static) | :312 | 완전 순수 |
| `scaledTimeLabelFont(for:compatibleWith:)` | :335 | `style` + trait |

**목표 시그니처**

```swift
/// 순수 기하 계산. `ABControlsVisibilityMachine`과 같은 이유로 값 타입이며
/// 뷰를 모른다 — 유일한 입력이 style과 trait collection이므로
/// UIView 인스턴스 없이 전량 단위 테스트가 가능하다.
struct ABControlsLayout {
    let style: ABPlayerControlsStyle
    let traitCollection: UITraitCollection

    static let seekBarTouchRowHeight: CGFloat = 44

    var scaledTimeLabelFont: UIFont { … }
    var rootStackSpacing: CGFloat { … }
    var bottomRowVisibleContentSlack: CGFloat { … }
    func timeLabelMinimumWidth(using font: UIFont) -> CGFloat { … }   // :596에서 함께 이동

    private func rateButtonBottomRowSlack(rowHeight: CGFloat) -> CGFloat { … }
    private static func frameTopToInkTop(font: UIFont, centeredIn: CGFloat) -> CGFloat { … }
}
```

**뷰 쪽 호출 규약 — 반드시 지킬 것**

```swift
// ✅ 호출 시점마다 새로 만든다
private var layout: ABControlsLayout {
    ABControlsLayout(style: style, traitCollection: traitCollection)
}
// ❌ 저장 프로퍼티로 캐시하지 말 것 (아래 R-A2 참조)
```

**절대 규칙: 이 WP는 순수 이동이다.** 상수 하나, 식 하나도 바꾸지 않는다. `frameTopToInkTop`의 계산 방식은 고정소수점·비율 보정을 둘 다 시도해 폐기한 이력이 있고(주석 :300–311, `docs/IMPL-v0.2-RESULT.md`), 이 이력이 붙은 주석 블록도 **원문 그대로 옮긴다**. 리팩터링·"정리"·주석 축약 전부 금지.

**절차 (순서 고정)**

1. **먼저 characterization 테스트를 추가한다** (별도 선행 커밋): 현재 `ABPlayerControlsView`에서 `.default`/`.minimal` 스타일 × 3개 trait(기본 / `.accessibilityExtraExtraExtraLarge` / `.extraSmall`)에 대해 `rootStackSpacing`·`scaledTimeLabelFont.pointSize` 실측값을 리터럴로 고정한다. 이 테스트는 **이동 전후 모두 통과해야 한다** — 이동이 수치적으로 중립임을 기계적으로 증명하는 유일한 장치다.
2. 타입을 신설하고 본문을 옮긴다.
3. 호출부 4곳(`registerForSpacingTraitChanges` :236–241, `applyStyle` :512, `applyConfiguration` :552, `updateTimeLabelWidthConstraints` :596)을 `layout.` 경유로 교체한다.
4. 1번 테스트를 `ABControlsLayoutTests`로 복제해 순수 타입에 직접 걸고, 뷰 쪽 원본도 남긴다(양쪽이 같은 값을 내는 것이 배선 검증이다).

**신규 테스트** `Tests/ABPlayerKitControlsTests/ABControlsLayoutTests.swift`, 8–10개:
`frameTopToInkTop` 경계(컨테이너 < 폰트 lineHeight → 음수 클램프), `rootStackSpacing` 음수 허용(:211 "routinely goes negative"), `rateButtonBottomRowSlack`의 `.text`/`.icon` 분기, AX 사이즈에서 `rowHeight`가 rateButton 높이를 넘어서는 :274 분기.

**제거 가능해지는 훅**: `scaledTimeLabelFont`(사용 1회).
**반드시 남길 훅**: `renderedSeekBarVisibleTrackFrame`, `renderedBottomRowFrame`, `renderedTimeLabelFrame`, `renderedRateButtonVisibleContentFrame` — 계산된 값이 *실제 뷰 계층에 반영되는지*를 확인하는 배선 테스트다. 순수 테스트가 이것을 대체하지 못한다.

**규모**: 뷰 −140줄, 신규 +150줄, 호출부 수정 ~25줄, 신규 테스트 +120줄.

---

### WP-A3 — `ABControlsTimeLabelFormatter` 추출 (순수 포매팅)

**선행**: WP-A2 (독립적이나 파일 충돌 회피 위해 순차).

**대상**: `updateTimeLabels`(:691–733)의 문자열 조립부, `formattedTime`(:735), `fixedHoursString`(:752), `timePlaceholder`(:761), `accessibilityTimelineValue`(:959)의 문자열 부분.

**목표 시그니처**

```swift
struct ABControlsTimeLabelFormatter {
    let timeFormat: ABPlayerControlsConfiguration.TimeTextFormat
    let timeLabelLayout: ABPlayerControlsConfiguration.TimeLabelLayout

    /// 라운드3 WP12에서 확정한 `.custom` 계약이 여기 산다:
    /// `.custom`은 elapsed+duration을 한 번에 받아 라벨 전체를 만들며,
    /// `timeLabelLayout` 조합을 적용하지 않는다.
    func label(elapsedSeconds: TimeInterval?, durationSeconds: TimeInterval?) -> String
    func accessibilityValue(elapsedSeconds: TimeInterval?, durationSeconds: TimeInterval?) -> String
}
```

이동 후 `updateTimeLabels`는 아래로 줄어든다:

```swift
private func updateTimeLabels(currentTime: CMTime, duration: CMTime?) {
    elapsedLabel.text = timeLabelFormatter.label(
        elapsedSeconds: currentTime.isNumeric ? CMTimeGetSeconds(currentTime) : nil,
        durationSeconds: duration.flatMap { $0.isNumeric ? CMTimeGetSeconds($0) : nil }
    )
}
```

**부수 효과로 해소되는 라운드3 잔여 항목** (`REVIEW-round3-final.md`):
- **N14** — `formattedTime`의 `.custom` 분기가 시간 라벨 경로에서 도달 불가한 죽은 코드로 남아 있는 문제. 포매터로 옮기면서 `.custom`을 `label(…)` 진입점에서 한 번만 분기하면 자연 소멸한다.
- `formattedTime`의 stale doc 주석(:733–735, "`.custom`에 referenceDuration을 넘겨 필드 폭을 맞춘다")도 이 WP에서 정정한다.

**주의**: WP12에서 확정한 계약(`.custom`은 조합하지 않음)을 **바꾸지 말 것.** 이 WP는 계약을 *옮기는* 작업이지 재검토가 아니다. `customTimeFormatIgnoresTimeLabelLayout` 테스트가 계약을 고정하고 있다.

**신규 테스트** `ABControlsTimeLabelFormatterTests.swift`, 12개 내외:
`.automatic`/`.fixedHours`/`.custom` × `.elapsedOnly`/`.elapsedAndTotal`/`.elapsedAndRemaining` 조합, `duration == nil`(라이브) 플레이스홀더, 비유한 elapsed, 음수 remaining 클램프(:721 `max(0,…)`).

**훅 이동**: `displayedElapsedText`(현 8회)를 통합 검증 2회로 축소하고 나머지 6개 케이스를 포매터 단위 테스트로 이관.

**규모**: 뷰 −80줄, 신규 +110줄, 신규 테스트 +140줄.

---

### WP-A4 — `ABControlsPresenter` 추출 (상태 기계) ⚠️ 최대 리스크

**선행**: WP-A2, WP-A3. **두 개의 하위 커밋으로 나눈다.**

`ABControlsVisibilityMachine`과 **동일한 형태**를 강제한다. 프레젠터는 `ABPlayer`를 보유하지 않고, 플레이어 호출을 `Effect`로 되돌려 뷰가 실행한다 — 이것이 순수성과 테스트 가능성의 핵심이다.

```swift
struct ABControlsPresenter: Equatable {
    enum Input: Equatable {
        case attached(grade: ABPlaybackGrade, promotesToCurrentOnPlay: Bool)
        case detached
        case playerEvent(ABPlayerEvent)
        case playPauseTapped
        case skipTapped(TimeInterval)
        case rateSelected(Float)
        case scrubBegan
        case scrubChanged(progress: Double)
        case scrubEnded(progress: Double)
        case accessibilityAdjusted(direction: Int)
    }

    enum PlayerCommand: Equatable {
        case play, pause, promoteToCurrent
        case seek(to: CMTime), skip(by: TimeInterval), setRate(Float)
        case beginScrubbing, scrub(to: CMTime), endScrubbing
    }

    enum Effect: Equatable {
        case setPlaybackIcon(isPlaying: Bool)
        case setRateTitle(rate: Float)
        case renderTimeline(ABPlaybackTime)
        case resetTimeline
        case setEnabled(Bool, allowsPromotionTap: Bool)
        case bouncePlayPause
        case emit(ABControlsEvent)
        case send(PlayerCommand)
    }

    private(set) var isPlaying = false
    private(set) var currentPlaybackTime = ABPlaybackTime.zero
    private(set) var rate: Float = 1.0

    mutating func handle(_ input: Input) -> [Effect]
}
```

#### WP-A4a — 상태 매핑만 (읽기 전용 방향)

`handlePlayerEvent`(:470–510) → `.playerEvent` Input, 그리고 `render`(:681) / `updatePlaybackIcon`(:606) / `updateRate`(:656) / `resetTimeline`(:770) / `setControlsEnabled`(:793) / `canPromoteToCurrentOnPlayTap`(:784) → `Effect`.

플레이어를 호출하는 경로(`togglePlayback` 등)는 **이 커밋에서 손대지 않는다.** 방향이 하나뿐이라 되돌리기 쉽다.

#### WP-A4b — 명령 방출 방향

`togglePlayback`(:805) / `skip(by:)`(:848) / `selectRate`(:891) / `scrubBegan/Changed/Ended`(:899–936) / `adjustTimelineForAccessibility`(:938) → `.send(PlayerCommand)` Effect.

**⚠️ 순서 보존이 이 WP의 전부다.** 현재 이 경로들은 플레이어를 **동기 호출**하고, 그 호출이 `ABPlayerEvent` 브로드캐스트를 통해 `handlePlayerEvent`로 **재진입**한다(예: `togglePlayback` → `player.play()` → `.timeControlStatusChanged` → 아이콘 갱신). Effect 리스트 간접화는 이 인터리빙을 바꿀 수 있다.

**필수 선행 작업**: WP-A4b 착수 전, 재진입 순서를 고정하는 characterization 테스트를 별도 커밋으로 추가한다 — 재생 탭 → 관측된 `ABControlsEvent` + `ABPlayerEvent` **시퀀스 전체**를 배열로 단언. 이 테스트가 없으면 WP-A4b를 시작하지 말 것.

**신규 테스트** `ABControlsPresenterTests.swift`, 18–22개. `ABControlsVisibilityMachineTests`의 구조(Input 넣고 Effect 배열 단언)를 그대로 따른다.

**규모**: 뷰 −250줄, 신규 +260줄, 신규 테스트 +260줄.

---

### WP-A5 — 훅 예산 정산

**선행**: WP-A2~A4 전부.

WP-A1의 census를 재실행하고, 커버리지가 순수 타입으로 이관된 훅만 삭제한다.

**목표: 31개 → 18개 내외.**

| 분류 | 훅 | 처리 |
|---|---|---|
| 구동 시임 (삭제 불가) | `seekBar`(68회), `rateButton`(28), `playPauseButton`(24), `handlePlayerEvent`(23), `skipForward/BackwardButton`(각 11) | **유지** — 거의 모든 테스트의 입력 경로다 |
| 배선 검증 (삭제 불가) | `rendered*Frame` 6종 | **유지** — 순수 테스트가 대체 못 하는 "계산값이 실제 계층에 반영되는가" |
| 이관 후 삭제 대상 | `scaledTimeLabelFont`, `hasFixedWidthTimeLabels`, `fixedTimeLabelMinimumWidth`, `isShowingPauseIcon`, `backgroundContentAlpha`, `lastVisibilityAnimationDuration` | A2/A4 완료 후 삭제 |
| 축소 대상 | `displayedElapsedText` 8→2, `displayedRateText` 4→2, `controlsAreEnabled` 7→3 | 나머지는 순수 테스트로 |

**"테스트 훅 제거"를 문자 그대로 수행하지 말 것.** 상위 6개 훅이 전체 사용량의 60%를 차지하며 이들은 설계상 필요한 시임이다. 이 WP의 성과 지표는 "훅 개수"가 아니라 **"뷰 인스턴스 없이 도는 테스트 비율"**(현재 110개 중 27개 → 목표 70개 이상)이다.

## A-2. 리스크 표

| ID | 리스크 | 영향 | 확률 | 완화책 |
|---|---|---|---|---|
| **R-A1** | 레이아웃 수치가 미세하게 달라지는데 단위 테스트가 못 잡음 — `frameTopToInkTop`은 온디바이스 튜닝 이력이 있고 ±1.5pt 오차를 의도적으로 허용한다(:307–311) | 높음 (AX 폰트에서 라벨이 트랙과 충돌 — 이 함수가 존재하는 이유 그 자체) | 중 | WP-A2 절차 1번의 characterization 테스트를 **이동 전에** 커밋. 상수/식 변경 전면 금지. 리뷰어는 diff가 순수 이동인지만 확인 |
| **R-A2** | `ABControlsLayout`을 저장 프로퍼티로 캐시 → `registerForSpacingTraitChanges`(:235)가 죽고 Dynamic Type 변경이 레이아웃에 반영 안 됨 | 높음 (조용한 접근성 회귀, 시각 확인 없이 안 잡힘) | **높음** (가장 자연스러운 실수) | 호출 시점 생성 규약을 WP 지시에 명시. AX3 trait로 `rootStack.spacing` 변화를 단언하는 테스트 추가 |
| **R-A3** | WP-A4b에서 플레이어 재진입 순서가 바뀜 | 높음 (스크러빙/재생 토글 이벤트 순서 뒤바뀜) | 중 | 순서 characterization 테스트를 선행 커밋으로 강제. 없으면 착수 금지 |
| **R-A4** | 브랜치 장기화 → 대형 충돌 | 중 | 중 | WP당 1커밋, WP마다 `main` 리베이스. A4는 a/b로 분할 필수 |
| **R-A5** | 훅을 과하게 지워 커버리지 상실 | 중 | 중 | WP-A5의 4분류 표를 그대로 적용. 삭제 전 census 재실행 필수 |
| **R-A6** | 총 LOC 증가를 실패로 오독 | 낮음 | 높음 | 성과 지표를 "한 파일 줄 수"와 "뷰 없이 도는 테스트 비율"로 사전 합의 |
| **R-A7** | `updateTimeLabels`가 `elapsedLabel` 단일 라벨 전제로 동작 — 포매터 추출 시 이 전제를 깨고 라벨을 추가하면 :705 조기 반환 경로가 어긋남 | 낮음 | 낮음 | WP-A3은 라벨 개수를 바꾸지 않는다는 제약 명시 |

---

# (B) accessoryViews SwiftUI API 정리

## B-0. ⚠️ 선행 게이트 — Q6 재검토 (구현 착수 전 필수)

`docs/DESIGN-OPEN-QUESTIONS.md:129`:

> **Q6 오버레이 주입 방식 | A — UIKit `UIView` 오버레이만 지원. SwiftUI 소비자는 직접 `UIHostingController` 래핑. 원본이 겪은 호스팅 어긋남 위험을 라이브러리가 떠안지 않음 | 추천(C)과 다른 사용자 결정**

**(B)는 이 결정을 뒤집는 작업이다.** Q6은 추천안과 다른 *사용자의 명시적 결정*으로 기록돼 있고, 그 근거가 정확히 이 WP가 도입하려는 위험("호스팅 어긋남")이다.

**따라서 WP-B1 이전에 다음이 선행되어야 한다:**

1. `DESIGN-OPEN-QUESTIONS.md` Q6 행에 **Q6-A 개정 행**을 추가하고, 재결정 사유와 완화책(WP-B1의 부모 VC 부착 전략)을 기록한다.
2. **이 개정은 사용자가 결정한다.** 구현 에이전트가 임의로 진행해서는 안 된다.

Q6이 유지된다면 (B) 전체를 폐기하고, 대신 DocC에 "SwiftUI에서는 `UIHostingController`로 직접 감싸십시오" 레시피를 추가하는 축소 WP(B-alt)로 대체한다.

## B-1. 현재 API 표면

| 심볼 | 종류 | 처리 |
|---|---|---|
| `ABPlayerControlsView.accessoryViews: [UIView]` (:25–36) | UIKit public var | **유지, deprecate 금지** — UIKit 소비자에게 올바른 API다 |
| `ABPlayerControls.init(player:style:configuration:accessoryViews:onEvent:)` (:13–25) | SwiftUI | deprecate 대상 |
| `ABVideoPlayerWithControls.init(player:videoGravity:style:configuration:accessoryViews:)` (:14–26) | SwiftUI | deprecate 대상 |

**deprecation 폭발 반경 (실측)**

| 호출부 | CI 영향 |
|---|---|
| `ABVideoPlayerWithControls.swift:35` → `ABPlayerControls` | 🔴 **CI 즉시 실패** (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, ci.yml:44) |
| `Examples/…/PlaybackScreen.swift:21` | 🟡 CI 스킴 미포함이라 안 깨짐. 그래도 레퍼런스 예제이므로 이관 |
| `Tests/…/ABPlayerControlsViewTests.swift:82,84,86,560` | 🟢 UIKit `accessoryViews` 사용 — 영향 없음 |
| `CustomizingControls.md:18,77,80` | 🟢 UIKit 심볼 참조 — 영향 없음 |

→ 실제 위험은 **한 곳**뿐이다. WP-B3에서 같은 커밋 내 이관하면 해소된다.

## B-2. WP 목록

### WP-B1 — `ABAccessoryHostingBox` (internal)

**선행**: B-0 게이트 통과.

`UIHostingController<AnyView>`를 소유하고 `ABPlayerControlsView.accessoryViews`에 넣을 `UIView`를 제공하는 internal 타입. **Q6이 우려한 실패 모드를 전부 명시적으로 처리하는 것이 이 WP의 존재 이유다.**

```swift
@MainActor
final class ABAccessoryHostingBox {
    private let controller: UIHostingController<AnyView>
    var view: UIView { controller.view }
    init<Content: View>(@ViewBuilder content: () -> Content)
    func update<Content: View>(@ViewBuilder content: () -> Content)
    func attach(to parentSearchOrigin: UIView)
    func detach()
}
```

**필수 처리 항목 (하나라도 빠지면 Q6의 우려가 현실이 된다)**

1. `controller.sizingOptions = [.intrinsicContentSize]` — 없으면 `UIStackView`가 크기를 못 정해 0×0으로 접힌다.
2. `controller.view.backgroundColor = .clear` — `UIHostingController`는 불투명 시스템 배경이 기본이라 오버레이 위에 사각형이 그려진다.
3. `controller.view.translatesAutoresizingMaskIntoConstraints = false`.
4. **부모 VC 부착**: `didMoveToWindow` 시점에 responder chain으로 가장 가까운 `UIViewController`를 찾아 `addChild` → `view` 삽입 → `didMove(toParent:)`. 제거 시 역순.
5. **부모를 못 찾은 경우**: 레이아웃은 동작하되 safe-area 전파·appearance 콜백·trait 상속이 불완전함을 **DocC와 코드 주석에 명시**한다. 조용히 넘어가지 않는다 — 이것이 Q6이 지목한 위험이며, 감추면 결정을 뒤집은 의미가 없다.
6. `update`는 `controller.rootView = AnyView(content())` 재대입. SwiftUI가 내부 diff를 하므로 매 업데이트 재대입해도 무방하다(`[UIView]` 시절의 `!=` 가드는 재현 불가).

**테스트** `ABAccessoryHostingBoxTests.swift`, 6개: 박스 생성 후 `view` 부모 유지, `update` 후 렌더 내용 변경, `detach` 후 자식 VC 관계 해제, 배경 투명, `intrinsicContentSize` 비영, 부모 VC 없는 환경에서 크래시 없음.

---

### WP-B2 — additive `@ViewBuilder` 이니셜라이저

**선행**: WP-B1. **오버로드 추가일 뿐, 기존 이니셜라이저는 그대로 둔다.**

```swift
// ABPlayerControls
public init<Accessories: View>(
    player: ABPlayer,
    style: ABPlayerControlsStyle = .default,
    configuration: ABPlayerControlsConfiguration = .init(),
    onEvent: (@MainActor (ABControlsEvent) -> Void)? = nil,
    @ViewBuilder accessories: @escaping () -> Accessories
)

// ABVideoPlayerWithControls — 동일 패턴
```

**설계 제약**

- `accessories`를 **마지막 파라미터**로 두어 trailing closure가 자연스럽게 붙게 한다.
- `onEvent`는 그 앞에 두어 trailing closure 모호성을 피한다.
- 호스팅 박스는 `Coordinator`가 소유한다(`ABPlayerControls.Coordinator`는 이미 `observationToken` 생명주기를 관리하고 있어 자연스러운 소유자다). `ABVideoPlayerWithControls`는 `ABPlayerControls`에 위임하므로 별도 소유가 필요 없다.
- 액세서리 없는 기본 케이스에 `EmptyView`가 들어가면 호스팅 컨트롤러를 **아예 만들지 않도록** 분기한다(빈 오버레이에 VC를 붙이는 비용 회피).

**컴파일 전용 모호성 테스트 필수**: 4가지 호출 형태(기존 배열형 / 신규 trailing closure / `onEvent` + trailing closure / 전부 기본값)를 한 테스트 파일에서 모두 작성해 컴파일되는지 확인. 오버로드 추가에서 가장 흔한 실패가 호출 모호성이다.

---

### WP-B3 — deprecation (CI 함정 주의)

**선행**: WP-B2.

```swift
@available(*, deprecated, message: "Use the @ViewBuilder `accessories:` initializer instead. \
Scheduled for removal in 1.0.0.")
public init(player:style:configuration:accessoryViews:onEvent:)
```

**같은 커밋에서 반드시 함께 처리**

1. `ABVideoPlayerWithControls.swift:35`를 신규 이니셜라이저 경유로 이관 — **하지 않으면 CI가 즉시 빨간불이 된다**(ci.yml:44 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`).
2. `Examples/…/PlaybackScreen.swift:21` 이관 (CI는 안 깨지지만 레퍼런스 예제).
3. `ABPlayerControlsView.accessoryViews`에는 **절대 `@available` 붙이지 말 것.** UIKit 경로의 정식 API이며, 붙이는 순간 테스트 4곳과 DocC 3곳이 함께 무너진다.

**검증**: `xcodebuild … SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build test` 통과 = deprecation 내부 잔존 사용 0건 증명.

---

### WP-B4 — 0.x deprecation 정책 문서화

**선행**: 없음 (WP-B3과 병렬 가능).

`docs/POLICY-api-stability.md` 신설. 이 레포는 이미 `ABPlayerEvent`/`ABPlayerError` 비전수 관례를 문서화해 왔으므로 그 연장선에 둔다.

**제안 정책 (0.x)**

| 규칙 | 내용 |
|---|---|
| 대체 API | 항상 **additive**로 먼저 추가한다. 같은 릴리스에서 구 API를 제거하지 않는다 |
| deprecation 시점 | 대체 API가 들어간 **같은 마이너**에서 `@available(*, deprecated, message:)` 부여. `message`에 대체 심볼과 제거 예정 버전을 반드시 명시 |
| 제거 시점 | **1.0.0 이전에는 제거하지 않는다.** 최소 한 개 마이너 이상의 중첩 기간 보장 |
| 패치 릴리스 | 패치(0.x.**y**)에서는 deprecation을 새로 도입하지 않는다 |
| enum case 추가 | 기존 관례 유지 — 비전수 선언 + `default` 요구를 타입 doc과 DocC 양쪽에 기재 |
| behavior change | 시그니처 불변이라도 관측 가능한 출력이 바뀌면 CHANGELOG `### Changed`에 **마이그레이션 한 줄**을 포함한다 |

마지막 행은 라운드3의 실제 사례를 규칙화한 것이다: WP12의 `.custom` 계약 변경이 `### Fixed`에 들어가 마이그레이션 안내가 빠졌다(`REVIEW-round3-final.md` N13).

README(영/한)에 "API Stability" 절을 추가하고 이 문서를 링크한다.

---

### WP-B5 — 문서/테스트 마감

**선행**: WP-B1~B4.

1. `CustomizingControls.md`에 SwiftUI 액세서리 절 추가. UIKit 경로(`accessoryViews`)와 SwiftUI 경로(`accessories:`)를 **나란히** 제시하고, WP-B1 항목 5(부모 VC 부재 시 한계)를 명시.
2. `ABPlayerControlsViewTests.swift:536` `accessoryViewsWinHitTestingOverAnEnabledSeekBar`를 SwiftUI 호스팅 액세서리 버전으로 확장 — 히트테스트 우선순위(:157 `hitTest`)가 호스팅 뷰에도 성립하는지가 실질 회귀 위험 지점이다.
3. CHANGELOG `### Added`(신규 이니셜라이저) + `### Deprecated`(구 이니셜라이저, 제거 예정 버전 명시).

## B-3. 리스크 표

| ID | 리스크 | 영향 | 확률 | 완화책 |
|---|---|---|---|---|
| **R-B0** | Q6 결정을 상의 없이 뒤집음 | **높음** (기록된 사용자 결정 무시) | — | B-0 게이트. 사용자 재결정 없이는 착수 금지 |
| **R-B1** | deprecation이 CI를 즉시 빨간불로 만듦 (`ABVideoPlayerWithControls.swift:35`) | 중 (즉시 발견됨) | **높음** | WP-B3에서 같은 커밋 내 이관 강제 |
| **R-B2** | 부모 VC 미부착 → safe area/appearance 콜백 유실 = Q6이 지목한 바로 그 위험 | 높음 | 중 | WP-B1 항목 4의 responder-chain 부착 + 항목 5의 한계 명시 |
| **R-B3** | 호스팅 뷰가 0×0으로 접힘 (`sizingOptions` 누락) | 높음 (액세서리 안 보임) | **높음** (가장 흔한 실수) | WP-B1 항목 1 + `intrinsicContentSize` 비영 테스트 |
| **R-B4** | 불투명 배경이 오버레이를 가림 | 중 | 높음 | WP-B1 항목 2 + 투명도 테스트 |
| **R-B5** | 오버로드 호출 모호성 | 중 (컴파일 실패) | 중 | WP-B2의 4형태 컴파일 테스트 |
| **R-B6** | 호스팅 컨트롤러 미보유로 갱신 중단 | 중 | 중 | `Coordinator` 소유 + `update` 후 렌더 변경 테스트 |
| **R-B7** | `ABPlayerControlsView.accessoryViews`까지 deprecate | 중 | 중 | WP-B3 항목 3에 금지 명시 |
| **R-B8** | 히트테스트 우선순위가 호스팅 뷰에서 깨짐 | 중 | 중 | WP-B5 항목 2 |

---

# 우선순위와 실행 순서

```
1. WP-A1   훅 census + 죽은 훅 1개 삭제         [리스크 없음, 즉시]
2. WP-A2   ABControlsLayout                     [순수 이동, characterization 선행]
3. WP-A3   ABControlsTimeLabelFormatter         [순수 이동, N14 동시 해소]
   ── 여기서 뷰 1109 → ~890줄 (−20%), 리스크 낮음 ──

4. B-0     Q6 재검토 게이트                      [🚦 사용자 결정 필요]
5. WP-B1   ABAccessoryHostingBox
6. WP-B2   @ViewBuilder 이니셜라이저 (additive)
7. WP-B3   deprecation (+ 내부 이관, CI 함정)
8. WP-B4   0.x API 안정성 정책 문서
9. WP-B5   문서/테스트 마감
   ── B 트랙 완료: 사용자 대면 API 개선 확정 ──

10. WP-A4a ABControlsPresenter — 상태 매핑
11. WP-A4b ABControlsPresenter — 명령 방출     [⚠️ 순서 characterization 선행 필수]
12. WP-A5  훅 예산 정산
```

**순서 근거**

- **A1–A3을 먼저**: 리스크가 가장 낮으면서 뷰를 20% 줄인다. 여기서 멈춰도 순이익이다.
- **B 트랙을 A4보다 먼저**: B는 A와 파일이 겹치지 않아 독립적이고, 유일하게 **사용자 대면 개선**이다. A4는 내부 구조 개선이라 사용자 체감이 없다.
- **A4를 마지막**: 단일 최대 리스크(R-A3 재진입 순서)이자 사용자 가치가 가장 낮다. 라운드 예산이 부족하면 여기서 잘라내는 것이 손실이 가장 적다.
- B-0 게이트는 1–3번 진행과 **병렬**로 사용자에게 물어볼 수 있다. 게이트가 막히면 4–9를 B-alt(DocC 레시피)로 대체하고 곧장 10번으로 간다.

# 예상 규모 총계

| | 프로덕션 | 테스트 | 커밋 |
|---|---|---|---|
| (A) | 뷰 −470줄 / 신규 3파일 +520줄 | +520줄, +38~42 `@Test` | 8 (characterization 선행 2 포함) |
| (B) | +180줄 (호스팅 박스 + 오버로드) | +140줄, +9 `@Test` | 5 |
| **합계** | **+230줄** (총 3725 → ~3955) | **+660줄, +~50 `@Test`** (373 → ~423) | **13** |

핵심 지표: `ABPlayerControlsView.swift` **1109 → ~620줄(−44%)**, 뷰 인스턴스 없이 도는 컨트롤 테스트 **27 → 70+**.

# 완료 정의

- 전 WP에서 `xcodebuild test -scheme ABPlayerKit-Package … SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 통과, 경고 0
- WP마다 독립 커밋 · 독립 테스트 가능 (WP-A4는 a/b 분할)
- characterization 테스트 2종(레이아웃 수치, 재진입 순서)이 해당 이동보다 **먼저** 커밋됨
- `docs/briefs/ROADMAP-round4-hook-census.md`가 WP-A1과 WP-A5 시점 수치를 모두 담음
- B-0 게이트 결과가 `DESIGN-OPEN-QUESTIONS.md` Q6 행에 기록됨 (진행이든 폐기든)
- CHANGELOG `Unreleased`에 Added/Deprecated/Changed 반영, `docs/POLICY-api-stability.md` 존재
