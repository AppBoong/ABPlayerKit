# RESULT: 라운드6 트랙 S — fix1 (PR #4 `build-and-test` 실패 수정)

담당: Sonnet. 브랜치 `round6/swiftui`. 입력: `BRIEF-round6-swiftui-fix1.md`. **커밋하지 않았음** — 작업 트리 변경만.

---

## 1. 가설 검증

브리프의 가설: "신규 `url:`/`source:` 편의 생성자의 `autoplay` 기본값이 `true`라서, `UIHostingController`+`UIWindow`로 마운트하는 테스트가 실제 `AVPlayer` 재생을 시작하고, 그 실제 재생이 메인 액터를 오래 점유해 같은 액터에서 병렬 실행되는 형제 테스트들이 굶는다."

**검증 결과: 가설이 맞았다 — 다만 정확한 메커니즘은 "메인 액터 점유"가 아니라 "해소 불가능한 원격 호스트에 대한 무기한 재생 재시도"였다.**

### 확인한 사실

1. `Tests/ABPlayerKitControlsTests/ABVideoPlayerWithControlsTests.swift`의 신규 테스트 2개(`urlMountSharesPlayerInstance`, `urlMountAppliesStyleModifier`, 브리프가 지목한 `:124`)는 `ABVideoPlayerWithControls(url: URL(string: "https://example.com/...")!)`를 `autoplay:` 인자 없이(기본값 `true`) `UIHostingController`+`UIWindow`로 실제 마운트한다. `ABOwnedPlayerBox.apply(source:autoplay:)`는 이 값이 `true`면 실제 `ABPlayer.play()`를 호출한다 — 페이크가 아닌 진짜 `AVPlayer`다.
2. `ABPlayer.swift:272`의 `play()`는 `target.play()` → `avPlayer.rate = desiredRate`를 호출할 뿐, **타임아웃이 없다.** 반면 같은 파일의 프리롤(`armPreroll`, `ABPlayer.swift:541-560`)은 `configuration.prerollTimeout`(기본 10초)으로 상한이 있다. 즉 등급만 `.current`로 승격하는 것(프리롤)은 유한 시간 안에 끝나지만, **`play()`까지 호출하면 존재하지 않는 원격 호스트에 대해 AVFoundation이 무기한 재연결/버퍼링을 시도**하며 이 두 테스트 어디에도 `player.release()`나 `dismantleUIView` 호출이 없어 그 재생 플레이어가 테스트 스위트가 끝날 때까지 살아서 계속 시도한다.
3. 이 두 테스트는 `ABPlayerKitControlsTests`의 **다른** 스위트(사전부터 있던 `ABPlayerControlsSwiftUITests` 등)와 xctest 번들을 공유한다 — Swift Testing이 병렬 실행하더라도 전부 같은 프로세스, 같은 CPU 예산을 공유한다. 로컬 10코어 머신에서는 여유가 있어 드러나지 않지만, CI의 3 vCPU 러너에서는 두 개의 "무기한 네트워크 재시도" 백그라운드 작업이 실제 CPU/스레드를 지속적으로 점유해 나머지 11개 호스팅 테스트(그리고 그 스위트들의 180초 제한)를 굶겼다 — 브리프가 관측한 "기존 테스트까지 함께 멎었다"와 정확히 일치한다.
4. **감사 중 같은 패턴 2건을 추가로 발견**했다 — 브리프가 지목한 11개 목록에는 없지만 근본 원인이 동일하다:
   - `Tests/ABPlayerKitControlsTests/ABOwnedPlayerBoxTests.swift`의 `applyIsIdempotent`: `https://example.com/owned-box-test.mp4`에 `autoplay: true`로 재생을 시작하고 릴리스하지 않는다. `ABPlayerKitControlsTests`와 같은 번들이라 같은 위험을 공유한다.
   - `Tests/ABPlayerKitTests/ABVideoPlayerOwnershipTests.swift`의 `urlChangeReusesInstanceAndReapplies`: 소스를 `https://example.com/second.mp4`로 바꾸며 `autoplay: true`로 재생을 시작한다. `ABPlayerKitTests` 번들 소속이라 브리프가 지목한 `ABPlayerKitControlsTests`와는 다른 번들이지만 동일한 메커니즘이며, 방치하면 다음 CI 실행에서 같은 클래스의 실패를 재현할 수 있는 잠재 위험이었다.

