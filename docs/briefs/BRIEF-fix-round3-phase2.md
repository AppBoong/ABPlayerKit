# BRIEF: 리뷰 라운드3 Phase 2 — 테스트 공백 메우기

시니어 리뷰에서 "어려운 부분을 회피했다"고 지적된 테스트 공백 3곳 + flaky 패턴 정리. Phase 1 변경이 이미 커밋된 상태에서 시작한다. **커밋은 하지 마라** — 별도 에이전트 담당.

## 공통 규칙
- Swift 6, zero-warning. Swift Testing(@Suite/@Test) 사용 — XCTest 금지.
- **새 시뮬레이터를 부팅하지 마라.** 이미 부팅된 시뮬레이터만 사용 (`xcrun simctl list devices | grep Booted` → `xcodebuild test -scheme ABPlayerKit-Package -destination 'id=<UDID>'`).
- sleep 기반 대기 금지. 결정론적 신호(continuation, confirmation, 주입 클록) 또는 데드라인 있는 폴링 헬퍼만 사용.

## WP6 — 코어 엔진 미검증 경로 (Critical 지적)
1. **`ReadyWaitState` 동시성 테스트** (Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift:199-296):
   - 타입이 파일-프라이빗이면 internal로 승격해 `@testable import`로 접근 (프로덕션 동작 변경 금지).
   - KVO resolve vs 타임아웃 vs 취소가 경합해도 단일 결과만 나오는지 `withTaskGroup`으로 동시 타격 테스트.
   - "취소가 continuation 설치보다 먼저 도착"하는 경로 검증.
2. **`waitUntilReady` 통합 테스트**: 번들 리소스로 초소형 mp4를 Tests에 추가(수 KB, 생성 스크립트나 기존 리소스 활용) → `.ready` 도달 / 존재하지 않는 파일 URL → `.failed` / `timeout: 0.01` → `.timedOut` 3케이스. 시뮬레이터에서 AVPlayerItem 실사용.
3. **`ABPlayer.handle(_ event:)` 5개 case 테스트** (Engine/ABPlayer.swift:344-358): `ABFakePlaybackTarget`에 `func emit(_ event: ABTargetEvent)` 헬퍼 추가(onEvent 호출) 후 — `.failed` → `lastError` 갱신+`.failed` 브로드캐스트, `.playedToEnd`/`.playbackStalled`/`.itemStatusChanged`/`.timeControlStatusChanged` 각각 대응 `ABPlayerEvent` 방송 단언. 최소 5개 테스트.
4. Fake 정합: `ABFakePlaybackTarget.preroll`이 `timeout` 인자를 기록하도록 `recordedPrerollTimeout` 추가, 기존 "Preroll timeout" 테스트에 `#expect(target.recordedPrerollTimeout == 0.25)` 단언 보강 + 테스트 이름을 실제 검증 내용에 맞게 갱신.

## WP7 — 캐시 동시성/에러 경로 (Major 지적)
Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift 보강:
1. **동시 load 중복 제거**: `withTaskGroup`으로 같은 키 10개 동시 `load` → fetcher GET 요청이 1회인지 + 10개 결과 동일 단언.
2. **에러 경로**: `ABFakeHTTPFetcher`(또는 기존 fake)에 에러 주입 능력 추가 → `StoreError.invalidResponse`(비2xx), `.entryTooLarge`, `.requestFailed`, 스트림 도중 throw 각각 `#expect(throws:)` 검증.
3. **인덱스 복구**: 인덱스 JSON을 손상시킨 뒤 `ABCacheStore` 재생성 → 빈 인덱스로 복구. 인덱스는 있는데 파일이 없는 케이스도.
4. **LRU 정확성**: 오래된 키 재접근 후 그 키가 축출에서 생존하는지 (`metadataCacheOrder` 검증).
5. Phase 1 WP4에서 추가된 취소 테스트와 중복되지 않게 확인.

## WP8 — 폴링 데드라인 통일 (Major 지적)
1. 테스트 공용 헬퍼 작성: `func waitUntil(_ deadline: Duration = .seconds(2), _ predicate: @MainActor () -> Bool) async throws` — ContinuousClock 데드라인 초과 시 `Issue.record` 후 throw.
2. `while !x { await Task.yield() }` 패턴 전부(ABPlayerEngineTests, ABScrubbingEngineTests, ABPlayerControlsViewTests 등 15곳+)를 이 헬퍼로 치환.
3. 각 테스트 타겟의 주요 @Suite에 `.timeLimit(.minutes(1))` 부여 (Swift Testing timeLimit 단위 제약 확인 후 최소 단위 적용).
4. `ABVideoPlayerWithControlsTests.swift:10-23`의 단언 0개 테스트(`_ = view.body`)는 삭제하거나 실제 단언 추가.

## 완료 보고
추가/수정된 테스트 파일과 테스트 개수, 전체 스위트 통과 여부, 치환한 폴링 루프 개수를 요약하고 대기하라.
