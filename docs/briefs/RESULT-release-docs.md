# RESULT: 릴리스 문서 정리 (ROADMAP-round5 트랙 1, 1-1~1-3)

- **범위**: `CHANGELOG.md`, `README.md`, `README.ko.md`, `docs/POLICY-api-stability.md`, `.github/ISSUE_TEMPLATE/bug_report.yml`
- **커밋**: 하지 않음 (지시에 따라 워킹 디렉토리에만 존재)
- **제외**: 1-4 태깅/릴리스는 손대지 않음

## 1-1 — CHANGELOG 버전 확정 및 재분류

- `[Unreleased]`를 `[0.3.0] - 2026-08-05`로 스탬프하고, 빈 `[Unreleased]` 헤더를 그 위에 남겨 다음 라운드(캐시 sparse range)가 곧바로 채울 수 있게 했다.
- 기존 항목을 Keep a Changelog 순서(Added → Changed → Deprecated → Fixed)로 재배열했다(기존 순서는 Added → Deprecated → Changed → Fixed).
- **소비자 관점 언어 정리**: `Q6-A`(내부 설계질문 코드) 참조 1건을 발견해 문서 경로만 남기고 코드는 제거했다. 그 외 본문에는 `MJ-`/`WP-`/`N`+숫자류 내부 리뷰 코드가 이미 없었다(사전에 소비자 언어로 작성돼 있었음).
- **CHANGELOG 공백 발견 및 보강**: 커밋 `8d9ab94`(재생 중 아이템 실패 감지 — `AVPlayerItemFailedToPlayToEndTime`/`AVPlayerItemNewErrorLogEntry` 구독, `ABPlayerError.itemErrorLogEntry` 신규 케이스 추가)가 이전 CHANGELOG 갱신(`958ae5a`) **이후**의 커밋인데도 `[Unreleased]`에 전혀 기록되지 않은 것을 실제 소스(`Sources/ABPlayerKit/Model/ABPlayerError.swift`)와 diff로 대조해 발견 — Added 섹션에 2개 항목으로 추가했다:
  - `ABPlayerError`가 초기 로드 실패뿐 아니라 재생 중간 실패도 `.itemFailed`로 승격해 알린다는 점(behavior 확장, 기존 케이스 재사용이라 API 추가는 아님)
  - 신규 `ABPlayerError.itemErrorLogEntry(description:)` 케이스(비종결 진단 신호)

## 1-2 — 마이그레이션 노트

`[0.3.0]` 섹션 하단에 `### Migration notes` 소절을 신설하고, 기존에 개별 항목 안에 인라인으로 흩어져 있던 마이그레이션 설명을 코드 before/after와 함께 이곳으로 모았다(개별 Fixed/Deprecated 항목은 "See Migration notes below."로 짧게 참조만 남김 — 중복 축소):

1. **`.custom` timeFormat 계약 변경** — 0.2.0에서 elapsed만 반환하던 포매터가 어떻게 동작이 달라지는지, 0.3.0에서 `(elapsed, total)` 두 값을 받아 전체 라벨을 직접 조립하는 방법을 실제 시그니처(`@Sendable (TimeInterval, TimeInterval?) -> String`)에 맞춰 작성.
2. **`[UIView]` accessories deprecation** — `accessoryViews: [UIView]` 호출과 accessories 인자 없는 호출 모두가 deprecated 경로로 해석된다는 점, `@ViewBuilder` 트레일링 클로저로 교체하는 방법, 빈 클로저(`{}`)로 신규 이니셜라이저로 이관하는 방법, `UIViewRepresentable` 대안을 before/after 코드로 정리.

## 1-3 — 버전 스윕

`grep -rn "0.2.0"` / `grep -rln "\[Unreleased\]"`로 전체 저장소를 스윕한 결과:

| 파일 | 조치 |
|---|---|
| `README.md` / `README.ko.md` | SPM 설치 예시 `from: "0.2.0"` → `"0.3.0"` (영/한 각 2곳: 코드 블록 + "unreleased development" 안내 문장) |
| `README.md` / `README.ko.md` | accessories 관련 안내문의 `CHANGELOG [Unreleased] ### Deprecated` 참조 → `CHANGELOG [0.3.0] Migration notes` 참조로 갱신 (내가 만든 스탬핑으로 인해 stale해질 참조라 함께 수정) |
| `docs/POLICY-api-stability.md` | `[Unreleased]` CHANGELOG 참조 1곳 → `[0.3.0]` + "Migration notes"로 갱신 (같은 이유) |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | 버그 리포트 폼의 버전 placeholder `"0.2.0"` → `"0.3.0"` |

**의도적으로 남긴 것** (스탬핑 대상이 아닌 과거 기록/예시):
- `docs/IMPL-v0.2-RESULT.md`, `docs/DESIGN-v0.2-CONTROLS.md`, `docs/BRIEF-v0.2-CONTROLS.md`, `docs/briefs/REVIEW-round3-final.md`, `docs/briefs/REVIEW-round3-phase1-2.md` — 모두 v0.2.0 시점을 서술하는 과거 기록이라 그대로 둠.
- `CHANGELOG.md`의 `## [0.2.0]` 섹션 헤더, `[0.2.0]`/`[0.3.0]` compare 링크, Migration notes의 "0.2.0 —" 예시 주석 — 버전 히스토리 자체이므로 정확히 `0.2.0`을 가리켜야 함.
- `docs/briefs/ROADMAP-round5.md`(이 작업 지시서 자체) — 다른 에이전트/향후 참고용 브리프라 수정 대상 아님.
- Xcode 프로젝트/DocC 카탈로그 — grep 결과 버전 번호나 `[Unreleased]` 참조 없음(별도 버전 필드 없음, `Package.swift`도 `swift-tools-version`만 있고 패키지 자체 버전은 git 태그로만 관리).

## 검증

- 마크다운 정합만 확인 (docbuild 등 불필요, 지시대로 생략).
- `grep -rn "0\.2\.0"` / `grep -rln "\[Unreleased\]"` 재실행으로 남은 참조가 모두 의도된 것임을 확인.
- CHANGELOG 섹션 순서(Added/Changed/Deprecated/Fixed), 내부 리뷰 코드 부재, README ↔ CHANGELOG 상호 참조 정합을 육안으로 재확인.
- 커밋하지 않음.
