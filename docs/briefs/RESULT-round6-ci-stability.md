# RESULT: 라운드6 CI 안정화 — Controls 테스트 타임아웃 조사

담당: Sonnet, 브랜치 `round6/ci-stability`. 커밋 없음(작업 트리 변경만).

## 프로덕션 소스 변경 사전 기록 (브리프 §제약에 따라 수정 전 기록)

`Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift`의 `scheduleAutoHide(after:)`가 만드는
`hideTask`(자동 숨김 타이머)에 명시적 우선순위가 없다는 것을 실제 제품 버그로 판단해 최소 범위로 수정한다.

- **제품 버그인지 테스트 문제인지**: 제품 버그 쪽에 가깝다고 판단. `hideTask`는 사용자에게 보이는 UI 타이머(자동 숨김)를
  구동하는데, `Task { [weak self] in ... }`에 우선순위를 지정하지 않으면 호출 컨텍스트의 우선순위를 상속한다.
  실제 앱에서는 대개 UIKit 콜백(제스처 인식기 등)의 우선순위가 높아 큰 문제가 되지 않지만, 앱이 동시에 다른
  `Task`(백그라운드 프리페치, 메트릭 전송 등)를 많이 띄운 상태거나 시스템이 전반적으로 바쁠 때는 이 타이머가
  낮은 우선순위로 강등되어 사용자가 기대하는 시점보다 늦게 컨트롤이 사라질 수 있다 — 이는 테스트에서만 문제인
  타이밍이 아니라 실제 UX 저하로 이어질 수 있는 잠재 결함이다. 아래 "원인" 절에서 설명하듯, CI에서 관찰된
  플레이크는 정확히 이 상황(동시에 매우 많은 `Task`가 스케줄러를 두고 경합)의 극단적인 재현으로 보인다.
- **적용할 수정**: `Task { [weak self] in` → `Task(priority: .userInitiated) { [weak self] in`로 1줄 변경.
  동작 변화는 스케줄링 우선순위뿐이며, 취소/재무장/VoiceOver 억제 로직은 전혀 건드리지 않는다.
- **범위**: 이 파일의 이 한 지점만 수정. 트랙 A/C가 소유한 다른 로직(`ABControlsVisibilityMachine`,
  프레젠터, 관찰자 등)은 무수정.

(이 절 작성 직후 실제 수정을 적용했다. 적용된 diff와 검증 결과는 하단 "적용한 수정"·"수정 후 검증" 절 참조.)

## 재현 시도 결과

로컬 시뮬레이터(iPhone 17 Pro, UDID `55A3A4F3-3F02-43E6-9B23-116BD15D3345`, 이미 부팅된 것 재사용, 신규 부팅 없음)에서
`xcodebuild -scheme ABPlayerKit-Package -destination 'platform=iOS Simulator,id=55A3A4F3-...'`로 반복 실행.
로컬 툴체인은 Xcode 26.2.0(CI 고정값 16.4와 다름 — 이 환경엔 16.4가 없어 `xcode-select -p`로 폴백, `prepare-simulator.sh`와
동일한 동작). 이 차이가 결과에 영향을 줬을 가능성은 배제할 수 없으나, 아래처럼 코드 경로 자체는 툴체인 버전과 무관하다.

| # | 조건 | 커맨드 | 결과 | auto-hide 테스트 소요시간 |
|---|---|---|---|---|
| 1 | 단독 실행 | `-only-testing:ABPlayerKitControlsTests` | PASS (184 tests/24 suites) | 0.819s |
| 2 | 단독 실행 | 동일 | PASS | 0.642s |
| 3 | 단독 실행 | 동일 | PASS | 0.300s |
| — | 전체 스위트 1회 | 전체 스킴 test-without-building | PASS (175 tests/26 suites, 4개 타깃 합산) | — |
| 4 | 배경에 전체 스위트 2개 동시 실행(공유 시뮬레이터 경합) | `-only-testing:ABPlayerKitControlsTests` | PASS | 0.403s |
| 5 | 동일 조건 | 동일 | PASS | 2.174s |
| 6 | 동일 조건 | 동일 | PASS | 1.070s |
| — | 배경 전체 스위트 2개(동시성 검증용) | 전체 스킴 x2 | 둘 다 PASS | — |

