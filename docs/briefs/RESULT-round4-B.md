# RESULT: 라운드4 (B) — accessoryViews SwiftUI API 정리

`docs/briefs/ROADMAP-round4.md`의 (B) 파트, WP-B0~WP-B5를 순서대로 구현한 결과다. Q6 개정은 사용자 승인 완료 상태로 시작했다.

각 WP는 (A) 트랙과 동일한 방식으로 검증했다: `xcodebuild -scheme ABPlayerKit-Package -destination "platform=iOS Simulator,id=<부팅된 시뮬레이터>" SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build test`로 4개 테스트 번들 전부 `** TEST SUCCEEDED **`, 경고 0을 매 WP 종료 시점에 확인했다(새 시뮬레이터 부팅 없이 기존 부팅된 `iPhone Air` 사용). 추가로 WP-B3에서 데모 앱(`ABPlayerKitDemo` 스킴)을, WP-B5에서 `DOCC_WARNINGS_AS_ERRORS=YES` 문서 빌드(`docbuild`)를 각각 별도로 검증했다 — 둘 다 CI(`ci.yml`)가 실제로 게이트하는 항목이라 라이브러리 테스트만으로는 잡히지 않는 실패 모드다.

## 전체 결과 요약

| 시점 | 전체 테스트(4번들 합) | Controls 테스트 |
|---|---|---|
| (B) 착수 전(= (A) 완료 시점) | 385 | 165 |
| WP-B0 (Q6-A 기록) | 385 | 165 |
| WP-B1 이후 | 391 | 171 |
| WP-B2 이후 | 398 | 178 |
| WP-B3 이후 | 398 | 178 |
| WP-B4 이후 (문서만) | 398 | 178 |
| **WP-B5(최종)** | **399** | **179** |

신규 프로덕션 파일: `SwiftUI/ABAccessoryHostingBox.swift`(85줄). 수정 파일: `ABPlayerControls.swift`(+약 100줄, 신규 이니셜라이저·`Coordinator` 확장), `ABVideoPlayerWithControls.swift`(+약 30줄, 위임 경로).

## WP-B0 — Q6 재검토 게이트

`docs/DESIGN-OPEN-QUESTIONS.md`의 Q6 확정 행 옆에 **Q6-A 개정 행**을 추가했다: 재결정 사유(SwiftUI 라이브러리로서의 API 완성도), 완화책(WP-B1의 부모 VC 부착 전략), 결정일(2026-08-05), 사용자 승인 완료를 명시. Q6 원본 행은 삭제하지 않고 "2026-08-05 Q6-A로 개정, 아래 참조" 메모만 덧붙여 감사 추적을 보존했다.

## WP-B1 — `ABAccessoryHostingBox` (internal)

- `UIHostingController<AnyView>`를 소유하는 internal 클래스. Q6이 우려한 5가지 실패 모드를 전부 명시적으로 처리:
  1. `sizingOptions = [.intrinsicContentSize]` — 0×0 붕괴 방지
  2. `view.backgroundColor = .clear` — 불투명 배경이 오버레이를 가리는 문제 방지
  3. `translatesAutoresizingMaskIntoConstraints = false`
  4. `attach(to parentSearchOrigin:)` — responder chain을 걸어 올라가 가장 가까운 `UIViewController`를 찾아 `addChild` → `didMove(toParent:)`; `detach()`가 역순으로 해제
  5. **부모를 못 찾는 경우** 조용히 넘어가지 않고 타입 doc 주석에 한계(safe-area 전파·appearance 콜백·trait 상속 미보장)를 명시 — `attach(to:)`는 단순히 아무 것도 하지 않고 반환하며, 크래시하지 않는다
- **로드맵에 없던 설계 결정**: "didMoveToWindow 시점에 부착"이라는 로드맵 문구를 문자 그대로 구현할 수 없었다 — `box.view`는 `UIHostingController.view`(SwiftUI 내부 비공개 타입)를 그대로 반환하므로 서브클래싱해 `didMoveToWindow`를 오버라이드할 수 없다. 대신 `attach(to:)`를 `view.window != nil`일 때만 시도하도록 호출부(WP-B2의 `Coordinator`)에서 게이팅하고, 실패하면 다음 SwiftUI 업데이트 패스에서 재시도되도록 설계했다 — 여러 번 호출해도 안전(`isAttachedToParent` 가드로 멱등).
- 신규 테스트 `ABAccessoryHostingBoxTests.swift` 6개: view 유지, `update` 후 intrinsicContentSize 변화, attach+detach(부모 VC 채택/해제), 배경 투명, intrinsicContentSize 비영, 부모 VC 없는 환경에서 크래시 없음.

