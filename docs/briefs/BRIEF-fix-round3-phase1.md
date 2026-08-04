# BRIEF: 리뷰 라운드3 Phase 1 — 정합성 패치

시니어 리뷰(4개 관점 에이전트)에서 나온 Critical/Major 중 즉시 수정 항목. 아래 5개 워크패키지를 순서대로 구현하라. 각 WP 완료 시 빌드+전체 테스트가 통과해야 한다. **커밋은 하지 마라** — 커밋은 별도 에이전트가 담당한다.

## 공통 규칙
- Swift 6, zero-warning (CI가 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`).
- 테스트 실행: **새 시뮬레이터를 부팅하지 마라.** 이미 부팅된 시뮬레이터만 사용 (`xcrun simctl list devices | grep Booted`로 확인 후 그 destination id로 `xcodebuild test -scheme ABPlayerKit-Package -destination 'id=<UDID>'`).
- 기존 코드 스타일/주석 밀도/네이밍(AB 프리픽스) 준수. public API 문서 주석은 기존 수준 유지.
- 설계 결정 근거는 `docs/DESIGN-ABPlayerKit.md`, `docs/DESIGN-OPEN-QUESTIONS.md` 참조. 코드와 문서가 어긋나면 문서도 함께 갱신.

## WP1 — deinit 부재로 인한 AVPlayer dealloc 크래시 (Critical)
문제: `ABAVPlaybackTarget`(Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift)과 `ABPlayer`(Engine/ABPlayer.swift)에 `deinit`이 없다. 소비자가 `release()` 없이 참조를 버리면 periodic time observer가 등록된 채 AVPlayer가 dealloc → `NSInternalInconsistencyException`.
할 일:
1. `ABAVPlaybackTarget`에 `deinit` 추가 — periodic time observer 토큰과 player를 deinit에서 접근 가능하도록 `nonisolated(unsafe)` 박스(또는 NSLock 보호 박스)로 옮기고, deinit에서 `removeTimeObserver` 수행. `@MainActor` 클래스의 deinit은 nonisolated임에 유의.
2. `ABPlayer`에 `deinit` 추가 — `prerollTask`, `seekWorkerTask` 등 보유 Task 취소. 역시 nonisolated 접근 가능 형태로 정리.
3. 기존 `releasePlayer()` 경로와 이중 해제가 안전한지 확인(멱등).
4. 회귀 테스트: `ABPlayer`를 release() 없이 scope 밖으로 버리고 크래시 없이 observer가 정리되는 테스트(Tests/ABPlayerKitTests). 결정론적으로 — sleep 도박 금지.

## WP2 — audioSessionPolicy 죽은 API 실구현 (Critical)
문제: `ABPlayerConfiguration.audioSessionPolicy`(Model/ABPlayerConfiguration.swift:23)는 선언·비교만 되고 어디서도 읽히지 않는다. `docs/DESIGN-OPEN-QUESTIONS.md` Q4 확정안은 "C — 기본 `.unmanaged` + 설정 시 자동 적용 옵트인(이전 카테고리 복원 포함)"인데 미구현.
할 일:
1. `ABPlayer`가 grade `.current` 승격 시(또는 재생 시작 시) 정책이 `.unmanaged`가 아니면 `ABAudioSession`(Policy/ABAudioSession.swift)을 통해 적용. 적용 전 이전 카테고리/모드/옵션을 저장.
2. `.unmanaged`로 강등되거나 `release()` 시 이전 카테고리 복원. `deactivate()`가 호스트 앱 오디오를 깨지 않도록 복원 로직 포함.
3. 적용 실패는 조용히 삼키지 말고 `ABPlayerEvent` 기존 이벤트 체계로 통지(적절한 케이스가 없으면 lastError 갱신 등 기존 패턴 준수 — 새 public enum case 추가 시 semver 주석 확인).
4. 테스트: `ABAudioSession`을 직접 의존하지 말고 프로토콜 심을 뚫어(`ABAudioSessionControlling` 등 internal) fake로 적용/복원 순서를 검증.
5. `docs/DESIGN-OPEN-QUESTIONS.md` Q4 행에 구현 완료 표기.

## WP3 — ABPlaybackTuning 기본값 + 튜닝 재적용 가드 (Major)
1. `ABPlaybackTuning.init`(Model/ABPlaybackTuning.swift:18-27)의 4개 파라미터 전부에 현재의 권장 기본값 부여 (semver 비파괴 확장 가능하게).
2. `ABPlayer.applyConfigurationChange`(Engine/ABPlayer.swift:446-482) 마지막 튜닝 블록에 `previousConfiguration.currentTuning != configuration.currentTuning || previousConfiguration.preloadTuning != configuration.preloadTuning` 가드 추가 — 무관한 설정 변경(예: periodicTimeInterval)에 튜닝 재적용·`.tuningApplied` 방송이 일어나지 않게. 단 grade 전이에 의한 재적용 경로는 유지.
3. 테스트: periodicTimeInterval만 바꿨을 때 `.tuningApplied`가 방송되지 않음을 단언.

## WP4 — 캐시 waitForProgress 취소 무시 (Major)
문제: `ABCacheStore.waitForProgress`(Sources/ABPlayerKitCache/ABCacheStore.swift:558-562)가 순수 `withCheckedContinuation`이라 취소 시 즉시 깨어나지 못함 → 취소된 로딩 요청이 readerRegistry에 남아 LRU 축출을 막음.
할 일:
1. `withTaskCancellationHandler`로 감싸고 onCancel에서 해당 waiter를 개별 resume(waiter UUID 활용). resume 후 `Task.checkCancellation()`이 던지도록.
2. actor 격리 주의 — onCancel은 동기 컨텍스트이므로 waiter resume 경로를 안전하게 설계 (예: NSLock 보호 waiter 저장소 또는 actor에 Task로 재진입).
3. 테스트(Tests/ABPlayerKitCacheTests): fill이 진행 없는 상태에서 load Task를 cancel → 유한 시간 내 CancellationError로 종료 + `readerRegistry`가 비워져 이후 evict가 가능함을 단언.

## WP5 — 문서/죽은 코드 정합 (Minor, 빠른 승리)
1. DocC 오기 수정: `Sources/ABPlayerKit/ABPlayerKit.docc/ABPlayerKit.md`의 `ABTimeFormatter` 설명("hours field at every duration")을 실제 동작(1시간 미만은 시 필드 없음, `docs/DESIGN-v0.2-CONTROLS.md` R5 롤백 반영)에 맞게 수정.
2. `Sources/ABPlayerKitControls/ABPlayerKitControls.swift`(import 한 줄짜리 빈 파일) 삭제 — 빌드 영향 확인.
3. `ABPlayerError.cacheUnavailable`은 이번엔 건드리지 말 것 (Phase 4 스코프).

## 완료 보고
모든 WP 완료 후: 변경 파일 목록, 각 WP별 테스트 결과(추가된 테스트 이름 포함), 전체 테스트 스위트 통과 여부를 요약 출력하고 대기하라.
