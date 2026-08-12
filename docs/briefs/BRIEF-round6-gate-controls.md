# BRIEF: 라운드6 트랙 C 최종 게이트 (C-8)

당신은 트랙 C(Controls UX)의 **최종 게이트**다. 구현은 끝났고 커밋되지 않은 상태로 working tree에 있다. 당신의 일은 **독립적으로 검증하고 APPROVE / REQUEST-CHANGES를 판정**하는 것이다.

작업 디렉터리: `/Users/jymac/orca/workspaces/ABPlayerKit/round6-controls` (브랜치 `AppBoong/round6-controls`, base `main`)

이 트랙은 Wave 2에서 **diff가 가장 크고 기존 테스트 200건을 안고 간다.** 무회귀가 신규 기능보다 우선이다.

---

## 0. 이 게이트의 제1 원칙

**구현자의 보고를 근거로 인정하지 마라.** 이번 라운드에 게이트가 정적 리뷰만으로 "무회귀 PASS"를 냈다가, 이후 실제로 테스트를 돌리자 신규 33건 중 3건이 실패했고 원인이 프로덕션 로직 결함 2건이었던 전례가 있다.

→ **당신은 부팅된 시뮬레이터에서 테스트를 직접 실행한다.** 실행하지 않은 것을 통과라고 쓰지 마라.

동시에 문제를 만들어 내지도 마라. 지적할 때는 **파일:라인과 실패 시나리오**를 대라. 설계가 닫지 않은 구멍을 구현자가 합리적으로 메운 것은 정상적인 구현 판단이다 — 엄격히 볼 것은 그 결정이 **기존 동작이나 공개 계약을 바꾸는지**다.

---

## 1. 입력

1. `docs/briefs/DESIGN-round6-controls.md` — 확정 설계(898줄). 판정 기준의 원본. 특히 §5.1 절대 불변식(I-C1~I-C12), §5.2 수정 금지 테스트 파일, §5.3 사전 승인된 변경, §7 완료 정의 체크리스트.
2. `docs/briefs/BRIEF-round6-controls.md` — 구현자가 받은 지시.
3. `docs/briefs/RESULT-round6-controls.md` — 구현자 보고. **검증 대상이지 근거가 아니다.**
4. `git status` / `git diff`.

---

## 2. 반드시 실행할 검증

### 2.1 전체 스킴 3회 연속 그린 (독립 실행)

이미 부팅된 기기를 재사용하라. **새로 부팅·생성하지 마라.**

```bash
cd /Users/jymac/orca/workspaces/ABPlayerKit/round6-controls
DEST='platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF'
for i in 1 2 3; do
  echo "=== RUN $i ==="
  xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" \
    -derivedDataPath .dd \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    EXTRACT_APP_INTENTS_METADATA=NO build test || { echo "RUN $i FAILED"; break; }
done
```

셸 스크립트를 쓸 때 zsh에서 `status`는 읽기 전용 예약 변수다 — `status=$?`로 대입하면 스크립트가 그 자리에서 죽는다. 다른 변수명을 써라(직전 게이트가 이걸로 한 번 헛돌았다).

`-only-testing`으로 좁힌 결과는 인정하지 않는다. **실제 테스트 수와 실패 수를 기록하라.**

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

### 2.3 파일 경계

**diff 0줄이어야 함** (직접 `git diff --stat`으로 확인):
- `Sources/ABPlayerKitControls/SwiftUI/` 4파일 전부 — 설계 §0의 자기 선언 제약
- `Sources/ABPlayerKit/**`, `Sources/ABPlayerKitMetrics/**`, `Sources/ABPlayerKitCache/**`
- `Package.swift`, `.github/**`, `Examples/**`
- `Tests/` 중 `ABPlayerKitControlsTests` 이외 전부

한 줄이라도 벗어났으면 REQUEST-CHANGES다.

### 2.4 무회귀 하드 제약

- **설계 §5.2의 수정 금지 테스트 파일이 실제로 무수정인가.**
- **§5.3 사전 승인 범위를 넘는 기존 테스트 변경이 없는가.** 구현자는 정확히 2줄(`liveMarker` → 로컬라이즈 키 치환)만 바꿨다고 보고했다. `git diff`로 기존 테스트 파일들의 변경이 **말미 추가**인지 **기존 케이스 수정**인지 직접 구분하라 — 이것이 이 트랙에서 가장 중요한 검증이다.
- **설계 §5.1의 절대 불변식 I-C1~I-C12** 각각에 대응 테스트가 존재하고 통과하는가(특히 I-C2·I-C3·I-C4·I-C7·I-C10).
- **hitTest 우선순위 매트릭스**: 4버튼 × 슬롯 3종 × 시크바 × 패스스루 3케이스. 실제로 그 케이스들이 테스트로 존재하는지 세어 보라.
- **스타일 facet 소진성 테스트**(`Mirror` 라벨 집합 일치)가 존재하고 통과하는가.
- 신규 localized 키가 **en/ko 양쪽**에 존재하는가.

### 2.5 위생

```bash
git diff -U0 -- Sources Tests | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(round[0-9])|(§)|(리뷰 ID)|(감사 ID))'
git diff -U0 -- Sources Tests | grep '^+' | grep -nE '@unchecked Sendable|MainActor\.assumeIsolated|@available\(\*, deprecated'
```

신규 파일은 `git diff`에 안 잡히니 **`git status`의 untracked 신규 파일도 같은 패턴으로 스캔하라.** 문서(`docs/briefs/**`)의 히트는 무시하라 — 금지 대상은 소스 주석이다.

