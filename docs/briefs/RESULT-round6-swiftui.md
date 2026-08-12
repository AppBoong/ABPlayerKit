# RESULT: 라운드6 트랙 S — SwiftUI 간편 API

구현 담당: Sonnet. 브랜치 `round6/swiftui`, 기준 커밋 995bb6d. 입력: `DESIGN-round6-swiftui.md`(유일한 사양), `ROADMAP-round6.md` §0·§2, `REVIEW-round6-portfolio-audit.md` §C.

작업 순서는 지시대로 S-1w → S-2w → S-3w. **커밋하지 않았음** — 작업 트리 변경만 존재.

---

## 1. WP별 변경 요약

### S-1w — URL 편의 생성자 + 소유 박스

- `Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift` (기존 파일 수정)
  - `Ownership` enum(`.explicit(ABPlayer)` / `.owned(ABMediaSource, autoplay:, ABPlayerConfiguration)`)으로 명시 소유와 자동 소유를 한 곳에서 분기.
  - `init(url:videoGravity:autoplay:configuration:)`, `init(source:videoGravity:autoplay:configuration:)` 신규 추가. `url:` 은 `source:`로 위임.
  - `makeCoordinator()` 신규. `Coordinator`가 `Void`에서 실제 클래스로 바뀜(§3.1이 예고한 대로, CHANGELOG에 `### Changed`로 기록).
  - `Coordinator`가 소유 플레이어 생성(`player(configuration:videoGravity:)`, `configuration`은 최초 1회만 적용) / 소스 적용(`apply(source:autoplay:)`, 동일 소스 재적용은 완전 no-op) / 해제(`releaseIfOwned()`, `didRelease` 플래그로 이중 해제 방지)를 담당.
  - `dismantleUIView`가 `coordinator.releaseIfOwned()`만 호출 — 명시 소유 경로에서는 `owned`가 `nil`이라 자동으로 no-op(I-3).
  - `makeUIView`/`updateUIView`는 설계가 지정한 순서(`P` 획득 → `apply` → `view.player = P` → `view.videoGravity = videoGravity`)를 그대로 구현.

- `Sources/ABPlayerKitControls/SwiftUI/ABOwnedPlayerBox.swift` (신규)
  - 코어의 `Coordinator`와 동일한 3책임(생성 1회/적용 멱등/해제 멱등)을 Controls 타깃 내부 클래스로 복제. 설계가 명시적으로 기각한 "공유 공개 타입" 대신 각 ~50줄짜리 내부 클래스 2벌 유지.

- `Sources/ABPlayerKitControls/SwiftUI/ABVideoPlayerWithControls.swift` (기존 파일 수정)
  - `Ownership` enum을 `.explicit(ABPlayer, controls: AnyView)` / `.owned(ABMediaSource, autoplay:, ABPlayerConfiguration)`로 정의. 명시 소유 경로는 기존과 동일하게 `controls: AnyView`를 이니셜라이저에서 즉시 빌드해 `Ownership` 페이로드에 담는다(강제 언래핑 없이 타입으로 "항상 존재"를 보장).
  - `url:`/`source:` 신규 이니셜라이저 4종(액세서리 없음 2 + `@ViewBuilder accessories:` 2). URL 계열에는 설계가 지정한 대로 `style:`/`configuration:`(Controls용) 파라미터가 없다 — 커스터마이즈는 S-2w의 modifier로.
  - `@State private var owner = ABOwnedPlayerBox()` 추가. `body`는 `switch ownership`으로 분기하며, `.owned` 분기는 별도의 **일반 함수**(`ownedContent(source:autoplay:playerConfiguration:)`, `@ViewBuilder` 아님)에서 `owner.apply(...)`(`Void` 반환) 부작용을 수행한 뒤 뷰를 반환한다 — `body`가 `@ViewBuilder` 컨텍스트라 `Void` 문장을 직접 넣으면 `buildExpression` 요구사항 위반으로 컴파일 에러가 나는 것을 처음 빌드에서 확인하고 이렇게 고쳤다(§4 참고).
  - 기존 `player:` 경로(레거시 `accessoryViews:` deprecated 이니셜라이저 포함)는 동작 변화 없음 — `style:`/`configuration:`이 옵셔널화된 것 외에는 그대로.

### S-2w — Environment modifier

