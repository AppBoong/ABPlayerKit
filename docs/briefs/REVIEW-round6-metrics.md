# REVIEW: 라운드6 트랙 F 게이트 (F-7)

## 판정

**APPROVE**

---

## 1. 독립 실행 결과

**전체 스킴 3회 연속** (`xcodebuild -scheme ABPlayerKit-Package ... build test`, 시뮬레이터 `60DA735B-87EC-4159-9BE3-EF981A127FAF`, 직접 부팅된 기기 재사용, `-only-testing` 미사용):

| 회차 | 결과 | 테스트 수 | 실패 |
|---|---|---|---|
| RUN 1 | `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` | Cache 72 + Controls 200 + Metrics 49 + Core 250 = **571** | **0** |
| RUN 2 | 동일 | 571 | 0 |
| RUN 3 | 동일 | 571 | 0 |

3회 모두 `xcodebuild` exit code `0`을 직접 확인했다(로그: `gate-run.log`, 4785줄). RESULT 문서의 571/0 주장과 일치한다.

**주의**: 1차 시도는 게이트 스크립트 자체의 버그(zsh에서 `status`가 읽기 전용 예약 변수라 `status=$?` 대입이 즉시 에러를 내며 스크립트가 중단됨)로 RUN 1이 4개 테스트 타깃 중 1개(Core, 250개)만 완료한 채 조용히 죽었다. `rc`로 변수명을 바꿔 재실행해 위 3회를 모두 처음부터 다시 얻었다 — 구현 코드와는 무관한, 게이트 측 스크립트 오류였다.

**docbuild** (`DOCC_WARNINGS_AS_ERRORS=YES`): `** BUILD DOCUMENTATION SUCCEEDED **`. 로그 전체(`docbuild.log`)에 실제 `warning:` 라인이 **0건** — RESULT가 언급한 "Controls docc의 View/EnvironmentValues 미해결 경고"는 이번 실행에서 재현되지 않았다(경고 자체가 없어 실패로 이어질 수도 없는 상태). `git stash`를 이용한 base 대비 비교는 이 세션의 권한 분류기(permission classifier)가 차단해 수행하지 못했지만, 애초에 현재 트리에 경고가 0건이므로 트랙 F 귀책 여부를 판단할 대상 자체가 없다 — 판정에 영향 없음(비차단 관찰 §6 참고).

**데모 빌드**: `xcodebuild -project .../ABPlayerKitDemo.xcodeproj ...` → `** BUILD SUCCEEDED **`. 추가로 게이트가 직접 `xcrun simctl install`/`launch`로 시뮬레이터에 설치·실행해 Playback 탭이 정상 렌더링됨을 스크린샷으로 확인했다(크래시 없음, HLS 소스 재생 준비 상태 도달). Metrics 탭 전환은 이 환경에 Simulator.app GUI 프로세스가 노출되지 않아(System Events로 확인 — foreground 프로세스 목록에 Simulator 없음) 탭 좌표 입력 수단이 없어 인터랙션 검증은 여전히 불가했다 — RESULT가 보고한 것과 동일한 환경 제약을 게이트가 독립적으로 재확인했다.

**SwiftLint**: `swiftlint --strict` → `Found 0 violations, 0 serious in 147 files.`

---

## 2. 파일 경계

```
CHANGELOG.md                                       |  22 ++
Examples/.../DemoModel.swift                       |  59 +++-
Examples/.../MetricsScreen.swift                   |  35 +-
Sources/ABPlayerKitMetrics/ABClock.swift           |   6 +
Sources/ABPlayerKitMetrics/ABMetricEvent.swift     |  54 +++-
Sources/ABPlayerKitMetrics/ABMetricsRecorder.swift | 203 +++++++++++-
Sources/ABPlayerKitMetrics/ABMetricsSink.swift     | 359 ++++++++++++++++++---
Sources/ABPlayerKitMetrics/ABPlaybackStatistics.swift |  28 +-
Sources/ABPlayerKitMetrics/*.docc/*.md             |  21 ++
+ 신규 파일: ABLatencyDistribution.swift, ABQoESummary.swift, Model/*.swift(4),
  Session/*.swift(3), Tests/ABPlayerKitMetricsTests/*.swift(3 신규)
```

`git diff --stat main -- Sources/ABPlayerKit Sources/ABPlayerKitControls Sources/ABPlayerKitCache Package.swift .github Tests`(Metrics 제외)를 직접 실행 — **0줄**. `Tests/` 중 `ABPlayerKitMetricsTests` 밖의 diff도 **0줄**. 위반 없음.

---

## 3. 무회귀 하드 제약

- **기존 테스트 8개 무수정**: `git diff main -- Tests/ABPlayerKitMetricsTests/ABMetricsTests.swift` → 0줄. 직접 확인.
- **JSONL v1 바이트 동일**: `git show main:.../ABMetricsSink.swift`로 base 인코딩 로직을 통째로 대조 — `ttff`/`stall`/`preloadStarted`/`itemDetached`/`tuning` 5종의 키 이름·타입·문자열 변환 로직이 라인 단위로 동일함을 직접 확인했다(리팩터링된 코드지만 산출 형태는 불변). `access` 서브오브젝트는 기존 5키 유지 + 신규 키 추가만(R2 준수). 추가로 `ABJSONLinesSinkTests.swift`의 골든 바이트 테스트(`goldenStallEventIsByteIdentical`, `v1RecordShapesAreUnchanged`, `itemDetachedAccessKeepsLegacyKeys` 등)가 이를 기계적으로 잠근다.
- **`ABMetricEvent` 기존 5케이스 시그니처 불변, 신규 4케이스 전부 additive**: 소스 직접 확인.
- **`ABPlaybackStatistics.p50/p95/max` 의미 불변**: `ABLatencyDistribution.percentile`의 `rank = max(1, Int(ceil(percentile * count)))` 공식이 base의 `percentile` 함수와 완전히 동일한 것을 직접 대조했다. `successfulDurations`(`.hit`을 0으로 포함)를 그대로 `legacy` 분포 산출에 사용하고, `waited`만 별도 배열로 분리 — 레거시 필드의 계산 경로 자체가 손대지 않았다.
- **비범위 항목 미구현**: `grep`으로 타이머(`Timer(`/`scheduledTimer`/`heartbeat`), 네트워크 전송(`URLSession`/`dataTask`), 콘텐츠 시간 누적(`.rate` 참조), 샘플링/캡 정책, 데모 차트(`Chart(`/`LineMark`/`import Charts`)를 신규·수정 소스 전체에서 검색 — 전부 0건.

