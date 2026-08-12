# BRIEF: 라운드6 트랙 G 설계 게이트 (G-0) — Opus

당신은 라운드6 트랙 G(NowPlaying · PiP · AirPlay)의 **설계 게이트**입니다. 코드를 수정하지 말고, 설계 문서만 산출하세요.

작업 디렉터리: `/Users/jymac/orca/workspaces/ABPlayerKit/round6-nowplaying` (브랜치 `AppBoong/round6-nowplaying`, base `main` = `d29e231`)

---

## 입력 (반드시 먼저 읽을 것)

1. `docs/briefs/ROADMAP-round6.md` — §0 컨벤션, §3 트랙 G 표(G-1w~G-4w, G-5 게이트), §6 리스크, §7 완료 정의
2. `docs/briefs/REVIEW-round6-portfolio-audit.md` — 섹션 G(G-1~G-6). 이 트랙이 해소해야 할 감사 항목의 원문이다.
3. `docs/briefs/DESIGN-round6-core.md` §3.2 / §5.5 — **트랙 A가 이미 구현해 main에 병합한 이벤트 표면.** 9종 신규 이벤트와 관찰 가능 프로퍼티(`isPlaying`, `duration`, `isBuffering`, `pendingSeekTime`, `lastFailure`, `lastDiagnostic`)는 실코드에 존재한다. NowPlaying 브리지의 입력 피드가 정확히 이것이다.
4. `docs/briefs/DESIGN-round6-swiftui.md` — **§1.1~§1.5(소유권 모델과 알려진 한계), §3.2(소유 저장소의 계약), §9-4(당신에게 온 전달 사항).** 아래 "필수 판단 사항 4"의 입력이다.
5. `docs/briefs/DESIGN-round6-metrics.md` §12 "트랙 G" 항목 — 데모 파일의 메트릭 영역은 트랙 F 소유이며 병합 순서상 G가 리베이스한다.
6. 실제 소스 — 최소한 다음은 직접 읽을 것:
   - `Sources/ABPlayerKit/ABPlayerView.swift` (특히 `AVPlayerLayer`가 완전 private인 현 구조, 감사 G-1의 근거)
   - `Sources/ABPlayerKit/ABPlayer.swift` (생명주기, `release()`, detach 경로, `deinit`)
   - `Sources/ABPlayerKit/ABPlayerConfiguration.swift` (`backgroundPolicy` 4종, `audioSessionPolicy`)
   - 배경 정책과 `pauseAndDetachLayer` 구현 경로 전체
   - `Examples/ABPlayerKitDemo/**` (G-1w 데모 연동 지점)

---

## 결정해야 할 사항

### 1. `ABPlayerKitNowPlaying` 신규 타깃 API (감사 G-3)

- `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` 브리지(~150줄 규모 상정). 이벤트 스트림을 소비해 NowPlaying 정보를 채우고 리모트 커맨드를 플레이어 동작으로 되돌린다.
- **리모트 커맨드 선택**: 어떤 커맨드를 기본 활성화하고 어떤 것을 opt-in으로 둘지. 활성화한 커맨드는 반드시 대응 동작이 있어야 한다(빈 핸들러는 컨트롤 센터에서 활성 버튼으로 보이면서 아무 일도 안 하는 최악의 UX다).
- **아트워크 공급자**: 동기/비동기, 취소 가능성, 실패 시 폴백. `MPMediaItemArtwork`의 requestHandler는 임의 크기로 여러 번 호출될 수 있다는 점을 반영할 것.
- **다중 플레이어 중 "현재" 선정 규칙**: NowPlaying은 프로세스 전역 단일 자원이다. 여러 `ABPlayer`가 살아 있을 때 누가 소유하는가. 코어의 grade(`.current` 등) 개념과의 관계를 명시하라. 소유권 이전·반납·경합을 각각 정의할 것.
- **프로세스 전역 상태를 몰래 건드리지 않는다**는 이 프로젝트의 확립된 입장(README §Audio Session, `audioSessionPolicy` 기본 `.unmanaged`)과 정합하게 설계하라. NowPlaying 브리지는 **명시적 opt-in**이어야 한다.

