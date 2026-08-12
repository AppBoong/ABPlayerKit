# ROADMAP: 라운드6 — 포트폴리오 완성 (v0.4.0 목표)

기준 커밋 995bb6d. 근거: `REVIEW-round6-portfolio-audit.md` (항목 ID A-1 ~ H-6을 본 문서가 인용).
제품 목표: **(1) SwiftUI에서 URL로 간편 재생 (2) README 사용법 완결 (3) 커스텀 (4) 배속·건너뛰기 설정.**

## 0. 파이프라인 컨벤션 (HANDOFF-round5 §4 승계)

- **모델 역할**: 설계·리뷰 게이트 = **Opus**(`claude --model opus`), 구현 = **Sonnet**(`claude --model claude-sonnet-5`), 커밋 = **Haiku**. 전부 Orca 터미널 탭 디스패치(`orca terminal create --worktree ...`).
- **병렬화 기준**: **모듈/파일 경계가 겹치지 않는 트랙만 동시 worktree**. 겹치면 직렬. 각 병렬 트랙은 독립 worktree + 독립 브랜치(`round6/<track>`), 병합은 오케스트레이터가 Wave 경계에서 수행.
- **산출물 규약**: 설계 게이트 → `docs/briefs/DESIGN-round6-<track>.md`, 구현 결과 → `docs/briefs/RESULT-round6-<track>.md`, 리뷰 → `REVIEW-round6-<track>.md` 마지막 줄 `FINAL-VERDICT: APPROVE|REQUEST-CHANGES`. 완료 감지는 산출물 파일 생성 감지(TUI 폴링 금지).
- **구현 규칙**(모든 브리프에 명시): Swift 6 zero-warning, 새 시뮬레이터 부팅 금지, sleep 대기 금지(`ABWaitUntil` 사용), 커밋 금지(Haiku 담당), 이벤트/공개 API 추가는 additive-only(POLICY-api-stability 준수), 새 코드 주석에 리뷰 ID 인용 금지(불변식만 서술 — H-2 재발 방지).

## 1. Wave 구조 요약

```
Wave 1 (4 병렬 worktree)          Wave 2 (A 병합 후, 3 병렬)        Wave 3 (직렬 마무리)
├─ 트랙 CI  : 커버리지·TSan·Lint   ├─ 트랙 C : Controls UX           ├─ (선택) 트랙 P : tvOS
├─ 트랙 A   : 코어 신뢰성+관찰성   ├─ 트랙 F : Metrics QoE           ├─ 트랙 H : 주석·문서·위생
├─ 트랙 E   : 캐시 무결성          └─ 트랙 G : NowPlaying·PiP        └─ 릴리스 v0.4.0
└─ 트랙 S   : SwiftUI 간편 API
```

- **Wave 1 병렬 근거**: CI(코드 무관) / A(`Sources/ABPlayerKit` Engine·Policy·Observation·Model) / E(`Sources/ABPlayerKitCache`) / S(SwiftUI 래퍼 파일 + 신규 파일만) — 파일 교집합 없음. S 브리프에 "`ABPlayer.swift`·`ABAVPlaybackTarget.swift` 수정 금지" 명시로 A와의 충돌 차단.
- **Wave 2가 A에 의존하는 이유**: C는 A가 추가하는 `bufferingChanged`/observable `isPlaying`을 소비(D-2, D-3, D-9), F는 `stallEnded`를 소비(F-1), G는 A 안정화 후 `ABPlayerView` 소폭 수정(G-1). C/F/G 상호 간 파일 교집합 없음 → 3 병렬.
- **Wave 2 설계 선행 가능**: A의 설계 게이트(DESIGN-round6-core.md)가 이벤트 이름·시그니처를 확정하므로, C/F의 Opus 설계는 A **구현 중에** 병렬로 시작 가능.

---

## 2. Wave 1

### 트랙 CI — 리포 인프라 (코드 무관, 리스크 0)

