# REVIEW: 라운드6 포트폴리오 감사 (2026-08-12, 기준 커밋 995bb6d)

시니어 영상 도메인 iOS 관점의 전체 감사 결과. 라운드6 로드맵(`ROADMAP-round6.md`)의 근거 문서.
각 항목에 ID를 부여 — 로드맵 WP와 구현 브리프가 이 ID를 인용한다.

제품 목표 재확인: **(1) SwiftUI에서 URL로 간편하게 재생, (2) README 사용법 완결, (3) 커스텀 가능, (4) 재생속도·건너뛰기 설정.**

---

## A. 코어 버그 (수정 필수)

| ID | 내용 | 위치 |
|---|---|---|
| A-1 | **루프가 재생을 재개하지 않음** — `isLooping`이 `seekToStart()`만 호출. `actionAtItemEnd` 기본 `.pause`라 rate=0 상태로 처음에서 정지. `play()` 재호출 또는 `AVPlayerLooper` 필요. 테스트는 `setLooping` 호출 여부만 검증 | `ABAVPlaybackTarget.swift:358-367` |
| A-2 | **포그라운드 복귀가 오디오 세션 우회** — `audioSessionActivationDirty = true` 직후 `self.play()`가 아닌 `target.play()` 직접 호출로 `applyAudioSessionPolicyIfNeeded()` 스킵. 관리형 세션 + 백그라운드 복귀 시 무음 재생 가능. `handleInterruptionEnded`(`:768`)는 올바르게 `self.play()` 사용 | `ABPlayer.swift:677,683,689` |
| A-3 | **`lastError` 영구 잔존 + 비종료 진단 오염** — attach/sourceChanged/release에서 리셋 없음. `.itemErrorLogEntry`(정상 스트리밍 중에도 발생)가 `.failed`와 동일 채널로 `lastError`에 기록됨. `ABPlayerError.swift:26-28` 스스로 "non-terminal"이라 문서화하면서 병합 | `ABPlayer.swift:475-477` |
| A-4 | **TTFF 거짓 히트** — `hasDisplayedFirstFrame`이 `.attachItem`에서만 리셋. `release()` 후 `true` 잔존 → `beginTTFF`가 false cache hit 기록 | `ABPlayer.swift:501-502`, `ABMetricsRecorder.swift:33-41` |
| A-5 | **preroll TOCTOU** — status 확인(`:300`)과 `[.new]` 관찰 등록(`:312`) 사이 전이 시 10초 타임아웃까지 행. 자매 관찰(`:338`)은 `[.initial, .new]`로 올바름 | `ABAVPlaybackTarget.swift:299-319` |
| A-6 | **배경 캡처 시점 오류** — `didEnterBackground`에서 `isPlaying` 캡처. iOS가 그 전에 디코드를 멈춰 대개 이미 `false` → auto-resume 불발. `willResignActive`가 정답 | `ABApplicationStateObserver.swift:24`, `ABPlayer.swift:654` |
| A-7 | **시크 진입점 4곳 중 1곳만 세대 가드** — 세션 밖 `scrub(to:)`(`:362-369`, per-call 무제한 Task), `seekToStart` 경로(`:523`), 공개 `seek(to:)`(`:300-312`, duration 클램프도 없음)가 코얼레서/`seekGeneration` 밖. stale `.seekCompleted`가 소스 교체 후 도착 가능 | `ABPlayer.swift` |
| A-8 | **`.itemDetached`를 detach 전에 방송** — `ABPlayerView`가 옛 아이템을 읽고 리바인드, 이후 `.gradeChanged`로 우연히 자기수정. 순서 하나로 stale-layer 버그 | `ABPlayer.swift:513-515` |

## B. 코어 관찰성/이벤트 갭

