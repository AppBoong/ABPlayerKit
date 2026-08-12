# RESULT: 라운드6 트랙 A — A-8 게이트 REQUEST-CHANGES 수정 (fix1)

`docs/briefs/REVIEW-round6-core.md` §9 지적 사항(새 주석/테스트명의 감사·설계 ID 인용) 수정. **로직 변경 없음 — 텍스트만.** 커밋 없음.

## 방법

`git diff`(추적 파일)와 신규 파일 전체(미추적 — `git diff`는 이를 보여주지 않으므로 별도로 각 파일 전체를 "추가 라인"으로 취급)를 합쳐, ID 패턴(`[A-Z]{1,2}-[0-9]+w?`, `WP...`, `round[0-9]+`, `Wave ?[0-9]`, `M[0-9]+`, `N[0-9]+`, `mn?[0-9]+`)으로 전수 스캔했다. 리뷰가 열거한 12개 지점과 정확히 일치하는 12개 지점을 확인했고, 그 외 추가 발견은 없었다. 수정 후 동일한 스캔을 재실행해 0건을 확인했다(아래 §3).

## 1. Sources (3건)

| 파일:행(리뷰 기준) | Before | After |
|---|---|---|
| `Engine/ABAVPlaybackTarget.swift:222` | `concept of its own to resolve against (B-7 — a feed cell's correct cap is the cell's size, never UIScreen.main).` | `concept of its own to resolve against — a feed cell's correct cap is the cell's own size, not the device screen's.` |
| `Engine/ABAVPlaybackTarget.swift:420` | `since this isn't ABPlayer's seek path (A-5w owns that channel).` | `since this isn't a seek ABPlayer itself issued.` |
| `Engine/ABAVPlaybackTarget.swift:504` | `Buffering-suppression signal only (B-2) — never the sole basis for a buffering verdict.` | `Buffering-suppression signal only — never the sole basis for a buffering verdict.` |
| `Engine/ABPlayer.swift:685` | `Before .tuningApplied, same action — the confirmed attach-order contract Wave 2 depends on.` | `Before .tuningApplied, same action — consumers can rely on an attached item always being announced before its tuning.` |

의미 손실 없음 — ID가 가리키던 "왜"는 전부 불변식 문장 자체에 남아 있다(예: "B-7"이 전달하던 "화면 크기가 아니라 셀 크기"라는 근거는 그대로 문장에 서술됨).

## 2. Tests (10개 파일)

| 파일 | Before(요지) | After(요지) |
|---|---|---|
| `ABAVPlaybackTargetObservabilityTests.swift:6` | "Integration coverage for the KVO registrations A-6/B-2 added to..." | "Integration coverage for the buffering/duration/presentation-size KVO registrations in..." |
| `ABBackgroundLifecycleEngineTests.swift:7` | "Engine-level coverage for A-2/A-6: willResignActive capturing..." | "Engine-level coverage for willResignActive capturing..." |
| `ABBackgroundLifecycleEngineTests.swift:31` | "...the exact scenario A-6 identified." | "...so capturing at willResignActive is what makes this scenario recoverable." |
| `ABBackgroundPolicyMachineTests.swift:7` | "...combination the audit's A-2/A-6 fixes depend on." | "...combination the background/foreground lifecycle fixes depend on." |
| `ABDetachOrderingTests.swift:6` | "Coverage for A-4/A-5/A-8: TTFF bookkeeping resets on detach..." | "Coverage for TTFF bookkeeping resetting on detach..." |
| `ABDisplaySizeTuningTests.swift:6` | "Coverage for B-7: preferredMaximumResolution's sentinel now resolves..." | "Coverage for preferredMaximumResolution's sentinel resolving..." |
| `ABFailureLifecycleTests.swift:6` | "Coverage for A-3: lastFailure/lastDiagnostic/lastError reset on..." | "Coverage for lastFailure/lastDiagnostic/lastError resetting on..." |
| `ABObservabilityEventsTests.swift:6` | "Engine-level coverage for A-6/B-1~B-5: the new observable mirrors..." | "Engine-level coverage for the observable mirrors and event surface..." |
| `ABObservabilityEventsTests.swift:65`(`@Test` 이름) | `"...identifies a stalled-but-intending-to-play state (D-2's icon-inversion fix)"` | `"...identifies a stalled-but-intending-to-play state"` |
| `ABRateTuningTargetTests.swift:6` | "Coverage for B-8: ABAVPlaybackTarget.setRate(_:) mirrors into..." | "Coverage for ABAVPlaybackTarget.setRate(_:) mirroring into..." |
| `ABSeekUnificationTests.swift:6` | "Coverage for A-5/A-7/D-1: all seek entry points now funnel through..." | "Coverage for all seek entry points funneling through..." |
| `ABSeekUnificationTests.swift:131`(`@Test` 이름) | `"...matches pre-existing I-3 invariant"` | `"...never blocks on it"` |
| `Fakes/ABFakePlaybackTarget.swift:83` | `"...from inside a .itemDetached observer (the A-4/A-8 ordering fix)."` | `"...from inside a .itemDetached observer, since the target detaches before that event broadcasts."` |

## 3. Examples (1건)

| 파일:행 | Before | After |
|---|---|---|
| `DemoModel.swift:474` | `New round6 cases fall through here with a generic label...` | `Newer event cases fall through here with a generic label...` |

## 검증

- 재스캔(ID 패턴 전수, Sources+Tests+Examples 추가 라인 전체): **0건**.
- `xcodebuild -scheme ABPlayerKit-Package -destination "generic/platform=iOS Simulator" ... build-for-testing` → **TEST BUILD SUCCEEDED**, 경고 0건.
- `xcodebuild -project Examples/ABPlayerKitDemo/... -scheme ABPlayerKitDemo -destination "generic/platform=iOS Simulator" ... build` → **BUILD SUCCEEDED**, 경고 0건.
- 코드 로직 변경 없음(전부 주석/문자열 리터럴만 수정) — `git diff`로 각 변경이 주석·문자열 라인에 한정됨을 재확인.
- 부팅된 시뮬레이터 없음 — 이번에도 테스트 스위트 실행은 하지 않음(빌드 검증까지).

## 대조군 확인

`ABLoopRestartTests.swift`, `ABBufferingEvaluatorTests.swift`는 이번 수정 대상에 없었다(원래부터 ID 미인용) — 재스캔 결과로도 확인됨.
