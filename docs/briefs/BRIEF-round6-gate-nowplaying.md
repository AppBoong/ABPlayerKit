# BRIEF: 라운드6 트랙 G 최종 게이트 (G-5)

당신은 트랙 G(NowPlaying · PiP · AirPlay)의 **최종 게이트**다. 구현은 끝났고 **이미 커밋되어 최신 `origin/main` 위로 리베이스된 상태**다(트랙 F 병합분 포함). 당신의 일은 **독립적으로 검증하고 APPROVE / REQUEST-CHANGES를 판정**하는 것이다.

작업 디렉터리: `/Users/jymac/orca/workspaces/ABPlayerKit/round6-nowplaying` (브랜치 `AppBoong/round6-nowplaying`, 6개 커밋이 `origin/main` 위에 있음)

---

## 0. 이 게이트의 제1 원칙

**구현자의 보고를 근거로 인정하지 마라.** 이번 라운드에 게이트가 정적 리뷰만으로 "무회귀 PASS"를 냈다가, 이후 실제로 테스트를 돌리자 신규 33건 중 3건이 실패했고 원인이 프로덕션 로직 결함 2건이었던 전례가 있다.

→ **당신은 부팅된 시뮬레이터에서 테스트를 직접 실행한다.** 실행하지 않은 것을 통과라고 쓰지 마라.

**이번 게이트에는 추가 임무가 하나 더 있다.** 구현자는 트랙 F 병합 **이전**의 main에서 작업했고, 오케스트레이터가 방금 트랙 F가 들어간 main 위로 리베이스했다(CHANGELOG 충돌 1건을 양쪽 보존으로 해결). **따라서 당신이 실행하는 테스트가 F+G 통합 상태의 첫 검증이다.** Wave 1에서 두 트랙이 자기 타깃만 돌리고 PR을 올렸다가 둘 다 CI에서 실패했고 실패가 전부 자기 타깃 밖에 있었던 전례가 정확히 이 지점이다.

---

## 1. 입력

1. `docs/briefs/DESIGN-round6-nowplaying.md` — 확정 설계(1206줄). 판정 기준의 원본. 특히 §4 PiP×정책 상호작용 매트릭스, §9 확정 API 시그니처, §10 확인 불가 10건, §12 무회귀 가드와 절대 불변식, §14 비범위, §15 완료 정의.
2. `docs/briefs/BRIEF-round6-nowplaying.md` — 구현자가 받은 지시.
3. `docs/briefs/RESULT-round6-nowplaying.md` — 구현자 보고. **검증 대상이지 근거가 아니다.**
4. `git log origin/main..HEAD`, `git diff origin/main` — 실제 변경분.

---

## 2. 반드시 실행할 검증

### 2.1 전체 스킴 3회 연속 그린 (독립 실행, 리베이스된 트리에서)

이미 부팅된 기기를 재사용하라. **새로 부팅·생성하지 마라.**

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

zsh에서 `status`는 읽기 전용 예약 변수다 — `status=$?`로 대입하면 스크립트가 그 자리에서 죽는다. 다른 변수명을 써라(직전 게이트가 이걸로 한 번 헛돌았다).

**리베이스 전 구현자가 본 테스트 수는 580건이었다**(Cache 72 / Controls 200 / Metrics 8 / NowPlaying 31 / 코어 269). 리베이스로 트랙 F의 Metrics 테스트가 들어왔으므로 **Metrics 스위트 수가 늘어야 정상이다.** 실제 수를 세어 보고, 늘지 않았다면 리베이스가 제대로 반영되지 않은 것이니 그 자체가 지적 대상이다.

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

데모는 이번에 **트랙 F의 Metrics 탭과 트랙 G의 Now Playing 토글이 처음 한 트리에 있는 상태**다. 빌드가 통과하는지 반드시 직접 확인하라.

### 2.3 리베이스 정합성 (이번 게이트 고유 항목)

```bash
git log --oneline origin/main..HEAD          # 6개 커밋
git diff origin/main --stat                   # 트랙 G 변경분만 보여야 한다
```

