# BRIEF: 라운드6 트랙 CI — 리포 인프라 (Sonnet 구현)

당신은 라운드6 트랙 CI의 구현 담당입니다. 이 worktree(브랜치 `round6/ci`)에서 아래 4개 WP를 구현하세요. 설계 게이트는 없습니다(정형 작업).

## 입력

1. `docs/briefs/ROADMAP-round6.md` — §0 컨벤션, §2 트랙 CI
2. `docs/briefs/REVIEW-round6-portfolio-audit.md` — H-3, H-4, H-5
3. 기존 CI 워크플로(`.github/workflows/`), `CONTRIBUTING.md`, 테스트 타깃 구조(`Package.swift`, `Tests/`)

## 작업 항목

| WP | 내용 | 감사 ID |
|---|---|---|
| CI-1 | CI에 커버리지 요약 스텝(xccov) + README 커버리지 배지 | H-3 |
| CI-2 | ThreadSanitizer 잡 추가(코어+캐시 테스트 타깃) — **별도 job으로 분리**해 메인 잡 지연 방지 (ROADMAP §6) | H-3 |
| CI-3 | `.swiftlint.yml` + lint 스텝 — CONTRIBUTING이 열거한 컨벤션의 기계 강제. 기존 코드가 대량 위반하는 규칙은 disabled로 시작하고 파일에 사유 주석 | H-4 |
| CI-4 | `ABTestSupport` 테스트 지원 타깃 신설 — 3벌 복붙된 `ABWaitUntil` 통합 + busy-spin(`Task.yield()` 폴링) → `Task.sleep(5ms)` 폴링으로 교체. 모든 테스트 타깃이 이를 사용하도록 전환 | H-5 |

## 구현 규칙 (ROADMAP §0)

- Swift 6 **zero-warning** 유지.
- **새 시뮬레이터 부팅 금지**, **sleep 대기 금지**(`ABWaitUntil` 사용 — CI-4에서 통합하는 그것).
- **커밋 금지** — 커밋은 Haiku 담당. 작업 트리에 변경만 남겨두세요.
- 공개 API 추가는 additive-only. `ABTestSupport`는 테스트 전용 타깃이므로 라이브러리 제품에 포함 금지.
- 새 코드 주석에 리뷰 ID("H-5" 등) 인용 금지 — 불변식만 서술.
- CI 러너 느림 대응: suite timeLimit 3분·waitUntil 여유(라운드5 확립) 유지 — 줄이지 말 것.

## 검증

- `swift build` + `swift test`(macOS에서 가능한 타깃) 또는 기존 CI와 동일한 xcodebuild 인보케이션으로 로컬 검증. 이미 부팅된 시뮬레이터가 있으면 재사용, 없으면 macOS 타깃 검증까지만 하고 RESULT에 명시.
- TSan을 로컬로 1회 실행해 보고, **실패 발견 시 고치지 말고** RESULT 문서의 "타 트랙 전달 사항"에 재현 정보와 함께 기록 (트랙 A/E 브리프로 전달됨).

## 산출물

`docs/briefs/RESULT-round6-ci.md` 생성. 구조: WP별 변경 요약(파일 목록), 검증 결과(빌드/테스트/TSan), 미해결·이슈·타 트랙 전달 사항. **RESULT 파일 작성 완료가 곧 작업 완료 신호입니다. 완료 후 추가 작업 없이 대기하세요.**