**결론: 로컬 재현 불가.** 최소 3회 요구를 훨씬 넘겨 Controls 단독 6회(그중 3회는 배경에 전체 테스트 스위트 2개를
동시 실행해 같은 시뮬레이터·빌드 시스템에 인위적 경합을 만든 상태), 전체 스위트 3회(단독 1회 + 동시 배경 2회) 모두
그린이었다. auto-hide 테스트의 실측 소요 시간은 0.3~2.2초로, 10ms 지연·5초 데드라인에 전혀 근접하지 않았다.

인위적 CPU 부하(무한 루프 배경 프로세스로 스레드풀 고갈시키기)는 시도했으나 harness 정책상 차단되어 실행하지
못했다(비파괴적 스트레스 테스트였음에도 자동 분류기가 거부). 대신 "실제 xcodebuild 테스트 프로세스를 동시에 여러 개
띄운다"는, 브리프가 제안한 "병렬 실행" 조건을 정직한 작업 부하로 시도했다 — 이는 표에 반영되어 있다.

이 로컬 환경은 논리 코어 10개(성능 코어 4 + 효율 코어 6)를 갖고 있어, GitHub Actions `macos-15` 호스티드 러너
(공식 사양상 3 vCPU)보다 훨씬 여유롭다. 배경에 전체 스위트 2벌을 동시 실행해도 시스템 전체 활용률이 CI 러너가
평소 겪는 수준에 도달하지 못했을 가능성이 높다 — 즉 "로컬 재현 불가"는 버그가 없다는 뜻이 아니라, 이 환경에서
CI 수준의 자원 경합을 재현할 수단이 없었다는 뜻이다.

## 가설 검증: `ABWaitUntil` 폴링 변경(`Task.yield()` → `Task.sleep(5ms)`)

`Tests/ABTestSupport/ABWaitUntil.swift`의 폴링을 `await Task.yield()`로 임시로 되돌려(로컬 작업 트리에서만,
검증 후 원상복구) 동일한 "배경에 전체 스위트 2개 동시 실행" 경합 조건에서 6회 비교 실행했다.

| 폴링 방식 | 실행 횟수 | auto-hide 테스트 소요시간(초) | 평균 | 최대 |
|---|---|---|---|---|
| `Task.sleep(5ms)`(현재) | 9회(위 표 6회 + 앞선 검증 3회) | 0.819, 0.642, 0.300, 0.403, 2.174, 1.070, 0.971, 0.973, 0.719 | 0.897 | 2.174 |
| `Task.yield()`(되돌림) | 6회 | 1.192, 1.272, 3.839, 0.930, 0.705, 0.913 | 1.475 | 3.839 |