- **CHANGELOG 충돌 해결이 옳은가.** 오케스트레이터가 트랙 F 항목과 트랙 G 항목을 양쪽 보존으로 합쳤다. `### Added` 목록과 `### Migration notes`에 **F의 항목 7건과 G의 항목이 모두 살아 있는지**, 중복·유실·충돌 마커 잔재가 없는지 직접 확인하라.
- **트랙 F가 건드린 파일을 트랙 G가 덮어쓰지 않았는가.** 특히 `Examples/.../DemoModel.swift`는 F(메트릭 멤버)와 G(NowPlaying 멤버)가 모두 수정한 파일이다. `git diff origin/main -- Examples/ABPlayerKitDemo/ABPlayerKitDemo/DemoModel.swift`로 **G의 추가분만 있고 F의 멤버가 사라지지 않았는지** 확인하라.
- `Examples/.../MetricsScreen.swift`는 F 소유다 — G의 diff가 0줄이어야 한다.

### 2.4 파일 경계

**diff 0줄이어야 함**: `Sources/ABPlayerKitControls/**`, `Sources/ABPlayerKitMetrics/**`, `Sources/ABPlayerKitCache/**`, `.github/**`, `Tests/ABPlayerKitControlsTests/**`, `Examples/.../MetricsScreen.swift`

`ABPlayerEvent`/`ABPlayerError`에 신규 케이스 추가가 없어야 한다(설계 §0의 "이벤트 표면은 소비만").

### 2.5 무회귀 하드 제약

- **설계 §12.1의 절대 불변식** 각각에 대응 테스트가 존재하고 통과하는가.
- **매트릭스 A 전수 테스트**(5정책 × grade × 3신호 × PiP 2상태)가 실제로 존재하는가. 그리고 **`isActive == false`인 열이 현행 동작과 완전히 동일한가** — 이것이 I-G4이고, PiP를 안 쓰는 기존 소비자에게 동작 변경이 0이라는 보장이다.
- **`ABBackgroundPolicy` 기본값이 `.pause` 그대로인가**(동작 변경 0).
- 설계 §14의 비범위 항목이 구현되지 않았는가.
- 설계 §12.3의 사전 승인 범위를 넘는 기존 테스트 변경이 없는가. 구현자는 `ABBackgroundPolicyMachineTests`에 **승인 목록 밖의 신규 테스트 메서드 1개**를 추가했다고 신고했다(§5). 기존 단언을 바꾸지 않은 순수 추가인지 `git diff`로 직접 확인하라.

### 2.6 위생

```bash
git diff origin/main -U0 -- Sources Tests | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(I-G[0-9])|(WP[0-9])|(round[0-9])|(MJ-[0-9])|(§))'
git diff origin/main -U0 -- Sources Tests | grep '^+' | grep -nE '@unchecked Sendable|MainActor\.assumeIsolated|@available\(\*, deprecated'
```

구현자는 최초 스캔에서 20여 건이 걸려 전부 제거했다고 보고했다. **직접 재확인하라.**

- CHANGELOG `### Added` 4건 + Migration 노트 2건이 실제 파일에 있는가.
- 신규 공개 심볼이 DocC에 큐레이션됐는가. `ABBackgroundPolicy`에 non-exhaustive 계약 주석이 붙었는가.

---

## 3. 집중 검토

### 3.1 §6.4 필수 수반 수정 — 놓치면 조용히 깨지는 곳

`ABPlayer.applyConfigurationChange`의 레이어 재부착 조건이 `.pauseAndDetachLayer` 케이스 비교에서 `detachesLayerInBackground` 성질 비교로 일반화됐는가. **회귀 테스트가 실제로 존재하고 통과하는가**(`switchingAwayFromContinueAudioOnlyMidBackgroundReattachesLayer`). 이게 없으면 `.continueAudioOnly → .ignore` 전환 시 레이어가 영구 detach로 남아 검은 화면이 된다.

### 3.2 설계 §10 "확인 불가" 10건의 처리 (RESULT §3)

구현자가 항목별로 검증/미검증을 구분해 보고했다. **검증했다고 주장한 것(10-5, 10-6, 10-8, 10-10 부분)이 실제로 그 테스트로 뒷받침되는지 확인하라.** 미검증으로 남긴 것(10-2·10-3·10-4·10-7·10-9)에 대해 REQUEST-CHANGES 하지 마라 — 물리 기기가 없으면 확인할 수 없는 항목들이고, 정직한 미검증 보고가 정답이다.

