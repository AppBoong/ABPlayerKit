# BRIEF: 라운드6 트랙 E 최종 게이트 (E-6) — Opus

당신은 라운드6 트랙 E의 **최종 리뷰 게이트**입니다. 이 worktree(브랜치 `round6/cache`)의 작업 트리 diff 전체를 리뷰하세요.

## 입력

1. `git status` / `git diff` — 리뷰 대상은 **미커밋 작업 트리 전체**
2. `docs/briefs/DESIGN-round6-cache.md` — 승인된 설계(사양)
3. `docs/briefs/RESULT-round6-cache.md` — 구현자의 자기 보고
4. `docs/briefs/ROADMAP-round6.md` §0·§6, `REVIEW-round6-portfolio-audit.md` §E

## 집중 리뷰 항목 (ROADMAP §2 E-6: 기존 취소/coalescing 불변식 무회귀 중심)

1. **설계 §6 무회귀 가드 표의 불변식 9개** 각각 코드 레벨 검증 — 특히: `ABCacheProgressWaiter` 무수정, fill GET 코얼레싱의 동기 구간에 suspension point 미추가, `resolvedMetadata` 4단계 순서(claimPending 동기 → 빠른 경로 → pending 합류 → holder 설치가 첫 suspension 이전), holder 식별자 정리 로직 무수정, reader 등록 해제 defer 범위.
2. **E-1w 재개 검증 분기 4종**의 정확성: 200 폴백 truncate-and-continue(같은 스트림 소비), 206 불일치 시 `FillSuperseded`로 원 task 조용히 종료 + `launchFill(offset:0)` 재시작 — 이 재시작 경로가 `fills[key]` 교체 시 waiter/취소 시맨틱을 깨지 않는지 집중 검토.
3. **E-3w 세대 카운터**: `purgeGeneration` 증가 위치(waiter 재개 전), passthrough 강등 분기가 `fillErrors` 검사보다 앞, 기존 에러 경로 바이트 보존.
4. **E-4w boundedData**: 스트림 조기 종료 → `onTermination` 취소 경로, 8MB 상한, 픽스처 shim이 기존 어서션을 실제로 무수정 유지하는지 diff로 확인.
5. **E-5w 추출**: `ABLoadingRequestServicer`가 기존 델리게이트 본문과 동작 동일(순수 추출)인지, `beginAssetSession` 동기 호출 위치(스폰 Task 밖).
6. `fillHandles` 불변식: `fillResponses`와의 동치, 해제 4곳 일원화, eviction 제외 집합에 미개입.
7. 공개 API diff 0건 재확인. 주석 위생(리뷰 ID 인용 0건). CHANGELOG/DocC 정확성.

참고: 테스트 실제 실행은 로컬 시뮬레이터 부재로 불가(새 부팅 금지). 정적 리뷰로 판정하되 실행 검증 필요 잔여 리스크는 명시 — 병합 후 PR CI가 실행을 담당한다(TSan 포함).

## 산출물

`docs/briefs/REVIEW-round6-cache.md` — 발견 사항(심각도별), 불변식 9개 검증 결과, 잔여 리스크. **마지막 줄은 반드시 `FINAL-VERDICT: APPROVE` 또는 `FINAL-VERDICT: REQUEST-CHANGES`**.

## 제약

- **코드 수정 금지, 커밋 금지.** 산출물은 리뷰 문서 1개뿐.
- 리뷰 문서 작성 완료가 완료 신호입니다. 작성 후 추가 작업 없이 대기하세요.
