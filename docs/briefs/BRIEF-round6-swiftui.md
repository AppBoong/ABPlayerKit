# BRIEF: 라운드6 트랙 S 구현 — SwiftUI 간편 API (Sonnet)

당신은 라운드6 트랙 S의 구현 담당입니다. 이 worktree(브랜치 `round6/swiftui`)에서 승인된 설계를 구현하세요.

## 입력 (읽는 순서대로)

1. `docs/briefs/DESIGN-round6-swiftui.md` — **승인된 설계. 유일한 사양.** 확정 API 시그니처(§3), 구현 함정(§4.3), identity 시나리오(§5), README 초안(§6.2), WP 지침(§7), 테스트 전략(§8), 완료 정의(§10)까지 전부 구속력이 있다.
2. `docs/briefs/ROADMAP-round6.md` — §0 컨벤션, §2 트랙 S
3. `docs/briefs/REVIEW-round6-portfolio-audit.md` — §C

## 작업 순서

S-1w(편의 생성자 + 소유 박스) → S-2w(Environment modifier) → S-3w(README/DocC/CHANGELOG). 설계 §7 지침 그대로.

## 파일 경계 (위반 시 게이트 REQUEST-CHANGES)

- **`ABPlayer.swift` / `ABAVPlaybackTarget.swift` / `ABPlayerControlsView.swift` — diff 0줄** (설계 §10 첫 항목, 절대 조건).
- 수정 허용: `Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift`, `Sources/ABPlayerKitControls/SwiftUI/` 하위, 신규 파일, README 2종, DocC 카탈로그, CHANGELOG, 테스트(§8 목록).
- `Tests/*/Support/ABWaitUntil.swift` 수정 금지(트랙 CI 소관).
- 기존 Controls 테스트 184개는 **무수정 통과**해야 한다(§8-18). 고쳐야 한다면 설계 위반 신호 — 중단하고 RESULT "게이트 문의"에 기록.

## 구현 규칙 (ROADMAP §0)

- Swift 6 zero-warning. 새 시뮬레이터 부팅 금지. sleep 대기 금지(`waitUntil`).
- **커밋 금지** — 작업 트리 변경만.
- additive-only. 신규 코드에 `onAppear`/`onDisappear`/`task` 0건(설계 §10).
- 새 주석에 리뷰 ID·설계 불변식 ID("C-1", "I-3" 등) 인용 금지 — 불변식 내용만 서술.
- §3.2의 deinit MainActor 홉이 Swift 6에서 거부되면 설계가 정한 폴백(dismantle/ABPlayer.deinit 의존)을 택하고 어느 쪽인지 RESULT에 명시.

## 검증

- xcodebuild generic iOS 빌드 zero-warning + DocC(`DOCC_WARNINGS_AS_ERRORS=YES`) 확인. 부팅된 시뮬레이터가 있으면 테스트 실행, 없으면 빌드 검증까지만 하고 RESULT에 명시.
- 설계 §10 체크리스트를 RESULT에 항목별 체크 상태로 옮겨 적을 것.

## 산출물

`docs/briefs/RESULT-round6-swiftui.md` — WP별 변경 요약, 검증 결과, §10 체크리스트, deinit 홉 채택 여부, 게이트 문의 사항. **RESULT 파일 작성이 완료 신호입니다. 작성 후 추가 작업 없이 대기하세요.**
