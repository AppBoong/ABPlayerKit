# RESULT: 라운드6 트랙 A — PR #3 CI 실패 수정 (fix2)

`docs/briefs/BRIEF-round6-core-fix2.md` 지시대로 4건 전부 수정. 커밋 없음.

## 요약

| # | 원인 | 분류 | 수정 위치 |
|---|---|---|---|
| 1 | `ABBufferingEvaluator.isBuffering`가 파라미터 6개 | 정적 결함(lint) | `Sources/ABPlayerKit/StateMachine/ABBufferingEvaluator.swift`, 호출부(`ABPlayer.swift`), 테스트 |
| 2 | 루프가 실제로 재생을 재개해 `tiny.mp4`가 반복 재생되며 `.playedToEnd`가 머신 속도만큼 방송됨 | 테스트의 타이밍 의존 단언 | `Tests/ABPlayerKitTests/ABLoopRestartTests.swift` |
| 3 | 신규 `bufferingChanged`가 재진입 이벤트의 정확 시퀀스 단언 사이에 끼어듦 | 테스트가 추가적(additive) 이벤트에 안 열려있었음 | `Tests/ABPlayerKitControlsTests/ABControlsPlayPauseReentrancyCharacterizationTests.swift` |
| 4 | 테스트가 `player.isScrubbing`을 "컨트롤스가 스크럽 종료 처리를 끝냈다"의 대리 신호로 오용 — 인과적으로 보장되지 않는 타이밍 가정 | 테스트의 동기화 지점 오류(프로덕션 회귀 아님) | `Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift` |

---

## 1. `ABBufferingEvaluator` 파라미터 수

**원인**: `isBuffering(hasItem:intendsToPlay:timeControlStatus:isWaitingWithNoItem:isPlaybackLikelyToKeepUp:isPlaybackBufferEmpty:)` — 6개 파라미터, SwiftLint `function_parameter_count` 기본 상한(5) 초과.

**수정**: `ABBufferingSignals`(6개 필드를 묶은 `Equatable` 값 타입)을 신설하고 `isBuffering(_ signals: ABBufferingSignals) -> Bool`로 단일 파라미터화. 순수성·표 테스트 가능성 불변 — 판정 로직 자체는 한 글자도 바뀌지 않았고, 입력을 어떻게 전달받는지만 바뀌었다.

- `Sources/ABPlayerKit/StateMachine/ABBufferingEvaluator.swift`: `ABBufferingSignals` 추가, `isBuffering` 시그니처 변경.
- `Sources/ABPlayerKit/Engine/ABPlayer.swift`(`refreshPlaybackMirrors()`): 호출부를 `ABBufferingEvaluator.isBuffering(ABBufferingSignals(...))`로 갱신.
- `Tests/ABPlayerKitTests/ABBufferingEvaluatorTests.swift`: 4개 테스트 전부 새 시그니처로 갱신(표 테스트 커버리지·기대값 불변, 호출 형태만 변경).

`.swiftlint.yml`은 건드리지 않았다(규칙 무력화 금지 준수).

---

## 2. `ABLoopRestartTests` 타이밍 의존 단언

**원인**: `playedToEndBroadcastsOnceForLoopedItem`이 `target.play()`로 실제 재생을 시작한 뒤 수동으로 `.AVPlayerItemDidPlayToEndTime`을 1회 포스트했다. 그런데 `isLooping == true`인 `ABAVPlaybackTarget.didPlayToEnd` 핸들러는 그 뒤 실제로 `seekToStart()` → `avPlayer.play()`를 호출해 **진짜 재생을 재개**한다 — 이것이 A-1w가 고친 정확한 동작이다. `tiny.mp4`가 짧기 때문에, 테스트가 이어서 수행하는 두 번의 `waitUntil` 폴링 동안 아이템이 실제로 여러 번 끝에 도달해 `.playedToEnd`가 반복 방송된다. 로컬(0.6초 실행)에서는 우연히 0회 반복으로 끝나 통과했을 뿐, 느린/부하가 걸린 러너에서는 4회·30회로 벌어진다.

