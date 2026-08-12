# BRIEF: 라운드6 트랙 C — Controls UX 구현

당신은 트랙 C의 **구현자**다. 설계는 이미 승인·확정돼 있다. 당신의 일은 설계를 그대로 구현하고, 아래 검증 프로토콜을 실제로 통과시키는 것이다.

작업 디렉터리: `/Users/jymac/orca/workspaces/ABPlayerKit/round6-controls` (브랜치 `AppBoong/round6-controls`, base `main` = `d29e231`)

이 트랙은 Wave 2에서 **diff가 가장 크고, 기존 테스트 184건을 안고 간다.** 무회귀가 신규 기능보다 우선이다.

---

## 1. 필독 문서 (이 순서로)

1. `docs/briefs/DESIGN-round6-controls.md` — **당신의 설계 문서. 전문(898줄)을 읽어라.** 결정 1~6, §3 확정 API 시그니처, §4 WP별 구현 지침과 테스트 전략, §5 리스크와 무회귀 가드, §7 완료 정의가 모두 확정 사항이다.
2. `docs/briefs/DESIGN-round6-core.md` §3.2 / §5.5 — 트랙 A가 이미 구현해 main에 병합한 이벤트 표면. **설계가 전제한 9종 이벤트와 관찰 가능 프로퍼티는 실코드에 존재한다.**
3. `docs/briefs/ROADMAP-round6.md` §3 트랙 C 표 — WP와 감사 ID(D-1~D-11) 대응.

설계 문서와 이 브리프가 충돌하면 **설계 문서가 우선**한다. 단, §5 검증 프로토콜과 §6 규칙은 이 브리프가 우선한다.

---

## 2. 범위 — C-1w ~ C-7w

| WP | 내용 | 설계 참조 |
|---|---|---|
| C-1w | 버퍼링 상태: 아이콘 유지 + 글리프 자리 스피너 오버레이, 해소 축 `isPlaying \|\| isBuffering`, 스톨 중 auto-hide 억제 | 결정 1, §4 C-1w |
| C-2w | skip UI + 코어 누적 시맨틱 소비 + VoiceOver 라벨/커맨드 일치 | §6.2, §4 C-2w |
| C-3w | 더블탭 시크 + `passthroughTouches` + 햅틱 | 결정 2·3, §4 C-3w |
| C-4w | 리플레이(`.playedToEnd` 후 play 탭 → `seekToStart`+play) | §6.1, §4 C-4w |
| C-5w | 배속 로케일(`NumberFormatter`) + 메뉴 타이틀 훅 + `liveMarker` 번역 + 구분자 노출 | §6.3·§6.4, §4 C-5w |
| C-6w | 레이아웃 슬롯 + `showsPlayPauseButton`/`showsSeekBar` | 결정 4, §4 C-6w |
| C-7w | 구조 정리: 스타일 diff 단일화, 프리젠터 미러 제거, Style `Sendable`화 | 결정 5·§6.5, §4 C-7w |

WP 순서대로 진행하고, 각 WP를 논리적으로 완결시킨 뒤 다음으로 넘어가라(커밋은 하지 말 것 — §6 참조).

### 반드시 지킬 하드 제약

- **스킵 누적의 진실원은 코어의 `pendingSeekTime`이다. Controls가 자체 누적기를 두지 않는다.**
- 설계 §5.1의 **절대 불변식**을 위반하면 게이트 REQUEST-CHANGES다. 구현 중 수시로 확인하라.
- 설계 §5.2의 **수정 금지 테스트 파일**은 건드리지 마라. §5.3에 사전 승인된 3줄 변경만 예외다. 그 밖에 기존 테스트를 고쳐야 할 것 같으면 **고치지 말고** `RESULT`에 사유와 함께 보고하라 — 대개는 프로덕션 결함의 신호다.
- 파일 경계: `Sources/ABPlayerKitControls/SwiftUI/` 4개 파일(`ABPlayerControls.swift`, `ABVideoPlayerWithControls.swift`, `ABPlayerControlsEnvironment.swift`, `ABOwnedPlayerBox.swift`)은 **diff 0줄**. 설계 §0이 스스로 선언한 제약이고 트랙 S와의 교집합을 0으로 유지하는 근거다.

### 당신이 실코드로 확인해야 할 것

설계 §6-2가 트랙 A에 확인 요청한 항목이 있다. 트랙 A는 이미 병합됐으므로 **당신이 직접 코드를 읽고 확인**하라:

> `.itemDetached` / `sourceChanged` 이후 `pendingSeekTime`이 `nil`로 리셋되는가? C의 시크 배지는 `seekTargetChanged(nil)`을 소멸 신호로 쓴다. 코어 결정 4는 `resetSeeking()`에서 `nil`이 된다고 했으나, **소스 교체 경로가 반드시 `resetSeeking()`을 지나는지가 명시돼 있지 않다.** 지나지 않으면 배지가 화면에 남는다.

확인 결과를 `RESULT`에 쓰고, 지나지 않는다면 **코어를 고치지 말고**(파일 경계) Controls 쪽에서 방어하는 방법을 설계 범위 안에서 택한 뒤 그 선택을 보고하라.

### 알려진 CI 불안정 — 당신 범위다

`ABPlayerControlsViewTests`의 `"Given duration disappears during scrubbing, controls always end the session"`가 CI에서 **간헐 실패**했다(`hasScheduledAutoHide` 단언에서 실패). `d29e231`이 auto-hide 지연을 테스트 소요보다 길게 잡아 벽시계 경합을 제거했고 그 뒤 1회 그린이다.

설계 검토 시 제기된 가설: **auto-hide 스케줄 여부가 그 시점의 `isPlaying`에 좌우되는데, 코어의 관찰성 미러가 KVO 홉을 거쳐 비동기로 갱신되는 경로가 있어 가시성 판단이 보는 값이 타이밍에 따라 달라진다.**

C-1w(auto-hide 정책)와 C-7w(프리젠터 미러 제거)가 이 코드를 정면으로 건드린다. **이 상호작용을 명시적으로 판단하고 결과를 `RESULT`에 기록하라.** 가설을 지지하는 데이터가 없으면 "기각됨"이라고 그대로 보고하라 — 잘못된 되돌림보다 정직한 기각이 낫다.

---

## 3. 파일 경계 (위반 시 게이트 REQUEST-CHANGES)

**수정 허용:**
- `Sources/ABPlayerKitControls/**` — 단 `SwiftUI/` 하위 4파일 **제외**
- `Tests/ABPlayerKitControlsTests/**` — 단 설계 §5.2 금지 목록 제외, §5.3 사전 승인분만 예외
- `Sources/ABPlayerKitControls/Resources/**` — 신규 localized 키는 **en/ko 양쪽**에 추가
- `CHANGELOG.md` — 초안이 아니라 **실제 파일에 반영**할 것

**수정 금지 (diff 0줄):**
- `Sources/ABPlayerKit/**`, `Sources/ABPlayerKitMetrics/**`, `Sources/ABPlayerKitCache/**`
- `Sources/ABPlayerKitControls/SwiftUI/**`
- `Tests/` 중 `ABPlayerKitControlsTests` 이외 전부
- `Package.swift`, `.github/**`, `Examples/**`

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

**`-only-testing:`으로 좁힌 결과는 근거로 인정하지 않는다.** Wave 1에서 두 트랙이 자기 타깃만 돌리고 PR을 올렸다가 **둘 다 CI에서 실패**했고, 실패는 전부 자기 타깃 밖에 있었다. 개발 중 빠른 반복에는 좁혀 써도 되지만, **완료 판정은 반드시 전체 스킴 3회 연속 그린**이다.

C는 특히 이 규칙이 중요하다 — 당신의 변경이 코어 특성화 테스트나 SwiftUI 테스트를 깨는지는 전체 스킴에서만 드러난다.

### 5.2 CI가 돌리는 나머지도 로컬에서 통과시켜라

```bash
# DocC (신규 공개 심볼이 다수이므로 필수)
xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  DOCC_WARNINGS_AS_ERRORS=YES EXTRACT_APP_INTENTS_METADATA=NO docbuild

# 데모 (Controls 공개 표면이 바뀌므로 컴파일 확인 필수)
xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj \
  -scheme ABPlayerKitDemo -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  EXTRACT_APP_INTENTS_METADATA=NO build

# SwiftLint (CI lint 잡)
swiftlint --strict 2>/dev/null || swiftlint
```

데모가 깨지면 **데모를 고치지 말고**(파일 경계) 공개 표면 설계를 재검토하라 — additive여야 한다. 정말 데모 수정이 필요하면 보고하고 지시를 기다려라.

### 5.3 hitTest 우선순위 매트릭스