| ID | 내용 |
|---|---|
| B-1 | **`isPlaying`/`currentTime`/`duration`이 @Observable 아님** (computed, `ABPlayer.swift:40-46`) — SwiftUI 뷰 재렌더 안 됨. Controls가 자체 미러(`ABControlsPresenter.swift:73`, 114-131의 20줄 주석)를 유지하는 것이 증거. 워크어라운드를 엔진으로 이동 |
| B-2 | **버퍼링 상태 전무** — `isPlaybackLikelyToKeepUp`/`isPlaybackBufferEmpty`/`reasonForWaitingToPlay` 미관찰. `bufferingChanged(Bool)` 이벤트 + observable 프로퍼티 필요. 스피너는 `.waitingToPlay`로 유추 불가(레이트 평가 대기와 혼동) |
| B-3 | **`ABPlayerError`가 NSError domain/code 소실** (`ABPlayerError.swift:12` 문자열화) — `-1009`(재시도)와 `-11829`(포기) 구분 불가, 소비자 재시도 정책 원천 차단. `(domain: String, code: Int, description: String)` 캐리는 Sendable 유지하며 무비용 |
| B-4 | 누락 이벤트(우선순): `durationAvailable`(스크러버 1순위 — 현재 폴링 필요), `stallEnded`(스톨 시간 측정 불가), `itemAttached`(대칭성), `presentationSizeChanged`(현재 `ABPlayerView.swift:99-109` 폴링), `mutedChanged` |
| B-5 | `.playbackRejected`가 어떤 호출·grade였는지 페이로드 없음 (`ABPlayerEvent.swift:55`). 첫 사용 경험의 "왜 아무 일도 안 일어나지"의 원인 |
| B-6 | `ABMediaSource.httpHeaders`가 코어 기본 팩토리에서 무시됨 (`ABAssetFactory.swift:13-15`) — Authorization 헤더 401을 진단 없이 유발 |
| B-7 | `UIScreen.main` deprecated + 개념 오류 — 피드에서 올바른 캡은 셀 크기, 화면 크기 아님 (`ABAVPlaybackTarget.swift:204-210`) |
| B-8 | `defaultRate`(iOS16) 미사용으로 `desiredRate` 수기 북키핑, `audioTimePitchAlgorithm` 미노출 |

## C. SwiftUI 간편화 갭 (제품 목표 1 직결)

| ID | 내용 |
|---|---|
| C-1 | **URL 편의 API 부재** — `ABVideoPlayer(url:)`/`ABVideoPlayerWithControls(url:)` 없음. 최소 경로가 4단계 + `onDisappear { release() }` 수동. autoplay/자동 해제 포함 편의 생성자 필요 |
| C-2 | **modifier/Environment API 전무** — `EnvironmentKey`/`ViewModifier` grep 0건. `.playerControlsStyle(_:)`/`.playerControlsConfiguration(_:)` 필요 |
| C-3 | README Quick Start가 `kind:`를 명시하나 확장자 추론이 이미 존재 (`ABMediaSource.swift:24`) — 첫 예제를 더 짧게 |

## D. Controls UX 버그/갭 (제품 목표 3·4 직결)