**진짜 불변식 판단**: "루프 중에도 `.playedToEnd`가 방송된다"가 아니라, **"매 end-of-item마다 정확히 1회, 그리고 루프 재시작이 시작되기 전에 방송된다"**이다 — 이 테스트 이름 자체가 그렇게 말하고 있다. `>= 1`로 완화하면 그 의미(루프 재시작 로직이 `.playedToEnd`를 삼키지 않는다는 것, 그리고 중복 방송하지 않는다는 것)를 잃는다.

**수정**: 사이클 경계를 결정적으로 제어했다 — (1) `target.play()` 호출을 제거해 실제 재생이 애초에 시작되지 않게 했다(이 테스트는 재개 자체를 검증하지 않는다 — 그건 `loopedEndOfItemResumesPlayback`의 몫이다). (2) 첫 `.playedToEnd`를 관측한 순간 `target.onEvent` 콜백 안에서 `setLooping(false)`를 호출한다. `didPlayToEnd`의 재시작 분기(`guard ... self.isLooping ...`)는 `onEvent` 콜백이 반환된 직후, 같은 `Task` 안에서 `await` 없이 동기적으로 평가되므로, 이 시점의 `setLooping(false)`가 재시작 자체(그 안의 `avPlayer.play()` 호출 포함)를 확실히 막는다 — 실제 비디오가 다시는 끝에 도달하지 않으므로 후속 `.playedToEnd`가 발생할 여지 자체가 없어진다. 이후 `for _ in 0..<10 { await Task.yield() }`로 바운드된 드레인을 거쳐 "혹시 재시작 가드가 실패했다면" 그 신호가 여기서 잡히도록 유지했다.

`ABLoopRestartTests.swift`의 다른 4개 테스트는 카운트를 단언하지 않아(불리언 상태 또는 존재 여부만 확인) 영향 없음 — 무수정.

---

## 3. Controls 재진입 특성화 테스트 2건

**원인**: `play()`/`pause()`가 이제 동기적으로 `refreshPlaybackMirrors()`를 호출한다(I-1 불변식 — 재생/일시정지 직후 `isPlaying`이 동기적으로 갱신되어야 하므로 A-6w에서 의도적으로 추가). 이 리프레시가 버퍼링 신호를 재평가해 `isBuffering`이 실제로 바뀌면 `.bufferingChanged`를 **동기적으로** 방송한다.

- 테스트 1(`playTapReentrantSequence`)에서는 `togglePlayback()`이 `promote(to: .current)` 다음에 `player.play()`를 호출하는데, 이 시점의 실제(가짜 아닌 진짜) `AVPlayerItem`(URL이 로드되지 않은 상태)이 `isPlaybackBufferEmpty == true`를 기본값으로 갖고 있어 `play()`가 `isBuffering`을 `false → true`로 바꾸고 `.bufferingChanged(true)`를 방송한다 — `gradeChanged` 직후, `controls.playPauseTapped` 직전에 끼어든다.
- 테스트 2(`pauseTapProducesNoSynchronousReentrantPlayerEvent`)에서는 테스트 셋업의 `player.play()`(토큰 등록 전이라 기록되지 않음)가 이미 `isBuffering`을 `true`로 만들어 놓은 상태였고, 탭에 의한 `pause()`가 그것을 다시 `false`로 되돌리며 `.bufferingChanged(false)`를 방송한다 — 이번엔 `controls.playPauseTapped` 앞에.

이것은 **버그가 아니라 additive 이벤트의 정상적인 신규 발생**이다. 다만 이 두 테스트는 정확한 시퀀스를 리스트로 통째 비교하므로 깨졌다.

**수정**: 이 특성화 스위트가 원래 고정하려던 것을 재확인했다 — "promote()가 스스로 내보내는 이벤트들이 play() 실행보다 먼저 재진입한다"는 순서이지, 탭 한 번이 만들어내는 이벤트의 총 목록이 아니다. `isPinnedReentrantEvent(_:)`(케이스 매칭, 문자열 아님 — `preloadCancelled`/`tuningApplied`/`gradeChanged`만 참)를 추가해 두 테스트의 플레이어 이벤트 기록 지점에서 필터링했다. 이렇게 하면 `bufferingChanged`뿐 아니라 **앞으로 추가될 모든 additive 이벤트**에 대해서도 이 스위트가 깨지지 않는다 — 브리프가 명시적으로 경고한 "기대값에 그냥 끼워 넣기"의 재발 패턴을 구조적으로 차단한다. 상단 독크 코멘트도 "play()/pause() 자체는 절대 동기 재진입하지 않는다"는 이제 틀린 문장을 "이 스위트가 고정하는 이벤트 종류는 promote()의 팬아웃뿐이고, play()/pause()가 동기적으로 내보낼 수 있는 관찰성-미러 이벤트는 의도적으로 핀에서 제외한다"로 갱신했다.

