# BRIEF: 라운드6 트랙 G — NowPlaying · PiP · AirPlay 구현

당신은 트랙 G의 **구현자**다. G-0 설계 게이트는 **통과·승인됐다**(오케스트레이터 판정: APPROVE). 당신의 일은 승인된 설계를 그대로 구현하고, 아래 검증 프로토콜을 실제로 통과시키는 것이다.

작업 디렉터리: `/Users/jymac/orca/workspaces/ABPlayerKit/round6-nowplaying` (브랜치 `AppBoong/round6-nowplaying`, base `main` = `d29e231`)

---

## 1. 필독 문서 (이 순서로)

1. `docs/briefs/DESIGN-round6-nowplaying.md` — **당신의 설계 문서. 전문(1206줄)을 읽어라.** 결정 1~6, §4 PiP×정책 상호작용 매트릭스, §9 확정 API 시그니처, §10 확인 불가 항목, §11 WP별 지침, §12 무회귀 가드, §14 비범위, §15 완료 정의가 전부 확정 사항이다.
2. `docs/briefs/DESIGN-round6-core.md` §3.2 / §5.5 — 트랙 A가 이미 구현해 main에 병합한 이벤트 표면. 설계 §0.2가 소비한다고 적은 심볼은 실코드에 존재한다.
3. `docs/briefs/DESIGN-round6-swiftui.md` §1.1~§1.5, §3.2 — 설계 결정 4의 근거가 된 소유권 모델.
4. `docs/briefs/ROADMAP-round6.md` §3 트랙 G 표.

설계 문서와 이 브리프가 충돌하면 **설계 문서가 우선**한다. 단, §4 검증 프로토콜과 §5 규칙은 이 브리프가 우선한다.

---

## 2. 범위 — G-1w ~ G-4w

**착수 순서는 설계 §11.0의 권고를 따른다: `G-3w → G-2w → G-1w → G-4w`.** WP ID는 유지하되 순서만 그렇게 간다. 근거는 설계 §11.0에 있다(`ABBackgroundPolicyMachine` 변경이 두 WP에 걸쳐 있어, 케이스 추가를 먼저 끝내면 PiP 억제 테이블을 최종 5개 정책 전부에 대해 한 번에 고정할 수 있다).

| WP | 내용 | 설계 참조 |
|---|---|---|
| G-3w | `ABBackgroundPolicy.continueAudioOnly` + `detachesLayerInBackground` 일반화 | 결정 3(§6), §11.4 |
| G-2w | `ABPictureInPictureSession` + 뷰 바인딩 + AirPlay 노브 | 결정 2·5(§3·§7), §4 매트릭스, §11.3 |
| G-1w | `ABPlayerKitNowPlaying` 신규 타깃 + 데모 연동 | 결정 1(§2), §11.2 |
| G-4w | README/DocC | 결정 6(§8), §11.5 |

### 오케스트레이터가 승인하며 덧붙이는 사항

1. **설계 §6.4의 필수 수반 수정을 빠뜨리지 마라.** `applyConfigurationChange`의 `.pauseAndDetachLayer` 문자열 비교를 `detachesLayerInBackground` 성질로 일반화하는 것 — 이것이 없으면 `.continueAudioOnly → .ignore` 전환 시 레이어가 영구 detach로 남아 검은 화면이 된다. 이 회귀를 잡는 테스트를 반드시 작성하라.
2. **설계 §10의 "확인 불가" 10건은 구현 중 실제로 검증하라.** 특히:
   - **10-1**(`AVPictureInPictureController`가 `playerLayer`를 강하게 보유하는가) — 설계가 단위 테스트로 검증 가능하다고 적었다. **실제로 그 테스트를 작성하라.** 강한 보유가 아니면 설계가 지시한 대로 세션에 레이어 보유 필드를 추가하라(설계 변경 아님).
   - **10-8**(`externalPlaybackVideoGravity` 실제 기본값) — 런타임 확인 후 AVPlayer 기본값을 따르라.
   - **10-5 / 10-9 / 10-3**은 기기 수동 확인이 필요해 이 세션에서 검증 불가다. **검증했다고 쓰지 마라.** `RESULT`에 "미검증, 기기 확인 필요"로 정직하게 남겨라.
   - 검증 결과가 설계 가정을 깨면 우회하지 말고 **그대로 보고**하라.
