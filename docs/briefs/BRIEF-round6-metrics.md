# BRIEF: 라운드6 트랙 F — Metrics QoE 구현

당신은 트랙 F의 **구현자**다. 설계는 이미 승인·확정돼 있다. 당신의 일은 설계를 그대로 구현하고, 아래 검증 프로토콜을 실제로 통과시키는 것이다.

작업 디렉터리: `/Users/jymac/orca/workspaces/ABPlayerKit/round6-metrics` (브랜치 `AppBoong/round6-metrics`, base `main` = `d29e231`)

---

## 1. 필독 문서 (이 순서로)

1. `docs/briefs/DESIGN-round6-metrics.md` — **당신의 설계 문서. 전문을 읽어라.** 결정 1~7, §8 스키마 전체 표, §9 WP별 구현 지침, §10 무회귀 가드, §13 비범위가 모두 확정 사항이다.
2. `docs/briefs/DESIGN-round6-core.md` §3.2 / §5.5 — 트랙 A가 이미 구현해 main에 병합한 이벤트 표면. **설계 문서가 전제한 9종 이벤트는 실코드에 존재한다.** 그대로 신뢰해도 된다.
3. `docs/briefs/ROADMAP-round6.md` §3 트랙 F 표 — WP와 감사 ID 대응.

설계 문서와 이 브리프가 충돌하면 **설계 문서가 우선**한다. 단, §5 검증 프로토콜과 §6 규칙은 이 브리프가 우선한다.

---

## 2. 범위 — F-1w ~ F-6w

| WP | 내용 | 설계 참조 |
|---|---|---|
| F-1w | 세션 스캐폴딩(`ABPlaybackSessionAccumulator`, `(playerID, sessionStartedAt)` 복합 키) + 리버퍼 구간 | 결정 1·2·6, §9 F-1w |
| F-2w | watch time + 완료율 | 결정 3, §9 F-2w |
| F-3w | 실패 이벤트(`.failureReported` 소비) | 결정 4, §9 F-3w |
| F-4w | `.hit`/waited 분포 분리 + accessLog 전체 순회 + 집계 v2 | 결정 5, §9 F-4w |
| F-5w | 싱크 개선(`flush()` 공개, 핸들 유지, 에러 카운터, 타임스탬프 앵커) | 결정 7, §9 F-5w |
| F-6w | 데모 Metrics 탭 확장 | §9 F-6w |

WP 순서대로 진행하고, 각 WP를 논리적으로 완결시킨 뒤 다음으로 넘어가라(커밋은 하지 말 것 — §6 참조).

### 반드시 지킬 하드 제약

- **JSONL v1 레코드는 바이트 동일 하위호환.** 설계 §7.1의 규칙을 그대로 따른다. 기존 키의 이름·타입·의미를 바꾸지 않고, 신규 필드는 추가만 한다.
- **기존 Metrics 테스트 8개는 한 줄도 수정하지 않는다**(설계 §10.1). 수정이 필요하다고 판단되면 그것은 설계 위반 신호다 — 수정하지 말고 `RESULT` 문서에 사유와 함께 보고하라.
- **`ABMetricEvent` 기존 케이스 변경·삭제 금지.** 신규는 전부 additive.
- 설계 §13의 비범위 항목은 **구현하지 마라**(하트비트 타이머, 네트워크 전송, 콘텐츠 시간 누적, 샘플링/캡 정책, 데모 차트 시각화 등).

### 설계가 남긴 확인 항목 (당신이 실코드로 검증할 것)

설계 §12는 트랙 A에 세 가지를 확인 요청했다. 트랙 A는 이미 병합됐으므로 **당신이 직접 코드를 읽고 확인**하라:

1. `.itemAttached(source:)` 방송 시점에 `player.avPlayerItem`이 비-nil인가? (F의 세션 아이템 보유가 여기에 의존)
2. `.itemDetached`가 release/sourceChanged/demotion/backgroundPolicy 전 경로에서 정확히 1회인가? (F의 세션 종료가 여기에 의존)
3. `ABPlayerError`가 `Hashable`인가? — **비차단**. 아니면 `ABErrorOrigin` 기준 집계로 진행한다(설계가 그렇게 닫아 뒀다). `ABPlayerError`를 수정하지 마라(코어 파일 경계 위반).

**가정이 깨지면 우회하지 말고 `RESULT` 문서에 그대로 보고하라.** 가정을 지지하는 데이터가 없으면 없다고 쓰는 것이 정답이다.

---

## 3. 파일 경계 (위반 시 게이트 REQUEST-CHANGES)

**수정 허용:**
- `Sources/ABPlayerKitMetrics/**`
- `Tests/ABPlayerKitMetricsTests/**`
- `Examples/ABPlayerKitDemo/**` — 단 **메트릭 관련 프로퍼티/메서드만**. `MetricsScreen.swift`와 `DemoModel.swift`의 메트릭 영역은 F 소유다.
- `CHANGELOG.md` — 초안이 아니라 **실제 파일에 반영**할 것.

**수정 금지 (diff 0줄):**
- `Sources/ABPlayerKit/**`, `Sources/ABPlayerKitControls/**`, `Sources/ABPlayerKitCache/**`
- `Tests/` 중 `ABPlayerKitMetricsTests` 이외 전부
- `Package.swift`, `.github/**`

