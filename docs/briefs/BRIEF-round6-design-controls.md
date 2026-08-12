# BRIEF: 라운드6 트랙 C 설계 게이트 (C-0) — Opus

당신은 라운드6 트랙 C(Controls UX — 제품 목표 3·4번)의 **설계 게이트**입니다. 코드를 수정하지 말고, 설계 문서만 산출하세요.

## 입력 (반드시 먼저 읽을 것)

1. `docs/briefs/DESIGN-round6-core.md` — **§3(확정 이벤트 표면)·§3.5(C 트랙 지침)·§5.5(동결 인터페이스)는 확정 계약이다.** 트랙 A가 구현 중이므로 이 표면에 의존해 설계하되, 추가 요구가 생기면 "타 트랙 전달 사항"으로 기록만 할 것.
2. `docs/briefs/DESIGN-round6-swiftui.md` — §9-3의 C 트랙 전달 사항(D-10 Sendable화 시 EnvironmentKey 단순화, `ABPlayerControlsView.style/configuration` 비옵셔널 유지 요청).
3. `docs/briefs/ROADMAP-round6.md` — §0, §3 트랙 C
4. `docs/briefs/REVIEW-round6-portfolio-audit.md` — §D (D-1~D-11)
5. 실소스: `Sources/ABPlayerKitControls/` 전체 — 특히 `ABPlayerControlsView.swift`(hitTest, 슬롯), `ABControlsPresenter.swift`(미러, skip), `ABPlayerControlsStyle.swift`, `ABTimeFormatter.swift`. 감사 위치를 직접 확인할 것.

## 결정해야 할 사항 (ROADMAP §3 C-0)

1. **버퍼링 시각 상태**: 스피너 vs 아이콘 유지+오버레이 — `bufferingChanged`/`isBuffering` 소비 방식, 아이콘 역전(D-2) 해소 축(`isPlaying && isBuffering` 조합, core 설계 §3.5), 스톨 중 auto-hide 정책.
2. **더블탭 시크 UX** (D-4): 좌우 영역 분할, 연속 탭 누적 표시(코어 `pendingSeekTime`/`seekTargetChanged` 소비 — Controls 자체 누적기 금지), Reduce Motion 대응, 햅틱.
3. **passthrough 터치 옵션 형태** (D-4): hitTest 우선순위와의 상호작용 포함.
4. **레이아웃 슬롯 API** (D-7): `.topTrailing`/`.bottomTrailing`/`.transportTrailing` — accessoryStack 하위호환, `showsPlayPauseButton`/`showsSeekBar`.
5. C-1w~C-7w 각 WP의 구현 방향 요약(D-1 잔여, D-5 리플레이, D-6 로케일, D-8 스타일 diff 단일화, D-9 프리젠터 미러 제거 — observable 소비로 대체, D-10 Style Sendable화, D-11 하드코딩 문자열).

## 산출물

`docs/briefs/DESIGN-round6-controls.md` — 결정별 선택안/기각안/실코드 근거, 확정 API 시그니처(슬롯·옵션·스타일 변경), WP별 구현 지침 + 테스트 전략, 무회귀 가드(기존 184개 Controls 테스트 + hitTest 우선순위), 타 트랙 전달 사항.

## 제약

- **코드 수정 금지, 커밋 금지.** 산출물은 설계 문서 1개뿐.
- 공개 API·이벤트 additive-only. deprecated 신규 부착 금지.
- 시뮬레이터 부팅·빌드 불필요(읽기 전용 분석).
- 설계 문서 작성 완료가 완료 신호입니다. 작성 후 추가 작업 없이 대기하세요.
