# HANDOFF: 라운드6 Wave 2 착수 (다음 세션용)

이 문서는 새 세션에서 Wave 2를 시작하기 위한 인수인계다. 기준 시점의 Wave 1 상태, 확정된 계약, 그리고 이전 세션에서 얻은 운영 교훈을 담는다.

---

## 1. Wave 1 결과 (완료된 것)

| 트랙 | 결과 | 병합 |
|---|---|---|
| CI | 커버리지 배지·TSan 잡·SwiftLint·`ABTestSupport` 타깃 | `f7403cb` (PR #1) |
| CI 안정화 | auto-hide 타이머 `Task(priority: .userInitiated)` | `d17c288` (PR #2) |
| A (코어) | A-1~A-8·B-1~B-8 해소, 이벤트 표면 9종 추가 | `8689cb5` (PR #3) |
| S (SwiftUI) | URL 편의 API, Environment modifier, README 개편 | `04fbc51` (PR #4) |
| E (캐시) | 재개 검증, reader 조정, 메모리 상한, 로더 테스트 | `75346b6` (PR #5) |

**Wave 1 완료.** 게이트 판정: S-4 APPROVE / A-8 APPROVE(주석 위생 수정 후 재승인) / E-6 1차 REQUEST-CHANGES → 로직 수정 후 재게이트 APPROVE.

**커버리지 배지 발행 확인**: `badges` 오펀 브랜치에 `coverage.json`이 생성되어 **90.6%(brightgreen)** 표시 중. README 배지 링크 정상 동작.

### 알려진 불안정 (Wave 2에서 다룰 것)

`ABPlayerControlsViewTests`의 `"Given duration disappears during scrubbing, controls always end the session"`가 CI에서 **간헐적으로** 실패한다(트랙 A 병합 직후 main 실행에서 1회 실패, 다음 실행에서 통과). fix2가 대기 신호를 인과적으로 올바른 것(`.scrubbingChanged(isScrubbing: false)`)으로 고쳤음에도 그 뒤의 `hasScheduledAutoHide` 단언에서 떨어졌다.

가설: auto-hide 스케줄 여부가 그 시점의 `isPlaying`에 좌우되는데, A-6w가 도입한 관찰성 미러는 KVO 홉을 거쳐 비동기로 갱신되는 경로가 있어 가시성 판단이 보는 값이 타이밍에 따라 달라질 수 있다. **Controls를 소유하는 트랙 C의 범위**이므로 C-0 설계 검토 시 이 상호작용을 명시적으로 판단할 것.

### Wave 2가 의존하는 확정 계약

`docs/briefs/DESIGN-round6-core.md` §3.2의 **9개 신규 `ABPlayerEvent` 케이스**와 §5.5 동결 표면이 트랙 A 구현으로 실코드에 반영됐다. C-0·F-0 설계가 이미 이 표면을 전제로 작성돼 있으므로, Wave 2 구현자는 설계 문서를 그대로 신뢰해도 된다.

- `bufferingChanged(Bool)`, `durationAvailable(CMTime)`, `stallEnded`, `itemAttached(source:)`, `presentationSizeChanged(CGSize)`, `mutedChanged(Bool)`, `callRejected(ABRejectedCall, grade:)`, `failureReported(ABPlayerFailure)`, `seekTargetChanged(CMTime?)`
- 관찰 가능 프로퍼티: `isPlaying`, `duration`, `isBuffering`, `pendingSeekTime`, `lastFailure`, `lastDiagnostic`
- 스킵 누적의 진실원은 코어의 `pendingSeekTime`이다 — **Controls가 자체 누적기를 두지 않는다**.

---

## 2. Wave 2 범위

### 설계 상태

| 트랙 | 설계 | 상태 |
|---|---|---|
| C (Controls UX) | `docs/briefs/DESIGN-round6-controls.md` (898줄) | **완료** — 바로 구현 착수 가능 |
| F (Metrics QoE) | `docs/briefs/DESIGN-round6-metrics.md` (746줄) | **완료** — 바로 구현 착수 가능 |
| G (NowPlaying·PiP) | 없음 | **G-0 설계 게이트부터 시작해야 함** |

### 트랙별 작업

- **C**: C-1w~C-7w. 버퍼링 스피너(아이콘 유지 + 글리프 자리 오버레이, 해소 축은 `isPlaying || isBuffering`), skip UI, 더블탭 시크 + passthrough 옵션, 리플레이, 배속 로케일, 레이아웃 슬롯, 구조 정리(D-8~D-10). 파일 경계는 `Sources/ABPlayerKitControls/`만이며, 설계 §0이 트랙 S가 만든 SwiftUI 파일 4개(`ABPlayerControls.swift`, `ABVideoPlayerWithControls.swift`, `ABPlayerControlsEnvironment.swift`, `ABOwnedPlayerBox.swift`) 수정 금지를 자체 선언했다.
- **F**: F-1w~F-6w. 순수 누적기 `ABPlaybackSessionAccumulator` + `(playerID, sessionStartedAt)` 복합 키. JSONL v1 레코드는 **바이트 동일 하위호환** 유지가 제약.
- **G**: G-0 설계(Opus) → G-1w~G-4w. `ABPlayerKitNowPlaying` 신규 타깃, PiP 팩토리, `.continueAudioOnly`, 문서. 설계 시 `DESIGN-round6-swiftui.md` §9-4의 전달 사항(편의 API의 자동 해제와 PiP 세션 수명의 상호작용)을 반드시 판단할 것.

### 병합 순서

F → G → C (C가 최대 diff).

---

## 3. Wave 3 (참고 — Wave 2 이후)

`H-1w`(소스 주석 약 90곳의 리뷰 ID 인용 정리 — 라운드3~4 시절 기존 주석이 대상, 이번 라운드 신규 코드는 게이트에서 이미 정리됨) → `H-2w`(README/DocC/CHANGELOG 최종화) → 최종 Opus 게이트 → `H-3w`(`docs/briefs/`를 orphan 브랜치 `archive/briefs`로 이전 후 main에서 제거) → `R-1`(v0.4.0 태그·릴리스). tvOS(P-1)는 선택 항목으로 일정 압박 시 v0.5.0 이월.

---

## 4. 운영 교훈 (이전 세션에서 실제로 겪은 것 — 반드시 반영할 것)

### 4-1. 정적 리뷰만으로는 부족하다 — 게이트도 테스트를 실행해야 한다

트랙 E의 1차 게이트는 시뮬레이터가 없어 정적 리뷰만 했고 "무회귀 9개 불변식 PASS"로 판정했다. 이후 구현자가 실제로 테스트를 돌리자 **신규 33건 중 3건이 실패**했고, 원인은 프로덕션 로직 결함 2건이었다(재개 검증 전 stale prefix 서빙, 취소된 fill Task가 purge 직후 인덱스 엔트리를 부활시킴). 정적 리뷰가 놓친 종류의 결함이다.

→ **Wave 2에서는 구현자와 게이트 모두 부팅된 시뮬레이터에서 해당 타깃 테스트를 실제로 실행하고, 게이트는 구현자 보고를 신뢰하지 말고 독립 실행할 것.**

### 4-1b. 로컬 검증은 반드시 **전체 스킴**으로 — 부분 실행은 트랙 간 파급을 놓친다

트랙 A는 `-only-testing:ABPlayerKitTests`만, 트랙 S는 두 타깃만 로컬 실행하고 PR을 올렸다가 **둘 다 CI에서 실패**했다. 실패는 전부 자기 타깃 밖에 있었다:

- A가 추가한 `bufferingChanged`가 **Controls의 특성화 테스트**가 단언하는 정확한 이벤트 시퀀스를 깨뜨렸다. 이벤트 추가는 additive지만, 시퀀스를 통째로 비교하는 테스트는 영향을 받는다 — 로드맵의 "additive면 기존 소비자 무영향" 가정이 성립하지 않는 지점이다.
- S가 추가한 테스트가 도달 불가능한 원격 URL로 **실제 재생**을 시작시켰고(`autoplay` 기본값 `true`, `play()`에는 프리롤과 달리 타임아웃이 없다), 릴리스하지 않아 AVFoundation이 스위트 내내 재연결을 시도하며 같은 번들의 다른 호스팅 테스트 11개를 굶겨 180초 제한을 넘겼다.

→ **모든 트랙의 구현·게이트 브리프에 "전체 스킴 테스트 3회 연속 그린"을 검증 조건으로 명시하라.** `-only-testing`으로 좁힌 결과는 근거로 인정하지 말 것.

→ 테스트에서 실제 네트워크 URL로 재생을 시작시키지 말 것. 재생 자체가 검증 대상이 아니면 `autoplay: false`, 필요하면 로컬 픽스처를 쓸 것.

### 4-1c. CI(3 vCPU)와 로컬(10코어)의 격차가 반복해서 문제를 만든다

이번 라운드의 CI 실패 상당수가 "로컬에서는 재현 불가, CI에서만 실패"였다. 원인은 대체로 **협력 스레드 풀이 좁을 때만 드러나는 스케줄링 기아**였다:

- 테스트 헬퍼의 `Task.yield()` 바쁜 대기가 정작 기다리는 대상을 밀어냄
- 첫 동기화 지점까지 불필요하게 깊은 비동기 사슬(별도 Task 3개 + actor 홉 6곳)

인위적 CPU 부하(`yes` 프로세스 10개, 부하 평균 23)로도 재현되지 않았고, 툴체인도 다르다(CI는 Xcode 16.4 + iPhone 16 Pro, 로컬은 Xcode 26.2 + iPhone 17 Pro). **로컬 그린을 "해결됨"의 증거로 삼지 말고, CI 1회 통과도 확정 증거가 아니라는 점을 문서에 남길 것.**

또한 실패 시 원인 구분이 가능하도록 대기 헬퍼의 타임아웃 메시지에 진단 정보를 넣는 관행이 유용했다(예: "fill이 아예 시작 못 함" vs "시작했는데 멈춤").

### 4-2. 시뮬레이터 정책

로드맵 §0의 "새 시뮬레이터 부팅 금지"는 **새로 부팅·생성하지 말라**는 뜻으로 운용한다. 이미 부팅된 기기가 있으면 재사용해 테스트를 실행하는 것이 오히려 필수다(4-1 참조). 세션 시작 시 `xcrun simctl list devices booted`로 확인하고, 없으면 기존 기기 **한 대만** 부팅해 전 트랙이 공유하라.

### 4-3. 디스크

작업 중 데이터 볼륨이 98%까지 찼다. worktree당 `.build`가 400~700MB, DerivedData가 트랙당 300~600MB 쌓인다. **트랙이 끝나면 해당 worktree의 `.build`와 DerivedData를 즉시 정리하고**, 세션 중간에도 `df -h /System/Volumes/Data`로 여유를 확인할 것.

### 4-4. Orca 터미널 디스패치의 함정

`orca terminal wait --for tui-idle`이 satisfied를 반환해도 Claude TUI가 아직 부팅 중일 수 있다. 이 상태로 프롬프트를 보내면 **텍스트가 셸이나 배너에 섞여 유실**된다(이번 세션에서 3회 발생, 그중 한 번은 조사 에이전트가 한 시간 가까이 아무것도 안 하고 있었다).

→ 프롬프트 전송 후 **반드시 20초쯤 뒤에 터미널을 읽어 실제로 작업이 시작됐는지 확인**하라. cursor 값이 수천 단위로 증가하고 스피너/작업 로그가 보이면 정상이다.

### 4-5. 완료 감지

TUI 폴링 대신 **산출물 파일 생성 감지**를 쓴다(로드맵 §0). 백그라운드 워처가 중간에 종료되는 경우가 있으니, 알림이 오면 파일 존재를 직접 재확인하라.

### 4-6. 병합에는 사용자 조치가 필요하다

`main` 브랜치 보호가 승인 리뷰 1건 + `require_last_push_approval`을 요구하고, PR 작성자가 리포 소유자 본인이라 셀프 승인이 불가능하다. `--admin` 우회는 세션 안전 분류기가 차단한다.

→ PR이 그린이 되면 사용자에게 다음 명령을 안내하고 대기하라:
```
! gh pr merge <번호> --merge --admin --repo AppBoong/ABPlayerKit
```
병합 방식은 시행착오 커밋이 섞인 PR이면 squash, WP 단위로 의미 있게 나뉜 PR이면 rebase를 권한다.

### 4-7. Opus 사용량 한도

게이트 3개를 Opus로 동시에 돌리면 한도에 걸린다(이번 세션에서 실제로 발생, 세 터미널이 모두 멈춤). Sonnet 게이트로도 품질은 충분했다 — 실제로 두 건의 REQUEST-CHANGES를 정확히 잡아냈다. **게이트는 Sonnet으로 돌리고, Opus는 설계 게이트에만 쓰거나 순차 실행하라.**

### 4-8. 브리프 작성 시 반드시 넣을 것

- 파일 경계(위반 시 REQUEST-CHANGES)
- **새 주석에 리뷰/설계 ID 인용 금지** — 이번 라운드에 두 트랙이 모두 위반해 재작업했다. 브리프에 쓰고, 구현자에게 "제출 전 diff 추가 라인을 ID 패턴으로 직접 재스캔하라"고 명시할 것.
- 커밋 금지(커밋은 별도 담당), CHANGELOG는 **실제 파일에 반영**할 것(초안만 쓰고 완료 체크한 사례가 있었다)
- 가설 검증을 지시할 때는 "가설을 지지하는 데이터가 없으면 그대로 보고하라"를 명시 — 이번에 폴링 가설이 실제로 기각됐고, 그 정직한 보고가 잘못된 되돌림을 막았다
- **커밋 메시지는 영어로** — 이 리포의 기존 커밋이 전부 영어다. 한국어로 작성한 사례가 있어 전량 재작성했다
- 커밋 담당에게는 **파일 경계까지 지정**하라. WP 단위 분할을 지시했더니 변경 대부분을 첫 커밋에 몰아넣고 빈 커밋을 만든 뒤 "커밋 1에 포함"이라는 깨진 상호 참조를 메시지에 남긴 사례가 있었다(전량 재작성). 커밋 후 `git log --stat`으로 분할이 실제 내용과 맞는지 확인할 것
- 브리프 문서는 **해당 트랙의 worktree에** 만들 것. 메인 작업 디렉터리에 untracked로 두면, 같은 경로가 트랙 브랜치를 통해 병합됐을 때 `git pull`이 "untracked working tree files would be overwritten"으로 중단된다(이번에 실제로 발생)

---

## 5. 새 세션 시작 프롬프트

아래를 그대로 붙여넣으면 된다.

```
docs/briefs/HANDOFF-round6-wave2.md 와 docs/briefs/ROADMAP-round6.md §3(Wave 2)를 읽고 Wave 2를 시작하세요.

먼저 상태를 확인하세요: origin/main 최신 커밋, 열린 PR, 그리고 Wave 1 다섯 트랙(CI·CI안정화·A·S·E)이 모두 병합됐는지.
미병합 PR이 있으면 그것부터 정리한 뒤 진행하세요.

Wave 2 디스패치:
1. C-0·F-0 설계는 이미 완료돼 있으므로(DESIGN-round6-controls.md, DESIGN-round6-metrics.md) 구현 브리프를 작성해
   Sonnet worktree 2개(round6/controls, round6/metrics)로 즉시 착수.
2. G-0 설계 게이트는 미착수이므로 Opus 터미널로 먼저 설계를 산출(DESIGN-round6-nowplaying.md).
   설계 승인 후 round6/nowplaying worktree로 구현 착수.
3. 각 트랙 완료 시 Sonnet 게이트(C-8/F-7/G-5) → APPROVE 시 Haiku 커밋 → 리베이스 → PR.
   병합 순서는 F → G → C.

HANDOFF 문서 §4의 운영 교훈을 반드시 반영하세요. 특히: 구현자와 게이트 모두 부팅된 시뮬레이터에서 테스트를 실제로
실행할 것, 프롬프트 전송 후 터미널이 실제로 작업을 시작했는지 확인할 것, 트랙 종료 시 빌드 산출물을 정리할 것,
그리고 병합은 사용자에게 요청할 것.
```
