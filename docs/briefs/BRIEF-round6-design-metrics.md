# BRIEF: 라운드6 트랙 F 설계 게이트 (F-0) — Opus

당신은 라운드6 트랙 F(Metrics QoE)의 **설계 게이트**입니다. 코드를 수정하지 말고, 설계 문서만 산출하세요.

## 입력 (반드시 먼저 읽을 것)

1. `docs/briefs/DESIGN-round6-core.md` — **§3(확정 이벤트 표면)·§3.4(F 트랙 지침: 리버퍼 1차 소스는 `bufferingChanged` 쌍, `stallEnded`의 미종결 처리 책임, `.failureReported`의 domain/code)·§5.5(동결 인터페이스)는 확정 계약이다.** 트랙 A가 구현 중이므로 이 표면에 의존해 설계하되, 추가 요구는 "타 트랙 전달 사항"으로 기록만 할 것.
2. `docs/briefs/ROADMAP-round6.md` — §0, §3 트랙 F
3. `docs/briefs/REVIEW-round6-portfolio-audit.md` — §F (F-1~F-6)
4. 실소스: `Sources/ABPlayerKitMetrics/` 전체 — `ABMetricsRecorder.swift`, `ABPlaybackStatistics.swift`, JSONL 싱크. 데모 Metrics 탭(`Examples/`)도 참조(F-6w 대상).

## 결정해야 할 사항 (ROADMAP §3 F-0)

**이벤트 스키마 v2** 확정:
1. 리버퍼: 시작/종료/누적 duration·비율 — `bufferingChanged(true/false)` 쌍 기반(코어 §3.4), 미종결 세션(detach/release로 종료 신호가 안 오는 경우) 처리 방침.
2. watch time 누적기(`.periodicTime` 소비 — `periodicTimeInterval` 기본 nil인 점 처리 방침 포함)와 완료율(`.playedToEnd`).
3. 에러 이벤트: `.failureReported(ABPlayerFailure)` 매핑, domain/code 보존, isTerminal=false 제외 규칙.
4. `.hit`/waited 분포 분리(F-4) + accessLog 전체 이벤트 순회(스위치 횟수, dropped frames — F-5).
5. 벽시계 앵커: 세션 시작 시 1회 매핑(서버 로그 조인용).
6. **JSONL 하위호환**: 기존 필드/포맷 유지 방침, 신규 이벤트 타입 추가 방식, `flush()` 공개·핸들 유지·에러 카운터·로테이션(F-6).

각 결정에 F-1w~F-6w WP별 구현 지침과 테스트 전략을 붙일 것.

## 산출물

`docs/briefs/DESIGN-round6-metrics.md` — 결정별 선택안/기각안/실코드 근거, 이벤트 스키마 v2 전체 표(필드·타입·직렬화), WP별 구현 지침 + 테스트 전략, 무회귀 가드(기존 Metrics 테스트), 타 트랙 전달 사항.

## 제약

- **코드 수정 금지, 커밋 금지.** 산출물은 설계 문서 1개뿐.
- 공개 API additive-only. JSONL 소비자 하위호환 유지.
- 시뮬레이터 부팅·빌드 불필요(읽기 전용 분석).
- 설계 문서 작성 완료가 완료 신호입니다. 작성 후 추가 작업 없이 대기하세요.