가설이 지목한 정확한 두 테스트뿐 아니라, "실제 도달 불가능한 URL에 대해 `autoplay: true`로 재생을 남겨둔다"는 동일 클래스의 결함이 이 트랙이 이번 라운드에 추가한 테스트 중 총 4곳에 있었다.

---

## 2. 확정 원인

**신규 테스트가 실제(가짜가 아닌) `AVPlayer`로, 해소 불가능한 원격 URL에 대해 무기한 재생 재시도를 시작시키고, 릴리스하지 않은 채 남겨둔다.** `play()`에는 프리롤과 달리 자체 타임아웃이 없으므로 이 재생 시도는 스위트가 끝날 때까지(또는 프로세스가 끝날 때까지) 계속되며, CI의 제한된 CPU 예산 아래에서 같은 프로세스의 다른 모든 스위트를 실행 지연시켜 180초 제한을 넘겼다. 제품 코드(`ABPlayer`/`ABOwnedPlayerBox`/`ABVideoPlayer.Coordinator`)에는 결함이 없다 — `autoplay: true`가 실제로 `play()`를 호출하는 것은 설계된 동작이고, 문제는 테스트가 그 결과로 생기는 실제 재생을 도달 불가능한 네트워크 자원에 대해 무기한 방치한다는 점이었다.

---

## 3. 적용한 수정

파일 경계 준수: `Sources/ABPlayerKit/Engine/ABPlayer.swift`·`ABAVPlaybackTarget.swift`·`Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift` 무수정. 테스트 파일 3개만 수정했다(`git status` 결과는 §5 참고). 타임아웃 숫자는 건드리지 않았다.

### `Tests/ABPlayerKitControlsTests/ABVideoPlayerWithControlsTests.swift`

`urlMountSharesPlayerInstance`/`urlMountAppliesStyleModifier` 둘 다 `ABVideoPlayerWithControls(url:autoplay: false, ...)`로 변경. 이 두 테스트가 검증하는 것은 **소유권 identity 공유**(`controlsView?.player === videoView?.player`)와 **modifier가 합성 뷰를 관통하는지**(`controlsView?.style == .minimal`)이며, 둘 다 재생 시작 여부와 무관하다 — `autoplay: false`로도 플레이어는 여전히 생성·소유·부착(`grade == .current`)되므로 검증 대상 자체는 그대로 확인된다. "`autoplay: true`가 실제로 재생을 시작하는가"라는 별도 질문은 `Tests/ABPlayerKitTests/ABVideoPlayerOwnershipTests.swift`의 `autoplayControlsPlaybackStart`가 이미 격리해서 검증하고 있다 — 로컬 번들 리소스 `tiny.mp4`(네트워크 없음)를 쓰므로 이 문제와 무관하다.

### `Tests/ABPlayerKitControlsTests/ABOwnedPlayerBoxTests.swift`

공유 `url` 프로퍼티를 원격 URL에서 **존재하지 않는 로컬 파일 URL**(`/private/tmp/abplayerkit-owned-box-test-<uuid>.mp4`)로 교체 — 이 리포에 이미 있는 관용구(`ABAVPlaybackTargetWaitUntilReadyTests`의 "nonexistent file URL resolves to .failed" 테스트, `ABAVPlaybackTargetReadyWaitTests.swift:230`)와 동일 패턴이다. `AVPlayer.play()`는 항목 유효성과 무관하게 `rate`를 동기적으로 설정하므로 `applyIsIdempotent`가 필요로 하는 `isPlaying` 전이는 그대로 관측되지만, 로컬 파일 부재는 원격 호스트 미해결과 달리 즉시 실패해 무기한 재시도가 없다.

### `Tests/ABPlayerKitTests/ABVideoPlayerOwnershipTests.swift`

`urlChangeReusesInstanceAndReapplies`의 두 번째 소스를 원격 URL 대신 **첫 번째 로컬 픽스처(`tiny.mp4`)를 런타임에 임시 디렉터리로 복사한 두 번째 로컬 파일**로 교체(`FileManager.copyItem` + `defer`로 정리). 원래 설계(§8 시나리오 3 "url 변경 → 인스턴스 동일, source.url 갱신, autoplay 재적용")가 요구하는 "실제로 다른 URL로 바뀌고, 그 새 소스에 대해 autoplay가 재적용되어 진짜 재생이 시작된다"는 검증을 네트워크 의존 없이 그대로 보존한다.