3. **`.github/**` 수정 금지.** TSan 잡이 `ABPlayerKitTests`/`ABPlayerKitCacheTests`만 돌려 신규 NowPlaying 테스트가 TSan 범위 밖이 되지만, Wave 진행 중 CI 설정을 건드리지 않는다. 이 사실은 `RESULT`에 기록해 Wave 3에서 판단하게 하라.
4. **`Package.swift`에 타깃을 추가하면 전체 스킴의 빌드·테스트 범위가 늘어난다.** 검증 3회는 그 늘어난 범위로 돌려야 한다.
5. **데모 리베이스 주의.** 병합 순서는 F → G → C다. 트랙 F가 `Examples/.../MetricsScreen.swift`와 `DemoModel.swift`의 **메트릭 관련 멤버**를 동시에 수정 중이다. G는 재생/PiP/NowPlaying 영역에만 **별도 프로퍼티로 추가**하고, F 병합 후 리베이스한다. 같은 함수 본문을 재구성하지 마라.

---

## 3. 파일 경계 (위반 시 G-5 게이트 REQUEST-CHANGES)

설계 §0.1이 확정한 경계를 그대로 따른다. 요약:

**신규**: `Sources/ABPlayerKitNowPlaying/**`, `Sources/ABPlayerKit/View/ABPictureInPictureSession.swift`, `Tests/ABPlayerKitNowPlayingTests/**`, 설계 §0.1이 열거한 신규 테스트 파일 3개

**수정 허용**: `Sources/ABPlayerKit/` 하위의 `View/ABPlayerView.swift`, `Engine/ABPlayer.swift`·`ABPlaybackTarget.swift`·`ABAVPlaybackTarget.swift`, `Policy/ABBackgroundPolicy.swift`·`ABBackgroundPolicyMachine.swift`, `Model/ABPlayerConfiguration.swift`, `SwiftUI/ABVideoPlayer.swift`, `ABPlayerKit.docc/**` / `Package.swift` / `README.md`·`README.ko.md`·`CHANGELOG.md` / `Examples/**`의 재생·PiP·NowPlaying 영역 / 설계 §6.4·§12.3의 사전 승인 범위 내 기존 테스트

**수정 금지 (diff 0줄)**:
- `Sources/ABPlayerKitControls/**` 전체 — 트랙 C가 동시 작업 중이다. **읽고 쓰는 것은 허용, 수정은 금지.**
- `Sources/ABPlayerKitMetrics/**`, 데모의 메트릭 관련 멤버 — 트랙 F 소유
- `Sources/ABPlayerKitCache/**`, `Tests/ABPlayerKitControlsTests/**`, `.github/**`

**설계 §5.4의 S-PiP-1~4는 이번 라운드에 구현하지 않는다.** v0.5.0 이월 요구사항으로 문서에만 남긴다. 대신 G-4w 문서에 **"PiP는 명시 소유 경로에서 지원된다"**를 한계로 명시하라(설계 §5.4의 권고).

---

## 4. 검증 프로토콜 (필수 — 이걸 통과하지 못하면 완료가 아니다)

### 4.1 시뮬레이터

이미 부팅된 기기를 **재사용**하라. 새로 부팅·생성하지 마라. 다른 트랙과 **공유**한다.

```
iPhone 17 Pro Max — 60DA735B-87EC-4159-9BE3-EF981A127FAF (iOS 26.2, Booted)
```

### 4.2 전체 스킴 3회 연속 그린

```bash
cd /Users/jymac/orca/workspaces/ABPlayerKit/round6-nowplaying
DEST='platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF'
for i in 1 2 3; do
  echo "=== RUN $i ==="
  xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" \
    -derivedDataPath .dd \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    EXTRACT_APP_INTENTS_METADATA=NO build test || { echo "RUN $i FAILED"; break; }
done
```

**`-only-testing:`으로 좁힌 결과는 근거로 인정하지 않는다.** Wave 1에서 두 트랙이 자기 타깃만 돌리고 PR을 올렸다가 둘 다 CI에서 실패했고, 실패는 전부 자기 타깃 밖에 있었다. **트랙 G는 코어를 수정하므로 이 규칙이 특히 중요하다** — 당신의 변경이 Controls/Metrics/Cache 스위트에 파급되는지는 전체 스킴에서만 드러난다.

### 4.3 CI가 돌리는 나머지도 로컬에서 통과시켜라

```bash
# DocC (신규 공개 심볼이 다수 — 신규 타깃 전체가 포함된다)
xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  DOCC_WARNINGS_AS_ERRORS=YES EXTRACT_APP_INTENTS_METADATA=NO docbuild

# 데모
xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj \
  -scheme ABPlayerKitDemo -destination "$DEST" -derivedDataPath .dd \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  EXTRACT_APP_INTENTS_METADATA=NO build

# SwiftLint
swiftlint --strict 2>/dev/null || swiftlint
```

