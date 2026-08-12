# REVIEW: 라운드6 트랙 S 최종 게이트 (S-4)

리뷰어: Sonnet(브리프상 Opus 슬롯, 모델만 교체). 대상: 작업 트리 전체 미커밋 diff(브랜치 `round6/swiftui`, 기준 995bb6d).
입력: `DESIGN-round6-swiftui.md`(승인 설계), `RESULT-round6-swiftui.md`(구현 자기보고), `ROADMAP-round6.md` §0·§2, `REVIEW-round6-portfolio-audit.md` §C.

## 0. 검증 방법론

정적 리뷰(코드 레벨 추적)에 더해, 시뮬레이터를 새로 부팅하지 않는 범위에서 **독립적으로 빌드를 재현**했다(RESULT의 자기보고를 그대로 신뢰하지 않고 직접 확인):

| 검증 | 명령 | 결과 |
|---|---|---|
| generic iOS 빌드, Swift 6 zero-warning | `xcodebuild -scheme ABPlayerKit-Package -destination 'generic/platform=iOS' build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES` | **BUILD SUCCEEDED** |
| 테스트 타깃 컴파일(시뮬레이터, 미부팅) | `xcodebuild -destination 'generic/platform=iOS Simulator' build-for-testing` (동일 경고=에러 플래그) | **TEST BUILD SUCCEEDED** — 신규 5개 + 수정 2개 테스트 파일 포함 48개 테스트 파일 전부 |
| DocC 빌드 | 위 + `docbuild DOCC_WARNINGS_AS_ERRORS=YES` | **BUILD DOCUMENTATION SUCCEEDED**, 진단 0건 |

세 빌드 모두 RESULT의 §5 보고와 일치했다. 이로써 §3.2가 우려했던 "Swift 6이 `deinit`의 `Task { @MainActor in }` 홉을 거부할 수 있다"는 리스크가 실제로는 발생하지 않음을 **직접 재현으로 확인**했다(자기보고 신뢰가 아님). 시뮬레이터 미부팅으로 실제 **테스트 실행**은 여전히 하지 못했다 — 브리프 지시대로 CI에 위임.

---

## 1. 파일 경계 (완료 정의 1번)

```
$ git diff --stat -- Sources/ABPlayerKit/Engine/ABPlayer.swift \
    Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift \
    Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift
(출력 없음 — diff 0)
```

세 파일 모두 diff 0줄, `git status`에도 나타나지 않음. **PASS.** 트랙 A(`ABPlayer.swift`/`ABAVPlaybackTarget.swift`)·트랙 C(`ABPlayerControlsView.swift`)가 Wave 2에서 수정할 파일과 겹치지 않으므로 충돌 없음.

## 2. 시나리오 10개 추적 (설계 §5)