설계 §7 완료 정의가 요구한다: **4버튼 × 슬롯 3종 × 시크바 × 패스스루 3케이스**. 이 매트릭스를 커버하는 테스트를 실제로 작성하고 통과시켜라. 패스스루는 hitTest 우선순위 루프 **뒤, 마지막 한 줄**로만 들어간다(설계 §3.2).

### 5.4 CI와 로컬의 격차를 의식하라

CI는 3 vCPU + Xcode 16.4 + iPhone 16 Pro, 로컬은 10코어 + Xcode 26.2 + iPhone 17 Pro Max다. 이번 라운드 CI 실패 상당수가 "로컬 재현 불가, CI에서만 실패"였고 원인은 **협력 스레드 풀이 좁을 때만 드러나는 스케줄링 기아**였다.

→ 신규 테스트에 `Task.yield()` 바쁜 대기, 불필요하게 깊은 비동기 사슬, 실제 네트워크 URL 재생을 넣지 마라. 타이머에 의존하는 단언은 **테스트 소요보다 긴 지연**을 명시적으로 주입하라(`d29e231`이 그렇게 고쳤다). 대기 헬퍼의 타임아웃 메시지에는 진단 정보를 넣어라.

---

## 6. 규칙

- **커밋하지 마라.** 커밋은 별도 담당이 WP 경계에 맞춰 수행한다. 당신은 working tree를 깨끗한 상태로 남기고 보고만 하라.
- **새 주석에 리뷰/설계 ID를 인용하지 마라.** `D-2`, `C-1w`, `round4 review MJ-1`, `설계 §5.2` 같은 표기가 **신규 주석에 들어가면 안 된다**. 제출 전 `git diff` 추가 라인을 직접 재스캔하라:
  ```bash
  git diff -U0 | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(round[0-9])|(§)|(리뷰 ID)|(감사 ID))'
  ```
  히트가 있으면 전부 제거하고 다시 스캔하라. 이번 라운드에 두 트랙이 이걸 위반해 재작업했다.
- `@unchecked Sendable` / `MainActor.assumeIsolated` / `@available(*, deprecated)` **신규 0건**.
- Swift 6 zero-warning. 신규 공개 심볼은 전부 DocC 큐레이션.
- 신규 localized 키는 **en/ko 양쪽**에 존재해야 한다.
- 스타일 facet 소진성 테스트(`Mirror` 라벨 집합 일치)를 실제로 작성하라(설계 §5.1).
- CHANGELOG는 **실제 파일에 반영**하라. 설계 §7이 요구하는 `### Added` / `### Changed` 항목과 마이그레이션 노트 전부.
- D-10(Style `Sendable`화)이 툴체인 사정으로 이월되면, **사유와 툴체인 버전**을 `RESULT`에 남겨라.

---

## 7. 완료 보고

전부 끝나면 `docs/briefs/RESULT-round6-controls.md`를 **새로 만들어** 아래를 담아라. 이 파일의 생성이 완료 신호다 — 그 전에는 만들지 마라.

```markdown
# RESULT: 라운드6 트랙 C

## 1. WP별 완료 상태
(C-1w ~ C-7w 각각: 완료/부분/미착수 + 한 줄 요약)

## 2. 검증 결과
- 전체 스킴 3회: (각 회차 테스트 수 / 실패 수 / 소요 시간)
- 기존 Controls 184건 무회귀 여부
- hitTest 매트릭스: (케이스 수 / 통과 여부)
- docbuild / 데모 빌드 / SwiftLint

## 3. auto-hide 간헐 실패 가설 판정
(가설 지지/기각 + 근거. 기각이면 기각이라고 그대로 쓸 것)

## 4. pendingSeekTime 리셋 확인 결과
(소스 교체 경로가 resetSeeking()을 지나는가? 아니면 어떻게 방어했는가)

## 5. 설계에서 벗어난 지점 / 기존 테스트 변경
(§5.3 사전 승인 3줄 외에 건드린 것이 있으면 전부, 사유와 함께. 없으면 "없음")

## 6. 파일 경계 준수
(수정한 파일 전체 목록 + SwiftUI 4파일 diff 0줄 확인)

## 7. 게이트가 집중해서 볼 것
(당신이 가장 불안한 부분 3가지)
```

작업을 시작하기 전에 설계 문서 전문을 읽어라. 질문이 생기면 추측하지 말고 `RESULT`에 기록하되, 진행을 막을 정도면 즉시 보고하라.