| ID | 내용 | 위치 |
|---|---|---|
| D-1 | **연속 skip 탭 비누적** — live `currentTime` 기반 + `AVPlayer.seek`의 in-flight 취소로 +20 두 번 = 20초. VoiceOver increment는 라벨(절대값)과 커맨드(상대값)가 불일치. `ABSeekCoalescer`가 스크럽에만 연결됨 | `ABControlsPresenter.swift:142-164,411-414`, `ABPlayer.swift:315-338` |
| D-2 | **리버퍼링 중 아이콘 역전** — `.waitingToPlay` → `isPlaying=false` → ▶︎ 표시인데 탭하면 pause. 스톨=일시정지 구분 불가, 오버레이는 스톨 내내 고정 | `ABControlsPresenter.swift:174-176` |
| D-3 | **버퍼링 스피너 부재** — `.playbackStalled` 케이스 자체가 없음 (B-2 의존) | `ABPlayerControlsView.swift:419-454` |
| D-4 | **더블탭 시크 부재** — 2026년 표준. `skipInterval`의 자연 소비자. 오버레이가 모든 터치를 삼켜(`hitTest :157-192`) 소비자가 직접 추가도 불가 — passthrough 옵션 필요 |
| D-5 | **종료 후 리플레이 불가** — `.playedToEnd` 후 play 탭이 끝 지점 `play()`만 호출, `seekToStart` 미발행 | `ABControlsPresenter.swift:208-210` |
| D-6 | 배속 메뉴 `"%g×"` 하드코딩 — 로케일 소수점 무시(de/fr), 메뉴 타이틀 커스텀 불가 | `ABPlayerControlsView.swift:599,741` |
| D-7 | 레이아웃 슬롯 1개(accessoryStack 고정 위치)뿐 — 상단바/transport 내부/위치 지정 불가. `showsPlayPauseButton`/`showsSeekBar` 없음 | `ABPlayerControlsView.swift:232-311` |
| D-8 | 스타일 diff 리스트 3벌 수기 유지 — 프로퍼티 추가 시 조용한 버그 1순위 | `ABPlayerControlsView.swift:923-956`, `ABSeekBar.swift:256-269` |
| D-9 | 뷰↔프리젠터 상태 3중 미러(`seed`/`syncPlaybackTime`가 증거). B-1 해소 시 대부분 제거 가능 | `ABPlayerControlsView.swift:54-55`, `ABControlsPresenter.swift:73-99` |
| D-10 | `ABPlayerControlsStyle`이 non-Sendable (Configuration은 Sendable) — 표면 불일치 | `ABPlayerControlsStyle.swift` |
| D-11 | 하드코딩 문자열: `liveMarker = "LIVE"`(가시 라벨 미번역, spoken용 키는 존재), `"/"` 구분자, 햅틱 전무, `accessibilityHint` 전무 | `ABTimeFormatter.swift:6` 외 |

## E. Cache 무결성

| ID | 내용 | 위치 |
|---|---|---|
| E-1 | **재개 검증 부재(유일한 "버그"급)** — `bytes=N-` 재개에서 `Content-Range` 시작 검증·`ETag`/`If-Range` 없음 → 원본 변경 시 무음 손상. 메타데이터 TTL/재검증도 없음 | `ABCacheStore.swift:515-562,763-769` |
| E-2 | `FileHandle` 누수 2곳 — throw 경로에서 `close()` 미보장 (`defer` 아님) | `ABCacheStore.swift:542-544,572-575` |
| E-3 | `removeAll()`/`remove(_:)`가 `readerRegistry` 무시 — 재생 중 삭제 시 다음 read throw → 재생 실패. 데모 버튼이 정확히 이 경로 노출 | `ABCacheStore.swift:300-337` |
| E-4 | actor 내 동기 디스크 I/O + 청크당 핸들 open/close — 멀티플레이어 피드에서 상호 블로킹 | `ABCacheStore.swift:564-585,734-761` |
| E-5 | `application/octet-stream` → `public.data`로 확장자 폴백 도달 불가 | `ABCacheStore.swift:933-945` |
| E-6 | 원본이 Range 무시(200) 시 전체 바디 RAM 버퍼링 | `ABCacheStore.swift:646-704,725-727` |
| E-7 | LRU: O(n log n)/청크, 벽시계 recency, 쓰기도 access로 카운트. 규모상 당장 무해하나 문서화 가치 | `ABCacheIndex.swift:38-76` |
| E-8 | `ABResourceLoaderDelegate` 직접 테스트 0건 | — |

## F. Metrics 폭 (업계 QoE 대비)

