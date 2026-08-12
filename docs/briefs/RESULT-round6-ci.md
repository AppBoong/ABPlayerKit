# RESULT: 라운드6 트랙 CI — 리포 인프라

담당: Sonnet, worktree `round6/ci`. 커밋 없음(작업 트리 변경만).

## WP별 변경 요약

### CI-1 — 커버리지 요약 스텝 + README 배지 (H-3)

- `.github/workflows/ci.yml`
  - `build-and-test` 잡에 `Summarize coverage` 스텝 추가: `xcrun xccov view --report --json`으로 전체 라인 커버리지 %를 계산해 `$GITHUB_STEP_SUMMARY`에 마크다운 리포트로 기록.
  - `Write coverage badge data` / `Upload coverage badge data` 스텝 추가: 커버리지 %를 shields.io endpoint 스키마(`{"schemaVersion":1,"label":"coverage","message":"NN%","color":"..."}`)로 아티팩트화(색상은 80%/60% 임계치로 결정).
  - 신규 잡 `coverage-badge`: `build-and-test` 완료 후(`needs:`), **`main` push에서만** 실행. 아티팩트를 내려받아 `peaceiris/actions-gh-pages@v4`로 `badges` 오펀 브랜치에 `coverage.json`을 퍼블리시(`contents: write`는 이 잡에만 범위 한정, 별도 시크릿 불필요 — 기본 `GITHUB_TOKEN` 사용).
- `README.md`, `README.ko.md`: 기존 CI 배지 아래에 `![Coverage](https://img.shields.io/endpoint?url=...raw.githubusercontent.com/AppBoong/ABPlayerKit/badges/coverage.json)` 배지 추가.

**주의(타 트랙/오케스트레이터 전달)**: 배지는 `main`에 최초 push된 이후 `badges` 브랜치가 생성되어야 실제로 채워짐. 그 전까지는 shields.io가 404를 받아 "invalid" 배지를 표시할 수 있음 — 이번 브랜치가 `main`에 병합되고 CI가 최소 1회 성공해야 정상화됨.

### CI-2 — ThreadSanitizer 잡 (H-3, ROADMAP §6)

- `.github/workflows/ci.yml`: 신규 잡 `thread-sanitizer` 추가. `ABPlayerKitTests` + `ABPlayerKitCacheTests`만 `-only-testing`으로 골라 `-enableThreadSanitizer YES`로 실행.
- `build-and-test`에 대한 `needs:` 없이 독립 잡으로 정의 → GitHub Actions가 기본적으로 병렬 실행하므로 메인 잡을 지연시키지 않음(ROADMAP §6 요구사항 충족).

### CI-3 — `.swiftlint.yml` + lint 스텝 (H-4)

- `.swiftlint.yml` 신규 생성. `included`에 `Sources`/`Tests`/`Examples`.
- 기존 코드가 대량 위반하는 12개 규칙을 `disabled_rules`로 시작, 각 항목에 위반 건수와 사유를 인라인 주석으로 기록(`line_length` 96건, `identifier_name` 24건, `file_length`/`cyclomatic_complexity` 9건, `type_body_length`/`function_body_length` 6건, `trailing_comma` 7건, `multiple_closures_with_trailing_closure`/`large_tuple` 3건, `type_name`/`duplicate_imports` 2건, `static_over_final_class`/`private_over_fileprivate` 1건).
- CONTRIBUTING.md의 "no `MainActor.assumeIsolated`" 컨벤션을 `custom_rules.no_main_actor_assume_isolated`로 기계 강제(`match_kinds: identifier`로 주석/문자열 오탐 방지 — 코드베이스에 이미 주석으로만 2건 언급되어 있어 실제 오탐 없음을 확인).
- `.github/workflows/ci.yml`: 신규 잡 `lint` 추가, `swiftlint lint --strict` 실행(경고도 실패로 취급 — 리포의 zero-warning 관행과 일치).

### CI-4 — `ABTestSupport` 타깃 신설 (H-5)

- `Package.swift`: 신규 `.target(name: "ABTestSupport", path: "Tests/ABTestSupport")` 추가(제품 목록에는 미등록 → 라이브러리에 포함 안 됨). 4개 테스트 타깃 전부 `ABTestSupport`를 의존성에 추가.
  - 부수 변경: `platforms`에 `.macOS(.v13)` 추가. `ABTestSupport`가 (테스트 타깃이 아닌) 일반 타깃이 되면서 `swift build`가 macOS 호스트로 직접 컴파일을 시도하는데, 기존 3벌의 `ABWaitUntil.swift`가 쓰던 `ContinuousClock`/`Task.sleep(for:)`가 macOS 13+ API라 플랫폼 최소값 미선언 시 컴파일 실패. iOS 17이 사실상 macOS 14+ 툴체인에서만 빌드되므로 런타임 영향 없는 순수 선언적 수정.
- `Tests/ABTestSupport/ABWaitUntil.swift` 신규: `waitUntil` / `ABWaitUntilTimedOut`을 `public`으로 공개. busy-spin `await Task.yield()`를 `try await Task.sleep(for: .milliseconds(5))` 폴링으로 교체.
- 삭제: `Tests/ABPlayerKitTests/Support/ABWaitUntil.swift`, `Tests/ABPlayerKitControlsTests/Support/ABWaitUntil.swift`, `Tests/ABPlayerKitCacheTests/Support/ABWaitUntil.swift`(및 빈 `Support/` 디렉터리).
- `Tests/ABPlayerKitControlsTests/ABPlayerControlsAutoHideTests.swift`: 유일한 실제 호출부에 `import ABTestSupport` 추가(다른 3개 파일은 헬퍼를 정의만 하고 호출하지 않았음 — 확인차 `grep -rn "waitUntil("` 전수 조사로 검증).