| # | 시나리오 | 코드 추적 | 판정 |
|---|---|---|---|
| 1 | 최초 표시 | `ABVideoPlayer.makeUIView`/`ABVideoPlayerWithControls.ownedContent`가 `Coordinator.player(...)`/`ABOwnedPlayerBox.player(...)`를 통해 최초 1회 생성(`if let owned { return owned }` 가드), `apply` 1회 적용 | PASS |
| 2 | 부모 body 재평가 (identity 동일) | `apply(source:autoplay:)`의 `guard let owned, appliedSource != source else { return }` — 동일 소스 재적용은 완전 no-op. `ABVideoPlayerOwnershipTests.repeatedUpdatesReuseInstance`/`pauseSurvivesRepeatedApply`, `ABOwnedPlayerBoxTests.applyIsIdempotent`가 실제로 "일시정지가 되살아나지 않음"까지 검증(단순 `===` 비교보다 강함) | PASS |
| 3 | `url` 변경, identity 동일 | `appliedSource != source` → 새 소스로 `set(source:grade:.current)`, 인스턴스는 `owned`로 유지·재사용. `urlChangeReusesInstanceAndReapplies`가 인스턴스 동일성 + 소스 갱신 + autoplay 재적용을 함께 확인 | PASS |
| 4 | 지연 컨테이너 스크롤 아웃 | 신규 코드 전체에 `onAppear`/`onDisappear`/`.task` 실사용 0건(§4 확인) — 구조적으로 구독 자체가 없음. 별도 단정 테스트는 없음(RESULT §6도 동일하게 인정) | PASS (구조적 보장, 실행 테스트는 아님 — 잔여 리스크로 하단 명시) |
| 5 | 지연 컨테이너 셀 파기 | `dismantleUIView` → `coordinator.releaseIfOwned()` → `didRelease=true` + `owned.release()`. `dismantleReleasesOwnedPlayer`가 `grade == .released && source == nil` 확인 | PASS |
| 6 | `.id(x)` 변경 / 분기 전환 | 옛 identity의 `Coordinator`/`@State owner`는 SwiftUI가 통째로 파기 → `deinit` 경유 해제. 새 identity는 새 `Coordinator`/`owner`로 독립 생성. 각 저장소가 자기 소유물만 다루므로 상호 간섭 없음(코드상 각 `Coordinator`/`Box`가 정확히 자신이 만든 `owned` 하나만 참조) | PASS — 코드 구조로 보장, 전용 identity-교체 테스트는 없음(아래 §5-2) |
| 7 | 명시 소유(`player:`) 뷰의 파기 | `Ownership.explicit`일 때 `Coordinator.owned`/`ABOwnedPlayerBox`가 애초에 값을 받지 않으므로 `releaseIfOwned()`의 `guard ... let owned else { return }`가 항상 해당 — **구조적으로 release 호출 자체가 불가능**(단순 플래그가 아니라 옵셔널 부재). `explicitOwnershipNeverReleases`가 `dismantleUIView` 이후 `grade == .current` 유지를 확인 | PASS — 최우선 항목, 전용 테스트 존재 |
| 8 | 화면 전체 종료(호스팅 컨트롤러 해제) | `Coordinator.deinit`/`ABOwnedPlayerBox.deinit`이 `didRelease` 미설정 시 `Task { @MainActor in owned.release() }`로 홉. `deinitReleasesWhenDismantleNeverRuns`/`deinitReleasesUnreleasedPlayer`가 `dismantleUIView`/`releaseIfOwned`를 호출하지 않고 스코프 이탈만으로 `ABWaitUntil`로 `.released` 도달을 관측 | PASS |
| 9 | `release()`가 두 경로로 두 번 | `didRelease` 플래그가 `dismantleUIView`/`releaseIfOwned` 쪽에서 먼저 세팅되면 `deinit`의 홉 자체가 스킵되어 `Task` 생성 자체를 회피(설계가 요구한 "불필요한 Task 생성 회피" 최적화). 설사 플래그가 어긋나도 `ABPlayer.swift:217`의 `guard previousGrade != resolvedGrade || sourceChanged else { return }`가 최종 방어선. `doubleDismantleIsHarmless`/`releaseIfOwnedIsIdempotent`가 실제 이중 호출 경로를 검증 | PASS |
| 10 | 소유 `P`를 관찰하는 SwiftUI 뷰 존재 | `Coordinator`/`ABOwnedPlayerBox`의 어떤 메서드도 `owned.grade`/`.source`/`.isPlaying`을 **직접** 읽지 않는다(`apply`의 멱등성 판단은 자체 저장 `appliedSource`와 비교, `player`의 존재 판단은 자체 저장 `owned` 옵셔널로). `ABPlayerControls.update(_:coordinator:environment:)`도 `view.player`(UIKit 뷰의 비관찰 프로퍼티)만 읽는다 | **부분 PASS — 잔여 리스크 있음, 하단 §5-1 참조** |

## 3. 불변식 I-1~I-4 검증 (완료 정의 2번, 브리프 항목 2)

설계가 지목한 "단언이 약하지 않은가"를 기준으로 확인했다.

