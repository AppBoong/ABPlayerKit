# BRIEF: 라운드6 CI 안정화 — Controls 테스트 타임아웃 조사 (Sonnet)

당신은 main이 레드가 된 원인을 규명하고 고치는 담당입니다. 브랜치 `round6/ci-stability`(기준 `origin/main` = f7403cb).

## 배경 사실 (추측 아님, 실제 관측)

트랙 CI 병합(f7403cb) 직후 main CI가 **2회 연속** `build-and-test` 실패. `thread-sanitizer`와 `lint`는 두 번 다 성공.

- **1차 실행**: Controls 테스트 3개가 동시에 시작해 전부 스위트 제한 180초 초과 →
  `ABAccessoryHostingBoxTests.swift:96`, `ABPlayerControlsViewTests.swift:61`, `ABControlButtonTests.swift:18`.
  이 중 `ABControlButtonTests`/`ABAccessoryHostingBoxTests`는 `waitUntil`을 **쓰지도 않는다**.
  이후 "Restarting after unexpected exit, crash, or test timeout" 후 exit 65.
- **2차 실행(같은 커밋 재실행)**: `ABPlayerControlsAutoHideTests` "Given playing controls, playback state arms and fires auto-hide"가
  `ABWaitUntilTimedOut()`으로 실패(6.399초). 이 테스트는 `autoHideDelay = 0.01`(10ms)을 걸고 최대 5초를 기다린다.
- 시뮬레이터는 두 실행 모두 동일(iPhone 16 Pro, 동일 UDID). PR #1 실행(동일 트리 내용)은 5분 31초에 **통과**했다.

**유일하게 의심되는 변경**: CI-4가 `ABWaitUntil`을 `Tests/ABTestSupport/`로 통합하며 폴링을 바꿨다.
`git show 995bb6d:Tests/ABPlayerKitControlsTests/Support/ABWaitUntil.swift`와 `Tests/ABTestSupport/ABWaitUntil.swift`를
비교하면 deadline 기본값(2초)·`@MainActor`·타임아웃 처리는 동일하고 **폴링만** `await Task.yield()` → `try await Task.sleep(for: .milliseconds(5))`로 바뀌었다.

단, 1차 실행에서 `waitUntil`을 쓰지 않는 테스트까지 멎은 점은 이 가설만으로 설명되지 않는다. 러너 전역 정체 가능성도 열어둘 것.
참고로 이 테스트는 라운드5에도 플레이크 이력이 있다(커밋 219d7c3 "widen auto-hide wait deadline for loaded CI runners", 52f18e8 "raise suite time limits to 3 minutes").

## 환경 (이번 작업에 한해 규칙 완화)

**로컬 시뮬레이터 사용이 허용됐다.** 이미 부팅해 두었다:

```
iPhone 17 Pro  UDID 55A3A4F3-3F02-43E6-9B23-116BD15D3345  (Booted)
```

`-destination 'platform=iOS Simulator,id=55A3A4F3-3F02-43E6-9B23-116BD15D3345'`로 실행하라.
**새 시뮬레이터를 추가로 부팅하거나 생성하지 말 것** — 이 한 대만 재사용한다. 종료도 하지 말 것(오케스트레이터가 정리한다).

## 과제

1. **재현**: Controls 테스트 타깃을 로컬에서 **여러 번**(최소 3회) 실행해 실패가 재현되는지 확인하라.
   `-only-testing:ABPlayerKitControlsTests`로 좁혀 반복하고, 전체 스위트도 최소 1회 실행하라.
   재현되지 않으면 "로컬 재현 불가"도 유효한 결과다 — 부하 조건 차이(병렬 실행, CPU 경합)를 만들어 시도해 보라.
2. **가설 검증**: 폴링을 `await Task.yield()`로 되돌린 변형과 현재(`Task.sleep(5ms)`)를 **같은 조건에서 비교 실행**하라.
   차이가 없다면 폴링은 원인이 아니다 — 그 사실도 그대로 보고하라(되돌림을 정당화하기 위해 데이터를 맞추지 말 것).
3. **원인 규명**: 특히 auto-hide가 10ms 지연인데 5초 안에 발동하지 않는 경로를 코드로 추적하라
   (`ABPlayerControlsView`의 auto-hide 스케줄링, `hasScheduledAutoHide`, 취소/재무장 로직).
   `waitUntil`을 쓰지 않는 테스트까지 180초를 넘긴 1차 실행의 전역 정체 가설도 함께 검토하라.
4. **수정**: 원인에 맞는 최소 수정을 구현하라. **타임아웃 숫자를 키우는 것은 최후의 수단**이며,
   그 경우에도 왜 다른 해법이 불가능한지 문서에 근거를 남겨라(이미 라운드5에 두 번 키운 이력이 있다).
5. 수정 후 로컬에서 Controls 스위트를 **최소 3회 연속** 그린으로 통과시켜라.

## 제약

- Swift 6 zero-warning 유지. **커밋 금지**(커밋은 별도 담당). push 금지.
- 프로덕션 소스(`Sources/`) 수정이 필요하다고 판단되면, 그것이 진짜 제품 버그인지 테스트 문제인지 명확히 구분해 보고하라.
  제품 버그라면 트랙 A/C와 파일이 겹칠 수 있으므로 **수정 전에 RESULT 문서에 먼저 기록**하고 최소 범위로만 손대라.
- 새 주석에 리뷰 ID 인용 금지 — 불변식만 서술.

## 산출물

`docs/briefs/RESULT-round6-ci-stability.md` — 재현 결과(실행 횟수와 성공/실패 표), 가설 검증 데이터, 확정된 원인,
적용한 수정, 수정 후 3회 연속 그린 증거, 남은 리스크. **이 파일 작성이 완료 신호다. 작성 후 추가 작업 없이 대기하라.**
