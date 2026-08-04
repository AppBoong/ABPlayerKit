# BRIEF: 리뷰 라운드3 Phase 4 — API/도메인 개선

시니어 리뷰 잔여 Major 항목. 아래 WP를 순서대로 구현하라. 각 WP 완료 시 빌드+전체 테스트 통과 필수. **커밋 금지** — 별도 에이전트 담당.

## 공통 규칙
- Swift 6, zero-warning. **새 시뮬레이터 부팅 금지** — 부팅된 시뮬레이터만 사용.
- sleep 대기 금지. 기존 코드 스타일 준수. 기존 public API 파괴 변경 금지 (additive만 허용).
- 각 WP에서 관련 설계 문서(docs/DESIGN-*.md)와 어긋나면 문서도 갱신.

## WP9 — @Observable 채택 (Major: iOS 17 요구 근거 회복)
문제: iOS 17+를 요구하는 근거(Q7)가 `@Observable`인데 사용 0건. SwiftUI 소비자는 `player.grade`/`isScrubbing`/`hasDisplayedFirstFrame`/`lastError` 변경에 뷰가 갱신되지 않음.
할 일:
1. `ABPlayer`(Engine/ABPlayer.swift)에 `@Observable` 적용. 기존 옵저버+토큰 이벤트 체계는 그대로 유지(Q3 결정 — 둘은 병행). `@ObservationIgnored`로 내부 상태(Task, 레지스트리 등) 제외.
2. `@MainActor` + `@Observable` 조합의 Swift 6 이슈(매크로 전개, deinit 접근) 확인. deinit의 nonisolated 정리 로직과 충돌하지 않게.
3. 데모 앱(Examples/ABPlayerKitDemo)에서 옵저버 브리지 없이 `player.grade`를 직접 읽는 화면이 실제로 갱신되는지 코드 수준에서 정리(데모 빌드는 CI 스킴으로 확인).
4. 테스트: `withObservationTracking`으로 `grade`/`isScrubbing` 변경이 관찰 알림을 발화하는지 검증.

## WP10 — 오디오 인터럽션/라우트 변경 처리 (Major: 도메인 필수 누락)
1. `ABInterruptionPolicy` 추가 (`.ignore` 기본 / `.pauseAndResume`) — `ABPlayerConfiguration`에 옵트인 필드.
2. `ABApplicationStateObserver` 패턴을 따라 인스턴스-소유 옵저버로 `AVAudioSession.interruptionNotification` 구독: `.began` → pause + 상태 동기화, `.ended` + `.shouldResume` → 정책이 `.pauseAndResume`일 때 재생 재개.
3. `routeChangeNotification` `.oldDeviceUnavailable`(이어폰 분리) → pause (HIG 준수). 정책과 무관하게 기본 동작으로 할지 여부는 별도 플래그로.
4. `ABPlayerEvent`에 인터럽션 통지 추가 시 비전수 enum 주석 규칙 준수.
5. 테스트: NotificationCenter에 직접 userInfo를 실어 post하여 pause/resume 경로 검증 (AVAudioSession 인스턴스 실사용 금지 — userInfo 키만 재현).
6. README(영/한)에 인터럽션 처리 섹션 추가.

## WP11 — 캐시 passthrough 폴백 (Critical 완화: 선형 prefix 대기 상한)
문제: `ABCacheStore.load`는 요청 오프셋이 현재 prefix보다 멀리 앞서 있어도 무한 대기(:223-251). 비-faststart MP4에서 TTFF가 파일 크기에 비례.
할 일 (sparse range 전면 개편은 스코프 밖 — 폴백만):
1. 요청 오프셋이 현재 prefix 끝보다 설정 가능한 임계(예: `passthroughGapThreshold`, 기본 2MB) 이상 앞서면 해당 요청을 fill 대기 없이 즉시 `passthrough`(네트워크 직행)로 처리.
2. passthrough 응답도 전량 메모리 적재 대신 스트리밍 청크(최대 1MB 단위)로 respond하도록 `ABResourceLoaderDelegate` 루프와 연동.
3. `ABCacheConfiguration`에 임계값 필드 추가 (기본값 있는 additive).
4. 테스트: prefix 0인 상태에서 뒤쪽 오프셋 요청 → 유한 시간 내 passthrough 경로로 데이터 반환 + fill 대기하지 않음 단언.
5. README/DocC에 "캐시는 선형 prefix + 원거리 시크는 passthrough" 동작 명시.

## WP12 — custom timeFormat 계약 수정 (테스트에 박제된 버그)
문제: `.custom` 포매터와 `timeLabelLayout` 조합 시 `"12s/90s/90s/90s"` 같은 이중 조합 출력 (ABPlayerControlsView.swift:696-712, 테스트 ABPlayerControlsViewTests.swift:219-234가 이를 기대값으로 박제).
할 일:
1. 계약 확정: `.custom`일 때는 조합 없이 elapsed 호출 결과를 그대로 라벨에 사용 (custom이 duration을 이미 받으므로 조합 불필요).
2. 구현 수정 + 박제 테스트를 의도된 계약으로 갱신.
3. `TimeLabelFormat` 문서 주석에 계약 명시.

## WP13 — 문서/레포 정리 (오픈소스 인상)
1. `docs/README.md` 신설: "docs/ 하위 DESIGN-*/BRIEF-*/briefs/ 는 메인테이너용 설계 기록이며 사용자는 README와 DocC만 보면 된다" 명시 (영어).
2. 루트의 `IMPL-v0.2-RESULT.md`를 `docs/`로 이동.
3. README(영/한)에 이번 라운드 신기능 반영: audioSessionPolicy, 인터럽션 정책, 캐시 passthrough 동작.
4. CHANGELOG.md에 Unreleased 섹션으로 이번 변경 정리 (Keep a Changelog 형식, 기존 스타일 준수).
5. CI(ci.yml)에 `-enableCodeCoverage YES` + `-resultBundlePath` + xcresult 아티팩트 업로드 추가.

## 스코프 제외 (건드리지 말 것)
- README 스크린샷/GIF (사용자 확인 필요), ABPlayerControlsView 1092줄 분해(대규모 리팩토링), 캐시 sparse range 전면 개편, accessoryViews SwiftUI API 변경(파괴 변경 위험).

## 완료 보고
WP별 변경 파일/테스트, 전체 스위트 통과 여부 요약 후 대기.