### 4.4 CI와 로컬의 격차

CI는 3 vCPU + Xcode 16.4 + iPhone 16 Pro, 로컬은 10코어 + Xcode 26.2 + iPhone 17 Pro Max다. 이번 라운드 CI 실패 상당수가 "로컬 재현 불가, CI에서만 실패"였고 원인은 **협력 스레드 풀이 좁을 때만 드러나는 스케줄링 기아**였다. 실제로 이번 Wave 시작 직전에도 TSan 잡이 전면 180초 타임아웃 캐스케이드로 한 번 떨어졌다.

→ 설계 §11.1이 요구한 대로: `sleep` 금지(`ABTestSupport`의 `ABWaitUntil` 사용), `Task.yield()` 바쁜 대기 금지, 불필요하게 깊은 비동기 사슬 금지, **테스트에서 실제 원격 URL로 재생 시작 금지**(로컬 픽스처 또는 `ABFakePlaybackTarget`). 대기 헬퍼의 타임아웃 메시지에 진단 정보를 넣어라. 순수 리듀서로 분리 가능한 로직은 전부 순수하게 테스트하라 — 설계 §2가 그 구조를 이미 지시했다.

---

## 5. 규칙

- **커밋하지 마라.** 커밋은 별도 담당이 WP 경계에 맞춰 수행한다. working tree를 깨끗한 상태로 남기고 보고만 하라.
- **새 주석에 리뷰/설계 ID를 인용하지 마라.** 불변식만 서술하라. 제출 전 `git diff` 추가 라인을 직접 재스캔하라:
  ```bash
  git diff -U0 | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(I-G[0-9])|(WP[0-9])|(round[0-9])|(MJ-[0-9])|(§))'
  ```
  히트가 있으면 전부 제거하고 다시 스캔하라. 이번 라운드에 두 트랙이 이걸 위반해 재작업했다.
- `@unchecked Sendable` / `MainActor.assumeIsolated` / 신규 `@available(*, deprecated)` **0건**.
- Swift 6 zero-warning. 신규 공개 심볼은 전부 DocC 큐레이션.
- `ABBackgroundPolicy`에 non-exhaustive 계약 주석 추가 + CHANGELOG **Migration 노트**(설계 §6.3의 수반 조치 4건 전부).
- CHANGELOG는 **실제 파일에 반영**하라. 초안만 쓰고 완료 체크한 사례가 있었다.
- **`ABPlayerConfiguration`의 `backgroundPolicy` 기본값은 `.pause` 유지.** 동작 변경 0.

---

## 6. 완료 보고

전부 끝나면 `docs/briefs/RESULT-round6-nowplaying.md`를 **새로 만들어** 아래를 담아라. 이 파일의 생성이 완료 신호다 — 그 전에는 만들지 마라.

```markdown
# RESULT: 라운드6 트랙 G

## 1. WP별 완료 상태
(G-1w ~ G-4w 각각: 완료/부분/미착수 + 한 줄 요약)

## 2. 검증 결과
- 전체 스킴 3회: (각 회차 테스트 수 / 실패 수 / 소요 시간)
- docbuild / 데모 빌드 / SwiftLint
- 신규 타깃 추가 후 전체 테스트 수 변화

## 3. 설계 §10 "확인 불가" 10건 처리 결과
(항목별로: 검증함(방법·결과) / 미검증(사유, 기기 확인 필요) 중 하나. 검증하지 않은 것을 검증했다고 쓰지 말 것)

## 4. §6.4 필수 수반 수정
(detachesLayerInBackground 일반화 완료 여부 + 회귀 테스트 존재 여부)

## 5. 설계에서 벗어난 지점
(없으면 "없음". 있으면 각각 사유와 함께)

## 6. 파일 경계 준수
(수정한 파일 전체 목록 + Controls/Metrics/Cache/.github diff 0줄 확인)

## 7. Wave 3 / 후속 라운드 이월 항목
(S-PiP-1~4 요구사항, TSan 잡의 신규 타깃 미포함 등)

## 8. 게이트가 집중해서 볼 것
(당신이 가장 불안한 부분 3가지)
```

작업을 시작하기 전에 설계 문서 전문을 읽어라. 질문이 생기면 추측하지 말고 `RESULT`에 기록하되, 진행을 막을 정도면 즉시 보고하라.
