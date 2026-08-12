# BRIEF: 라운드6 트랙 F 최종 게이트 (F-7)

당신은 트랙 F(Metrics QoE)의 **최종 게이트**다. 구현은 끝났고 커밋되지 않은 상태로 working tree에 있다. 당신의 일은 **독립적으로 검증하고 APPROVE / REQUEST-CHANGES를 판정**하는 것이다.

작업 디렉터리: `/Users/jymac/orca/workspaces/ABPlayerKit/round6-metrics` (브랜치 `AppBoong/round6-metrics`, base `main` = `d29e231`)

---

## 0. 이 게이트의 제1 원칙

**구현자의 보고를 근거로 인정하지 마라.** 이번 라운드에 게이트가 정적 리뷰만으로 "무회귀 PASS"를 냈다가, 이후 실제로 테스트를 돌리자 **신규 33건 중 3건이 실패**했고 원인이 프로덕션 로직 결함 2건이었던 전례가 있다. 정적 리뷰가 놓치는 종류의 결함이다.

→ **당신은 부팅된 시뮬레이터에서 테스트를 직접 실행한다.** 실행하지 않은 것을 통과라고 쓰지 마라.

동시에, 문제를 만들어 내지도 마라. 근거 없는 지적은 트랙을 지연시킬 뿐이다. 지적할 때는 **파일:라인과 실패 시나리오**를 대라.

---

## 1. 입력

1. `docs/briefs/DESIGN-round6-metrics.md` — 확정 설계. 판정 기준의 원본이다.
2. `docs/briefs/BRIEF-round6-metrics.md` — 구현자가 받은 지시(파일 경계·규칙·검증 조건).
3. `docs/briefs/RESULT-round6-metrics.md` — 구현자 보고. **검증 대상이지 근거가 아니다.**
4. `git status` / `git diff` — 실제 변경분.

---

## 2. 반드시 실행할 검증

### 2.1 전체 스킴 3회 연속 그린 (독립 실행)

이미 부팅된 기기를 재사용하라. **새로 부팅·생성하지 마라.** 다른 트랙과 공유한다.

```bash
cd /Users/jymac/orca/workspaces/ABPlayerKit/round6-metrics
DEST='platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF'
for i in 1 2 3; do
  echo "=== RUN $i ==="
  xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" \
    -derivedDataPath .dd \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    EXTRACT_APP_INTENTS_METADATA=NO build test || { echo "RUN $i FAILED"; break; }
done
```

`-only-testing`으로 좁힌 결과는 인정하지 않는다. 실제 테스트 수와 실패 수를 기록하라.

### 2.2 CI가 돌리는 나머지

```bash
xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  DOCC_WARNINGS_AS_ERRORS=YES EXTRACT_APP_INTENTS_METADATA=NO docbuild

xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj \
  -scheme ABPlayerKitDemo -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  EXTRACT_APP_INTENTS_METADATA=NO build

swiftlint --strict
```

**구현자가 docbuild 경고 중 일부를 "파일 경계 밖의 기존 상태"라고 보고했다. 이것을 검증하라** — `git stash`로 변경을 잠시 물린 뒤 같은 명령을 돌려 그 경고가 base에서도 나는지 확인하는 것이 확실한 방법이다(확인 후 반드시 `git stash pop`으로 되돌릴 것). base에서도 난다면 트랙 F의 책임이 아니다.

### 2.3 파일 경계

```bash
git status --short
git diff --stat
```

**허용**: `Sources/ABPlayerKitMetrics/**`, `Tests/ABPlayerKitMetricsTests/**`, `Examples/ABPlayerKitDemo/**`의 메트릭 관련 멤버, `CHANGELOG.md`, `docs/briefs/**`

**diff 0줄이어야 함**: `Sources/ABPlayerKit/**`, `Sources/ABPlayerKitControls/**`, `Sources/ABPlayerKitCache/**`, `Package.swift`, `.github/**`, `Tests/` 중 Metrics 이외 전부

한 줄이라도 벗어났으면 REQUEST-CHANGES다.

### 2.4 무회귀 하드 제약

- **기존 Metrics 테스트 8개가 한 줄도 수정되지 않았는가?** `git diff Tests/ABPlayerKitMetricsTests/ABMetricsTests.swift`가 비어 있어야 한다.
- **JSONL v1 하위호환** — 설계 §7.1의 규칙 대비 검증. 기존 5종 레코드의 키 이름·타입·값이 **바이트 동일**한가. 신규 키가 기존 레코드에 끼어들지 않았는가. 이것이 이 트랙의 가장 중요한 계약이다. 직접 직렬화 결과를 확인하라.
- **`ABMetricEvent` 기존 케이스가 변경·삭제되지 않았는가.** 추가만 있어야 한다.
- **`ABPlaybackStatistics.p50/p95/max`의 의미가 바뀌지 않았는가.**
- 설계 §13의 비범위 항목이 구현되지 않았는가(하트비트 타이머, 네트워크 전송, 콘텐츠 시간 누적, 샘플링/캡 정책, 데모 차트 시각화).