---

## 4. 3회 연속 실행 결과

시뮬레이터 재사용: `iPhone 17 Pro`, UDID `55A3A4F3-3F02-43E6-9B23-116BD15D3345`(브리프 지정, 신규 부팅 없음 — 매 실행 전후 `xcrun simctl list devices | grep Booted` 확인, 목록에 변화 없음). 매번 `xcodebuild test -scheme ABPlayerKit-Package -destination 'id=...'`(`-only-testing` 미사용, 전체 스킴) + `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`.

| 실행 | 결과 | 실패 수(`✘`) | `ABPlayerKitControlsTests` 번들(200 테스트/26 스위트) 소요 | 전체 4개 번들 테스트 수 | xcodebuild 전체 wall time |
|---|---|---|---|---|---|
| 1 | **PASSED** | 0 | **1.174초** | 39+200+8+185 = 432 | 59.65s (빌드 포함) |
| 2 | **PASSED** | 0 | **3.017초** | 432 | 81.67s (빌드 포함) |
| 3 | **PASSED** | 0 | **1.198초** | 432 | 23.43s (빌드 포함) |

수정 전(브리프 보고): 동일 스위트가 CI(3 vCPU)에서 **180초 제한을 초과**(11개 테스트 전부). 수정 후: 로컬(부팅된 시뮬레이터) 3회 전부 **1.174~3.017초**로 완료 — 두 자릿수 배율의 여유. 이전 세션에서 로컬 10코어 머신이 "빠르니 문제가 안 보였다"는 브리프의 관측과 일관되게, 이번에도 로컬에서는 원인 수정 전에도 즉시 실패로 재현되지는 않았다(자원이 넉넉해서). 그래서 수정 검증은 로컬 소요시간의 절대적 크기(180초에 비해 여유가 매우 큼)와 §1~§3의 원인 분석·수정 내용으로 뒷받침한다 — CI의 3 vCPU 조건 자체를 로컬에서 재현하지는 못했다는 점을 명시해 둔다.

`✘`(실패) 0건, `✔ Test`/`✔ Suite` 전부 통과. 3회 모두 `** TEST SUCCEEDED **`.

### 부가 검증

- `swiftlint lint --strict`: **0 violations, 0 serious** (120 files).
- `xcodebuild build-for-testing -scheme ABPlayerKit-Package -destination 'id=...' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`: **TEST BUILD SUCCEEDED**, 경고 0.

---

## 5. 파일 경계 확인

```
$ git status --porcelain
 M Tests/ABPlayerKitControlsTests/ABOwnedPlayerBoxTests.swift
 M Tests/ABPlayerKitControlsTests/ABVideoPlayerWithControlsTests.swift
 M Tests/ABPlayerKitTests/ABVideoPlayerOwnershipTests.swift
?? docs/briefs/BRIEF-round6-swiftui-fix1.md
```

`ABPlayer.swift`/`ABAVPlaybackTarget.swift`/`ABPlayerControlsView.swift` 무수정. 테스트 파일 3개만 손댔다(브리프가 지목한 2개 파일 + 감사로 발견한 1개 추가 파일). Sources 아래 SwiftUI 파일은 이번 수정에서 건드리지 않았다 — 문제가 테스트에만 있었기 때문이다.

---

## 6. 게이트 문의 사항

없음. 가설은 맞았고, 원인·수정·검증 모두 브리프가 요청한 범위 안에서 끝났다. 다만 브리프가 지목한 2개 테스트 외에 동일 패턴 2건(§1-4)을 추가로 발견해 함께 고쳤다는 점은 게이트가 diff 리뷰 시 참고할 수 있도록 여기에 명시해 둔다 — 요청 범위를 벗어난 수정이라 판단되면 되돌릴 수 있는 위치(`ABOwnedPlayerBoxTests.swift`의 `url` 프로퍼티, `ABVideoPlayerOwnershipTests.swift`의 `urlChangeReusesInstanceAndReapplies`)를 명확히 남겨두었다.
