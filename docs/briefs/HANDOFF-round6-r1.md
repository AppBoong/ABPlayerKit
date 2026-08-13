# HANDOFF: 라운드6 마무리 — 데모 검증 경로(트랙 A) + R-1

이 문서는 새 세션에서 v0.4.0 릴리스를 마무리하기 위한 인수인계다. Wave 3는 **최종 게이트 APPROVE까지 끝났고**, 남은 것은 데모에 기기 검증 경로를 추가하는 트랙 하나와 릴리스뿐이다.

---

## 1. 현재 상태 (전제해도 되는 것)

main = `8f98fdc`. 열린 PR 없음. CI 4개 잡 그린. 커버리지 91.3%. 테스트 **743건**(Controls 322 / Core 269 / Cache 72 / Metrics 49 / NowPlaying 31).

**최종 Opus 게이트: `FINAL-VERDICT: APPROVE`** (`docs/briefs/REVIEW-round6-final.md`). 게이트는 3회 돌았다 — REQUEST-CHANGES(문서 결함 4건) → REQUEST-CHANGES(스니펫 컴파일 불가) → APPROVE.

Wave 3 병합 이력:

| 커밋 | 내용 |
|---|---|
| `a6852a2` | H-1w — 소스 주석의 내부 문서·리뷰 ID 인용 106건 제거 |
| `8793bb6` | H-2w — README/DocC 최종화 + 데모 배경 오디오 경로 |
| `ebdf0d9` | 최종 게이트 지적 문서 결함 4건 |
| `fc547a0` | 스니펫 컴파일 오류 + TSan 근본 원인 |
| `8f98fdc` | 최종 리뷰 문서 + F1(hand-rolled 데드라인 스케일) |

### H-3w는 검토 후 생략하기로 확정됐다

`docs/briefs/`는 **main에 그대로 둔다.** 로드맵의 제거 근거는 "RESULT/REVIEW 산출 종료 시점"이라는 절차적인 것뿐인데, `docs/README.md`가 `briefs/`를 "how와 why를 다음 유지보수자에게 남기는 기록"으로 명시 선언하고 있어 충돌한다. orphan 브랜치는 main과 공통 조상이 없어 존재를 아는 사람만 찾을 수 있고, 옮기면 `docs/README.md`에 깨진 참조가 생겨 결국 안내를 남겨야 한다.

**ROADMAP §7 4-b는 "누락"이 아니라 "검토 후 판단 갱신"이다.** R-1에서 CHANGELOG·릴리스 노트에 그렇게 기록할 것.

---

## 2. 트랙 A — 데모에 기기 검증 경로 추가

### 2-1. 왜 필요한가

기기 수동 확인 6항목 중 **현재 데모로 확인 가능한 것은 2개뿐이다.** 직접 조사해 확인한 사실이다:

| # | 항목 | 현재 | 이유 |
|---|---|---|---|
| 1 | PiP 실동작 | **불가** | 데모에 PiP 코드가 없다 |
| 2 | 배경 진입 vs PiP KVO 순서 | **불가** | 위와 동일 |
| 3 | `.continueAudioOnly` | 가능 | H-2w가 추가 |
| 4 | NowPlaying 잠금화면·리모트 커맨드 | **부분** | 토글은 있으나 `attach`에 `configuration:`을 안 넘겨 기본 `commands`뿐 |
| 5 | AirPlay 라우팅 | **불가** | AirPlay 노브를 데모가 쓰지 않는다 |
| 6 | PiP 중 플레이어 소멸 | **불가** | PiP 없음 |

**PiP는 v0.4.0의 간판 기능(트랙 G 전체)인데 아무도 실기기 동작을 본 적이 없다.** 이 트랙이 그 간극을 메운다.

### 2-2. 결정적 제약 — 반드시 먼저 읽을 것

**PiP를 기존 `PlaybackScreen`에 붙일 수 없다.**