- **I-1(생성 1회)**: `mountsWithSourceAtCurrent`, `repeatedUpdatesReuseInstance`(`===` 동일성), `ABOwnedPlayerBoxTests.createsExactlyOnce`. `repeatedUpdatesReuseInstance`는 `configuration`이 다른 값이라도(`.resizeAspectFill` vs 필요시) 재호출이 기존 인스턴스를 반환하는지까지는 검증하지 않지만(둘 다 같은 `configuration` 사용), **핵심 불변식인 "1회만 생성"은 인스턴스 동일성 비교로 직접 단언**되어 약하지 않다.
- **I-2(해제는 identity 소멸 시에만)**: 별도 단정 테스트 없음 — `onDisappear` 미구독이라는 구조 자체가 증명이라는 RESULT §6의 설명에 동의한다. 다만 이는 "약한 테스트"가 아니라 **테스트가 아예 없는 항목**이다. 정적 리뷰로는 구조적 보장을 확인할 수 있으나, "지연 컨테이너에서 스크롤 아웃되어도 재생이 끊기지 않는다"는 제품 요구사항의 실사용 시나리오(`List`/`LazyVStack` cell 재사용)를 UIHostingController 기반으로 재현하는 통합 테스트는 없다. **REQUEST-CHANGES 사유는 아님**(브리프가 요구한 대응 테스트는 "§8의 1·3·7·8번"이며 I-2는 원래 그 목록에 없다 — 설계 §8 표에도 I-2 전용 행이 없다) — 잔여 리스크로만 기록.
- **I-3(남의 것은 건드리지 않는다)**: `explicitOwnershipNeverReleases`. **단언이 강하다** — 단순히 "예외가 안 남" 수준이 아니라 `grade == .current`(해제되지 않았음을 직접 관측)까지 확인한다. §2 시나리오 7 분석대로 코드 구조상(`Ownership.explicit` 케이스에서 `owned`가 애초에 옵셔널 `nil`) 회귀가 사실상 불가능한 설계이므로 테스트는 회귀 조기 발견용 안전망으로 충분하다.
- **I-4(이중 해제 무해)**: `doubleDismantleIsHarmless`, `releaseIfOwnedIsIdempotent`. `grade == .released && source == nil`을 이중 호출 후 확인 — 크래시 부재만이 아니라 상태 정합성까지 단언해 약하지 않다.

## 4. 소스 호환성 / additive-only (브리프 항목 3)

- `git diff -- Tests/ABPlayerKitControlsTests/ABPlayerControlsInitializerAmbiguityTests.swift Tests/ABPlayerKitControlsTests/ABVideoPlayerWithControlsTests.swift`를 직접 확인 — **양쪽 다 순수 추가(append)뿐, 기존 라인 삭제/수정 0건**. 설계 §10 체크리스트의 "무수정"이 문자 그대로 사실이다.
- `ABVideoPlayer.Coordinator`를 이름으로 참조하는 코드가 리포 전체(Sources/Tests/Examples)에 0건임을 grep으로 직접 확인 — CHANGELOG의 "리포 내 0건" 주장과 일치.
- `style:`/`configuration:` Optional 완화 후 이 두 값을 사용하는 기존(미수정) 테스트 파일 11개(`ABControlButtonTests`, `ABControlsLayoutTests`, `ABPlayerControlsSwiftUITests` 등)를 포함해 **`build-for-testing`이 전체 그린** — 컴파일 레벨에서 소스 호환이 실증됐다(§0). `ABPlayerControlsSwiftUITests.swift`의 2-인자 `update(_:coordinator:)` 호출부(`environment` 파라미터 없이)가 신규 3-인자 시그니처의 기본값(`= EnvironmentValues()`)에 그대로 안착함을 직접 확인.
- Optional 완화의 동작 동등성(`nil ?? nil ?? .default == .default`)은 `resolveStyle`/`resolveConfiguration`의 실제 구현(`style ?? environment.playerControlsStyle ?? .default`)과 정확히 일치.

**PASS.**

## 5. 잔여 리스크 (실행 검증 필요)

