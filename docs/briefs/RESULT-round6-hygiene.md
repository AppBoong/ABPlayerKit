# RESULT: 라운드6 H-1w — 소스 주석의 내부 문서·리뷰 ID 인용 제거

브랜치 `round6/hygiene`, worktree `/Users/jymac/Documents/GitHub/ABPlayerKit/.claude/worktrees/agent-a98ce2790a528eda7`.

## 1. 변경한 파일 목록과 파일별 인용 줄 수

`BRIEF-round6-hygiene.md` §2의 grep으로 확보한 인벤토리 기준, 파일별 인용 매치 줄 수(합계 85):

| 줄 수 | 파일 |
|---:|---|
| 20 | `Sources/ABPlayerKit/Engine/ABPlayer.swift` |
| 9 | `Sources/ABPlayerKitCache/ABCacheStore.swift` |
| 6 | `Sources/ABPlayerKitControls/SwiftUI/ABPlayerControls.swift` |
| 3 | `Sources/ABPlayerKitControls/Model/ABControlsTimeLabelFormatter.swift` |
| 3 | `Sources/ABPlayerKit/Policy/ABAudioSession.swift` |
| 3 | `Sources/ABPlayerKit/Model/ABPlayerConfiguration.swift` |
| 3 | `Sources/ABPlayerKit/Model/ABPlaybackTuning.swift` |
| 3 | `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift` |
| 2 | `Sources/ABPlayerKitControls/SwiftUI/ABAccessoryHostingBox.swift` |
| 2 | `Sources/ABPlayerKitCache/ABCacheConfiguration.swift` |
| 2 | `Sources/ABPlayerKit/View/ABPlayerView.swift` |
| 2 | `Sources/ABPlayerKit/StateMachine/ABGradePlanner.swift` |
| 2 | `Sources/ABPlayerKit/Presentation/ABTimeFormatter.swift` |
| 2 | `Sources/ABPlayerKit/Policy/ABInterruptionPolicy.swift` |
| 2 | `Sources/ABPlayerKit/Policy/ABAudioInterruptionObserver.swift` |
| 2 | `Sources/ABPlayerKit/Policy/ABApplicationStateObserver.swift` |
| 2 | `Sources/ABPlayerKit/Observation/ABObservationToken.swift` |
| 2 | `Sources/ABPlayerKit/Observation/ABObservationBag.swift` |
| 2 | `Sources/ABPlayerKit/Model/ABPlayerError.swift` |
| 2 | `Sources/ABPlayerKit/Engine/ABPlaybackTarget.swift` |
| 1 | `Sources/ABPlayerKitMetrics/Session/ABPlaybackSessionAccumulator.swift` |
| 1 | `Sources/ABPlayerKitControls/SwiftUI/ABVideoPlayerWithControls.swift` |
| 1 | `Sources/ABPlayerKitControls/StateMachine/ABControlsPresenter.swift` |
| 1 | `Sources/ABPlayerKitControls/Model/ABPlayerControlsConfiguration.swift` |
| 1 | `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/CustomizingControls.md` |
| 1 | `Sources/ABPlayerKit/View/ABFirstFrameDetector.swift` |
| 1 | `Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift` |
| 1 | `Sources/ABPlayerKit/Policy/ABAudioSessionCoordinator.swift` |
| 1 | `Sources/ABPlayerKit/Observation/ABPlayerEvent.swift` |
| 1 | `Sources/ABPlayerKit/Model/ABPlaybackGrade.swift` |
| 1 | `Sources/ABPlayerKit/Engine/ABAssetFactory.swift` |
| **85** | **합계 (31개 파일)** |

**브리프 §2의 "85줄 / 25파일"과의 차이**: 브리프 §2의 grep을 그대로 재현하면 85줄은 정확히 일치하지만 파일 수는 25가 아니라 **31**이었다(`grep -rl`로 직접 확인). 브리프의 파일 수 표기가 재현 명령의 실제 출력과 다른 것으로 보이나, 재현 명령 자체(85줄)는 정확히 일치하므로 grep 결과를 그대로 신뢰하고 31개 파일 전부를 처리했다. 커밋에는 이 31개 파일(스위프트 30 + DocC md 1)이 전부 포함된다.

`git diff --stat origin/main -- Sources/`: **31 files changed, 195 insertions(+), 212 deletions(-)**.

## 2. §4-1 코드 무변경 증명 — 원본 출력