### 2. PiP 노출 형태 (감사 G-1)

`ABPlayerView.makePictureInPictureController()` 팩토리 **vs** 레이어 접근자 노출 중 결정.

**레이어 detach 정책과의 상호작용을 반드시 검토하라** — 이것이 이 결정의 핵심 리스크다. `backgroundPolicy`의 `pauseAndDetachLayer`는 레이어를 떼어 낸다. `AVPictureInPictureController`는 자신이 붙은 `AVPlayerLayer`에 의존한다. 배경 진입 시 레이어가 detach되면 PiP 세션이 어떻게 되는가? PiP가 **켜져 있는 동안** detach 정책이 발동하면? 두 기능이 정면 충돌하는 조합을 전부 열거하고, 각각에 대해 확정된 동작을 정의하라.

### 3. `ABBackgroundPolicy.continueAudioOnly` (감사 G-4)

기존 4개 정책이 전부 "멈추는" 변형이라는 것이 감사 지적이다. 새 케이스의 **detach/유지 시맨틱**을 확정하라: 레이어는 떼는가 유지하는가, 오디오 세션 정책과의 관계(`.unmanaged` 기본에서 이 정책이 실제로 동작하려면 소비자가 무엇을 해야 하는가), 포그라운드 복귀 시 복구 경로.

`ABBackgroundPolicy`가 코어 공개 enum이라면 케이스 추가는 소비자의 `switch`를 깰 수 있다. additive-only 원칙과 어떻게 조화시킬지 명시하라(코어 파일 수정이 필요하면 §"파일 경계"의 절차를 따를 것).

### 4. **[필수] PiP × SwiftUI 편의 API 자동 해제의 상호작용**

트랙 S가 `DESIGN-round6-swiftui.md` §9-4로 당신에게 명시적으로 넘긴 판단이다. **반드시 결론을 내려라.**

사실관계:
- 트랙 S의 편의 API(`ABVideoPlayerWithControls(url:)` 등)는 **저장소(`Coordinator`/`@State`)의 파기**를 해제 트리거로 쓴다. `onDisappear`는 신뢰할 수 없다는 이유로 명시적으로 기각됐다(§1.2).
- 저장소 파기 = "이 뷰 identity는 다시 오지 않는다"와 동치이고, 그때 플레이어가 `release()`된다.
- 그런데 **PiP 세션은 뷰 파기보다 오래 살아야 한다.** 사용자가 PiP를 켜고 화면을 벗어나는 것이 PiP의 존재 이유다.
- 해제는 `deinit` → `Task { @MainActor }` 홉이라 1턴 지연된다(§1.5-4).

판단할 것: **PiP 사용 시 편의 API의 자동 해제를 억제할 수단이 필요한가?** 필요하다면 어떤 형태인가(예: PiP 활성 동안 소유 박스가 강한 참조를 유지하는 릴리스 억제 토큰, 명시 소유 API로만 PiP를 허용하는 제약, 기타). 필요 없다면 왜 안전한지 논증하라.

제약: **트랙 S가 만든 SwiftUI 파일 4개는 이번 라운드에 트랙 C도 수정 금지**이고, 이미 병합된 표면이다. 이 4파일 수정이 필요하다는 결론이 나오면 **직접 수정을 지시하지 말고** 설계 문서의 "타 트랙 전달 사항"에 요구사항으로 기록하고, v0.4.0 범위에 넣을지 이후 additive 옵션으로 미룰지 **권고안을 내라.**

### 5. AirPlay 노브 (감사 G-2)

`allowsExternalPlayback` 등 config 노브의 노출 형태. 어느 계층(configuration vs 런타임 setter)에 두는가, 기본값은 무엇인가.

### 6. 문서 범위 (감사 G-6)

자막/오디오 트랙 선택은 **선언된 non-goal로 유지**하되, README/DocC에 escape hatch(`avPlayerItem` 경유) 경로를 문서화한다. G-4w의 문서 작업 범위를 확정하라.