| WP | 내용 | 감사 ID | 담당 |
|---|---|---|---|
| CI-1 | CI에 커버리지 요약 스텝(xccov) + README 커버리지 배지 | H-3 | Sonnet |
| CI-2 | ThreadSanitizer 잡 추가(코어+캐시 테스트 타깃) — 락 기반 코드의 동시성 주장 실증 | H-3 | Sonnet |
| CI-3 | `.swiftlint.yml` + lint 스텝 (CONTRIBUTING 컨벤션의 기계 강제) | H-4 | Sonnet |
| CI-4 | `ABTestSupport` 테스트 타깃 신설 — `ABWaitUntil` 3벌 통합 + busy-spin → `Task.sleep(5ms)` 폴링 | H-5 | Sonnet |

게이트: 설계 게이트 불필요(정형 작업). CI 그린이면 병합. TSan 실패 발견 시 → 해당 트랙(A/E) 브리프에 이슈로 전달.

### 트랙 A — 코어 엔진 신뢰성 + 관찰성 (최대 규모, 트랙 내 직렬)

**A-0 설계 게이트 (Opus)** — 결정사항:
1. 에러 모델: `ABPlayerError`에 `(domain, code)` 캐리 방식 — additive(연관값 추가는 breaking이므로 새 케이스 or 구조체 페이로드 병행안) 결정 (B-3)
2. 관찰성: `isPlaying`/`duration`/`isBuffering`의 @Observable 저장 프로퍼티 전환 설계 — target 이벤트로 미러 갱신, KVO 소스(`isPlaybackLikelyToKeepUp` 등) 선정 (B-1, B-2)
3. 신규 이벤트 표면 확정: `bufferingChanged(Bool)`, `durationAvailable(CMTime)`, `stallEnded`, `itemAttached`, `presentationSizeChanged(CGSize)`, `.playbackRejected` 페이로드 보강 방식 (B-4, B-5) — **이 문서가 Wave 2 C/F 설계의 입력**
4. 시크 통일: 4개 진입점을 코얼레서+세대 가드로 수렴하는 구조 + **skip 누적 시맨틱**(pending delta 합산— D-1의 코어 절반) (A-7)
5. `ABPlayer` 분해 범위: 이번 라운드는 `BackgroundPolicyMachine`/`AudioSessionGate` 순수 리듀서 추출까지만(기존 `ABGradePlanner` 스타일), 전면 재설계 금지 — 회귀 리스크 통제

| WP | 내용 | 감사 ID |
|---|---|---|
| A-1w | 루프 수정(seek 후 play 재개 or `actionAtItemEnd` 활용) + 재개 검증 테스트 | A-1 |
| A-2w | 포그라운드 복귀 `self.play()` 경유 + 배경 캡처 `willResignActive` 이관 | A-2, A-6 |
| A-3w | `lastError` 라이프사이클(attach/source 변경 시 리셋) + error-log 진단을 별도 채널로 분리 | A-3 |
| A-4w | `hasDisplayedFirstFrame` detach 시 리셋 + preroll `[.initial,.new]` + `.itemDetached` 방송 순서 수정 | A-4, A-5, A-8 |
| A-5w | 시크 통일 + skip 누적(설계 4번) — 기존 스크럽 테스트 무회귀 필수 | A-7, D-1 |
| A-6w | 관찰성/이벤트(설계 2·3번) 구현 + `ABPlayerError` domain/code(설계 1번) | B-1~B-5 |
| A-7w | 소형: `httpHeaders` 기본 팩토리 적용(`AVURLAsset` options), `UIScreen.main` 제거, `defaultRate`/`audioTimePitchAlgorithm` 노출, 레지스트리 제네릭 통합 | B-6~B-8, H-6 |

**A-8 최종 게이트 (Opus)**: 전체 diff 리뷰. 특히 A-5w의 스크럽 회귀와 A-6w의 @Observable 매크로 상호작용(기존 WP9.2류 함정) 집중.

### 트랙 E — 캐시 무결성 (`Sources/ABPlayerKitCache`만)

**E-0 설계 게이트 (Opus)** — `If-Range`/`ETag` 재개 검증 프로토콜(검증 실패 시 prefix 폐기 후 재시작 vs 엔트리 무효화), 메타데이터 재검증 시점, `removeAll` vs reader 조정(지연 삭제 vs 실패 허용+문서화) 결정. **sparse range(라운드5 트랙2)는 이번 범위에서 제외** — 무결성 먼저.