- `Sources/ABPlayerKitControls/SwiftUI/ABPlayerControlsEnvironment.swift` (신규)
  - `ABPlayerControlsStyleKey`/`ABPlayerControlsConfigurationKey`, 둘 다 `static var defaultValue: ... ? { nil }` (computed, `static let` 아님 — §4.3-1).
  - `EnvironmentValues.playerControlsStyle`/`playerControlsConfiguration` (둘 다 Optional).
  - `View.playerControlsStyle(_:)`/`playerControlsConfiguration(_:)` modifier.
- `Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift` (기존 파일 수정)
  - `style`/`configuration` 저장 프로퍼티를 Optional로. 공개 이니셜라이저 3개(`deprecated` 배열형, 내부 `legacyPlayer:` 브리지, `accessories:` 제네릭형) 전부 옵셔널 파라미터로 완화, 기본값 `nil`.
  - `update(_ view:coordinator:environment: EnvironmentValues = EnvironmentValues())`로 시그니처 확장 — 기존 2-인자 호출부(`ABPlayerControlsSwiftUITests`)는 그대로 컴파일됨(§4.3-3).
  - `resolveStyle(environment:)`/`resolveConfiguration(environment:)`: `style ?? environment.playerControlsStyle ?? .default` / `configuration ?? environment.playerControlsConfiguration ?? .init()`. `makeUIView`/`updateUIView` 둘 다 `context.environment`로 해석해 사용.
- `Sources/ABPlayerKitControls/SwiftUI/ABVideoPlayerWithControls.swift`
  - `style`/`configuration` 파라미터 옵셔널화(위 S-1w 절 참고). `ABVideoPlayerWithControls` 자신은 Environment를 읽지 않고 옵셔널을 그대로 `ABPlayerControls`로 전달 — 해석은 그 한 곳에서만 일어난다(§4.2).
- DocC: `ABPlayerKitControls.md` Topics에 "SwiftUI Environment" 절 신규(`View/playerControlsStyle(_:)` 등 4개 심볼), `CustomizingControls.md`에 "Apply a Style Across Several Players" 절 신규.

### S-3w — README / DocC

- `README.md`, `README.ko.md`: Quick Start를 설계 §6.2 초안대로 재구성 — ① 원라이너(`ABVideoPlayerWithControls(url:)`) ② 코어 단독 원라이너 ③ Customizing(modifier + `ABPlayerConfiguration`) ④ Owning the Player Yourself(기존 명시 소유 예제, `.onDisappear { player.release() }` 유지) ⑤ UIKit 예제(위치 이동, `kind:` 제거) ⑥ Advanced — Grades and Preloading(기존 grade 표 + `set(source:grade:)` 예제를 이동, `kind:` 언급은 이 절에만 존치). `### ABPlayerKit — Core` 절의 중복 grade 표는 제거하고 Advanced 절로 링크.
- `CHANGELOG.md`: `[Unreleased]`에 `### Added`(신규 이니셜라이저 2벌 + modifier 2개) / `### Changed`(옵셔널 파라미터 완화 + `Coordinator` 연관 타입 변경) 기록.
- 리포 전역 `kind:` 잔재 점검: `README.md`/`README.ko.md`/DocC 카탈로그 모두 확인 완료(고급 절의 의도적 예시 1건만 남음). `Examples/`는 설계 지시대로 코드 미변경(여전히 `player:` 경로 사용).

---

## 2. 파일 경계 확인

```
$ git status --porcelain
 M CHANGELOG.md
 M README.ko.md
 M README.md
 M Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift
 M Sources/ABPlayerKitControls/ABPlayerKitControls.docc/ABPlayerKitControls.md
 M Sources/ABPlayerKitControls/ABPlayerKitControls.docc/CustomizingControls.md
 M Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift
 M Sources/ABPlayerKitControls/SwiftUI/ABVideoPlayerWithControls.swift
 M Tests/ABPlayerKitControlsTests/ABPlayerControlsInitializerAmbiguityTests.swift
 M Tests/ABPlayerKitControlsTests/ABVideoPlayerWithControlsTests.swift
?? Sources/ABPlayerKitControls/SwiftUI/ABOwnedPlayerBox.swift
?? Sources/ABPlayerKitControls/SwiftUI/ABPlayerControlsEnvironment.swift
?? Tests/ABPlayerKitControlsTests/ABOwnedPlayerBoxTests.swift
?? Tests/ABPlayerKitControlsTests/ABPlayerControlsEnvironmentTests.swift
?? Tests/ABPlayerKitTests/ABVideoPlayerOwnershipTests.swift
```