## 검증 결과

| 항목 | 결과 |
|---|---|
| `swiftlint lint --strict` (0.65.0, Homebrew로 로컬 설치) | **PASS** — 0 violations, 115 files |
| `swift build --target ABTestSupport` | **PASS** — macOS 호스트에서 독립 컴파일 확인 |
| `swift build`(전체 패키지) | **실패, 무관한 사전 존재 이슈** — `ABPlayerKit`이 `import UIKit`(예: `ABApplicationStateObserver.swift`)을 사용해 순수 macOS 타깃으로는 애초에 빌드 불가. 이번 트랙 변경과 무관(CONTRIBUTING.md도 `xcodebuild` + iOS 시뮬레이터 데스티네이션만 명시, `swift build`/`swift test`를 공식 경로로 삼지 않음) |
| `xcodebuild -scheme ABPlayerKit-Package -destination 'generic/platform=iOS' ... build` (SWIFT/GCC_TREAT_WARNINGS_AS_ERRORS=YES) | **PASS** — `BUILD SUCCEEDED`, 전체 패키지(4개 라이브러리 + `ABTestSupport`) Swift 6 zero-warning 컴파일 확인. 시뮬레이터 미부팅 상태로 실행 가능한 최대 수준의 검증 |
| `xcodebuild ... -destination 'platform=iOS Simulator,...' test` (기존 CI와 동일 인보케이션) | **미실행** — 이 환경에 이미 부팅된 iOS 시뮬레이터가 없고(`xcrun simctl list devices booted` 결과 없음(iOS 18.0/18.2/26.1/26.2 런타임만 존재, booted 없음), ROADMAP §0 "새 시뮬레이터 부팅 금지"에 따라 새로 부팅하지 않음. 브리프 §검증의 "없으면 macOS 타깃 검증까지만" 조항에 따라 이 단계는 생략 |
| TSan 로컬 1회 실행 | **미실행, 같은 사유** — `-enableThreadSanitizer`도 iOS 시뮬레이터 데스티네이션이 필요해 동일하게 차단됨. 아래 "미해결" 참조 |

## 미해결 · 이슈 · 타 트랙 전달 사항

1. **TSan 로컬 미검증**: 브리프는 "TSan을 로컬로 1회 실행해 실패 발견 시 재현 정보를 A/E 트랙에 전달"을 요구하지만, 이 환경에 부팅된 시뮬레이터가 없고 신규 부팅이 금지되어 실행 자체를 하지 못했다. `thread-sanitizer` 잡은 작성·YAML 문법 검증(`python3 -c yaml.safe_load`)만 마쳤고, 실제 GitHub Actions 러너(매번 새 macOS 인스턴스라 "새 시뮬레이터 부팅 금지" 제약이 적용되지 않는 환경)에서 첫 실행 시 데이터 경합이 발견되면 A(코어)/E(캐시) 트랙 브리프로 전달 바람. 락 기반 코드가 많다는 감사 근거(H-3)를 고려하면 첫 실행에서 발견 가능성이 낮지 않음 — 오케스트레이터가 CI 첫 그린 결과를 확인해줄 것을 권장.
2. **커버리지 배지 초기 상태**: `badges` 브랜치가 아직 존재하지 않아 이 브랜치가 `main`에 병합되고 CI가 최소 1회(push 이벤트) 성공하기 전까지는 README 배지가 "invalid"로 보일 수 있음. 정상 동작이며 별도 조치 불필요.
3. **`swift build`/`swift test` 전체 패키지 검증 불가**는 이 트랙이 만든 문제가 아니라 리포 구조상 원래 그랬던 것(순수 UIKit 의존). CONTRIBUTING.md에 이미 xcodebuild 경로만 명시되어 있어 정정 불필요라 판단, 문서 변경 없음.
4. **SwiftLint 로컬 설치**: 이 환경에는 swiftlint가 없어 `brew install swiftlint`(0.65.0)로 설치 후 검증함. CI 러너(`macos-15`)에는 GitHub 공식 `runner-images`에 SwiftLint가 사전 설치되어 있다고 문서화되어 있으나, 실제 첫 CI 실행에서 `swiftlint: command not found`가 뜨면 `lint` 잡에 설치 스텝(`brew install swiftlint` 또는 release 바이너리 다운로드) 추가가 필요 — 오케스트레이터가 첫 그린 확인 시 함께 확인 바람.
5. **`disabled_rules`의 12개 규칙**은 의도적으로 미해소 상태로 남김(브리프 지시대로 "기존 코드 대량 위반 → disabled + 사유 주석"). 향후 라운드에서 점진적으로 재활성화할 수 있으나 이번 트랙 범위 밖.

## 변경 파일 전체 목록

```
M  .github/workflows/ci.yml
M  Package.swift
M  README.ko.md
M  README.md
D  Tests/ABPlayerKitCacheTests/Support/ABWaitUntil.swift
M  Tests/ABPlayerKitControlsTests/ABPlayerControlsAutoHideTests.swift
D  Tests/ABPlayerKitControlsTests/Support/ABWaitUntil.swift
D  Tests/ABPlayerKitTests/Support/ABWaitUntil.swift
A  .swiftlint.yml
A  Tests/ABTestSupport/ABWaitUntil.swift
```