### 5-1. 시나리오 10 — `set(source:grade:)`/`play()` 내부가 자기 자신의 관찰 프로퍼티를 읽는다 (중간 심각도)

설계 §5 10번과 §7 구현 규칙은 "소유 경로의 `makeUIView`/`updateUIView`/`body`는 `ABPlayer`의 `@Observable` 프로퍼티를 읽지 않는다"를 근거로 "Modifying state during view update류 문제가 발생할 수 없다"고 결론짓는다. 이 근거는 **래퍼 코드(`Coordinator`/`ABOwnedPlayerBox`) 자신의 코드**에는 정확히 들어맞는다 — `apply`의 멱등성 판단은 전부 자체 저장 프로퍼티(`appliedSource`)로 하고, `owned.grade`/`owned.source`를 직접 읽는 줄은 새 코드에 단 한 줄도 없다(grep으로 확인).

다만 이 논증은 **`ABPlayer` 자신의 메서드 내부**까지는 검증하지 않는다. `ABPlayer.swift:20`에서 `grade`/`source`는 `@ObservationIgnored`가 붙지 않은 `@Observable` 추적 프로퍼티이고(코드 직접 확인, `Engine/ABPlayer.swift:26-27`), 새 소유 경로가 동기 호출하는:

- `set(source:grade:)`(`Engine/ABPlayer.swift:214-215`) — `newSource != source`, `let previousGrade = grade`로 **자기 자신의 추적 프로퍼티를 읽은 뒤 같은 호출 안에서 덮어쓴다**(`:231-232`).
- `play()`(`Engine/ABPlayer.swift:273`) — `guard grade == .current`로 추적 프로퍼티를 읽는다.

이 호출들이 **`makeUIView`/`updateUIView`/`body` 평가와 같은 동기 호출 스택 안**(`ABVideoPlayerWithControls.ownedContent`가 `body` 스위치 분기 안에서 직접 호출)에서 일어난다. 기존(round6 이전) 명시 소유 패턴은 이런 호출을 `.task { }`(비동기, 뷰 갱신 트랜잭션 밖)에서 했으므로 이 정확한 조합 — **representable의 update 콜백 안에서 자기 관찰 프로퍼티를 읽고 쓰는 메서드를 동기 호출** — 은 이번 라운드가 처음 도입하는 패턴이다.

실제로 SwiftUI의 "Modifying state during view update, this will cause undefined behavior" 진단이 발동하는지는 런타임에서만 관측 가능한 콘솔 경고이며, 컴파일이나 정적 분석으로는 확인 불가능하다(직접 재현한 빌드 3종 모두 이 문제를 잡아내지 못한다 — 컴파일 타임 검사 대상이 아니다). 다만 이 진단이 실제로 문제가 되려면 보통 "이미 이번 렌더 패스에서 읽은 `@State`/관찰 값을 다시 써서 같은 뷰 트리를 무효화"하는 경우인데, 여기서는 `body`/`makeUIView`가 `player.grade`/`.source` 값으로 **뷰 트리의 모양을 분기하지 않으므로**(어떤 `View`를 만들지 결정하는 데 쓰이지 않음, 순수 부수효과 타깃일 뿐) 실제로 문제가 될 가능성은 낮다고 판단한다 — 그러나 이는 추론이지 실증이 아니다.

새로 추가된 `ABVideoPlayerWithControlsTests.urlMountSharesPlayerInstance`/`urlMountAppliesStyleModifier`가 실제 `UIHostingController` + `layoutIfNeeded()`로 이 정확한 경로(owned 경로의 동기 `set`/`play`)를 이미 실행 가능한 형태로 작성돼 있으나, **테스트 미실행**이므로 콘솔 경고 유무는 확인되지 않았다. → **S-4 게이트가 요청**: 시뮬레이터에서 이 두 테스트를 실행하고 Xcode 콘솔에 "Modifying state during view update" 계열 경고가 없는지 육안 확인할 것(단정문으로 잡히는 종류의 실패가 아니므로 별도 assert 불가 — 콘솔 관찰 필요).