**10-1이 특히 중요하다.** 구현자는 테스트를 작성했으나 시뮬레이터가 PiP 미지원(`isSupported == false`)이라 컨트롤러 자체가 생성되지 않아 결과를 얻지 못했다고 보고했다. 설계가 이 결과에 의존하지 않도록 우회 설계(세션이 뷰를 보유)를 채택했다는 것이 근거인데, **그 우회가 실제 코드에 구현돼 있는지 확인하라**(`sessionDropsItsHoldOnceInactive` 등).

### 3.3 설계 이탈 5건 (RESULT §5)

각각 판단하라. 특히:
- **`MediaPlayer` import 범위 확대** — 설계는 "`ABNowPlayingSurface.swift` 한 파일"을 지시했으나 `ABNowPlayingCenter.swift`도 import한다. **순수 리듀서 3종(`ABNowPlayingOwnership`/`ABNowPlayingInfoBuilder`/`ABRemoteCommandRouter`)에 `import MediaPlayer`가 없는지**가 실질 판정 기준이다(제약의 목적이 테스트 가능성이므로). 직접 grep하라.
- **§12.4 리스크 완화 권고 미구현**(바인딩된 플레이어의 `avPlayer`가 `nil`이 되면 세션 강제 `stop()`) — 확정 API 밖의 권고였다는 구현자 논거가 타당한가, 아니면 안전망 없이 출하하면 실제로 깨지는 시나리오가 있는가.
- 나머지 3건(프로토콜 메서드 2개 추가, 매트릭스 테스트 메서드 1개 추가, `ABFakePlaybackTarget` 중복)도 확인하라.

### 3.4 PiP 기능이 기기에서 죽어 있을 가능성 (RESULT §8-1)

구현자 스스로 "자동 검증이 정책 리듀서 + 바인딩 수명 + 설정 전달까지이고, 실제 PiP 시작/렌더링/복원은 전혀 검증되지 않았다"고 신고했다. **이것을 판정에 어떻게 반영할지 결정하라.** 시뮬레이터에 PiP가 없는 것은 환경 제약이지 구현 결함이 아니다. 다만 **문서(README/DocC)가 이 한계와 전제조건을 정직하게 적고 있는지**는 당신이 확인할 수 있다 — 설계 §4.6의 전제조건 표가 실제 문서에 들어갔는지 보라.

---

## 4. 판정과 산출물

`docs/briefs/REVIEW-round6-nowplaying.md`를 **새로 만들어** 아래를 담아라. 이 파일의 생성이 완료 신호다.

```markdown
# REVIEW: 라운드6 트랙 G 게이트 (G-5)

## 판정
**APPROVE** 또는 **REQUEST-CHANGES**

## 1. 독립 실행 결과
(전체 스킴 3회 직접 실행: 회차별 스위트별 테스트 수 / 실패 수. docbuild / 데모 / SwiftLint)

## 2. 리베이스 정합성
(CHANGELOG 병합 결과, DemoModel.swift에 F와 G의 멤버가 공존하는지, MetricsScreen.swift diff 0줄)

## 3. 파일 경계

## 4. 무회귀
- 매트릭스 A 전수 테스트 존재 / I-G4(PiP 비활성 열이 현행과 동일)
- §6.4 필수 수반 수정 + 회귀 테스트
- 절대 불변식 대응 테스트
- 사전 승인 밖 기존 테스트 변경 여부

## 5. §10 확인 불가 10건 처리 판정

## 6. 설계 이탈 5건 판정

## 7. 지적 사항
(파일:라인 + 실패 시나리오. 차단 / 비차단 구분)

## 8. 기기 확인이 필요한 이월 항목
(v0.4.0 출하 전 사람이 기기에서 확인해야 할 것 목록)
```

커밋하지 마라. 코드를 고치지도 마라 — 당신은 판정만 한다. **이미 커밋된 상태이므로 `git commit`/`git rebase`/`git reset`을 실행하지 마라.** 검증 목적의 임시 조작을 했다면 반드시 원상복구하고 그 사실을 보고하라.