---

## 4. 설계 이탈 3건 판정

1. **`segmentsDownloadedCount`가 항상 0** — **수용**. `AVPlayerItemAccessLogEvent.numberOfSegmentsDownloaded`가 Swift에서 unavailable이라는 주장을 게이트가 직접 `swiftc -typecheck`로 재현해 확인했다(`'numberOfSegmentsDownloaded' is unavailable in iOS: APIs deprecated as of iOS 7 and earlier are unavailable in Swift`). 필드를 스키마에 유지하고 DocC/CHANGELOG에 명시한 처리가 적절하다. 공개 계약 영향: 없음(필드는 존재하되 값이 항상 0이라는 사실이 문서화됨).

2. **`ABSessionSummary.hasDisplayedFirstFrame` 추가** — **수용**. `ABSessionSummary`는 이번 라운드에 신설되는 타입이라(§8.2 자체가 v2 스키마 초안) 깨질 기존 소비자 계약이 없다. `sessionSummary` JSONL 레코드에 키가 하나 늘었지만, R1/R2(바이트 동일성)는 기존 5종 레거시 레코드에만 적용되고 `sessionSummary`는 애초에 신규 이벤트(R3 대상)다. 완료율 계산에 필요한 최소 필드라는 근거(TTFF 미측정 세션도 첫 프레임은 볼 수 있어 다른 필드로 역산 불가)가 타당하다. 공개 계약 영향: 없음.

3. **재-attach 시 이전 세션을 `.finalized`로 강제 종료** — **수용**. `ABPlaybackSessionAccumulator.ingest(.attached...)`에서 `isOpen`이면 `close(..., endReason: .finalized, access: nil, ...)`을 먼저 호출한 뒤 새 세션을 여는 코드를 직접 확인했고, 전용 표 테스트(`reattachWithoutDetachFinalizesPreviousSession`)로 이벤트 순서(`sessionSummary` → `sessionStarted`)까지 단언되어 있다. 대안(열어 둔 채 방치)은 요약이 영원히 나오지 않는 조용한 유실이 되므로 이 쪽이 명백히 낫다. 종료된 세션과 새로 열린 세션 각각의 내부 이벤트 순서는 §8.4 계약(세션 시작 → … → 세션 종료)을 세션 단위로는 그대로 지킨다 — 코어가 실제 `.detachItem`을 거치지 않는 경로이므로 레거시 `.itemDetached`가 끼지 않는 것도 설계상 자연스럽다. 공개 계약 영향: 없음(신규 동작 자체가 이번 라운드에 처음 정의됨).

**RESULT §6이 스스로 불안하다고 지목한 항목**도 확인했다:
- `bitrateSwitchCount`(인접 엔트리만 비교, 양쪽 > 0일 때만): 소스(`ABAccessLogFolder.fold`)가 설계 §5.2가 명시적으로 결정하고 `entryCount - 1` 대안을 기각한 바로 그 정의와 정확히 일치한다. 실 CDN 로그로 검증하지 못했다는 고백은 정직한 관찰이지 결함이 아니다(설계가 이미 이 정의를 확정했으므로 F-7 판정 대상이 아니다).
- 데모 탭 미검증: §1에서 게이트가 독립적으로 재확인 — 같은 환경 제약, 계산 로직은 단위 테스트로 커버됨. 비차단.

---

## 5. 지적 사항

없음.

---

## 6. 비차단 관찰

1. `git stash`를 이용한 base 대비 docbuild 경고 비교를 이 세션의 도구 권한 분류기가 차단했다. 게이트의 원칙(§1 "실행하지 않은 것을 통과라고 쓰지 마라")에 따라 시도했음을 기록한다 — 다만 현재 트리의 docbuild 자체가 경고 0건으로 완전히 클린하므로("Controls docc 경고가 base에도 있다"는 RESULT의 서술은 이번 게이트 실행에서 재현되지 않았다) 결론에는 영향이 없다.
2. 데모 Metrics 탭의 실제 탭 전환·카드 렌더링은 이번에도 인터랙티브하게 확인하지 못했다(헤드리스 환경에 Simulator.app GUI 프로세스가 노출되지 않음 — `System Events`로 재확인). 값 계산 로직은 `ABQoEAggregationTests`/`ABSessionAccumulatorTests`가 전부 커버한다. 다음에 GUI가 있는 환경에서 한 번은 눈으로 확인해 두는 편이 좋다.
3. `ABMetricsRecorder.deinit`이 명시적 정리 코드를 두지 않고 ARC에 의존하는 설계(결정 1의 "누수 방어")는 `@MainActor` 클래스라 격리 저장소를 deinit에서 건드릴 수 없다는 제약과 일치한다 — 코드로 재확인, 문제 없음.

---

## 다음 단계

APPROVE. 커밋 → 리베이스 → PR로 진행 가능하다.