### 5-2. 시나리오 6(identity 교체) 전용 테스트 부재 (낮은 심각도)

시나리오 6("`.id(x)` 변경/if-else 분기 전환")은 §2 표에서 코드 구조로 PASS 판정했지만, 옛 identity 파기와 새 identity 생성이 **같은 트랜잭션 안에서 겹칠 때**(옛 `Coordinator.deinit`의 `Task` 홉이 아직 실행되지 않은 상태에서 새 `Coordinator.player()`가 이미 새 `ABPlayer`를 만들어 재생을 시작하는 것) 실제로 오디오가 짧게 겹치는지(설계 §1.5-4가 이미 "알려진 한계"로 자백한 부분)를 검증하는 테스트는 없다. 설계가 이미 이 한계를 명시적으로 알려진 것으로 문서화했고 별도 트랙(§9-5, `isolated deinit` 전달)으로 이월했으므로 **이번 게이트의 REQUEST-CHANGES 사유는 아니다** — 설계에서 이미 승인된 한계.

### 5-3. 테스트 미실행 (브리프가 이미 인지한 한계)

시뮬레이터 미부팅 상태이며 브리프가 신규 부팅을 금지했으므로, §0에서 직접 재현한 빌드/타입체크 검증을 넘어서는 실제 테스트 실행(184개 기존 + 신규 약 30개)은 이번 게이트에서도 수행하지 못했다. **병합 후 PR CI가 이 책임을 진다** — 브리프 원문과 동일한 결론.

## 6. 설계 이탈 1건 검토 (브리프 항목 4)

RESULT §3이 보고한 "`body`(`@ViewBuilder`) 분기를 일반 함수 `ownedContent(...)`로 분리"는 코드로 직접 확인했다(`ABVideoPlayerWithControls.swift:179-195`). `@ViewBuilder`의 `buildExpression`이 `Void` 반환 문(`owner.apply(...)`)을 `View` 준수 요구로 거부하는 것은 Swift 언어 사실이며, 이 우회는:

- 설계 §7 S-1w의 지시("body에서 `ABPlayerControls`를 구성")를 위반하지 않는다 — `ownedContent`도 여전히 `body`가 호출하는 헬퍼로서 최종적으로 `body`가 반환하는 `some View`를 만든다.
- API 표면에 영향 없음(private 헬퍼).
- 대안(예: `let _ = owner.apply(...)`로 억지로 `View`처럼 위장)보다 명확하고, 코드베이스의 기존 관용구(`ownedControls(for:)`도 별도 `@ViewBuilder` 헬퍼로 분리돼 있음)와 일관적이다.

**타당하다고 판단한다. 승인 사유 불필요 수준의 사소한 구현 디테일.**

## 7. deinit MainActor 홉 (브리프 항목 5)