데모의 `PlaybackScreen`은 `ABVideoPlayerWithControls(player:...)`를 쓴다. 그런데 **PiP는 명시 소유 경로에서만 지원되고 이 편의 API와 조합되지 않는다.** 이것은 `DESIGN-round6-nowplaying.md` §5.4의 **S-PiP-1~4** 이월 항목이며 **부분 도입이 금지**돼 있다.

→ **PiP 확인용 화면을 새로 만들어라.** `ABVideoPlayer(player:videoGravity:pictureInPicture:)` 또는 UIKit `ABPlayerView.pictureInPictureSession`을 쓰는, 컨트롤 오버레이 없는 별도 화면이다.

→ **`ABVideoPlayerWithControls`에 PiP를 붙이려 시도하지 마라.** 그것이 S-PiP이고, 4건 묶음 요구사항이라 부분 도입이 금지돼 있으며, v0.5.0 additive로 이월이 확정됐다. 이 트랙의 범위가 아니다.

### 2-3. 할 일

**라이브러리 코드(`Sources/`)는 한 줄도 바꾸지 마라.** `Examples/`만 수정한다.

**(a) PiP 화면 신규 추가** — 확인 1·2·6용

- `ABPictureInPictureSession`을 만들어 `ABVideoPlayer(player:videoGravity:pictureInPicture:)`에 전달하거나, UIKit 경로면 `ABPlayerView.pictureInPictureSession`에 바인딩한다.
- 화면에 다음 상태를 **눈에 보이게** 표시하라 — 실패 시 사용자가 원인을 기록해야 한다:
  - `ABPictureInPictureSession.isSupported` (기기 지원 여부)
  - `isPossible`, `isActive`
  - `lastFailure?.description` (실패 원인이 여기 담긴다)
- 조작: **PiP 시작**(`start()`), **PiP 정지**(`stop()`), `startsAutomaticallyFromInline` 토글(확인 2에 필수), `requiresLinearPlayback` 토글.
- 확인 6을 위해 **PiP 활성 중 플레이어를 소멸시킬 수 있는 경로**를 두어라(소스 교체, `release()`, 화면 이탈 등). 무엇이 소멸을 유발하는지 화면에 설명 한 줄을 남겨라.

**(b) AirPlay 노브 노출** — 확인 5용

- `ABPlayerConfiguration`의 `allowsExternalPlayback`, `usesExternalPlaybackWhileExternalScreenIsActive`, `externalPlaybackVideoGravity`를 조작 가능하게.
- `ABPlayer.isExternalPlaybackActive`를 **실시간으로 표시**하라. 이 값의 관측이 확인 5의 핵심이다.
- AirPlay 라우트 피커를 두면 좋다(`AVRoutePickerView`). 제어 센터로도 되지만 앱 안에서 되는 편이 확인이 쉽다.

**(c) NowPlaying 확장 `commands`** — 확인 4-B용

- 현재 `DemoModel.setNowPlayingEnabled`는 `ABNowPlayingCenter.shared.attach(player, metadata:)`만 호출한다 — `configuration:`이 없어 `commands`가 `.default`다.
- **기본 `commands`와 확장 `commands`를 전환할 수 있게** 하라. 확장 쪽은 `commands = .default.union([.nextTrack, .previousTrack, .changePlaybackRate])` + `supportedPlaybackRates` 설정 + `setTrackNavigationHandlers(next:previous:for:)` 설치가 **전부 있어야** 커맨드가 실제로 활성화된다.
- 핸들러 본문은 데모에서 관측 가능한 것이면 된다(예: 카운터 증가 후 화면 표시). 이 라이브러리에는 큐 개념이 없다.
- **왜 중요한가**: 최종 게이트가 잡은 첫 번째 결함이 정확히 이 지점이었다 — 문서가 활성화 조건을 하나만 제시해 기본 구성으로는 핸들러가 조용히 설치되지 않았다. 이 확인이 그 수정을 실증한다.

**(d) `docs/CHECKLIST-device-verification.md`와 맞추기**