### 2.5 위생

```bash
# 신규 주석의 리뷰/설계 ID 인용 (0건이어야 함)
git diff -U0 | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(round[0-9])|(§)|(리뷰 ID)|(감사 ID))'

# 금지 패턴 (신규 0건이어야 함)
git diff -U0 | grep '^+' | grep -nE '@unchecked Sendable|MainActor\.assumeIsolated|@available\(\*, deprecated'
```

`docs/briefs/**`의 문서 파일에서 나오는 히트는 무시하라 — 금지 대상은 **소스 주석**이다.

- CHANGELOG가 **실제 파일에 반영**됐는가(설계 §10.3의 마이그레이션 노트 5건 포함). 초안만 쓰고 완료 체크한 사례가 있었다.
- 신규 공개 심볼이 DocC에 큐레이션됐는가.

---

## 3. 집중 검토 — 구현자가 설계에서 벗어났다고 스스로 보고한 3건

`RESULT-round6-metrics.md` §4에 3건이 있다. **각각에 대해 독립적으로 판단하라.** 구현자의 사유가 타당한지, 더 나은 대안이 있었는지, 그리고 **하위호환 계약을 건드리지 않는지**가 핵심이다.

1. **`segmentsDownloadedCount`가 항상 0** — `numberOfSegmentsDownloaded`가 Swift에서 unavailable이라는 주장. **사실인지 직접 확인하라.** 사실이라면 필드를 유지하되 항상 0인 것이 옳은 선택인지, 아니면 DocC에 명시하는 것으로 충분한지 판단하라.
2. **`ABSessionSummary`에 `hasDisplayedFirstFrame` 필드 추가** — 설계 §8.2 필드 표에 없는 추가. 구현자는 완료율 계산에 필요하고 R3 계약 범위 안이라고 주장한다. **`sessionSummary` JSONL 레코드에 키가 추가됐으므로 하위호환 규칙(설계 §7.1) 대비 판정이 필요하다.** 기존 소비자가 깨지는가?
3. **재-attach 시 이전 세션을 `.finalized`로 강제 종료** — 설계가 명시하지 않은 경로를 구현자 판단으로 채웠다. 대안(열린 채 두기)은 데이터 유실이라는 주장이 타당한지, 그리고 이 동작이 설계 §8.4의 **이벤트 순서 계약**을 깨지 않는지 확인하라.

**타당하면 타당하다고 판정하라.** 설계에 없다는 이유만으로 REQUEST-CHANGES 하지 마라 — 설계가 닫지 않은 구멍을 합리적으로 메운 것은 정상적인 구현 판단이다. 다만 그 결정이 **공개 계약을 바꾸는지**는 엄격히 볼 것.

추가로 `RESULT` §6이 스스로 불안하다고 지목한 3건(`bitrateSwitchCount` 정의, 데모 탭 미검증)도 확인하라.

---

## 4. 판정과 산출물

`docs/briefs/REVIEW-round6-metrics.md`를 **새로 만들어** 아래를 담아라. 이 파일의 생성이 완료 신호다.

```markdown
# REVIEW: 라운드6 트랙 F 게이트 (F-7)

## 판정
**APPROVE** 또는 **REQUEST-CHANGES**

## 1. 독립 실행 결과
- 전체 스킴 3회: (직접 실행한 결과. 각 회차 테스트 수 / 실패 수)
- docbuild / 데모 빌드 / SwiftLint
- (docbuild 경고가 base에도 존재하는지 확인한 결과)

## 2. 파일 경계
(git diff --stat 요약 + 위반 여부)

## 3. 무회귀 하드 제약
- 기존 테스트 8개 무수정: (확인 방법과 결과)
- JSONL v1 바이트 동일: (어떻게 확인했는지 — 직렬화 결과 대조 등)
- ABMetricEvent 기존 케이스 / p50·p95·max 의미 / 비범위 항목

## 4. 설계 이탈 3건 판정
(각각 수용/거부 + 사유. 공개 계약 영향 판정 포함)

## 5. 지적 사항
(있으면 파일:라인 + 실패 시나리오. 심각도 구분: 차단 / 비차단)

## 6. 비차단 관찰
(고치지 않아도 되지만 기록해 둘 것)
```

**REQUEST-CHANGES면 무엇을 어떻게 고쳐야 하는지 구체적으로 적어라.** APPROVE면 그다음 단계(커밋 → 리베이스 → PR)로 넘어간다.

커밋하지 마라. 코드를 고치지도 마라 — 당신은 판정만 한다. 단, 검증을 위한 임시 조작(`git stash` 후 복원)은 허용되며, 반드시 원상복구할 것.