- `ABVideoPlayer.Coordinator.deinit`, `ABOwnedPlayerBox.deinit` 둘 다 기존 `ABPlayerControls.Coordinator.deinit`(`ABPlayerControls.swift:191-216`, 미수정 기존 코드)과 **동일한 패턴**: `deinit`이 자기 자신의(같은 클래스의) 저장 프로퍼티를 동기적으로 읽는 것은 격리 검사 대상이 아니며(그 순간 다른 참조가 있을 수 없어 배타적 접근이 보장됨), 실제로 격리된 메서드(`release()`/`detach()`)를 호출하려면 `Task { @MainActor in }`로 홉해야 한다는 동일한 이유·동일한 해법을 쓴다.
- `owned`(비-Sendable, `@MainActor` 타입)를 `@Sendable` 클로저(`Task.init`의 요구사항)로 캡처하는 것이 SE-0414(region 기반 격리, "sending" 값 전달)에 의해 허용되며, 이는 §0에서 **직접 재현한 빌드**(`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 포함 3종)로 실증했다 — RESULT의 자기보고를 그대로 신뢰하지 않고 독립적으로 확인한 결과다.
- 기존 선례와의 일관성: 문서화 스타일까지 동일(둘 다 "왜 `MainActor.assumeIsolated`를 안 쓰는가", "왜 홉이 필요한가"를 주석으로 남기지는 않았지만 — `ABPlayerControls.Coordinator.deinit`만 상세 주석이 있고 신규 두 곳은 짧은 doc만 있음. 사소한 비대칭이나 기능적 문제는 아님).
- retain 사이클: `Coordinator`/`ABOwnedPlayerBox` → `owned`(`ABPlayer`) 단방향 참조만 존재. `ABPlayer` → `Coordinator`/`Box`로의 역참조는 코드 어디에도 없음(`ABPlayer`는 이 두 타입을 모른다). 사이클 없음.

**PASS.**

## 8. 주석 위생 (브리프 항목 7)

`grep -nE "C-1|C-2|C-3|I-1|I-2|I-3|I-4|S-1w|S-2w|S-3w|S-4|A-[0-9]|B-[0-9]|D-[0-9]|H-[0-9]|WP[0-9]"`를 전체 신규/수정 SwiftUI 소스 5개 파일에 직접 실행 — **0건**. `onAppear`/`onDisappear`/`.task` 문자열 검색도 실제 modifier 사용 0건, 프로즈 주석("~을 쓰지 않는다"는 서술) 2건만 확인. RESULT §6의 주장과 일치. **PASS.**

## 9. README/CHANGELOG/DocC 정확성 (브리프 항목 8)

- README.md/README.ko.md의 절 제목·순서가 정확히 대응(`grep "^##\|^###"` 비교로 직접 확인) — Quick Start → Customizing → Owning the Player Yourself → UIKit → Advanced 구조가 두 언어판에서 동일.
- `kind:`는 Advanced 절의 의도된 예시(`kind: .hls`) 1곳과 그 설명 문단에만 남고, 나머지 전부 제거됨을 grep으로 확인.
- CHANGELOG의 `### Added`/`### Changed` 서술이 실제 시그니처·동작과 정확히 일치(직접 코드 대조).
- DocC 상호참조("Add Application Controls" 앵커 링크 등)를 `docbuild` 재현으로 검증 — 진단 0건.

**PASS.**

---

## 종합 판정

이번 라운드에서 도입한 소유권 모델은 설계 문서의 10개 시나리오와 4개 불변식을 코드 레벨에서 충실히 구현했다. 가장 중요한 안전장치(I-3: 명시 소유 비해제, I-4: 이중 해제 무해)는 구조적으로(플래그가 아니라 타입 수준 부재로) 보장되며 전용 테스트도 강하다. 파일 경계·소스 호환·주석 위생·문서 정확성 모두 직접 재현으로 확인했다.

유일한 실질적 잔여 리스크는 §5-1(시나리오 10, 소유 경로의 동기 `set`/`play` 호출이 `ABPlayer` 자신의 관찰 프로퍼티 읽기와 겹치는 지점)이며, 이는 정적 리뷰의 한계를 넘는 런타임 관찰이 필요하다. 설계의 논증 자체에 작은 공백(래퍼 코드가 안 읽는다는 것과 `ABPlayer` 내부 메서드가 안 읽는다는 것은 다른 주장)이 있으나, 뷰 트리 분기에 쓰이지 않는다는 구조적 근거로 실제 위험은 낮다고 판단하며, 이미 이 정확한 경로를 실행하는 통합 테스트 2건이 작성돼 있어 CI 1회 실행으로 닫을 수 있는 항목이다. 이는 병합을 막을 사유가 아니라 병합 직후 CI에서 확인할 잔여 리스크다.

### 병합 후 CI에 요청할 것
1. `ABVideoPlayerWithControlsTests.urlMountSharesPlayerInstance`/`urlMountAppliesStyleModifier` 실행 시 콘솔에 "Modifying state during view update" 계열 경고가 없는지 확인.
2. 기존 184개 Controls 테스트 + 신규 약 30개 전체 실행 통과 확인(RESULT §10의 마지막 미확인 항목).

FINAL-VERDICT: APPROVE
