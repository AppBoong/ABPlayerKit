# BRIEF: 라운드6 트랙 A 최종 게이트 (A-8) — Opus

당신은 라운드6 트랙 A의 **최종 리뷰 게이트**입니다. 이 worktree(브랜치 `round6/core`)의 작업 트리 diff 전체를 리뷰하세요.

## 입력

1. `git status` / `git diff` — 리뷰 대상은 **미커밋 작업 트리 전체** (diff가 큼 — 파일 단위로 나눠 읽을 것)
2. `docs/briefs/DESIGN-round6-core.md` — 승인된 설계(사양)
3. `docs/briefs/RESULT-round6-core.md` — 구현자의 자기 보고 (§2 게이트 문의 3건 포함)
4. `docs/briefs/ROADMAP-round6.md` §0·§6, `REVIEW-round6-portfolio-audit.md` §A·§B

## 집중 리뷰 항목 (ROADMAP §2 A-8)

1. **A-5w 스크럽 회귀**: `enqueueSeek` 통일이 기존 스크럽/코얼레서 경로의 동작을 보존하는지 코드 추적. 수정 금지 파일 4종(`ABSeekCoalescer.swift`, `ABSeekCoalescerTests`, `ABScrubbingEngineTests`, `ABPeriodicTimeEngineTests`)의 diff 0 확인. `endScrubbing` standalone commit의 세대 가드가 기존 구조를 훼손하지 않는지.
2. **A-6w @Observable 상호작용**: 미러 3종+`pendingSeekTime`의 값-비교-후-대입이 빠짐없이 적용됐는지(동일값 재대입 → SwiftUI 무효화 폭풍 방지), `@ObservationIgnored`가 설계 §0 규칙대로 정확히 적용됐는지(신규 내부 상태는 붙이고, 관찰 대상엔 안 붙이고, deinit 접근 프로퍼티는 유지).
3. **설계 §5.1 불변식 I-1~I-8** 각각 코드 레벨 검증.
4. **RESULT §2 게이트 문의 3건에 대한 판정** (리뷰 문서에 각각 명시적 결론을 낼 것):
   - `.tuningApplied` 미해상 값 유지 (채택안) vs 해상값 방송
   - `ABBackgroundPolicyMachine` 액션 세분화 수준(조건부 로직을 해석 함수에 남긴 절충)
   - 신호-전용 KVO 4종의 stale-item 가드 생략(I-7의 좁은 해석)
5. 이벤트 표면이 설계 §3.2와 정확히 일치하는지(케이스 9개, 시그니처·방송 시점·중복 억제) — **Wave 2 설계가 이미 이 표면에 의존해 작성됐으므로 불일치는 REQUEST-CHANGES 사유.**
6. 에러 라우팅: `isTerminal` 분류, origin 채집 5개 지점, `.failed`→`.failureReported` 순서.
7. §5.3 허용 목록 밖 테스트 수정(RESULT §3에 열거된 4건)의 타당성.
8. 주석 위생: 새 주석에 리뷰/설계 ID 인용 0건.
9. CHANGELOG 초안(마이그레이션 노트 8건)의 정확성.

참고: 테스트 실제 실행은 로컬 시뮬레이터 부재로 불가(새 부팅 금지). 정적 리뷰로 판정하되 실행 검증 필요 잔여 리스크는 명시 — 병합 후 PR CI가 실행을 담당한다.

## 산출물

`docs/briefs/REVIEW-round6-core.md` — 발견 사항(심각도별), 불변식 검증 결과, 게이트 문의 3건 판정, 잔여 리스크. **마지막 줄은 반드시 `FINAL-VERDICT: APPROVE` 또는 `FINAL-VERDICT: REQUEST-CHANGES`**.

## 제약

- **코드 수정 금지, 커밋 금지.** 산출물은 리뷰 문서 1개뿐.
- 리뷰 문서 작성 완료가 완료 신호입니다. 작성 후 추가 작업 없이 대기하세요.