---

## 4. 시뮬레이터

이미 부팅된 기기를 **재사용**하라. 새로 부팅·생성하지 마라.

```
iPhone 17 Pro Max — 60DA735B-87EC-4159-9BE3-EF981A127FAF (iOS 26.2, Booted)
```

부팅된 기기가 없으면 위 UDID 하나만 부팅하고, 다른 기기는 건드리지 마라. 이 기기는 다른 트랙과 **공유**한다.

---

## 5. 검증 프로토콜 (필수 — 이걸 통과하지 못하면 완료가 아니다)

### 5.1 전체 스킴 3회 연속 그린

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

**`-only-testing:`으로 좁힌 결과는 근거로 인정하지 않는다.** 라운드6 Wave 1에서 두 트랙이 자기 타깃만 돌리고 PR을 올렸다가 **둘 다 CI에서 실패**했고, 실패는 전부 자기 타깃 밖에 있었다. 개발 중 빠른 반복에는 좁혀 써도 되지만, **완료 판정은 반드시 전체 스킴 3회 연속 그린**이다.

### 5.2 CI가 돌리는 나머지도 로컬에서 통과시켜라

```bash
# DocC (신규 공개 심볼이 있으므로 필수)
xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  DOCC_WARNINGS_AS_ERRORS=YES EXTRACT_APP_INTENTS_METADATA=NO docbuild

# 데모 (F-6w가 데모를 건드리므로 필수)
xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj \
  -scheme ABPlayerKitDemo -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  EXTRACT_APP_INTENTS_METADATA=NO build

# SwiftLint (CI lint 잡)
swiftlint --strict 2>/dev/null || swiftlint
```

### 5.3 CI와 로컬의 격차를 의식하라

CI는 3 vCPU + Xcode 16.4 + iPhone 16 Pro, 로컬은 10코어 + Xcode 26.2 + iPhone 17 Pro Max다. 이번 라운드의 CI 실패 상당수가 "로컬 재현 불가, CI에서만 실패"였고 원인은 **협력 스레드 풀이 좁을 때만 드러나는 스케줄링 기아**였다.

→ 당신의 신규 테스트는 설계가 의도한 대로 **순수·동기(대기 없음)** 로 유지하라. `Task.yield()` 바쁜 대기, 깊은 비동기 사슬, 실제 네트워크 URL 재생을 테스트에 넣지 마라. 대기가 불가피하면 타임아웃 메시지에 진단 정보를 넣어라("무엇을 기다리다 실패했는지" 구분이 가능하게).

---

## 6. 규칙

- **커밋하지 마라.** 커밋은 별도 담당이 WP 경계에 맞춰 수행한다. 당신은 working tree를 깨끗한 상태로 남기고 보고만 하라.
- **새 주석에 리뷰/설계 ID를 인용하지 마라.** `F-1`, `D-2`, `round4 review MJ-1`, `설계 §5.2` 같은 표기가 **신규 주석에 들어가면 안 된다**. 코드는 문서 없이 스스로 설명돼야 한다. 제출 전 `git diff` 의 추가 라인을 ID 패턴으로 **직접 재스캔**하라:
  ```bash
  git diff -U0 | grep '^+' | grep -nE '(^\+.*)(([A-Z]-[0-9]+w?)|(round[0-9])|(§)|(리뷰 ID)|(감사 ID))'
  ```
  히트가 있으면 전부 제거하고 다시 스캔하라. 이번 라운드에 두 트랙이 이걸 위반해 재작업했다.
- `@unchecked Sendable` / `MainActor.assumeIsolated` / `@available(*, deprecated)` **신규 0건**.
- Swift 6 zero-warning.
- CHANGELOG는 **실제 파일에 반영**하라(설계 §10.3의 마이그레이션 노트 5건 포함). 초안만 쓰고 완료 체크한 사례가 있었다.

---

## 7. 완료 보고

전부 끝나면 `docs/briefs/RESULT-round6-metrics.md`를 **새로 만들어** 아래를 담아라. 이 파일의 생성이 완료 신호다 — 그 전에는 만들지 마라.

```markdown
# RESULT: 라운드6 트랙 F

## 1. WP별 완료 상태
(F-1w ~ F-6w 각각: 완료/부분/미착수 + 한 줄 요약)

## 2. 검증 결과
- 전체 스킴 3회: (각 회차 테스트 수 / 실패 수 / 소요 시간)
- docbuild: (경고 0 여부)
- 데모 빌드: (성공 여부)
- SwiftLint: (위반 수)

## 3. 설계 확인 항목 결과
(§2의 확인 3건 각각에 대해 실코드에서 확인한 사실. 가정이 깨졌으면 그대로 기술)

## 4. 설계에서 벗어난 지점
(없으면 "없음". 있으면 각각 사유와 함께)

## 5. 파일 경계 준수
(수정한 파일 전체 목록)

## 6. 게이트가 집중해서 볼 것
(당신이 가장 불안한 부분 3가지)
```

작업을 시작하기 전에 설계 문서 전문을 읽어라. 질문이 생기면 추측하지 말고 `RESULT`에 기록하되, 진행을 막을 정도면 즉시 보고하라.
