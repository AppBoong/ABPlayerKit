# BRIEF: 라운드6 트랙 A 구현 — 코어 엔진 신뢰성 + 관찰성 (Sonnet)

당신은 라운드6 트랙 A의 구현 담당입니다. 이 worktree(브랜치 `round6/core`)에서 승인된 설계를 구현하세요.

## 입력 (읽는 순서대로)

1. `docs/briefs/DESIGN-round6-core.md` — **승인된 설계. 이 문서가 유일한 사양이며 그대로 구현한다.** 결정 1~5, WP별 지침(§4), 불변식(§5.1), 수정 금지/허용 테스트 목록(§5.2·§5.3)까지 전부 구속력이 있다.
2. `docs/briefs/ROADMAP-round6.md` — §0 컨벤션, §2 트랙 A
3. `docs/briefs/REVIEW-round6-portfolio-audit.md` — §A, §B (감사 원문)

## 작업 순서

트랙 내 직렬: A-1w → A-2w → A-3w → A-4w → A-5w → A-6w → A-7w (설계 §4의 WP별 지침 그대로). 각 WP 완료 시 해당 테스트를 통과시킨 뒤 다음으로 진행.

## 파일 경계 (위반 시 게이트 REQUEST-CHANGES)

- 수정 허용: `Sources/ABPlayerKit/`, `Tests/ABPlayerKitTests/` (§5.3의 허용 목록 내에서)
- **수정 금지**: `Sources/ABPlayerKitControls|Cache|Metrics/`, `Tests/ABPlayerKitControlsTests/` 전체, §5.2의 테스트 파일 3종, `Tests/*/Support/ABWaitUntil.swift`(트랙 CI 소관), `Examples/`(데모 코드 — 컴파일이 깨지는 경우에만 최소 수정하고 RESULT에 보고)
- `ABPlayerEvent.swift`는 트랙 A 전용 — 설계 §3.2의 9개 케이스만 추가.

## 구현 규칙 (ROADMAP §0)

- Swift 6 **zero-warning**. 새 시뮬레이터 부팅 금지. sleep 대기 금지(`waitUntil` 사용).
- **커밋 금지** — 작업 트리 변경만 남길 것(커밋은 Haiku 담당).
- 공개 API·이벤트는 additive-only. deprecated 신규 부착 금지(설계 §0).
- 새 주석에 리뷰 ID("A-3", "B-2", "WP9.2", "I-1" 등) 인용 금지 — 불변식만 서술.
- 설계와 실코드가 충돌해 설계 변경이 불가피하면, 임의로 결정하지 말고 RESULT 문서 "게이트 문의" 섹션에 기록하고 설계 §5.5(인터페이스 동결)를 존중하는 보수적 선택을 할 것.

## 검증

- 기존 검증 경로(xcodebuild generic iOS 빌드, zero-warning)로 빌드 확인. 부팅된 시뮬레이터가 있으면 테스트 스위트 실행, 없으면 빌드 검증까지만 하고 RESULT에 명시.
- 설계 §5.2 수정 금지 테스트 파일이 diff에 없음을 확인. §5.3 외 기존 테스트 수정이 필요했다면 전부 RESULT에 사유와 함께 나열.

## 산출물

`docs/briefs/RESULT-round6-core.md` — WP별 변경 요약(파일 목록), 검증 결과, 설계 이탈/게이트 문의 사항, CHANGELOG 초안(마이그레이션 노트 4건 포함). **RESULT 파일 작성이 완료 신호입니다. 작성 후 추가 작업 없이 대기하세요.**
