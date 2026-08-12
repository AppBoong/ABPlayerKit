# BRIEF: 라운드6 트랙 S 최종 게이트 (S-4) — Opus

당신은 라운드6 트랙 S의 **최종 리뷰 게이트**입니다. 이 worktree(브랜치 `round6/swiftui`)의 작업 트리 diff 전체를 리뷰하세요.

## 입력

1. `git status` / `git diff` — 리뷰 대상은 **미커밋 작업 트리 전체**
2. `docs/briefs/DESIGN-round6-swiftui.md` — 승인된 설계(사양)
3. `docs/briefs/RESULT-round6-swiftui.md` — 구현자의 자기 보고
4. `docs/briefs/ROADMAP-round6.md` §0, `REVIEW-round6-portfolio-audit.md` §C

## 집중 리뷰 항목 (ROADMAP §2 S-4: 소유권 모델의 SwiftUI identity 재생성 안전성)

1. **설계 §5의 시나리오 10개** 각각에 대해 실제 구현 코드가 그 결과를 보장하는지 코드 레벨로 추적 (특히 #6 identity 교체, #7 명시 소유 비해제, #8 dismantle 미호출, #10 body에서 @Observable 미독).
2. 불변식 I-1~I-4의 테스트가 실제로 그 불변식을 검증하는지(단언이 약하지 않은지).
3. `Coordinator` 연관 타입 변경(Void→클래스)과 `style:`/`configuration:` Optional 완화의 소스 호환 — 기존 테스트 파일 diff가 정말 0인지, 완화가 additive-only 정책에 부합하는지.
4. 구현자가 보고한 설계 이탈 1건(§3: 비-@ViewBuilder 헬퍼 함수 분리)의 타당성.
5. deinit `Task { @MainActor }` 홉의 Swift 6 안전성(기존 `ABPlayerControls.Coordinator.deinit` 선례와의 일관성, retain 사이클 부재).
6. 파일 경계: `ABPlayer.swift`/`ABAVPlaybackTarget.swift`/`ABPlayerControlsView.swift` diff 0 확인. 트랙 C가 Wave 2에서 수정할 파일과의 충돌 여부.
7. 주석 위생: 새 주석에 리뷰/설계 ID 인용 0건, 불변식 서술만.
8. README/CHANGELOG/DocC 정확성(예제가 실제 API와 일치하는지).

참고: 테스트 실제 실행은 로컬 시뮬레이터 부재로 불가(새 부팅 금지). 정적 리뷰로 판정하되, 실행 검증이 필요한 잔여 리스크는 문서에 명시하라 — 병합 후 PR CI가 실행을 담당한다.

## 산출물

`docs/briefs/REVIEW-round6-swiftui.md` — 발견 사항(심각도별), 시나리오 10개 추적 결과, 잔여 리스크. **마지막 줄은 반드시 `FINAL-VERDICT: APPROVE` 또는 `FINAL-VERDICT: REQUEST-CHANGES`** (REQUEST-CHANGES면 수정 요구 목록을 명확히).

## 제약

- **코드 수정 금지, 커밋 금지.** 산출물은 리뷰 문서 1개뿐.
- 리뷰 문서 작성 완료가 완료 신호입니다. 작성 후 추가 작업 없이 대기하세요.