| WP | 내용 | 감사 ID |
|---|---|---|
| E-1w | 재개 검증: `Content-Range` 시작 일치 확인 + `ETag`/`Last-Modified` 저장·`If-Range` 송신 + 불일치 시 안전 폐기 | E-1 |
| E-2w | `FileHandle` `defer` close 2곳 + fill 수명 동안 writer 핸들 유지(청크당 open/close 제거) | E-2, E-4 일부 |
| E-3w | `remove`/`removeAll`의 reader 조정(설계 결정 반영) — 데모 버튼 시나리오 테스트 | E-3 |
| E-4w | content-type 폴백(제네릭 supertype이면 확장자 우선) + Range 무시 원본의 메모리 상한 | E-5, E-6 |
| E-5w | `ABResourceLoaderDelegate` 직접 테스트(가짜 loading request로 contentInformation/데이터 경로) | E-8 |

**E-6 최종 게이트 (Opus)**: 기존 취소/coalescing 불변식(라운드3~4 확립) 무회귀 확인 중심. E-7(LRU 최적화)은 의도적 이월 — DocC에 제약 문서화만.

### 트랙 S — SwiftUI 간편 API (제품 목표 1번, 파일 격리 필수)

**S-0 설계 게이트 (Opus)** — 결정사항: URL 편의 API의 소유권 모델(내부 `@State` ABPlayer 자동 생성 + `onDisappear` 자동 release vs 명시 소유 유지), autoplay 기본값, modifier API의 Environment 전파 범위(style/configuration), deprecated 없이 additive로만. **제약: `ABPlayer.swift`/`ABAVPlaybackTarget.swift`/`ABPlayerControlsView.swift` 수정 금지** (A·C와 충돌 차단 — 필요 시 요구사항을 해당 트랙 브리프로 전달).

| WP | 내용 | 감사 ID |
|---|---|---|
| S-1w | `ABVideoPlayer(url:gravity:autoplay:)` + `ABVideoPlayerWithControls(url:...)` — 생명주기 자동 관리 편의 생성자 | C-1 |
| S-2w | `.playerControlsStyle(_:)` / `.playerControlsConfiguration(_:)` EnvironmentKey + modifier | C-2 |
| S-3w | README Quick Start 개편: 첫 예제를 URL 원라이너로, grade 시스템은 "고급" 섹션으로 강등. `kind:` 명시 제거 | C-3 |

**S-4 최종 게이트 (Opus)**: 소유권 모델의 SwiftUI 재생성(identity) 안전성 집중 리뷰.

**Wave 1 병합 순서**: CI → E → S → A (A가 최대 diff이므로 마지막, 충돌 발생 시 A 기준 해소).

---

## 3. Wave 2 (A 병합 후 착수, 3 병렬)

### 트랙 C — Controls UX (제품 목표 3·4번, `Sources/ABPlayerKitControls`만)

**C-0 설계 게이트 (Opus)** — 입력: `DESIGN-round6-core.md`의 이벤트 표면. 결정: 버퍼링 시각 상태(스피너 vs 아이콘 유지+오버레이), 더블탭 시크 UX(좌우 영역 분할, 연속 탭 누적 표시, Reduce Motion 대응), passthrough 터치 옵션 형태, 레이아웃 슬롯 API(`.topTrailing`/`.bottomTrailing`/`.transportTrailing` — accessoryStack 하위호환).

| WP | 내용 | 감사 ID |
|---|---|---|
| C-1w | 버퍼링 상태: `bufferingChanged` 소비 → 스피너 + 아이콘 역전 해소 + 스톨 중 auto-hide 정책 결정 반영 | D-2, D-3 |
| C-2w | skip UI: 코어 누적 시맨틱(A-5w) 소비 + VoiceOver 라벨/커맨드 일치화 | D-1 잔여 |
| C-3w | 더블탭 시크(`skipInterval` 재사용) + `passthroughTouches` 옵션 + 햅틱 | D-4 |
| C-4w | 리플레이: `.playedToEnd` 후 play 탭 → `seekToStart`+play | D-5 |
| C-5w | 배속 메뉴 로케일(`NumberFormatter`) + 메뉴 타이틀 커스텀 훅, `liveMarker` 번역, 구분자 노출 | D-6, D-11 |
| C-6w | 레이아웃 슬롯(설계 반영) + `showsPlayPauseButton`/`showsSeekBar` | D-7 |
| C-7w | 구조 정리: 스타일 diff 리스트 단일화, 프리젠터 미러 제거(observable 소비로 대체), Style Sendable화 | D-8~D-10 |