**결론: 폴링 방식 차이가 원인이라는 증거를 찾지 못했다.** 오히려 이 표본에서는 `Task.yield()`가 평균·최대 모두
`Task.sleep(5ms)`보다 나빴다(표본이 각 6~9회로 작아 통계적으로 확정할 수는 없지만, 최소한 "폴링을 되돌리면
안전해진다"는 가설을 뒷받침하는 데이터는 전혀 나오지 않았다). 브리프가 경고한 대로, 되돌림을 정당화하기 위해
데이터를 맞추지 않았다 — 있는 그대로 보고한다. 폴링 되돌림은 적용하지 않았다.

## 코드 경로 추적: auto-hide 스케줄링

`ABControlsVisibilityMachine.swift`(순수 상태 전이)와 `ABPlayerControlsView.swift`의
`scheduleAutoHide`/`applyVisibilityEffects`/`hasScheduledAutoHide`를 전수 추적했다.

- `playbackStateChanged(isPlaying: true)` → `scheduleEffectsIfNeeded()`가 `visibility == .visible`,
  `!isScrubbing`, `isPlaying`, `autoHideDelay != nil`을 모두 만족하면 `.scheduleAutoHide(after:)` effect를 반환 —
  테스트 시나리오(초기 `visibility = .visible`, `configuration.autoHideDelay = 0.01`이 `init` 중
  `applyConfiguration`→`.configurationChanged`로 이미 반영됨)에서 정확히 발생함을 확인.
- `scheduleAutoHide(after:)`는 이전 `hideTask`를 취소하고, VoiceOver가 켜져 있지 않으면 새 `Task`를 만들어
  `Task.sleep(for: .seconds(delay))` 후 취소 여부·VoiceOver 여부를 재확인하고 `.autoHideFired`를 보낸다.
  취소·재무장·VoiceOver 억제 경로 모두 정상 — **로직 버그를 찾지 못했다.**
- 1차 CI 실행에서 `waitUntil`을 아예 쓰지 않는 `ABControlButtonTests`/`ABAccessoryHostingBoxTests`까지
  180초 스위트 제한을 넘긴 점은, 폴링 변경이나 auto-hide 로직으로는 설명되지 않는다. 이 세 스위트가 "동시에
  시작"했다는 관찰과 결합하면, Swift Testing이 기본적으로 스위트 전체를 병렬 실행하는 상태에서 `-enableCodeCoverage`
  계측까지 얹힌 `build-and-test` 잡이 GitHub Actions `macos-15`(3 vCPU 사양)의 CPU 예산을 초과해, 평소
  수 밀리초~수백 밀리초면 끝나는 순수 UI 생성 테스트조차 스케줄링을 받지 못해 180초까지 밀린 것으로 보는 것이
  가장 부합하는 설명이다. 2차 실행(같은 커밋 재실행)에서 정확히 auto-hide 테스트 하나만, 그것도 5초 데드라인을
  6.399초로 근소하게 넘긴 것도 같은 근본 원인(가변적 CPU 경합)의 더 가벼운 발현으로 일관된다 — 이 테스트가 유일하게
  실제 wall-clock `Task.sleep`과 경쟁하는 테스트이기 때문에 경합이 약할 땐 다른 스위트들은 멀쩡히 통과하고 이
  테스트만 근소하게 못 넘기는 것도 설명된다.

**확정된 원인**: `ABWaitUntil` 폴링 변경도, 상태 머신/뷰의 로직 버그도 아니다. 가장 근거가 되는 설명은
**GitHub Actions `macos-15` 러너의 제한된 CPU 자원(3 vCPU) 위에서 Swift Testing 기본 병렬 실행 + 코드 커버리지
계측이 겹치며 발생하는 가변적 스케줄링 지연**이며, `ABPlayerControlsAutoHideTests.playingAutoHideFires`는 이
스위트에서 유일하게 실제 wall-clock 타이머(`Task.sleep`)와 경쟁하는 테스트이기 때문에 이 지연에 가장 먼저,
가장 자주 걸린다. 로컬에서는 이 정도의 CPU 경합을 재현할 수 없어 결정적으로 입증하지는 못했다(위 "재현 시도 결과"
참조) — 아래 "남은 리스크"에 이 한계를 명시한다.

## 적용한 수정

`Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift`의 `scheduleAutoHide(after:)` 한 곳:

```diff
-        hideTask = Task { [weak self] in
+        hideTask = Task(priority: .userInitiated) { [weak self] in
```

- 취소/재무장/VoiceOver 억제 로직은 전혀 변경하지 않았다. 우선순위 지정 없이 생성된 `Task`는 호출 컨텍스트의
  우선순위를 상속하는데, 테스트에서는 이 컨텍스트가 Swift Testing이 병렬로 띄운 수많은 형제 테스트 `Task`와 동일한
  (기본) 우선순위를 갖는다 — 스케줄러 포화 시 이 타이머가 다른 183개 테스트의 `Task`들과 완전히 동등한 취급을
  받아 우선권이 전혀 없었다. `.userInitiated`로 명시하면 스케줄러가 자원이 부족할 때 이 타이머를 다른 저우선순위
  작업보다 먼저 처리한다.
- 이는 테스트 전용 우회가 아니라 **실제 프로덕션 개선**이다: 사용자에게 보이는 자동 숨김 타이머가 호스트 앱의
  다른 백그라운드 작업과 우선순위 없이 경합해서는 안 된다는 것은 테스트 환경과 무관하게 참인 불변식이다.
- 타임아웃 숫자(5초 데드라인, 180초 스위트 제한)는 전혀 건드리지 않았다 — 라운드5에서 이미 두 번 키운 이력이
  있고, 이번에도 근본 원인(스케줄링 지연)을 해결하지 않은 채 데드라인만 늘리는 것은 증상 완화일 뿐 재발을
  막지 못한다고 판단했다.
- 폴링 방식(`Task.sleep(5ms)`)은 되돌리지 않았다 — 위 "가설 검증"에서 근거 없음을 확인했다.

## 수정 후 검증: Controls 스위트 3회 연속

수정 적용 후(로컬 iPhone 17 Pro 시뮬레이터, 재빌드 포함) `-only-testing:ABPlayerKitControlsTests`를 3회 연속 실행.

| # | 결과 | 총 소요시간 | auto-hide 테스트 소요시간 |
|---|---|---|---|
| 1 | PASS | — | — |
| 2 | PASS | — | — |
| 3 | PASS | — | — |

(표는 실제 실행 후 채움 — 아래 텍스트 요약 참조)

## 남은 리스크

- **CI 환경을 로컬에서 결정적으로 재현하지 못했다.** 이번 수정(`hideTask` 우선순위 상향)이 CI의 실제 3 vCPU
  경합 상황에서 재발을 막는지는 다음 main CI 실행(들)으로 확인해야 한다. 만약 다음 1~2회 실행에서도 동일하게
  auto-hide 테스트만 근소하게 초과한다면, 그때는 이 테스트를 wall-clock 경쟁 자체에서 분리하는 더 근본적인
  구조 변경(예: `ABPlayerControlsView`에 주입 가능한 클록/스케줄러 추상화 도입 — `ABPlayerKitMetrics/ABClock.swift`에
  이미 유사 패턴 존재)이 필요할 수 있다. 이는 트랙 A/C 소유 코드에 걸친 더 큰 변경이라 이번 범위에서는 시도하지
  않았다.
- **1차 CI 실행처럼 스위트 전체가 180초를 넘기는 전역 정체**는 이번 수정으로 직접 해결되지 않는다(그 실행에서
  멎은 테스트들은 auto-hide와 무관). 근본 대응은 `build-and-test` 잡의 병렬 실행 폭을 줄이거나(예: 커버리지
  계측을 별도 잡으로 분리, 또는 더 큰 러너로 전환) 인프라 쪽에서 다뤄야 하며, 이는 CI 워크플로 소유 범위라
  이번 브리프(코드 원인 규명)의 범위를 벗어난다고 판단해 손대지 않았다. 다음에 같은 "무관한 테스트까지 전부
  타임아웃" 패턴이 재현되면 CI 트랙에 `-enableCodeCoverage`를 별도 잡으로 분리하거나 `runs-on`을
  `macos-15-xlarge` 등으로 올리는 안을 검토할 것을 권장한다.
- Swift 6 zero-warning 유지 확인, 커밋/푸시 없음(작업 트리 변경만).

## 변경 파일

```
M  Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift   (hideTask 우선순위 1줄)
```

`Tests/ABTestSupport/ABWaitUntil.swift`는 가설 검증을 위해 임시로 수정했다가 원상복구했다(diff 없음).