체크리스트가 화면 이름과 조작을 언급한다. 구현이 끝나면 **체크리스트의 절차 서술이 실제 UI와 맞는지 확인하고, 다르면 체크리스트를 고쳐라.** 사용자가 그 문서를 보며 기기 확인을 수행한다.

### 2-4. 검증

1. **전체 스킴 3회 연속 그린**
   ```bash
   xcodebuild -scheme ABPlayerKit-Package \
     -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' test
   ```
   공유 시뮬레이터 재사용(새로 부팅 금지), `-only-testing` 금지, 기대 **743건**.

   ⚠️ **이 리포는 swift-testing을 쓴다.** 집계 줄은 `Test run with N tests`다. XCTest의 `Executed N tests`는 **항상 0**이며 그것으로 그린을 판정하면 안 된다.

2. **데모 빌드** — CI가 이 스킴을 빌드한다.
   ```bash
   xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj \
     -scheme ABPlayerKitDemo \
     -destination 'platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF' build
   ```

3. **시뮬레이터에서 앱을 띄워 새 화면이 실제로 그려지는지 확인하라.** PiP 자체는 시뮬레이터에서 동작하지 않지만, **화면이 열리고 상태값이 표시되는 것**까지는 확인 가능하다. `isSupported`가 false로 표시되는 것이 정상이다.

4. **위생 스캔 유지** (둘 다 0줄 + `exit=1`)
   ```bash
   grep -rnE '(DESIGN|PLANNING|REVIEW|ROADMAP|HANDOFF)[^ ]*\.md|round ?[0-9]|Round ?[0-9]|Phase [0-9]|§[0-9]' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
   grep -rnE '(^|[^A-Za-z0-9])(MJ-[0-9]+|mn-[0-9]+|[NMC][0-9]+|WP[0-9]+(\.[0-9]+)?|Q[0-9]+(-[A-Z])?)([^A-Za-z0-9]|$)' --include='*.swift' --include='*.md' Sources/; echo "exit=$?"
   ```

5. **`Sources/` 무변경 증명**
   ```bash
   git diff origin/main --name-only -- 'Sources/**/*.swift'   # 비어야 한다
   ```

---

## 3. R-1 — v0.4.0 릴리스

**기기 확인 6항목 결과를 사용자에게 받기 전에는 태그하지 마라.** `docs/CHECKLIST-device-verification.md`를 제시하고 결과를 받아라.

절차:
1. CI 그린 확인.
2. CHANGELOG의 `## [Unreleased]`를 `## [0.4.0] - YYYY-MM-DD`으로 스탬프.
3. **H-3w 생략을 릴리스 노트에 기록** — "검토 후 판단 갱신"으로. 근거는 §1을 참조.
4. 태그 + `gh release` (AppBoong 계정).
5. v0.5.0 이월 목록을 릴리스 노트에 포함(§4).

---

## 4. v0.5.0 이월 목록

- **P-1** — tvOS/visionOS 지원
- **S-PiP-1~4** — 편의 API(`ABVideoPlayerWithControls(url:)` 계열) + PiP 조합. 4건 묶음, **부분 도입 금지**, additive 권고
- **E-7** — LRU 최적화, sparse cache
- **설계 §12.4 안전망** — PiP 활성 중 바인딩된 플레이어의 `avPlayer`가 `nil`이 되면 세션 강제 `stop()`
- **TSan 잡에 `ABPlayerKitNowPlayingTests` 미포함**
- **`ABDetachOrderingTests`의 성능 단언** — `#expect(elapsed < .seconds(1))`. TSan 하에서 취약하나 스케일하면 "즉시 반환" 검증력 자체가 약해지는 트레이드오프가 있어 판단 보류
- **`Tests/`의 라운드 이력 인용 46건** — H-3w를 생략했으므로 참조는 유효하다. 정리 자체는 여전히 남은 일
- **`Package.swift`의 `.macOS(.v13)`** — `swift build`가 `no such module 'UIKit'`으로 실패. 기존 문제
- **CI DocC 게이트의 구조적 한계** — `DOCC_WARNINGS_AS_ERRORS`가 토픽 섹션 누락 부류를 승격시키지 못한다. 현재 경고 0건이라 당장은 무해하나, 향후 파손은 `topicSections` 덤프 같은 **산출물 확인**으로만 잡힌다