- CHANGELOG가 실제 파일에 반영됐는가(설계 §7이 요구하는 `### Added` / `### Changed` 항목 + 마이그레이션 노트).
- 신규 공개 심볼이 DocC에 큐레이션됐는가.

---

## 3. 집중 검토 — 구현자가 스스로 지목한 3건 + 자체 판단 2건

### 3.1 D-10(Style `Sendable`화) 이월 — **오케스트레이터가 사유를 이미 확인했다**

구현자는 "로컬에 Xcode 16.4가 없어 설계 §5.2가 요구한 CI 툴체인 선검증을 수행할 수 없었다"는 이유로 이월했다. **이 사실관계는 오케스트레이터가 독립 확인했다 — 이 머신에는 Xcode 26.2만 설치돼 있다.** 따라서 당신도 CI 툴체인 선검증은 할 수 없다. 그 점으로 REQUEST-CHANGES 하지 마라.

당신이 판단할 것은 두 가지다:
1. **C-7w의 나머지(facet 레지스트리, D-9 미러 제거)가 D-10과 독립적으로 온전히 완료됐는가.** 그렇다면 부분 완료가 유효하다.
2. **참고 정보로**: 현재 툴체인(Xcode 26.2)에서 5개 타입에 `Sendable`을 부착하면 컴파일되는가? 이건 필요조건일 뿐 충분조건이 아니지만(CI는 16.4), 데이터가 있으면 오케스트레이터가 "PR CI에서 시도해 볼지" 판단할 수 있다. **시도해 보고 결과만 보고하라 — 성공해도 그 상태를 커밋하거나 남기지 말고 반드시 원복하라.** 판단은 오케스트레이터가 한다.

### 3.2 hitTest 문구 차이 (RESULT §5.3)

구현자는 설계 §7 테스트 표의 "`.whenControlsHidden` + 표시 + 빈 영역 → `view`"가 실제로는 `controlsContentView`를 반환한다는 것을 발견하고 테스트를 다른 불변식으로 다시 썼다. **이것을 검증하라**: (a) 그것이 정말 기존 아키텍처의 산물인지(`controlsContentView`의 풀바운드 배치가 이번 라운드 이전부터 있었는지 `git log`/`git show main:`으로 확인), (b) 다시 쓴 불변식이 **의미를 약화시키지 않는지**, (c) 설계 §5.1의 I-C2를 침해하지 않는지.

### 3.3 VoiceOver 배지 "+0s" 경로 (RESULT §7-3)

구현자가 **고치지 않기로 결정한 알려진 결함**이다. `.accessibilityAdjusted`의 낙관적 사전 렌더 때문에 스트리크 첫 `seekTargetChanged` 시점에 앵커가 이미 전진해 배지가 "+0s"를 보일 수 있다고 한다. 판단하라: 이것이 설계 §6.2의 "VoiceOver 라벨/커맨드 일치" 요구사항 위반인가, 아니면 허용 가능한 한계인가. **배지는 시각 채널이고 VoiceOver 사용자의 주 채널은 스포큰 값**이라는 구현자 논거가 타당한지 따져라. 위반이라고 판단하면 차단 지적으로 올려라.

### 3.4 자체 판단으로 추가한 방어 코드 (RESULT §5.4)

`.detached` 시 `isBuffering`이었으면 `.setBuffering(false)`를 방출하도록 1줄 추가했다. **타당한지, 그리고 기존 보호 테스트를 무력화하지 않는지 확인하라.**

### 3.5 auto-hide 가설 "기각" 판정 (RESULT §3)

구현자는 브리프가 제시한 가설을 **기각**했다. 근거는 "지목된 테스트가 `staysVisibleWhilePaused = false`를 설정하므로 스케줄 게이트가 `isPlaying`과 무관하게 항상 참"이라는 것이다. **이 논거를 실코드로 검증하라.** 기각이 맞으면 맞다고 판정하라 — 정직한 기각은 잘못된 되돌림보다 낫다. 다만 근거가 틀렸다면 그것은 차단 지적이다.

---

## 4. 판정과 산출물

`docs/briefs/REVIEW-round6-controls.md`를 **새로 만들어** 아래를 담아라. 이 파일의 생성이 완료 신호다.

```markdown
# REVIEW: 라운드6 트랙 C 게이트 (C-8)

## 판정
**APPROVE** 또는 **REQUEST-CHANGES**

## 1. 독립 실행 결과
(전체 스킴 3회 직접 실행 결과: 회차별 테스트 수 / 실패 수. docbuild / 데모 / SwiftLint)

## 2. 파일 경계
(SwiftUI 4파일 diff 0줄 포함, 위반 여부)

## 3. 무회귀
- 기존 테스트 무수정 여부 (승인 2줄 외 변경이 있는지 직접 확인한 결과)
- I-C1~I-C12 대응 테스트 존재/통과
- hitTest 매트릭스 케이스 수
- facet 소진성 테스트 / en·ko 키

## 4. 집중 검토 5건 판정
(3.1~3.5 각각 수용/거부 + 사유)

## 5. 지적 사항
(파일:라인 + 실패 시나리오. 차단 / 비차단 구분)

## 6. 비차단 관찰
```

**REQUEST-CHANGES면 무엇을 어떻게 고쳐야 하는지 구체적으로 적어라.**

커밋하지 마라. 코드를 고치지도 마라 — 당신은 판정만 한다. §3.1의 `Sendable` 시도처럼 검증 목적의 임시 조작은 허용되며, **반드시 원상복구하고 그 사실을 보고하라.**
