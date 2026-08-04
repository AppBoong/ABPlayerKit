# BRIEF: 리뷰 라운드3 Phase 3 — Opus 리뷰 반영 (REQUEST-CHANGES 해소)

`docs/briefs/REVIEW-round3-phase1-2.md` 를 **먼저 정독**하라. 그 리뷰의 지적을 아래 우선순위로 수정한다. 각 그룹 완료 시 빌드+전체 테스트 통과 필수. **커밋 금지.**

## 공통 규칙
Swift 6, zero-warning. 새 시뮬레이터 부팅 금지(부팅된 것만 사용). sleep 대기 금지. public API 파괴 변경 금지.

## 그룹 A — 오디오 세션 소유권 재설계 (C1, C2, M1, M2, M4 일괄 해소)
리뷰 권고대로 개별 패치가 아니라 소유권 재설계로 푼다:
1. 프로세스 단위 공유 owner(`@MainActor` 싱글턴, 예: `ABAudioSessionCoordinator`, internal)를 도입 — 정책 적용을 요청한 ABPlayer 인스턴스를 refcount(또는 토큰 집합)로 추적.
2. 최초 참여자 진입 시에만 스냅샷 저장, 마지막 참여자 이탈 시에만 복원 — 다중 플레이어 상호 오염(C1) 차단.
3. 복원 시 무조건 deactivate 금지(C2): 실제로 이 라이브러리가 activate한 경우에만, notifyOthersOnDeactivation 옵션 포함해 상태 추적 기반으로 복원.
4. 인터럽션 후 재활성화(M1): 재생 재개 경로에서 세션이 비활성이면 재활성화. (Phase 4 WP10과 겹치면 여기서는 최소한 play/grade 승격 시 재활성화 보장만.)
5. 부분 실패 시 스냅샷 폐기 금지(M2): 실패해도 복원 가능 상태 유지, 에러는 기존 audioSessionOperationFailed 경로로 통지.
6. `ABPlayer.deinit`에서도 coordinator 참여 해제가 일어나게(M4) — deinit은 nonisolated이므로 coordinator에 스레드 세이프 해제 경로(락 보호) 필요.
7. 기존 `ABAudioSessionPolicyTests` 8개를 새 설계에 맞게 재작성 + 다중 플레이어 시나리오 테스트 추가(플레이어 2개 정책 적용 → 하나 해제 → 세션 유지, 둘 다 해제 → 복원).

## 그룹 B — deinit 스레드 안전 (M3)
`ABAVPlaybackTarget.deinit`의 `removeTimeObserver`가 메인 밖에서 불릴 수 있음 → `DispatchQueue.main.async`(이미 main이면 즉시)로 보내거나 애플 문서상 안전한 방식으로 수정. 테스트가 있으면 유지.

## 그룹 C — 캐시 HEAD 중복 (M5)
동시 `load`에서 메타데이터 HEAD 요청이 중복 발행되는 문제 — in-flight HEAD를 키별로 공유(coalesce)하고, 이를 우회하던 신규 테스트를 실제 단언(HEAD 1회)으로 강화.

## 그룹 D — 공허한 동시성 테스트 실질화 (m2, m3)
1. m2: `ReadyWaitState` 테스트의 `#expect(outcome != nil)` 류 공허 단언을 실제 결과 값 단언으로 교체 — 경합 시 "정확히 하나의 outcome, 값은 승자에 따라 ready/timedOut/cancelled 중 하나이며 이중 resume 없음"을 검증.
2. m3: `cancellationBeforeInstallStillResolvesOnce`를 순차 실행이 아닌 실제 인터리빙(취소를 install 이전에 확정적으로 선행시키는 결정론적 순서 제어)으로 재작성.

## 그룹 E — 빠른 정리 (m4~m8, m11, m12)
- m4: Phase 2 신규 파일에 남은 구식 폴링 패턴을 ABWaitUntil로 치환
- m5: `.timeLimit`을 전체 suite에 일괄 적용 (Phase 2 신규 suite 포함)
- m6: WP8.2 미완 치환 완료
- m7: `ABWaitUntil.swift` 3벌 복붙 — 각 파일 상단에 "공용 타깃 부재로 의도적 복제" 주석 1줄 추가로 처리(별도 타깃 신설은 스코프 밖)
- m8: 중복 `#expect` 제거
- m11: `displayCapped`를 `ABPlaybackTuning()` 기본 init 위임으로 정의해 중복 제거
- m12: `ABCacheStore` teardown deinit 추가(파일 핸들 등 정리할 것이 있으면)
- m9, m10: 문서 주석/코멘트 오기 수정

## 완료 보고
그룹별 변경 요약 + 전체 테스트 결과. 리뷰 항목 번호(C1~m12)별 처리 여부 표로 정리 후 대기.