(`docs/briefs/*.md` 4개는 이 세션 이전에 이미 untracked 상태였던 입력 문서.)

`ABPlayer.swift` / `ABAVPlaybackTarget.swift` / `ABPlayerControlsView.swift` — **diff 0줄, 목록에 없음.** `Tests/*/Support/ABWaitUntil.swift`도 무수정.

---

## 3. 구현 중 발견한 함정 (설계에 없던 것)

**`body`(`@ViewBuilder`) 안에서 `Void`를 반환하는 부작용 호출은 컴파일 에러.** `ABVideoPlayerWithControls.body`의 `.owned` 분기에서 `owner.apply(source:autoplay:)`(반환 `Void`)를 `let player = owner.player(...)` 다음 줄에 그냥 문장으로 썼더니 `error: type '()' cannot conform to 'View'`가 발생했다(`@ViewBuilder`의 `buildExpression`이 모든 문장-표현식에 `View` 준수를 요구하기 때문 — 일반 함수 바디와 다른 점). 해결: 그 분기를 `ownedContent(source:autoplay:playerConfiguration:)`라는 **일반(비-`@ViewBuilder`) 함수**로 뽑아 그 안에서 `let`/부작용 호출/`return`을 자유롭게 쓰고, `body`는 이 함수의 반환값(`some View`)만 받는다. 설계 §7 S-1w의 지시("body에서 `ABPlayerControls`를 구성")를 그대로 따르되 구현 세부는 이렇게 조정했다.

---

## 4. deinit MainActor 홉 채택 여부

