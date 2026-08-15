# v0.2 설계 판정

- 엔진: `setRate`(config `playbackRate` 경로) · `skip(by:)` · `seek(to:tolerance:)` · `begin/scrub/endScrubbing` · 옵트인 `.periodicTime`(버퍼 구간 포함) 5종을 v0.1 API 파괴 없이 추가하고, 불변식 T1~T7로 고정했다.
- 타겟: 컨트롤은 코어가 아닌 **신규 `ABPlayerKitControls`**(UIKit 코어 + SwiftUI 래퍼)로 분리 — 코어 설계서 §1의 비목표 선언과 숏폼 소비자의 링크 비용이 근거다.
- 커스터마이징: 외형 `ABPlayerControlsStyle`(아이콘·트랙 앞/뒷편색·썸 크기/색·틴트 등 40여 필드, 프리셋 3종)과 동작 `ABPlayerControlsConfiguration`을 분리하고, 라이브 갱신 시 재적용 범위를 표로 확정했다.
- 테스트: `ABSeekCoalescer` / `ABControlsVisibilityMachine` / `ABSeekBarGeometry` / `ABTimeFormatter`를 순수 타입으로 추출해 시간 의존 없는 `@Suite` 11개(코어 6 + 컨트롤 5)를 시나리오 단위로 설계했다.
- 실행: 커밋 27개(A 엔진 9 · B 골격 4 · C 뷰 8 · D 문서/데모 6, 의존 관계 명시)와 미결 쟁점 Q9~Q15(각 선택지·추천 포함)를 남겼다.

DESIGN-COMPLETE

---

## 수정 반영 (사용자 결정, 2026-08-04)

Q9~Q15 전부 추천안(A)으로 확정. Q9에 수정안 1건이 붙어 다음을 반영했다.

- **공유 순수 타입 승격**: `ABSeekBarGeometry`·`ABTimeFormatter`를 `ABPlayerKitControls` → **코어 `ABPlayerKit`의 public API**로 이동. 신설 디렉터리 `Sources/ABPlayerKit/Presentation/`. 근거는 ABShortsKit v0.2의 숏폼 제스처 UI(하단 슬림 시크바, 탭 재생/일시정지, 롱프레스 2× 배속) 재사용 — 숏폼 UI 자체는 이번 사이클 범위 밖.
- **문서 갱신**: §2.2 디렉터리, §2.3 승격 근거(신설), §5 소유권 표 + §5.3·§5.4 public 시그니처, §8 테스트 타겟 재배치(코어 8스위트 / 컨트롤 4스위트), §10 태스크(B5 → A4, C2·C3이 A4 의존, 총 27커밋), §11 결정 표, §12 확정 표, §13 체크리스트.
- **결정 기록**: `docs/DESIGN-OPEN-QUESTIONS.md`에 Q9~Q15 확정 결정 표 + 설계 영향 절 추가.

AMENDMENTS-APPLIED
