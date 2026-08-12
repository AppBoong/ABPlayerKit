# BRIEF: 라운드6 트랙 S 설계 게이트 (S-0) — Opus

당신은 라운드6 트랙 S(SwiftUI 간편 API — 제품 목표 1번)의 **설계 게이트**입니다. 코드를 수정하지 말고, 설계 문서만 산출하세요.

## 입력 (반드시 먼저 읽을 것)

1. `docs/briefs/ROADMAP-round6.md` — §0 컨벤션, §2 트랙 S, §6 리스크
2. `docs/briefs/REVIEW-round6-portfolio-audit.md` — 섹션 C(C-1~C-3)
3. 실제 소스: 현재 SwiftUI 표면(`ABVideoPlayer` 등 SwiftUI 래퍼 파일), `ABPlayer.swift`의 생명주기 API(attach/release), `ABPlayerControlsView.swift`의 style/configuration 주입 방식, README Quick Start. `ABMediaSource.swift`의 확장자 추론(`:24`) 확인.

## 결정해야 할 사항 (ROADMAP §2 트랙 S-0)

1. **URL 편의 API의 소유권 모델** (C-1): 내부 `@State` ABPlayer 자동 생성 + `onDisappear` 자동 release **vs** 명시 소유 유지 중 결정. **SwiftUI 뷰 identity 재생성(구조 변경, url 변경) 시 플레이어 생명주기 안전성**을 핵심 기준으로 — 재생성 시 이중 release/누수/재생 끊김 시나리오를 각각 분석할 것.
2. **autoplay 기본값**: `ABVideoPlayer(url:gravity:autoplay:)` / `ABVideoPlayerWithControls(url:...)` 시그니처 확정.
3. **modifier API의 Environment 전파 범위** (C-2): `.playerControlsStyle(_:)` / `.playerControlsConfiguration(_:)` EnvironmentKey 설계 — 기존 이니셜라이저 주입과의 우선순위 규칙(둘 다 지정 시), 전파 범위.
4. **README Quick Start 개편안** (C-3): 첫 예제 URL 원라이너, grade 시스템 "고급" 강등, `kind:` 제거 — 새 Quick Start 초안 포함.

전부 **deprecated 없이 additive로만**.

## 파일 경계 제약 (위반 시 게이트 REQUEST-CHANGES)

- **`ABPlayer.swift` / `ABAVPlaybackTarget.swift` / `ABPlayerControlsView.swift` 수정 금지** (트랙 A·C와의 충돌 차단). 설계상 이 파일들의 변경이 필요하다고 판단되면, 변경 요구사항을 설계 문서의 "타 트랙 전달 사항" 섹션에 기록할 것(직접 수정 지시 금지).
- 신규 파일 + 기존 SwiftUI 래퍼 파일 수정만 허용.

## 산출물

`docs/briefs/DESIGN-round6-swiftui.md` 생성. 구조:

- 결정 1~4 각각: 선택안, 기각안과 기각 사유, 실코드 근거(파일:라인)
- 확정 API 시그니처 전체(생성자·modifier·EnvironmentKey)
- identity 재생성 시나리오 분석(안전성 논증)
- WP별(S-1w~S-3w) 구현 지침 요약 + 테스트 전략
- (필요 시) 타 트랙 전달 사항

## 제약

- **코드 수정 금지, 커밋 금지.** 산출물은 위 설계 문서 1개뿐.
- 시뮬레이터 부팅 금지, 빌드/테스트 실행 불필요(읽기 전용 분석).
- 설계 문서 작성 완료가 곧 작업 완료 신호입니다. 완료 후 추가 작업 없이 대기하세요.