**C-8 최종 게이트 (Opus)**: 기존 184개 Controls 테스트 무회귀 + hitTest 우선순위 회귀 집중.

### 트랙 F — Metrics QoE (`Sources/ABPlayerKitMetrics`만)

**F-0 설계 게이트 (Opus)** — 이벤트 스키마 v2: 리버퍼(시작/종료/누적), watch time 누적기, 에러 이벤트, hit/waited 분포 분리, 벽시계 앵커(세션 시작 시 1회 매핑). JSONL 하위호환 결정.

| WP | 내용 | 감사 ID |
|---|---|---|
| F-1w | 리버퍼 duration/비율(`stallEnded` 소비) + 스톨 미종결 세션 처리 | F-1 |
| F-2w | watch time(`.periodicTime` 소비) + 완료율(`.playedToEnd`) | F-2 |
| F-3w | 에러율(`.failed` 매핑, domain/code 포함 — A-6w 산출 소비) | F-3 |
| F-4w | `.hit` 분포 분리 + accessLog 전체 이벤트 순회(스위치 횟수, dropped frames) | F-4, F-5 |
| F-5w | 싱크 개선: `flush()` 공개, 핸들 유지, 에러 카운터, 타임스탬프 앵커 | F-6 |
| F-6w | 데모 Metrics 탭 확장(새 지표 표시 — 얇음 해소) | — |

**F-7 최종 게이트 (Opus)**.

### 트랙 G — NowPlaying · PiP · AirPlay (신규 타깃 중심)

**G-0 설계 게이트 (Opus)** — `ABPlayerKitNowPlaying` 타깃 API(리모트 커맨드 선택, 아트워크 공급자, 다중 플레이어 중 "현재" 선정 규칙), PiP 노출 형태(`ABPlayerView.makePictureInPictureController()` vs layer 접근자 — 레이어 detach 정책과의 상호작용 필수 검토), `.continueAudioOnly` 배경 정책의 detach/유지 시맨틱.

| WP | 내용 | 감사 ID |
|---|---|---|
| G-1w | `ABPlayerKitNowPlaying` 신규 타깃: `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` 브리지(이벤트 스트림 소비, ~150줄) + 데모 연동 | G-3 |
| G-2w | PiP 팩토리(설계 반영) + `allowsExternalPlayback` 등 AirPlay 노브 config 노출 | G-1, G-2 |
| G-3w | `ABBackgroundPolicy.continueAudioOnly` | G-4 |
| G-4w | README/DocC: 자막·트랙 선택의 escape hatch 경로 문서화 | G-6 |

**G-5 최종 게이트 (Opus)**: PiP×`pauseAndDetachLayer` 상호작용, NowPlaying 다중 플레이어 시나리오 집중.

**Wave 2 병합 순서**: F → G → C (C가 최대 diff).

---

## 4. Wave 3 (직렬 마무리)

| WP | 내용 | 감사 ID | 담당 |
|---|---|---|---|
| P-1 (선택) | `.tvOS(.v17)`(+`.visionOS(.v1)` 검토) — `#if canImport(UIKit)` 가드, Controls는 iOS 한정 유지. CI 목적지 추가. **일정 압박 시 v0.5.0으로 이월** | G-5 | Opus 설계 → Sonnet |
| H-1w | **소스 주석 전수 정리**: 리뷰 ID 인용 ~90곳 → 불변식 서술로 재작성(코드 변경 0, 주석만). 모든 코드 트랙 완료 후라 충돌 없음 | H-2 | Sonnet (Opus 표본 검수) |
| H-2w | README/DocC/CHANGELOG 최종화: 새 기능 반영, Quick Start 재검, 마이그레이션 노트, 커버리지 배지 확인 | — | Sonnet |
| H-3w | **`docs/briefs/` 이전**: orphan branch `archive/briefs`로 이동 후 main에서 제거(RESULT/REVIEW 산출 종료 시점). `docs/DESIGN-*.md`·`POLICY-*`는 유지 | H-1 | 오케스트레이터 직접 |
| R-1 | 릴리스 v0.4.0: CI 그린 → CHANGELOG 스탬프 → 태그 → gh Release(AppBoong 계정 스위칭) — 라운드5 트랙1 절차 재사용 | — | 오케스트레이터 직접 |