---

## 5. 운영 교훈 (Wave 3에서 실증된 것)

Wave 2의 교훈은 전부 유효했다. 아래는 Wave 3에서 새로 얻었거나 값을 한 것이다.

### 5-1. 이번 웨이브의 결함은 전부 "실행해야만" 드러났다

네 건 모두 소스를 읽거나 CI가 그린인 것으로는 잡히지 않았다:

| 결함 | 무엇이 잡았나 |
|---|---|
| DocC 토픽 섹션 누락 | **빌드된 `.doccarchive`의 `topicSections` 덤프** |
| `INFOPLIST_KEY_UIBackgroundModes`가 동작 안 함 | **빌드된 앱 번들의 `plutil` 확인** |
| README 스니펫이 컴파일 안 됨 | **스크래치 소비자 패키지로 컴파일** |
| TSan 플레이크의 원인 | **어느 테스트가 실패했는지 로그를 읽음** |

→ **검증은 산출물에 대고 하라.** "경고 없음", "소스에 있음", "CI 그린"은 이 부류를 증명하지 못한다.
→ 스니펫을 문서에 추가했으면 **컴파일하라.** 두 번째 게이트 실패가 정확히 이것이었다.

### 5-2. 스캔 패턴은 인스턴스가 아니라 부류를 잡아야 한다

같은 실수가 세 번 반복됐다:

- H-1w의 grep이 `round4 review N1` 같은 접두어 형태만 잡고 **맨 `(C1)` `(M2)`를 놓쳐** 21줄이 남았다.
- PR #11이 `waitUntil` 데드라인만 스케일하고 **맨 `Task.sleep` 경쟁을 놓쳐** TSan이 계속 깨졌다.
- PR #16이 `Task.sleep`을 덮고 **hand-rolled 데드라인을 놓쳐** F1이 남았다.

→ 무언가를 고칠 때 **"같은 문제의 다른 형태가 무엇인가"를 먼저 스캔하라.** 고친 뒤 확장 패턴으로 재스캔하는 것이 습관이 돼야 한다.

### 5-3. 게이트를 오케스트레이터와 분리한 것이 값을 했다

최종 게이트는 새 Opus 에이전트에게 맡겼다. 오케스트레이터는 모든 범위 결정을 직접 내렸으므로 자기 결정에 대한 마지막 독립 검사가 될 수 없다. 그 게이트가 **두 번 REQUEST-CHANGES를 냈고 둘 다 실재하는 결함**이었다.

→ 게이트가 오케스트레이터의 주장("코드 변경 0줄")도 **받아들이지 않고 직접 확인**했다. 실제로 `.swift` 3개가 바뀌어 있었고(주석뿐이었지만) 게이트가 읽어서 확인했다. 이 규율이 옳다.
→ 오케스트레이터가 **자기가 도입한 변경**은 반드시 게이트에 부쳐라. Wave 3의 TSan 수정이 그랬고, 게이트가 오케스트레이터보다 나은 근거를 댔다(스위트의 `.timeLimit(.minutes(3))` 때문에 30초 × 6 = 정확히 180초라 스케일하면 진단이 오히려 나빠진다는 지적).

### 5-4. CI 실패는 "무엇이 실패했는지" 먼저 읽어라

TSan이 두 번 실패했는데 **원인이 서로 달랐다.** 첫 번째는 러너 과부하(정상 수 ms 테스트가 134초), 두 번째는 스케일 안 된 2초 타임아웃. 재실행만 반복했다면 두 번째의 진짜 원인을 영영 못 찾았다.

