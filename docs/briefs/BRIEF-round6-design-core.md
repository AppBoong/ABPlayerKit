# BRIEF: 라운드6 트랙 A 설계 게이트 (A-0) — Opus

당신은 라운드6 트랙 A(코어 엔진 신뢰성 + 관찰성)의 **설계 게이트**입니다. 코드를 수정하지 말고, 설계 문서만 산출하세요.

## 입력 (반드시 먼저 읽을 것)

1. `docs/briefs/ROADMAP-round6.md` — §0 컨벤션, §2 트랙 A, §6 리스크
2. `docs/briefs/REVIEW-round6-portfolio-audit.md` — 섹션 A(A-1~A-8), B(B-1~B-8), "강점" 목록
3. 실제 소스: `Sources/ABPlayerKit/` 전체 — 특히 `ABPlayer.swift`, `ABAVPlaybackTarget.swift`, `ABPlayerEvent.swift`, `ABPlayerError.swift`, `ABSeekCoalescer.swift`, 관찰 레지스트리. 감사 항목의 위치(파일:라인)를 직접 확인하고 설계 근거를 실코드에 기반할 것.
4. `docs/POLICY-api-stability.md` (존재 시) — additive-only 계약 확인.

## 결정해야 할 사항 (ROADMAP §2 트랙 A-0의 5개 항목)

1. **에러 모델**: `ABPlayerError`에 `(domain, code)` 캐리 방식 — 연관값 추가는 breaking이므로 새 케이스 or 구조체 페이로드 병행안 중 결정하고 근거 제시 (B-3). Sendable 유지 필수.
2. **관찰성**: `isPlaying`/`duration`/`isBuffering`의 @Observable 저장 프로퍼티 전환 설계 — target 이벤트로 미러 갱신 흐름, KVO 소스(`isPlaybackLikelyToKeepUp`, `isPlaybackBufferEmpty`, `reasonForWaitingToPlay` 등) 선정 (B-1, B-2). 기존 @Observable 매크로와의 상호작용 함정(과거 WP9.2류) 검토 포함.
3. **신규 이벤트 표면 확정**: `bufferingChanged(Bool)`, `durationAvailable(CMTime)`, `stallEnded`, `itemAttached`, `presentationSizeChanged(CGSize)`, `.playbackRejected` 페이로드 보강 방식 (B-4, B-5). **정확한 케이스 이름·연관값 타입·방송 시점·스레딩을 확정할 것 — 이 문서가 Wave 2 C/F 설계의 입력이 된다.**
4. **시크 통일**: 4개 진입점(코얼레서 밖 `scrub(to:)`, `seekToStart` 경로, 공개 `seek(to:)`, 스크럽 세션)을 코얼레서+세대 가드로 수렴하는 구조 + **skip 누적 시맨틱**(pending delta 합산 — D-1의 코어 절반) (A-7). 기존 스크럽/코얼레서 테스트 무회귀를 설계 제약으로 명시.
5. **`ABPlayer` 분해 범위**: 이번 라운드는 `BackgroundPolicyMachine`/`AudioSessionGate` 순수 리듀서 추출까지만(기존 `ABGradePlanner` 스타일). 전면 재설계 금지.

추가로 A-1~A-8 각 버그의 수정 방향을 WP(A-1w~A-7w) 단위로 요약하세요(구현 브리프가 그대로 인용 가능한 수준).

## 산출물

`docs/briefs/DESIGN-round6-core.md` 생성. 구조:

- 결정 1~5 각각: 선택안, 기각안과 기각 사유, 실코드 근거(파일:라인)
- 확정 이벤트 표면: 케이스 시그니처 전체 목록 (Wave 2 소비용 — 명확한 표)
- WP별(A-1w~A-7w) 구현 지침 요약 + 테스트 전략
- 리스크와 무회귀 가드 (기존 175개 코어 테스트 관련)

## 제약

- **코드 수정 금지, 커밋 금지.** 산출물은 위 설계 문서 1개뿐.
- 이벤트/공개 API 추가는 additive-only (non-exhaustive 계약 하에 케이스 추가만).
- 시뮬레이터 부팅 금지, 빌드/테스트 실행은 불필요(읽기 전용 분석).
- 설계 문서 작성 완료가 곧 작업 완료 신호입니다. 완료 후 추가 작업 없이 대기하세요.