**채택했다.** `ABVideoPlayer.Coordinator.deinit`과 `ABOwnedPlayerBox.deinit` 둘 다 `Task { @MainActor in owned.release() }` 패턴을 그대로 사용했고, Swift 6 모드(`swift-version 6`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`)에서 경고/에러 없이 빌드된다. 이는 이미 이 코드베이스에 있는 `ABPlayerControls.Coordinator.deinit`(`ABPlayerControls.swift:191-216`, 기존 코드)과 동일한 패턴이며, non-isolated `deinit`이 자신의(격리된 클래스의) 저장 프로퍼티를 동기적으로 읽어 `Task { @MainActor in }` 클로저로 넘기는 것이 이 리포에서 이미 확립된 관용구임을 재확인했다. 폴백(`dismantleUIView`/`ABPlayer.deinit`에만 의존)은 필요 없었다.

이 채택을 `Tests/ABPlayerKitTests/ABVideoPlayerOwnershipTests.swift`의 `deinitReleasesWhenDismantleNeverRuns`와 `Tests/ABPlayerKitControlsTests/ABOwnedPlayerBoxTests.swift`의 `deinitReleasesUnreleasedPlayer`가 직접 검증한다 — 두 테스트 모두 `dismantleUIView`/`releaseIfOwned`를 호출하지 않고 코디네이터/박스만 스코프 밖으로 보낸 뒤 `waitUntil { player.grade == .released }`로 관측한다.

---

## 5. 검증 결과

시뮬레이터가 부팅되어 있지 않아(`xcrun simctl list devices | grep Booted` 결과 없음) 브리프 지시대로 **새 시뮬레이터를 부팅하지 않고 빌드 검증까지만** 수행했다. 테스트는 실행하지 못했다 — 아래는 전부 빌드/타입체크 수준의 검증이다.

| 검증 | 명령 | 결과 |
|---|---|---|
| generic iOS 빌드 | `xcodebuild -scheme ABPlayerKit-Package -destination 'generic/platform=iOS' build` | **BUILD SUCCEEDED**, 경고 0 |
| Swift 6 zero-warning (CI 동일 플래그) | 위 + `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES` | **BUILD SUCCEEDED** |
| DocC 빌드 | 위 + `DOCC_WARNINGS_AS_ERRORS=YES` + `docbuild` | **BUILD DOCUMENTATION SUCCEEDED**, 4개 타깃(`ABPlayerKit`/`ABPlayerKitCache`/`ABPlayerKitControls`/`ABPlayerKitMetrics`) 전부 진단 0건 |
| 테스트 타깃 컴파일(시뮬레이터) | `xcodebuild build-for-testing -scheme ABPlayerKit-Package -destination 'generic/platform=iOS Simulator'` | **TEST BUILD SUCCEEDED** — 신규 테스트 5개 파일 + 수정된 2개 파일 전부 타입체크 통과 |
| 테스트 **실행** | — | **미실행.** 부팅된 시뮬레이터 없음(신규 부팅 금지 규칙 준수). §10 체크리스트의 "184개 무수정 통과" 항목은 컴파일 통과로만 대체 확인했다 — 실제 실행 검증은 CI 또는 S-4 게이트에서 필요. |

---

## 6. §10 완료 정의 체크리스트

- [x] `ABPlayer.swift` / `ABAVPlaybackTarget.swift` / `ABPlayerControlsView.swift` diff 0줄 — §2 참고.
- [x] 불변식 I-1~I-4 각각에 대응 테스트 존재
  - I-1(생성 1회): `ABVideoPlayerOwnershipTests.mountsWithSourceAtCurrent`/`repeatedUpdatesReuseInstance`, `ABOwnedPlayerBoxTests.createsExactlyOnce`
  - I-3(명시 소유는 건드리지 않음): `ABVideoPlayerOwnershipTests.explicitOwnershipNeverReleases`
  - I-4(이중 해제 무해): `ABVideoPlayerOwnershipTests.doubleDismantleIsHarmless`, `ABOwnedPlayerBoxTests.releaseIfOwnedIsIdempotent`
  - (I-2는 별도 단정문 없이 설계 자체가 구조적으로 보장 — `onDisappear` 미사용이므로 위반 경로 자체가 존재하지 않음. 대신 시나리오 4에 해당하는 "화면 밖에서도 계속 재생"은 별도 assert가 없다: 이 설계에서 `onDisappear`를 구독하지 않는다는 사실 자체가 증명이며, 그 부재를 코드로 직접 검증하는 테스트는 작성하지 않았다.)
- [x] `onAppear`/`onDisappear`/`task`가 신규 코드에 0건 — grep 확인(프로즈 주석 안의 언급 2건 제외, 실제 modifier 사용 0건).
- [~] 기존 Controls 테스트 184개 무수정 통과 — **무수정은 확정**(해당 파일들에 diff 없음), **컴파일 통과는 확인**, **실행 통과는 미확인**(§5 사유).
- [x] 신규 public 심볼 전부 DocC 큐레이션 + `docbuild` 경고 0 — `View/playerControlsStyle(_:)`, `View/playerControlsConfiguration(_:)`, `EnvironmentValues/playerControlsStyle`, `EnvironmentValues/playerControlsConfiguration`을 `ABPlayerKitControls.md`에 큐레이션. `ABVideoPlayer`/`ABVideoPlayerWithControls`의 신규 이니셜라이저는 기존에 이미 큐레이션된 타입의 오버로드라 추가 작업 불필요. `ABVideoPlayer.Coordinator`는 설계상 "공개 멤버 없는 구현 상세"라 별도 큐레이션 없이 부모 타입 페이지에 자동 포함.
- [x] README/README.ko의 첫 예제가 원라이너이며 `kind:` 부재
- [x] Swift 6 zero-warning, 신규 주석에 리뷰 ID 인용 0건 — grep 확인(C-1/I-3/S-1w 등 전부 0건).

---

## 7. 게이트 문의 사항

없음. §3.2가 예고한 "Swift 6이 MainActor 홉을 거부하면 폴백" 조건은 발생하지 않았다(§4). 설계를 벗어난 구현 판단은 §3 "구현 중 발견한 함정" 한 건(비-`@ViewBuilder` 헬퍼 함수 분리)뿐이며, 이는 설계의 의도(§7 S-1w 지시)를 그대로 satisfy하는 구현 세부 사항이라 별도 승인이 필요하다고 판단하지 않았다.

**S-4 게이트에 요청**: 부팅된 시뮬레이터에서 `ABPlayerKit-Package` 스킴 전체 테스트 실행(기존 184개 포함, 신규 약 30개)을 한 번 더 통과시켜 §10 체크리스트의 마지막 미확인 항목("184개 실제 실행 통과")을 닫아 달라.
