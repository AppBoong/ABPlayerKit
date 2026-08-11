# RESULT: 라운드6 트랙 CI — 픽스 라운드 2 (테스트 컴파일 에러 대응)

담당: Sonnet, worktree `round6/ci`. 커밋 없음(작업 트리 변경만). 기준: 픽스1 이후 `build-and-test`/`thread-sanitizer`가 "cannot find 'waitUntil' in scope" 컴파일 에러로 실패(`lint`·시뮬레이터 준비는 성공).

## 원인

CI-4에서 `Tests/*/Support/ABWaitUntil.swift` 3벌을 `ABTestSupport` 타깃으로 통합하며 각 호출부에 `import ABTestSupport`를 추가해야 했는데, 호출부 전수 조사를 `grep -rn "waitUntil("`(괄호 포함)로만 수행했다. 이 리포의 `waitUntil` 호출은 대부분 `try await waitUntil { ... }` 형태의 트레일링 클로저라 괄호가 없어 grep에서 전부 누락됨 — 유일하게 잡힌 `ABPlayerControlsAutoHideTests.swift`는 `waitUntil(.seconds(5)) { ... }`처럼 명시적 인자가 있어 우연히 괄호가 있었던 케이스였다.

## 조치

`grep -rn "waitUntil" Tests/`(괄호 없이)로 재조사해, 실제로 `waitUntil`을 **호출**하는 파일을 전수 확인(주석에서만 언급하거나 `waitUntilReady`처럼 다른 식별자인 경우는 제외):

| 파일 | 비고 |
|---|---|
| `Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift` | 3곳 호출 |
| `Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift` | 2곳 호출 |
| `Tests/ABPlayerKitTests/ABAudioInterruptionTests.swift` | 7곳 호출 |
| `Tests/ABPlayerKitTests/ABAudioSessionPolicyTests.swift` | 4곳 호출 |
| `Tests/ABPlayerKitTests/ABAVPlaybackTargetErrorEventsTests.swift` | 4곳 호출 |
| `Tests/ABPlayerKitTests/ABPlayerEngineTests.swift` | 11곳 호출 |
| `Tests/ABPlayerKitTests/ABPlayerObservationTests.swift` | 3곳 호출 |
| `Tests/ABPlayerKitTests/ABScrubbingEngineTests.swift` | 9곳 호출 |
| `Tests/ABPlayerKitControlsTests/ABPlayerControlsAutoHideTests.swift` | 픽스1 이전(CI-4)에 이미 처리됨 — 재확인만 |

위 8개 파일 각각에 `import ABTestSupport`를 추가(기존 파일의 알파벳 순 import 관례를 유지하며 삽입). `ABAVPlaybackTargetReadyWaitTests.swift`는 `waitUntilReady`(대상 타입의 다른 메서드)만 언급할 뿐 헬퍼 `waitUntil`을 호출하지 않아 변경 대상에서 제외 — grep 결과와 코드를 대조해 확인함.

## 검증 결과

| 항목 | 결과 |
|---|---|
| `grep -rn "waitUntil" Tests/` 재조사 후 9개 파일 모두 `import ABTestSupport` 존재 확인 | **PASS** |
| `xcodebuild -scheme ABPlayerKit-Package -destination 'generic/platform=iOS Simulator' ... build-for-testing` (클린, 처음부터) | **PASS** — `** TEST BUILD SUCCEEDED **`, `error:` 0건, "cannot find" 0건. 4개 테스트 타깃(`ABPlayerKitTests`, `ABPlayerKitControlsTests`, `ABPlayerKitCacheTests`, `ABPlayerKitMetricsTests`) 전부 컴파일 확인. 시뮬레이터 미부팅(generic 데스티네이션이라 필요 없음) |
| 동일 커맨드 재실행(증분) | **PASS** — exit 0, `TEST BUILD SUCCEEDED`, error 0건 재확인 |
| `swiftlint lint --strict` | **PASS** — 0 violations, 115 files (신규 import 라인이 lint 위반을 만들지 않음 확인) |

이번에는 요청대로 `build-for-testing`으로 전 테스트 타깃 컴파일을 실제로 검증했다 — 지난 라운드(RESULT-round6-ci.md/-fix1.md)에서는 `xcodebuild ... build`(라이브러리 타깃만) 또는 macOS 타깃 빌드까지만 확인했고 테스트 타깃 컴파일 자체는 검증 범위 밖이었던 것이 이번 실패의 검증 공백이었다.

## 재발 방지

향후 라운드에서 테스트 지원 코드를 갈아끼우거나 심볼을 이동할 때는 `grep`을 함수 호출 형태(괄호 포함)로만 하지 말고 식별자 자체로 재조사하고, **로컬 검증 단계에 `xcodebuild build-for-testing`(시뮬레이터 부팅 불필요)을 항상 포함**해야 한다는 점을 이번 두 차례 픽스로 확인했다. 다음 CI 트랙 관련 브리프에 이 교훈을 명시하는 것을 권장하나, 문서 갱신은 이번 픽스 범위 밖이라 실행하지 않음(오케스트레이터 판단에 맡김).

## 변경 파일 목록

```
M  Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift
M  Tests/ABPlayerKitControlsTests/ABPlayerControlsViewTests.swift
M  Tests/ABPlayerKitTests/ABAVPlaybackTargetErrorEventsTests.swift
M  Tests/ABPlayerKitTests/ABAudioInterruptionTests.swift
M  Tests/ABPlayerKitTests/ABAudioSessionPolicyTests.swift
M  Tests/ABPlayerKitTests/ABPlayerEngineTests.swift
M  Tests/ABPlayerKitTests/ABPlayerObservationTests.swift
M  Tests/ABPlayerKitTests/ABScrubbingEngineTests.swift
```