두 테스트의 최종 단언(정확한 배열 비교)은 값 자체를 전혀 건드리지 않았다 — 필터링된 결과가 기존과 동일한 배열이 되도록만 고쳤다.

---

## 4. `ABPlayerControlsViewTests.missingDurationStillEndsScrubbing` auto-hide 실패

**조사**: 이 테스트는 `try await waitUntil { !player.isScrubbing }`으로 스크럽 종료를 기다린 뒤 `view.hasScheduledAutoHide`를 단언한다. `ABPlayerControlsView.scrubEnded(progress:)`의 실제 실행 순서를 추적하면:

```swift
Task { ... in
    await sessionPlayer?.endScrubbing()   // player.isScrubbing이 이 안에서 false가 된다
    ...
    self.handleVisibility(.scrubEnded)     // auto-hide를 스케줄하는 지점 — isScrubbing=false보다 나중
    self.observerRegistry.broadcast(.scrubbingChanged(isScrubbing: false))
}
```

`player.isScrubbing`은 `ABPlayer.endScrubbing()` **내부**에서 `false`가 되고, `handleVisibility(.scrubEnded)`(auto-hide 스케줄을 실제로 발생시키는 호출)는 그 `await`가 반환된 **이후**, 같은 `Task`가 계속 실행되며 나온다. 즉 `player.isScrubbing == false`가 됐다고 해서 `handleVisibility(.scrubEnded)`가 이미 실행됐다는 보장은 원래부터 없다 — 두 상태 전이는 인과적으로 순서가 있지만(먼저/나중), `waitUntil`이 감시하는 신호(`player.isScrubbing`)는 그 순서의 **앞쪽** 지점이었다. Swift Concurrency는 `await` 지점에서 실제로 정지하지 않아도 스케줄러가 다른 태스크(이 테스트의 `waitUntil` 폴링 루프 자체)에 실행 기회를 줄 수 있으므로, 부하가 큰 러너에서 스케줄러의 공정성 판단이 달라지면 이 창이 실제로 관측 가능한 레이스가 된다.

이 창은 **A-6w 이전에도 구조적으로 존재했다** — `endScrubbing()`이 `isScrubbing`을 언제 `false`로 바꾸는지는 A-5w에서도 순서를 바꾸지 않았다(위치는 함수 마지막 부분, `broadcastPeriodicTime` 직전, 원래와 동일). 다만 A-6w가 실제 KVO 관찰 5종 + 각종 재계산 트리거(`refreshPlaybackMirrors` 호출 지점 다수)를 추가하면서 MainActor 큐에 걸리는 `Task`/훅 수가 늘었고, 이것이 스케줄러가 기존에 통과시켜 주던 좁은 창을 부하가 걸린 CI 러너에서 실제로 드러냈을 가능성이 높다고 판단한다.

**판정**: **프로덕션 회귀 아님.** `ABPlayer.isScrubbing`이 컨트롤스 레이어의 후속 처리 완료를 보장하는 신호였던 적이 없다 — 애초에 서로 다른 두 계층(코어의 스크럽 상태, 컨트롤스의 가시성 처리)이 같은 `Task` 체인 안에서 순차적으로만 연결되어 있을 뿐, 원자적으로 묶여 있지 않다. 이걸 프로덕션에서 "고치려면" `ABPlayer.endScrubbing()`이 컨트롤스 콜백을 동기적으로 알아야 하는 역방향 의존을 만들게 되어 아키텍처를 훼손한다 — 최소 범위 수정이 아니다. 반면 테스트는 인과적으로 정확한 신호(`.scrubbingChanged(isScrubbing: false)` 컨트롤스 이벤트 — `handleVisibility(.scrubEnded)` 다음에, 같은 동기 구간에서 방송됨)로 기다리면 되고, 이 신호를 기다리면 `hasScheduledAutoHide`가 이미 확정된 뒤에 단언하게 된다.