## WP-B2 — additive `@ViewBuilder` 이니셜라이저

- `ABPlayerControls`/`ABVideoPlayerWithControls`에 `@ViewBuilder accessories: @escaping () -> Accessories` 트레일링 클로저 이니셜라이저를 **추가만** 했다(기존 `accessoryViews: [UIView]` 이니셜라이저는 그대로 유지). `accessories`를 마지막 파라미터로, `onEvent`를 그 앞에 둬 트레일링 클로저 모호성을 피했다.
- `Accessories.self == EmptyView.self`일 때 호스팅 컨트롤러 자체를 만들지 않는다(빈 오버레이에 VC를 붙이는 비용 회피).
- 호스팅 박스는 `ABPlayerControls.Coordinator`가 소유(로드맵 명시대로) — `Coordinator`는 이미 `observationToken` 생명주기를 관리하고 있어 자연스러운 소유자다. `ABVideoPlayerWithControls`는 별도 소유 없이 내부 `ABPlayerControls`에 위임한다.
- `Coordinator.deinit`에서 `accessoryBox?.detach()`를 호출하려면 `isolated deinit`(SE-0371)이 필요했다 — `@MainActor` 클래스라도 일반 `deinit`은 자동으로 격리되지 않아 `detach()`(MainActor-isolated) 호출이 컴파일 에러였다.
- **필수 컴파일 전용 모호성 테스트** `ABPlayerControlsInitializerAmbiguityTests.swift` 4개: 기존 배열형 / 신규 트레일링 클로저 / `onEvent` + 트레일링 클로저 / 전부 기본값. 추가로 기능 테스트 3개(`ABPlayerControlsSwiftUITests.swift`): accessories가 실제로 1개 accessory view로 호스팅됨, `EmptyView`는 아무것도 호스팅하지 않음, 값 구조체가 업데이트돼도 같은 호스팅 뷰 인스턴스가 재사용됨(재구축 아님).

## WP-B3 — deprecation (⚠️ CI 함정)

- `ABPlayerControls`/`ABVideoPlayerWithControls`의 배열형 이니셜라이저에 `@available(*, deprecated, message: "... Scheduled for removal in 1.0.0.")` 부여. `ABPlayerControlsView.accessoryViews`(UIKit 프로퍼티)에는 **붙이지 않음** — 정식 UIKit API로 유지.
- **로드맵이 지목한 함정 + 추가로 발견한 함정 2건, 전부 해소**:
  1. (로드맵 지목) `ABVideoPlayerWithControls`가 내부적으로 `ABPlayerControls`의 배열형 이니셜라이저를 호출하는 경로 — deprecated 심볼을 non-deprecated 컨텍스트에서 참조하면 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`가 즉시 실패한다. 처음엔 "호출부를 deprecated로 같이 표시" 방식을 시도했으나, `controls`(전체 `@ViewBuilder` 프로퍼티)를 deprecated로 표시하면 **관련 없는 신규 accessories 경로까지** 경고가 억제돼 버려 잘못된 해법이었다. 최종 해법: `ABPlayerControls`에 `internal init(legacyPlayer:...)` — 배열형 이니셜라이저와 동일한 필드 초기화를 수행하지만 deprecated가 아닌 별도 진입점 — 을 신설하고, public deprecated 이니셜라이저와 `ABVideoPlayerWithControls`의 내부 위임 경로 둘 다 이것을 거치도록 했다.
  2. (직접 발견) 기존 테스트 5곳(`ABPlayerControlsSwiftUITests.swift` 3곳, `ABVideoPlayerWithControlsTests.swift` 3곳)이 트레일링 클로저 없이 `ABPlayerControls(player:)`/`ABVideoPlayerWithControls(player:)`를 호출해 배열형(이제 deprecated) 이니셜라이저로 해석되고 있었다. 의도적으로 레거시 형태를 테스트하는 것이 아닌 테스트들은 `{}` 트레일링 클로저를 추가해 신규 이니셜라이저로 이관했고, 레거시 형태 자체를 검증하는 게 목적인 테스트(`ABPlayerControlsInitializerAmbiguityTests.swift`의 2개 함수)만 `@available(deprecated)`로 명시적으로 표시했다.
  3. (직접 발견) `Examples/ABPlayerKitDemo/PlaybackScreen.swift`가 배열형 이니셜라이저로 `DemoAccessoryButton`(UIKit `UIButton` 서브클래스)을 주입하고 있었다 — CI 미포함 스킴이라 안 깨지지만 레퍼런스 예제이므로 이관. `DemoAccessoryButton` 클래스를 완전히 제거하고 순수 SwiftUI `Button`으로 교체 — 신규 API의 실제 사용례로 더 적합하다. 데모 앱 스킴(`ABPlayerKitDemo`)을 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`로 별도 빌드해 확인.

