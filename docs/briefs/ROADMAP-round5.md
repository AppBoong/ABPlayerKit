# ROADMAP: 라운드5 — v0.3.0 릴리스 & 캐시 sparse range

라운드4 종료 시점(58c376f, 406 tests, Opus APPROVE) 기준의 다음 로드맵. 두 트랙은 독립적이며 (1)이 선행되어야 (2)의 릴리스 노트가 깔끔해진다.

---

## 트랙 1 — v0.3.0 릴리스 (반나절, 리스크 낮음)

| # | 작업 | 내용 | 담당 권장 |
|---|---|---|---|
| 1-1 | CHANGELOG 버전 확정 | `[Unreleased]` → `[0.3.0] - 2026-08-XX`로 스탬프. 라운드3~4 변경(오디오세션 coordinator, 인터럽션 정책, @Observable, 캐시 passthrough, Controls 분해, @ViewBuilder accessories, deprecation)을 Added/Changed/Fixed/Deprecated 로 재분류 정리 | Haiku~Sonnet |
| 1-2 | 마이그레이션 노트 | `.custom` timeFormat 계약 변경 + `[UIView]` accessories deprecation 두 건의 소비자 마이그레이션 가이드를 CHANGELOG 또는 README에 명시 | Sonnet |
| 1-3 | 버전 스윕 | 코드/문서 내 버전 참조 확인 (DocC, README 설치 예시의 `from: "0.2.0"` → `"0.3.0"`) | Haiku |
| 1-4 | 태깅+릴리스 | `git tag v0.3.0` → push → GitHub Release 작성(gh CLI, AppBoong 계정 스위칭 필요 — `gh auth switch -u AppBoong` 후 복귀). 릴리스 노트는 CHANGELOG 발췌 | 오케스트레이터 직접 |
| 1-5 | (선택) Swift Package Index | SPI 등록 확인/등록 — 포트폴리오 노출 채널 | 사용자 확인 후 |

**게이트**: 태깅 전 CI 그린 확인 1회면 충분 (코드 변경이 없으므로 Opus 리뷰 불필요).

---

## 트랙 2 — 캐시 sparse range (2~4일, 리스크 높음 — 라운드3 C2의 완전 해소)

현재 상태: 선형 prefix + 원거리 요청 passthrough 폴백(2MB 임계). 폴백은 "대기 상한"만 보장하고 **원거리 바이트는 캐시에 저장되지 않음** — 비-faststart MP4의 moov(파일 끝)를 매 재생마다 다시 받는다.

| # | 작업 | 내용 |
|---|---|---|
| 2-0 | **설계 게이트 (Opus)** | 구간 맵 자료구조(`[(offset,length)]` vs 고정 블록 비트맵), 디스크 포맷(sparse file `FileHandle.seek` vs 블록 파일 분할), 인덱스 마이그레이션(기존 prefix 엔트리 호환), fill 스케줄링(동시 fill 상한, 병합 규칙)을 결정. **기존 캐시 데이터를 깨지 않는 마이그레이션이 필수 조건** |
| 2-1 | 구간 맵 + 인덱스 v2 | `ABCacheIndex.Entry`에 구간 리스트 추가, 기존 엔트리는 `[(0, size)]`로 무손실 승격. 손상/구버전 인덱스 복구 테스트 |
| 2-2 | sparse 쓰기 경로 | 요청 오프셋 기준 fill 시작 + 기존 구간과 병합. 청크 쓰기는 라운드4 N8 테스트가 고정한 1MB 계약 유지 |
| 2-3 | 읽기 경로 | 요청 range를 커버하는 구간 조합 + 미커버 구간만 네트워크. passthrough 폴백은 유지하되 결과를 구간으로 저장하도록 승격 |
| 2-4 | 동시성/축출 | 다중 fill의 구간 경합, LRU 축출 단위(엔트리 전체 vs 구간별) 결정 반영. 기존 `readerRegistry` 취소 경로와 정합 |
| 2-5 | 검증 | 비-faststart MP4 시나리오 테스트(moov 끝 → 두 번째 재생은 네트워크 0), 동시 load+seek 폭풍 테스트, 기존 109+개 캐시 테스트 무회귀 |
| 2-6 | **최종 게이트 (Opus)** | 전체 diff 리뷰 → APPROVE 시 병합 |

**권장 순서**: 트랙 1 먼저(현재 안정 상태를 v0.3.0으로 박제) → 트랙 2는 그 위에서 v0.4.0 목표로.

---

## 참고 — 이월 소항목 (트랙 2와 무관, 아무 때나)
- 재판정 리뷰(REVIEW-round4-reverdict.md)에 잔여 Minor가 있으면 트랙 1 전에 훑어 반영
- Metrics 데모 화면 스크린샷(TTFF 샘플 축적 후) 추가 여부