**수정**: `Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift`의 대기 조건을 `!player.isScrubbing` → `controlsEvents.contains(.scrubbingChanged(isScrubbing: false))`로 교체. 단언 자체(`hasScheduledAutoHide == true` 등)는 전혀 바꾸지 않았다 — "무엇을 보장해야 하는가"는 그대로 두고 "언제 확인해도 안전한가"만 정정했다.

이 파일은 브리프가 이번 fix2에 한해 허용한 `Tests/ABPlayerKitControlsTests/` 경계 예외에 포함된다고 판단했다 — 예외 문구가 "이 수정을 위해"라는 fix2 전체 맥락으로 도입됐고, 항목 4도 같은 디렉터리의 실패이기 때문이다. `ABPlayerControlsView.swift`(프로덕션)는 수정하지 않았다.

---

## 검증

- 시뮬레이터: iPhone 17 Pro, UDID `55A3A4F3-3F02-43E6-9B23-116BD15D3345`(기존 부팅됨, 새로 부팅·생성하지 않음).
- **전체 스킴 테스트 3회 연속 실행**(`-only-testing` 없이, 4개 타깃 전부):

  | 실행 | ABPlayerKitCacheTests | ABPlayerKitControlsTests | ABPlayerKitMetricsTests | ABPlayerKitTests | 결과 |
  |---|---|---|---|---|---|
  | 1 | 39 tests / 6 suites | 184 tests / 24 suites | 8 tests / 2 suites | 240 tests / 37 suites | **TEST SUCCEEDED** |
  | 2 | 39 tests / 6 suites | 184 tests / 24 suites | 8 tests / 2 suites | 240 tests / 37 suites | **TEST SUCCEEDED** |
  | 3 | 39 tests / 6 suites | 184 tests / 24 suites | 8 tests / 2 suites | 240 tests / 37 suites | **TEST SUCCEEDED** |

  합계 471개 테스트 × 3회, 전부 그린. 실패했던 4개 테스트(`playedToEnd broadcasts exactly once per end-of-item, before the loop restart begins`, `A play tap ... reentrant sequence`, `... pause tap produces no pinned reentrant player event ...`, `Given duration disappears during scrubbing, controls always end the session`) 전부 3회 실행 로그에서 개별 확인.
- `swiftlint lint --strict` → **0 violations, 0 serious in 127 files.**
- Swift 6 zero-warning: `build-for-testing` 로그에 `appintentsmetadataprocessor`의 무해한 도구 안내 문구 외 `warning:`/`error:` 0건.

## 파일 경계 예외 사용 내역

| 파일 | 원 경계 | 사유 |
|---|---|---|
| `Tests/ABPlayerKitControlsTests/ABControlsPlayPauseReentrancyCharacterizationTests.swift` | 원 브리프상 트랙 A 수정 금지 | fix2 브리프 항목 3이 명시적으로 이번 1회 한정 허용 |
| `Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift` | 원 브리프상 트랙 A 수정 금지 | fix2 브리프의 같은 예외 문구를 항목 4(같은 디렉터리, 같은 CI 실패군)에도 적용 — 위 §4 판정에 근거해 테스트만 수정, 프로덕션(`ABPlayerControlsView.swift`)은 무수정 |

## 변경 파일 목록

- `Sources/ABPlayerKit/StateMachine/ABBufferingEvaluator.swift`
- `Sources/ABPlayerKit/Engine/ABPlayer.swift`
- `Tests/ABPlayerKitTests/ABBufferingEvaluatorTests.swift`
- `Tests/ABPlayerKitTests/ABLoopRestartTests.swift`
- `Tests/ABPlayerKitControlsTests/ABControlsPlayPauseReentrancyCharacterizationTests.swift`
- `Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift`

로직 변경은 항목 1(파라미터 그룹화, 판정 결과 불변)뿐이며 나머지는 전부 테스트 파일의 동기화/필터링 정정이다. 커밋 없음.