## WP-B4 — 0.x API 안정성 정책 문서

- `docs/POLICY-api-stability.md` 신설: 대체 API는 additive 우선, deprecation은 대체 API와 같은 마이너에서, 제거는 1.0.0 이전 금지, 패치에서 신규 deprecation 금지, enum case는 비전수 관례 유지, 관측 가능한 동작 변경은 CHANGELOG에 마이그레이션 한 줄 필수 — 마지막 규칙은 라운드3 WP12의 실제 누락 사례(REVIEW-round3-final.md N13)를 규칙화한 것.
- WP-B3에서 실제로 밟은 절차를 "실제 사례"로 문서에 기록(추가만 우선, 내부 non-deprecated 브리지 경유 등).
- README(영/한) 각각에 "API Stability" 절 추가, 정책 문서 링크.

## WP-B5 — 문서/테스트 마감

- `CustomizingControls.md`의 "Add Application Controls" 절을 UIKit/SwiftUI 두 경로를 나란히 보여주는 형태로 재작성. SwiftUI 절에는 WP-B1 항목 5(부모 VC 부재 시 한계)를 명시하고, 배열형 이니셜라이저가 deprecated임과 정책 문서 링크를 포함.
- `accessoryViewsWinHitTestingOverAnEnabledSeekBar`(UIKit `accessoryViews` 경로)의 SwiftUI 호스팅 버전을 `swiftUIHostedAccessoryWinsHitTestingOverAnEnabledSeekBar`로 신설 — 동일한 기하 조건(짧은 오버레이, seek bar와 겹치는 accessory)에서 `ABAccessoryHostingBox`로 호스팅한 SwiftUI accessory도 히트테스트 우선순위 약속을 지키는지 검증. `CustomizingControls.md`가 문서화한 우선순위 약속이 두 경로 모두에서 성립함을 회귀 테스트로 고정했다.
- CHANGELOG `[Unreleased]`에 `### Added`(신규 `accessories:` 이니셜라이저) + 신설된 `### Deprecated`(배열형 이니셜라이저, 제거 예정 버전과 마이그레이션 한 줄 포함) 반영.
- `DOCC_WARNINGS_AS_ERRORS=YES`로 `docbuild` 별도 실행해 `CustomizingControls.md` 변경이 문서 빌드를 깨지 않음을 확인(`** BUILD DOCUMENTATION SUCCEEDED **`).

## 완료 정의 체크리스트 (로드맵 대비)

- [x] 전 WP에서 `xcodebuild test ... SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 통과, 경고 0
- [x] B-0 게이트 결과가 `DESIGN-OPEN-QUESTIONS.md` Q6 행에 기록됨 (Q6-A로 진행)
- [x] 기존 public API 파괴 변경 없음 — 전부 additive, deprecation은 `@available(*, deprecated)`로만 표시하고 실제 제거는 하지 않음
- [x] `ABPlayerControlsView.accessoryViews`는 deprecate하지 않음
- [ ] WP당 독립 커밋 — **커밋 금지** 지시에 따라 커밋하지 않음(사용자 확인 후 별도 진행 필요)

## 발견한 것 중 로드맵에 없던 사항 (요약)

1. `UIHostingController.view`는 서브클래싱 불가 — "didMoveToWindow 시점 부착"은 호출부의 `view.window != nil` 게이팅 + 멱등 재시도로 근사 구현.
2. `Coordinator.deinit`에서 `@MainActor` 멤버(`accessoryBox?.detach()`) 호출에 `isolated deinit`(SE-0371) 필요.
3. deprecated 이니셜라이저를 non-deprecated 컨텍스트에서 내부적으로 호출하는 "CI 함정"이 로드맵이 지목한 1곳 외에 기존 테스트 5곳 + 데모 앱 1곳에서 추가로 발견됨 — 전부 해소.