```
$ git diff origin/main -- Sources/ | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-]\s*(///|//|\*)'
-Internally this hosts your content in a `UIHostingController` that `ABAccessoryHostingBox` attaches as a child of the nearest `UIViewController` it can find by walking up from the controls view once it's actually in a window (see `DESIGN-OPEN-QUESTIONS.md` Q6-A for why this exists — an original design consideration behind this project's playback engine hit this same hosting problem and originally settled on UIKit-only overlays specifically to avoid it). **If no `UIViewController` is found** (an unusual hosting setup with no view controller anywhere in the view hierarchy), the accessory view still lays out and renders — but safe-area propagation, `UIViewController` appearance callbacks, and trait inheritance into the hosted content are not guaranteed. The `accessoryViews: [UIView]` initializers above stay the safer choice when you need those guarantees without a real, or reachable, view controller.
+Internally this hosts your content in a `UIHostingController` that `ABAccessoryHostingBox` attaches as a child of the nearest `UIViewController` it can find by walking up from the controls view once it's actually in a window — attaching as a real child view controller, rather than just embedding its view, is what gives the hosted content safe-area propagation, `UIViewController` appearance callbacks, and trait inheritance for free. **If no `UIViewController` is found** (an unusual hosting setup with no view controller anywhere in the view hierarchy), the accessory view still lays out and renders — but those three guarantees do not hold. The `accessoryViews: [UIView]` initializers above stay the safer choice when you need those guarantees without a real, or reachable, view controller.
```

