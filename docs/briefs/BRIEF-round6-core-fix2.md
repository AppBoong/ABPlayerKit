# BRIEF: 라운드6 트랙 A — PR #3 CI 실패 수정 (fix2)

PR #3(`round6/core`)의 CI가 3개 잡 모두 실패했다. **전부 실제 결함이며 플레이크가 아니다.** 로컬에서 `-only-testing:ABPlayerKitTests`만 돌렸기 때문에 놓쳤다.

## 실패 목록 (관측 사실)

### (1) lint — `function_parameter_count`
```
Sources/ABPlayerKit/StateMachine/ABBufferingEvaluator.swift:5:12: error:
Function should have 5 parameters or less: it currently has 6
```

### (2) `ABLoopRestartTests` — 타이밍 의존 단언
```
✘ ".playedToEnd broadcasts even for a looped item, exactly once"
   ABLoopRestartTests.swift:84: (events.filter { $0 == .playedToEnd }.count → 4) == 1
   (TSan 잡에서는 → 30)
```
루프가 실제로 재생을 재개하므로 아이템이 반복해서 끝에 도달하고 `.playedToEnd`가 그만큼 방송된다.
머신 속도에 따라 4회·30회로 달라진다. 로컬에서는 전체 실행이 0.6초로 끝나 한 번도 반복되지 않아 우연히 통과했다.

### (3) Controls 특성화 테스트 2건 — 신규 이벤트가 정확한 시퀀스 단언을 깨뜨림
```
✘ ABControlsPlayPauseReentrancyCharacterizationTests.swift:63
   recorded → [..., player(gradeChanged(...)), player(bufferingChanged), controls(playPauseTapped(...))]
✘ ABControlsPlayPauseReentrancyCharacterizationTests.swift:94
   recorded → [player(bufferingChanged), controls(playPauseTapped(isPlayingAfterTap: false))]
```
이 테스트들은 이벤트 시퀀스를 **정확히** 단언한다. A-6w가 추가한 `bufferingChanged`가 그 사이에 끼면서 깨졌다.
이벤트 추가는 additive지만, 정확 시퀀스를 검증하는 특성화 테스트는 영향을 받는다.

### (4) `ABPlayerControlsViewTests` — auto-hide 스케줄 상태
```
✘ "Given duration disappears during scrubbing, controls always end the session"
   ABPlayerControlsViewTests.swift:373: view.hasScheduledAutoHide → false (true를 기대)
```

## 과제

1. **(1) lint**: `ABBufferingEvaluator.isBuffering`의 파라미터 6개를 **규칙을 끄지 말고** 구조적으로 해결하라.
   입력 신호를 값 타입 하나(예: `ABBufferingSignals`)로 묶는 것이 자연스럽다. 순수 함수의 표 테스트 가능성은 유지할 것.
   `.swiftlint.yml`을 고쳐 규칙을 무력화하는 방식은 금지 — 그 규칙은 이번 라운드에 의도적으로 켠 것이다.

2. **(2) 루프 테스트**: 단언을 머신 속도에 의존하지 않게 고쳐라. 무엇이 이 테스트의 진짜 불변식인지 먼저 판단하라 —
   "루프 중에도 `.playedToEnd`가 방송된다"인지, "한 사이클당 정확히 1회"인지. 후자라면 사이클 경계를 제어할 수 있는
   방식으로(예: 첫 방송 직후 루프를 끄거나, 관찰 창을 한 사이클로 한정) 결정적으로 만들어라.
   **단순히 `>= 1`로 완화해 의미를 잃게 하지 말 것** — 무엇을 보장하는 테스트인지 주석에 불변식으로 서술하라.

3. **(3) Controls 특성화 테스트**: 이 수정을 위해 **`Tests/ABPlayerKitControlsTests/` 수정을 이번에 한해 허용한다**
   (원 브리프의 파일 경계 예외). 단 최소 범위로, 그리고 테스트의 **원래 의도를 보존**하는 방향으로 고쳐라.
   이 테스트들이 검증하려던 것은 "재진입 시 이벤트 순서"이지 "이벤트 총 개수"가 아니므로, 신규 이벤트를 걸러내고
   관심 있는 이벤트만 비교하는 편이 의도에 부합할 가능성이 높다 — 다만 직접 코드를 읽고 판단하라.
   기대값에 `bufferingChanged`를 그냥 끼워 넣는 방식은 앞으로 이벤트가 추가될 때마다 같은 실패를 재생산하므로 피하라.

4. **(4) auto-hide 스케줄 실패**: **먼저 원인을 규명하라.** 이것이 트랙 A의 변경(관찰성 미러, `isPlaying` 갱신 시점,
   `bufferingChanged` 방송) 때문에 생긴 실제 회귀인지, 아니면 테스트가 기존에 우연히 성립하던 조건에 의존했는지 판단하라.
   **실제 회귀라면 프로덕션 코드를 고쳐야 한다** — 테스트를 기대값에 맞추지 말 것.
   `ABPlayerControlsView.swift`는 트랙 C 소관이지만, 진짜 회귀로 확인되면 최소 범위 수정을 허용한다(사유를 문서에 남길 것).

## 검증 (이번엔 반드시)

부팅된 시뮬레이터가 있다(iPhone 17 Pro, UDID `55A3A4F3-3F02-43E6-9B23-116BD15D3345`, 새로 부팅·생성 금지).

- **전체 스킴 테스트를 실행하라** — `-only-testing`으로 좁히지 말 것. 4개 타깃 전부.
- 최소 **3회 연속 그린**을 확인하라((2)의 타이밍 의존성 때문에 1회로는 부족하다).
- `swiftlint lint --strict`를 로컬에서 실행해 0 violations를 확인하라(없으면 `brew install swiftlint`).
- Swift 6 zero-warning 유지.

## 산출물

`docs/briefs/RESULT-round6-core-fix2.md` — 4건 각각의 원인·수정·근거, 파일 경계 예외를 쓴 지점과 사유,
전체 스위트 3회 실행 결과. **커밋 금지.** 이 파일 작성이 완료 신호다.
