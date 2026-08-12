# BRIEF: 라운드6 트랙 E 구현 — 캐시 무결성 (Sonnet)

당신은 라운드6 트랙 E의 구현 담당입니다. 이 worktree(브랜치 `round6/cache`)에서 승인된 설계를 구현하세요.

## 입력 (읽는 순서대로)

1. `docs/briefs/DESIGN-round6-cache.md` — **승인된 설계. 유일한 사양.** 결정 1~3, WP별 지침(§5), 무회귀 가드(§6), DocC 문서화(§7), 완료 정의(§8)까지 전부 구속력이 있다.
2. `docs/briefs/ROADMAP-round6.md` — §0 컨벤션, §2 트랙 E
3. `docs/briefs/REVIEW-round6-portfolio-audit.md` — §E

## 작업 순서

설계 §5의 권장 순서 준수: **E-2w → E-1w → E-3w → E-4w → E-5w** (핸들 수명을 먼저 고쳐야 E-1w의 truncate가 유지 핸들 위에서 한 번에 작성됨). 트랙 내 직렬.

## 파일 경계 (위반 시 게이트 REQUEST-CHANGES)

- 수정 허용: `Sources/ABPlayerKitCache/`, `Tests/ABPlayerKitCacheTests/`
- **수정 금지**: 다른 모든 타깃, `Tests/*/Support/ABWaitUntil.swift`(트랙 CI 소관), `Examples/`, `ABCacheProgressWaiter` 및 설계 §6 표의 불변식 코드.
- 설계 §6의 "무수정 통과 강제" 기존 테스트 목록을 지킬 것 — 픽스처 shim(§5 E-4w의 fake 변환) 외에 어서션을 고쳐야 한다면 회귀 신호이므로 중단하고 RESULT "게이트 문의"에 기록.

## 구현 규칙 (ROADMAP §0)

- Swift 6 zero-warning. 새 시뮬레이터 부팅 금지. sleep 대기 금지(`waitUntil`).
- **커밋 금지** — 작업 트리 변경만.
- 공개 API 변경 0건이 설계 목표(§8) — diff에 신규 `public` 심볼이 없어야 한다.
- 새 주석에 리뷰 ID 인용 금지 — 불변식만 서술(설계 §6 말미의 규율 참조).

## 검증

- xcodebuild generic iOS 빌드 zero-warning 확인. 부팅된 시뮬레이터가 있으면 캐시 테스트 스위트 실행, 없으면 빌드 검증까지만 하고 RESULT에 명시.
- 설계 §8 체크리스트를 RESULT에 항목별 체크 상태로 옮겨 적을 것.

## 산출물

`docs/briefs/RESULT-round6-cache.md` — WP별 변경 요약, 검증 결과, §8 체크리스트, 게이트 문의 사항, CHANGELOG 초안(Fixed 2건 + Migration 1줄). **RESULT 파일 작성이 완료 신호입니다. 작성 후 추가 작업 없이 대기하세요.**