이 두 줄은 브리프 §4-1이 명시한 예외 대상, `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/CustomizingControls.md`(2-3의 DocC 1건)의 산문 줄이다 — `.md` 파일이라 `///`/`//`/`*` 접두사가 없어 필터에 걸리지 않는다. 브리프 지시대로 이 파일만 별도로 `git diff origin/main -- Sources/ABPlayerKitControls/ABPlayerKitControls.docc/`로 육안 확인했다: 변경분은 그 산문 문단 하나뿐이고, 코드 블록(````swift` 예제)은 변경 없음. 그 외 `.swift` 파일에서는 이 명령의 출력이 없다 — 즉 `///`/`//`/`*` 로 시작하지 않는 diff 라인은 이 DocC 문단이 유일하며, 코드 라인 변경은 0줄이다.

## 3. §4-2 위생 재스캔 — 원본 출력 + exit code

```
$ grep -rnE '(DESIGN|PLANNING|REVIEW|ROADMAP|HANDOFF)[^ ]*\.md|round ?[0-9]|Round ?[0-9]|Phase [0-9]|§[0-9]' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
exit=1
```

(출력 없음, `exit=1` — grep 매치 없음. 리베이스 후 재실행한 결과이며, `git rebase origin/main`은 "Current branch round6/hygiene is up to date"로 변경 없이 통과했다 — 이 worktree가 이미 `origin/main`의 최신 tip에서 분기했기 때문이다.)

## 4. §4-3 전체 스킴 테스트 3회 연속

공유 시뮬레이터 `iPhone 17 Pro Max` (`60DA735B-87EC-4159-9BE3-EF981A127FAF`, 이미 Booted 상태 확인 후 재사용, 재부팅 없음)로 `xcodebuild -scheme ABPlayerKit-Package -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' test`를 3회 연속 실행.

각 실행의 서브셋별 `Test run with N tests in M suites passed` 합과 최종 결과:

| 실행 | Cache | Controls | Metrics | NowPlaying | Core | 합계 | 결과 |
|---|---:|---:|---:|---:|---:|---:|---|
| 1회 | 72 | 322 | 49 | 31 | 269 | **743** | `** TEST SUCCEEDED **` (exit 0) |
| 2회 | 72 | 322 | 49 | 31 | 269 | **743** | `** TEST SUCCEEDED **` (exit 0) |
| 3회 | 72 | 322 | 49 | 31 | 269 | **743** | `** TEST SUCCEEDED **` (exit 0) |

3회 모두 기대치 743건과 정확히 일치, 3회 모두 그린. `-only-testing` 없이 스킴 전체(`ABPlayerKit-Package`)를 돌렸다. 각 실행 사이 시뮬레이터는 재부팅하지 않고 동일 인스턴스를 재사용했다(`xcrun simctl list devices`로 실행 전후 동일 UDID의 Booted 상태 확인).

1회차 원본 로그 발췌:
```
✔ Test run with 72 tests in 8 suites passed after 0.091 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.797 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.057 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.016 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.285 seconds.
** TEST SUCCEEDED **
```
2회차:
```
✔ Test run with 72 tests in 8 suites passed after 0.082 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.507 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.055 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.016 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.305 seconds.
** TEST SUCCEEDED **
```
3회차:
```
✔ Test run with 72 tests in 8 suites passed after 0.075 seconds.
✔ Test run with 322 tests in 39 suites passed after 0.530 seconds.
✔ Test run with 49 tests in 10 suites passed after 0.043 seconds.
✔ Test run with 31 tests in 4 suites passed after 0.016 seconds.
✔ Test run with 269 tests in 41 suites passed after 0.294 seconds.
** TEST SUCCEEDED **
```

## 5. 판단이 어려웠던 인용

- **`ABTimeFormatter.swift:17`의 `— see §2.3)`**: 어느 문서의 §2.3인지 코드에서 식별할 수 없었다(주변 문맥은 `DESIGN-v0.2-CONTROLS.md`를 가리켰던 §5.4와는 별개의 참조로 보이나, 어느 문서인지 특정 불가). 추측해서 문서명을 지어내는 대신, 그 인용을 제거해도 문장이 이미 자립하는지 확인한 뒤(주변 문맥이 "이 타입이 `ABShortsKit`과 공유되도록 public인 이유"를 충분히 설명하고 있었다) 인용만 제거했다. 정보 손실은 "§2.3에 더 자세한 논의가 있다"는 포인터뿐이며, 그 포인터가 가리키던 실질적 내용은 복원할 수 없었다.
- **`ABPlaybackSessionAccumulator.swift:56`의 `F-1w brief §9`**: 이 브리프 문서 자체에 접근할 수 없어 §9의 정확한 논거를 복원할 수 없었다. 다만 해당 문장("legacy 이벤트는 v1과 동일한 지점에서 recorder가 직접 발행한다")이 이미 불변식을 완결된 형태로 서술하고 있어, 인용을 제거해도 정보 손실이 없다고 판단했다.
- **`ABAccessoryHostingBox.swift`의 Q6/Q6-A 전체 구조**: 이 파일의 타입 doc 코멘트는 "Q6가 제기한 실패 모드들을 전부 명시적으로 처리한다"는 문장으로 시작해 1~5번 항목을 나열하는 구조였다. `DESIGN-OPEN-QUESTIONS.md` Q6-A 인용은 grep에 걸린 6번째 줄뿐이었지만, 그 정의를 제거하면 이후 10번째 줄("Q6 raised")과 40번째 줄("Q6's original risk")이 정의되지 않은 "Q6"를 가리키는 채로 남아 주석이 자기모순적이 된다. 브리프 §3의 자립성 원칙에 따라 이 두 줄도 함께 고쳤다 — grep이 잡아내지 못하는 범위지만, 나열된 실패 모드 1~5번이 곧 "Q6가 제기한 것"의 전체 내용이므로 "Q6"라는 라벨 자체가 그 목록과 중복이었다. 정보를 지어내지 않고 이미 있는 목록을 가리키는 표현으로 바꿨다.
- **`ABControlsPresenter.swift:149` 주변**: "Round4 review MJ-3: an earlier version branched on..." 문단에 "pre-extraction `togglePlayback`"과 "이 decomposition 전체가 지켜야 하는 'pure move' 원칙"이라는, grep에 안 걸린 부가 서술이 섞여 있었다. 핵심 버그 서술(과거형 → "이렇게 했다면 이런 일이 벌어진다" 가정법)은 브리프 예시 2 그대로 변환했지만, "pure move 원칙" 같은 리팩터링 정책 문구는 검증 불가능한 내부 프로세스 언급이라 판단해 드롭했다 — 정보 손실이지만, 코드 자체가 증명하는 불변식(라이브 값을 읽어야 buffering 중 정확하다)은 온전히 유지했다.

## 6. 브리프를 벗어난 변경

- `ABAccessoryHostingBox.swift`의 40번째 줄("Q6's original risk")은 grep 인벤토리(85줄)에 포함되지 않았지만, 위 §5에서 설명한 자기모순을 피하기 위해 함께 수정했다. 이 줄은 "round/Phase/§/문서명" 패턴에 걸리지 않아(§4-2 재스캔에서도 잡히지 않음) 위생 재스캔 결과에는 영향이 없다.
- 그 외 코드/식별자/포매팅 변경은 없다. `swift build`(호스트 macOS, iOS SDK 없음)는 `ABApplicationStateObserver.swift`의 `import UIKit`에서 예상된 "no such module 'UIKit'" 오류로 실패했지만 이는 이 작업과 무관한 플랫폼 문제이며, §4-3의 `xcodebuild`(iOS 시뮬레이터 대상) 3회 실행 전부가 그린이므로 실제 컴파일 가능성은 검증됐다.