| ID | 내용 |
|---|---|
| F-1 | **리버퍼 시간/비율 부재** — `.stall`이 타임스탬프만. `stallEnded`(B-4) 또는 `.timeControlStatusChanged(.playing)` 소비로 duration 산출. 스타트업+리버퍼가 업계 QoE 기본 페어 |
| F-2 | watch time 부재 (`.periodicTime` 미소비) — 모든 비율 지표의 분모 없음 |
| F-3 | 에러율 부재 — `.failed` 미매핑, `ABMetricEvent`에 error 케이스 자체가 없음 |
| F-4 | `.hit`이 0ms로 지연 분포 오염 — preload 피드에서 p50=0 붕괴. 별도 분포로 분리 (`ABPlaybackStatistics.swift:44-46`) |
| F-5 | accessLog `events.last`만, detach 시점만 — 비트레이트 스위치 횟수/dropped frames 소실 (`ABMetricsRecorder.swift:94-102`) |
| F-6 | JSONL 싱크: 이벤트당 open/close, 에러 무음, `flush()` internal, 로테이션 없음. 벽시계 앵커 부재로 서버 로그 조인 불가 |

## G. 차별화 기능 갭

| ID | 내용 |
|---|---|
| G-1 | **PiP 원천 불가** — `AVPlayerLayer` 완전 private (`ABPlayerView.swift:11-15`). 레이어 노출 또는 `makePictureInPictureController()` 팩토리가 최고 가치 추가 |
| G-2 | AirPlay 미노출 — `allowsExternalPlayback` 등 config 노브 1줄 부재가 오히려 눈에 띔 |
| G-3 | **NowPlaying/리모트 커맨드 브리지 부재** — 이벤트 스트림이 정확히 그 피드. `ABPlayerKitNowPlaying` 신규 타깃 ~150줄 |
| G-4 | 백그라운드 오디오의 실제 유즈케이스 `.continueAudioOnly` 부재 — 4개 정책 전부 "멈추는" 변형 |
| G-5 | tvOS/visionOS 미지원 — Cache/Metrics는 UIKit import 0으로 거의 무료. `.tvOS(.v17)` + `#if canImport(UIKit)` 소수 |
| G-6 | 자막/오디오 트랙 선택 — 선언된 non-goal 유지하되, README에 escape hatch(`avPlayerItem`) 경로 문서화 |

## H. 포트폴리오 위생

| ID | 내용 |
|---|---|
| H-1 | **`docs/briefs/`(20파일 230KB) 공개 부적합** — AI 파이프라인 운영 기록. 특히 `HANDOFF-round5-track2.md:22` "포트폴리오 방어 논리(면접 대비)" 사전 스크립트는 역효과. orphan branch/private 이전. `docs/DESIGN-*.md`/`POLICY-*`는 유지(강점) |
| H-2 | **소스 주석 ~90곳이 내부 리뷰 ID 인용** ("round4 N1", "WP9.2", "MJ-1") — briefs 이전 시 전부 깨진 참조. Bool 하나에 20줄(`ABPlayer.swift:116-135`). 불변식 3줄로 재작성, 히스토리는 커밋으로 |
| H-3 | CI 커버리지 수집만 하고 미리포트 — README 배지가 최고 ROI 1건. TSan 잡 부재(락 기반 코드 다수인데) |
| H-4 | SwiftLint/format 설정 부재 — CONTRIBUTING이 열거한 컨벤션을 기계 강제 안 함 |
| H-5 | 테스트: `waitUntil` busy-spin(`Task.yield()` 폴링), `ABWaitUntil.swift` 3벌 복붙 — `ABTestSupport` 타깃으로 통합 |
| H-6 | `ABObserverRegistry`/`ABLayerAttachmentObserverRegistry` 중복 — 제네릭 1개로 ~55줄 제거. `ABAudioSession.activate` 바이트 동일 중복 |

## 강점 (건드리지 말 것)

Grade 상태머신+순수 플래너, `ABSeekCoalescer`, TTFF 정의(레이어 ready AND item ready, 콜백 스레드 타임스탬프), `PeriodicObserverBox`, `ReadyWaitState`, 캐시 취소/coalescing(`ABCacheProgressWaiter`, UUID 동일성), 스크럽 세션의 `scrubbingPlayer` 고정, 배지 합성 skip 아이콘, VoiceOver spelled-out 시간, 4모듈 링크 분리, zero-dependency, DocC CI 강제, Design Rationale 문서.