---

## 파일 경계 제약 (설계 단계 — 위반 시 재작업)

- **코드 수정 금지.** 이 단계의 산출물은 설계 문서 1개뿐이다.
- 설계상 다음 파일의 변경이 필요하다고 판단되면, **직접 수정을 지시하지 말고** "타 트랙 전달 사항"에 요구사항으로 기록하라:
  - `Sources/ABPlayerKitControls/SwiftUI/` 4파일 (`ABPlayerControls.swift`, `ABVideoPlayerWithControls.swift`, `ABPlayerControlsEnvironment.swift`, `ABOwnedPlayerBox.swift`) — 트랙 C도 diff 0줄로 묶여 있다
  - `Sources/ABPlayerKitControls/**` 전반 — 트랙 C가 이번 Wave에 동시 작업 중이다
  - `Sources/ABPlayerKitMetrics/**`, `Examples/**`의 메트릭 영역 — 트랙 F 소유
- `Sources/ABPlayerKit/**`(코어) 수정은 이번 Wave에 다른 트랙이 잡고 있지 않으므로 **구현 단계에서 허용**된다. 다만 additive-only이고, 공개 enum 케이스 추가처럼 소비자를 깰 수 있는 변경은 설계에서 그 영향을 명시적으로 논증하라.

---

## 산출물

`docs/briefs/DESIGN-round6-nowplaying.md` 를 **이 worktree 안에** 생성하라. 구조는 같은 라운드의 기존 설계 문서(`DESIGN-round6-controls.md`, `DESIGN-round6-metrics.md`)를 기준선으로 삼되, 최소한 다음을 포함할 것:

- **§0 전역 제약** — 이 트랙이 스스로 선언하는 파일 경계와 additive-only 범위
- **결정 1~6 각각**: 선택안 / 기각안과 기각 사유 / **실코드 근거(파일:라인)**
- **확정 API 시그니처 전체** — 신규 타깃의 공개 표면, PiP 팩토리, 새 배경 정책 케이스, AirPlay 노브를 한자리에
- **PiP × detach 정책 상호작용 매트릭스** — 조합별 확정 동작 (결정 2의 핵심 산출물)
- **PiP × 편의 API 자동 해제 판정** (결정 4) — 결론 + 논증 + 필요 시 요구사항
- **WP별(G-1w~G-4w) 구현 지침 + 테스트 전략** — 무엇을 어떻게 테스트할지. 시뮬레이터에서 PiP/NowPlaying은 검증이 제한적이므로, **테스트 가능한 것과 불가능한 것을 정직하게 구분**하고 불가능한 것은 그렇게 적어라
- **무회귀 가드 / 절대 불변식** — G-5 게이트가 체크리스트로 쓸 형태
- **타 트랙 전달 사항** — 특히 트랙 S 4파일 관련 요구사항과 권고
- **명시적 비범위** — G-5 게이트가 위반 시 REQUEST-CHANGES할 목록
- **완료 정의 체크리스트**

## 제약

- **코드 수정 금지, 커밋 금지.** 시뮬레이터 부팅 금지, 빌드/테스트 실행 불필요(읽기 전용 분석).
- 근거는 추측이 아니라 **실코드 인용(파일:라인)**으로 대라. 코드를 읽고 확인할 수 없는 사항은 "확인 불가"라고 그대로 적어라 — 그 정직한 보고가 잘못된 설계보다 낫다.
- 설계 문서에는 리뷰/감사 ID를 자유롭게 인용해도 된다(문서이므로). **단 이 규칙은 문서 한정이며, 구현 단계의 소스 주석에는 ID 인용이 금지된다** — 설계 문서의 WP 지침에 그 금지 사항을 반드시 명기하라.
- **설계 문서 작성 완료가 곧 작업 완료 신호다.** 완료 후 추가 작업 없이 대기하라. 승인 후 구현 브리프를 별도로 받는다.