→ **재실행 전에 실패한 테스트 이름과 실패 종류를 확인하라.** data race인지, 타임아웃인지, 컴파일 경고인지에 따라 대응이 완전히 다르다.
→ 진단에 결정적이었던 것: 이 PR들은 런타임 코드가 0줄이라 **원인일 수 없다**는 대조.

### 5-5. 사용자 결정이 필요한 것을 임의로 진행하지 마라

H-3w는 되돌리기 어렵고 로드맵에 근거가 빈약했다. 선택지를 만들다가 `docs/README.md`가 briefs를 "유지보수자용 기록"으로 **명시 선언**한 것을 발견했고, 그 결과 **초기 권장(진행)을 뒤집었다.** 사실 확인이 권장을 바꾼 사례다.

→ 되돌리기 어려운 작업 앞에서는 **로드맵에 적혀 있다는 것만으로 진행하지 마라.** 근거가 여전히 유효한지 확인하라.

### 5-6. `git add -A`를 메인 체크아웃에서 쓰지 마라

에이전트 worktree가 `.claude/worktrees/` 아래 있어 embedded repo로 스테이징됐다. `.gitignore`에 규칙을 추가해 막았지만, **명시적 경로로 `git add`하는 습관**이 근본 대책이다.

---

## 6. 새 세션 시작 프롬프트

```
docs/briefs/HANDOFF-round6-r1.md 를 읽고 라운드6 마무리(트랙 A + R-1)를 시작하세요.

먼저 상태 확인: origin/main 최신 커밋(8f98fdc이어야 함), 열린 PR이 없는지,
main CI 4개 잡이 그린인지. 커버리지 배지 91.3%가 정상입니다.

트랙 A는 데모에 기기 검증 경로를 추가하는 작업입니다. 핸드오프 §2를 그대로 따르세요.
Sonnet worktree 1개로 구현하고 Opus 게이트를 거치세요.

**§2-2의 제약을 반드시 먼저 읽으세요**: PiP는 명시 소유 경로에서만 지원되고
`ABVideoPlayerWithControls`와 조합되지 않습니다(S-PiP-1~4, 부분 도입 금지, v0.5.0 이월).
따라서 PiP 확인용 화면을 별도로 만들어야 하며, 기존 PlaybackScreen에 붙이려 하면 안 됩니다.

라이브러리 코드(Sources/)는 한 줄도 바꾸지 마세요. Examples/ 만 수정합니다.

검증은 §2-4를 전부 수행하세요. 특히:
- 전체 스킴 3회 연속 그린. `-only-testing` 결과는 근거로 인정하지 마세요.
- 집계 줄은 swift-testing의 `Test run with N tests`입니다. XCTest의 `Executed N tests`는
  항상 0이며 그것으로 그린을 판정하면 안 됩니다. 기대 743건.
- 시뮬레이터에서 앱을 띄워 새 화면이 실제로 그려지는지 확인하세요.

게이트는 구현자 보고를 신뢰하지 말고 부팅된 시뮬레이터에서 직접 실행하세요.
자가 스캔은 명령의 원본 출력(exit code 포함)을 근거로 제출하게 하세요.
리베이스는 게이트 이전에 하세요.

트랙 A가 병합되면 `docs/CHECKLIST-device-verification.md`를 사용자에게 제시하고
기기 확인 6항목 결과를 받으세요. **결과를 받기 전에는 태그하지 마세요.**
그 다음 R-1(§3)입니다.

병합은 브랜치 보호 때문에 사용자만 가능합니다. PR이 그린이 되면
`gh pr merge <번호> --admin` 실행을 요청하세요.

공유 시뮬레이터: iPhone 17 Pro Max 60DA735B-87EC-4159-9BE3-EF981A127FAF (iOS 26.2).
새로 부팅하지 말고 재사용하세요.

§5의 운영 교훈을 지키세요. 특히 "검증은 산출물에 대고 하라" — 이번 라운드 결함 4건이
전부 소스 읽기나 CI 그린으로는 안 잡히고 빌드 산출물·컴파일러·로그로만 잡혔습니다.
```
