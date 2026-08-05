# HANDOFF: 라운드5 트랙 2 (캐시 sparse range) — 다음 세션 인수인계

작성일 2026-08-05. v0.3.0 릴리스 직후 시점의 상태 스냅샷과, 트랙 2를 이어서 진행하기 위한 전체 컨텍스트.

## 1. 현재 상태 (이 문서 작성 시점)

- **릴리스**: v0.3.0 태그 + GitHub Release 발행 완료 (CI 그린 커밋 `52f18e8`). https://github.com/AppBoong/ABPlayerKit/releases/tag/v0.3.0
- **테스트**: 406개 / 4개 번들 / zero-warning. CI에 커버리지·xcresult 아티팩트 활성.
- **리뷰 이력**: 라운드3(4관점 리뷰 → Phase1~4 → APPROVE), 라운드4(Controls 분해 + @ViewBuilder accessories → REQUEST-CHANGES → 수정 → APPROVE). 기록은 `docs/briefs/REVIEW-*.md`.
- **로드맵**: `docs/briefs/ROADMAP-round5.md` — 트랙 1(릴리스)은 완료, **트랙 2(sparse range)가 유일한 미착수 대형 작업**.

## 2. 트랙 2가 해결하는 문제 (왜 하는가)

현재 캐시(`ABPlayerKitCache`)는 **선형 prefix 모델**: 파일 앞에서부터 연속 구간 하나만 저장한다. 라운드4에서 원거리 요청에 passthrough 폴백(기본 2MB gap 임계, 1MB 청킹)을 넣어 "무한 대기/메모리 스파이크" 버그 범주는 해소했지만, passthrough로 흐른 바이트는 **캐시에 저장되지 않는다**. 남은 문제는 전부 "비효율" 범주:

1. **비-faststart MP4 반복 다운로드** — moov가 파일 끝에 있으면 AVFoundation이 재생 전 파일 끝을 읽는다 → 매 재생마다 끝부분 재다운로드. "한 번 본 영상은 즉시 재생"이라는 캐시 약속이 이 파일 유형에선 반쪽.
2. **시크 후 구간 유실** — 중간으로 시크해 본 구간도 저장 안 됨 → 시크 잦은 패턴(강의 영상)에서 적중률 반감.
3. **셀룰러 데이터 중복 수신** — 위 두 경우 모두 이미 받은 바이트를 재수신.

**영향 없는 것**: HLS(프리페처 경로), faststart MP4(moov 앞 — 배포용 인코딩 대부분). 크래시/행 아님. 제약은 DocC/README에 문서화돼 있어 "선언된 제약" 상태.

**포트폴리오 방어 논리**(트랙 2 착수 전 면접 대비): "구간 맵 자료구조·인덱스 마이그레이션·동시성 재검증이 필요한 고리스크 작업이라 v0.4.0으로 분리했고 설계 로드맵(`ROADMAP-round5.md` 트랙 2)이 이미 있다."

## 3. 실행 계획 (ROADMAP-round5.md 트랙 2 요약)

| # | 작업 | 핵심 결정/리스크 |
|---|---|---|
| 2-0 | **설계 게이트 (Opus)** — 최초 착수 지점 | 구간 맵(구간 리스트 vs 블록 비트맵), 디스크 포맷(sparse file `FileHandle.seek` vs 블록 파일), **기존 캐시 무손실 마이그레이션**(prefix 엔트리 → `[(0,size)]` 승격), 동시 fill 상한·병합 규칙 |
| 2-1 | 인덱스 v2 | 손상/구버전 복구 테스트 필수 |
| 2-2 | sparse 쓰기 | 라운드4 N8 테스트가 고정한 1MB 청크 계약 유지 |
| 2-3 | 읽기 | 구간 조합 + 미커버만 네트워크. passthrough 결과를 구간으로 저장 승격 |
| 2-4 | 동시성/축출 | **최고 리스크** — 라운드3~4의 취소(`waitForProgress`/`readerRegistry`)·HEAD coalescing 불변식을 깨기 쉬움. 기존 캐시 테스트 109+개가 안전망 |
| 2-5 | 검증 | 핵심 시나리오: 비-faststart MP4 **두 번째 재생 네트워크 0바이트**, 동시 load+seek 폭풍 |
| 2-6 | **최종 게이트 (Opus)** | APPROVE 후 v0.4.0 릴리스(트랙 1 절차 재사용) |

## 4. 작업 파이프라인 컨벤션 (이 레포에서 확립된 방식)

- **모델 역할**: 설계/리뷰 게이트=Opus(`claude --model opus`), 구현=Sonnet(`claude --model claude-sonnet-5`, Codex 리밋 복구 시 사용자에게 Codex 복귀 확인), 커밋=Haiku(`claude --model haiku`). 전부 **Orca 터미널 탭**으로 디스패치(`orca terminal create --worktree active --command ...`) — 사용자가 실시간 확인 가능해야 함.
- **완료 감지**: TUI 문자열 폴링은 놓친 전례 있음 — **산출물 파일 생성 감지**(에이전트에게 `docs/briefs/RESULT-*.md` 저장 지시) 또는 git 상태 폴링이 신뢰됨.
- **구현 규칙**(브리프마다 명시): Swift 6 zero-warning, **새 시뮬레이터 부팅 금지**(부팅된 것만, 현재 iPhone Air `65CDD0F3-...`), sleep 대기 금지(각 테스트 타깃의 `Support/ABWaitUntil.swift` 사용), 커밋 금지(Haiku 담당), 커밋은 Conventional Commits 영어 + `Co-Authored-By: Claude` 트레일러, push는 사용자 지시 시.
- **게이트 규칙**: 코드 수정 라운드 후 Opus가 `docs/briefs/REVIEW-*.md`에 전문 저장 + 마지막 줄 `FINAL-VERDICT: APPROVE|REQUEST-CHANGES`.
- **CI 주의**: GitHub macOS 러너는 심하게 느릴 수 있음 — suite timeLimit은 3분(1분에서 상향, `52f18e8` 직전 커밋 참조), waitUntil 데드라인도 여유 있게.

## 5. 트랙 2 외 잔여 소항목

- **SPI 등록** — SwiftPackageIndex/PackageList 레포에 PR (외부 레포라 사용자 승인 후)
- **Metrics 화면 스크린샷** — 데모에서 TTFF 샘플 축적 후 README 갤러리에 추가
- **재판정 잔여 참고** — `REVIEW-round4-reverdict.md`의 Minor 참고사항 훑기 (낮은 우선순위)

## 6. 다음 세션 시작 명령 (그대로 실행 가능)

1. Opus 터미널 생성 → 2-0 설계 게이트 브리프 전달: "docs/briefs/HANDOFF-round5-track2.md 와 ROADMAP-round5.md 트랙 2를 읽고, 2-0의 4개 결정사항을 근거와 함께 확정해 docs/briefs/DESIGN-sparse-cache.md 로 저장하라. 코드 수정 금지."
2. 설계 승인 후 Sonnet 구현(2-1~2-5, WP당 전체 테스트), Haiku 커밋, Opus 최종 게이트(2-6).
3. APPROVE 시 v0.4.0 릴리스는 트랙 1 절차(CHANGELOG 확정 → CI 그린 → 태그 → gh Release, AppBoong 계정 스위칭) 재사용.