**최종 게이트 (Opus)**: v0.4.0 태깅 전 전체 리포 관점 리뷰 1회 (`REVIEW-round6-final.md`, FINAL-VERDICT).

---

## 5. 디스패치 시퀀스 (오케스트레이터 실행 순서)

1. **Wave 1 설계**: Opus 터미널 3개 병렬 생성(A-0, E-0, S-0 — 각각 본 문서와 감사 문서의 해당 섹션을 입력으로, `DESIGN-round6-{core,cache,swiftui}.md` 산출, 코드 수정 금지). CI 트랙은 설계 없이 Sonnet 즉시 디스패치(worktree: `round6/ci`).
2. 설계 승인(사용자 확인) 후 **Wave 1 구현**: Sonnet worktree 3개 병렬(`round6/core`, `round6/cache`, `round6/swiftui`) + 각 완료 시 해당 트랙 Opus 게이트 → APPROVE 시 Haiku 커밋. 병합: CI → E → S → A.
3. A 설계 확정 직후(구현과 병렬) **Wave 2 설계** Opus 2개 선행 가능(C-0, F-0 — 입력: `DESIGN-round6-core.md`). G-0는 Wave 1 병합 후.
4. **Wave 2 구현**: Sonnet 3 병렬(`round6/controls`, `round6/metrics`, `round6/nowplaying`) → 트랙별 Opus 게이트 → 병합 F → G → C.
5. **Wave 3**: P-1(선택) → H-1w → H-2w → 최종 Opus 게이트 → H-3w(briefs 이전) → R-1(릴리스).

## 6. 리스크와 가드레일

- **최대 리스크 = 트랙 A-5w/A-6w** (시크 통일 + @Observable 전환): 기존 175개 코어 테스트가 안전망. 브리프에 "스크럽/코얼레서 기존 테스트 수정 금지(동작 보존 증명)" 명시.
- **worktree 병합 충돌**: 트랙별 파일 경계를 브리프에 명시(위반 시 게이트에서 REQUEST-CHANGES). 유일한 공유 파일 위험은 `ABPlayerEvent.swift`(A 전용으로 고정, C/F는 소비만).
- **이벤트 additive 원칙**: 모든 신규 이벤트/케이스는 non-exhaustive 계약 하에 추가만 — 기존 소비자 스위치 무영향.
- **CI 러너 느림**: suite timeLimit 3분·waitUntil 여유 유지(라운드5 확립). TSan 잡은 별도 job으로 분리해 메인 잡 지연 방지.
- **범위 방어**: sparse cache(라운드5 트랙2)·LRU 최적화(E-7)·`ABPlayer` 전면 분해·tvOS(일정 압박 시)는 **명시적 이월** — v0.4.0은 "신뢰성 + 제품 목표 정합 + 차별화 1종(NowPlaying/PiP)"으로 완결.

## 7. 완료 정의 (v0.4.0 릴리스 기준)

- [ ] 감사 A-1~A-8, B-1~B-8, C-1~C-3, D-1~D-11, E-1~E-6·E-8, F-1~F-6, G-1~G-4·G-6 해소 (E-7, G-5는 이월 허용)
- [ ] URL 원라이너 데모: `ABVideoPlayerWithControls(url:)` 한 줄로 재생되는 README 첫 예제
- [ ] 테스트 총량 증가 + 전 스위트 그린 + TSan 그린 + 커버리지 배지
- [ ] 소스에 내부 리뷰 ID 인용 0건, main에 `docs/briefs/` 부재
- [ ] Opus `REVIEW-round6-final.md` FINAL-VERDICT: APPROVE
