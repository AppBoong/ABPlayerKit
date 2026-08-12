# RESULT: 라운드6 트랙 F

## 1. WP별 완료 상태

- **F-1w (세션 스캐폴딩 + 리버퍼 구간)** — 완료. `ABPlaybackSessionAccumulator`/`ABSessionInput`/`ABSessionAnchor`/`ABBufferingInterval`/`ABSessionSummary` 신규, `ABMetricsRecorder`에 세션 딕셔너리·번역 계층(`ingest(_:playerID:hasItem:at:)` 심)·아이템 보유·`endSession(for:)`/`snapshot(for:)` 추가, `ABClock.wallClockEpoch` 추가.
- **F-2w (watch time + 완료율)** — 완료. 재생/스크럽 상태 기반 watch time 누적기, 위치/길이 추적, `completionRatio`/`rebufferRatio`/`startupMilliseconds` 계산 프로퍼티.
- **F-3w (실패 이벤트)** — 완료. `.failureReported`만 소비, `ABFailureRecord`, 터미널/진단 카운터 분리, `ABJSONLinesMetricsSink.kindName` 안정 문자열 매핑(전 케이스 + `@unknown default`).
- **F-4w (분포 분리 + accessLog 폴드 + 집계 v2)** — 완료. `ABLatencyDistribution`, `ABAccessLogFolder`(+ `ABAccessLogEntry`), `ABQoESummary`, `ABAccessSnapshot` 신규 필드, `ABPlaybackStatistics.waited`, `accessSnapshot(for:)`를 폴드로 교체.
- **F-5w (싱크)** — 완료. 핸들 지연 개방 + 큐 보관, `flush()` public, `writeFailureCount`/`lastWriteErrorDescription`(1회 재개방 재시도 후 카운트), 로테이션(`maxFileSizeBytes`/`maxRotatedFiles`), 신규 4종 JSONL 직렬화.
- **F-6w (데모 Metrics 탭)** — 완료. `DemoModel`에 `sessionSummaries`/`liveSession`/`qoe`/`terminalFailureCount`/`metricsLogFileURL`/`flushMetricsLog()` 추가(팬아웃 싱크로 in-memory + JSONL 병행, 로테이션 켠 채). `MetricsScreen`에 watch time/리버퍼 비율/리버퍼 횟수/완료율/터미널 실패 수/dropped frames/비트레이트 스위치/waited p50·p95 카드와 로그 경로 + Flush 버튼 추가.

## 2. 검증 결과

- **전체 스킴 3회 연속 그린**(`xcodebuild ... build test`, 시뮬레이터 `60DA735B-87EC-4159-9BE3-EF981A127FAF`):
  - RUN 1: 빌드 성공, 테스트 4개 타깃 합계 **571개 / 실패 0** (Cache 72, Controls 200, Metrics 49, Core 250). 테스트 실행 구간 5.9초.
  - RUN 2: 동일 571개 / 실패 0. 테스트 실행 구간 4.4초.
  - RUN 3: 동일 571개 / 실패 0. 테스트 실행 구간 4.2초.
  - 세 번 모두 `exit 0`, `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **`. (RUN 2·3는 소스 변경 없는 증분 재빌드라 컴파일 구간은 사실상 즉시 완료.)
- **docbuild**(`DOCC_WARNINGS_AS_ERRORS=YES`): `** BUILD DOCUMENTATION SUCCEEDED **`. `ABPlayerKitMetrics` 관련 경고 0건. `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/*`에 `View`/`EnvironmentValues` 심볼 미해결 경고가 남아 있으나, `git status`로 확인한 바 이번 작업에서 해당 파일은 한 줄도 건드리지 않았다 — 파일 경계 밖의 기존 상태다.
- **데모 빌드**: `xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj -scheme ABPlayerKitDemo ...` → `** BUILD SUCCEEDED **`. 시뮬레이터에 설치·런치해 Playback 탭이 정상 렌더링됨을 스크린샷으로 확인(HLS 소스가 실제 재생 준비 상태까지 도달). Metrics 탭은 이 헤드리스 환경에 Simulator.app GUI 창이 노출되지 않아(Orca computer-use의 `list-apps`에 Simulator가 없음) 탭 전환 인터랙션을 직접 캡처하지 못했다 — 컴파일 성공과 F-4w의 `ABQoESummary`/`ABPlaybackStatistics` 테스트로 화면이 읽는 모든 값의 계산 로직은 커버했다.
- **SwiftLint**: `swiftlint --strict` → `Found 0 violations, 0 serious in 147 files.`

## 3. 설계 확인 항목 결과

1. **`.itemAttached(source:)` 시점에 `player.avPlayerItem`이 비-nil인가?** — 확인됨. `ABAVPlaybackTarget.attachItem(...)`(`ABAVPlaybackTarget.swift:101`)이 `avPlayerItem = item`을 동기적으로 대입한 뒤, `ABPlayer.interpret(_:source:detachReason:)`의 `.attachItem` 케이스(`ABPlayer.swift:679-687`)가 `target.attachItem(...)` 호출 다음 줄에서 `broadcast(.itemAttached(source:))`한다. 두 호출 사이에 다른 코드가 끼어들지 않으므로 방송 시점에 `player.avPlayerItem`은 항상 비-nil이다. F는 이 지점에서 아이템을 캡처해 `heldItems`에 보관한다.
2. **`.itemDetached`는 release/sourceChanged/demotion/backgroundPolicy 전 경로에서 정확히 1회인가?** — 확인됨. `ABPlayer.swift` 전체에서 `broadcast(.itemDetached(...))` 호출은 `interpret(_:source:detachReason:)`의 `.detachItem` 액션 처리 지점 단 한 곳뿐이다(grep으로 재확인). `.detachItem` 액션 자체는 `ABGradePlanner`가 `from.holdsItem && !to.holdsItem`(및 그 조합)일 때만 생성하므로, 모든 release 경로가 이 단일 지점을 정확히 1회 경유한다. 추가로 `.itemDetached` 도달 시점에는 `player.avPlayerItem`이 이미 `nil`임을 별도 테스트(`ABQoEAggregationTests.swift`의 "player.avPlayerItem is already nil by the time .itemDetached reaches an observer")로 실증했다 — R-1 위험의 전제가 실코드에서 사실임을 확인했고, `heldItems`로 우회했다.
3. **`ABPlayerError`가 `Hashable`인가?** — 아니다(`ABPlayerError.swift`에 `Equatable, Sendable`만 선언). 설계가 닫아 둔 대로 `ABErrorOrigin`(이미 `Hashable`) 기준 집계로 진행했고, 실제로는 딕셔너리 키잉이 필요 없었다 — `kindName(_:)`이 안정 문자열 매핑만 제공하고, `ABErrorOrigin`은 `ABFailureRecord.failure.origin`을 통해 그대로 노출되므로 소비자가 원하면 자체로 `Hashable` 집계를 구성할 수 있다. `ABPlayerError`는 수정하지 않았다.

## 4. 설계에서 벗어난 지점

1. **`segmentsDownloadedCount`가 항상 0이다.** 설계 §5.2는 `AVPlayerItemAccessLogEvent.numberOfSegmentsDownloaded`를 합산 대상으로 지정했으나, 이 프로퍼티는 iOS 7부터 Swift에서 API 자체가 unavailable(컴파일 에러)이다 — `numberOfMediaRequests`로 대체된 지 오래다. 필드 자체는 스키마 하위호환을 위해 유지하되, 어댑터에서 항상 음수(unknown)를 넘겨 폴드가 자연히 0으로 떨어지게 했다. DocC와 CHANGELOG에 명시했다.
2. **`ABSessionSummary`에 `hasDisplayedFirstFrame: Bool` 필드를 추가했다.** 설계 §8.2의 필드 표에는 없다. 결정 3의 완료율 정의(`completionRate = playedToEnd 세션 수 / firstFrame을 본 세션 수`)를 `ABQoESummary.aggregate(_:)`가 **`.sessionSummary` 이벤트만으로** 계산해야 하는데(§8.2 명시), 세션이 첫 프레임을 봤는지 여부를 다른 기존 필드로 역산할 방법이 없었다(TTFF를 측정하지 않은 세션도 첫 프레임은 볼 수 있음). 최소한의 추가 필드로 막았고, JSONL `sessionSummary` 레코드에도 `hasDisplayedFirstFrame` 키를 추가했다 — 이 키는 §8.3 표에 없는 추가 키이지만, R3(신규 이벤트는 새 `"event"` 값으로만 등장하고 소비자는 모르는 키를 무시해야 한다는 계약)의 범위 안이며 R1/R2(기존 5종 레코드의 바이트 동일성)는 건드리지 않는다.
3. **재-attach(디태치 없는 소스 교체)에서 이전 세션을 `.finalized`로 닫고 새 세션을 연다.** 설계 §9의 결정 1 경계 표는 "다음 `.itemAttached`가 [아이템 참조를] 교체"라고만 적어 두었고, `preloaded→preloaded`/`current→current` 등 `sourceChanged`가 `.detachItem` 없이 `.attachItem`만 발생시키는 경로(`ABGradePlanner`의 명시된 동작)에서 **세션 자체**를 어떻게 처리할지는 명시하지 않았다. 열린 세션을 그대로 두면 요약이 영원히 나오지 않는 조용한 데이터 유실이 되므로, 순수 누적기 안에서 이전 세션을 `endReason == .finalized`로 닫고(접근 로그는 이 경로에서 얻을 수 없으므로 `access: nil`) 새 세션을 여는 동작을 추가했다. 표 테스트로 커버했다(`A re-attach without a prior detach finalizes the open session before opening the next`).
4. **F-4w의 "`.itemDetached`의 `access != nil` 회귀 잠금" 테스트를 순수 함수 수준으로만 검증했다.** `AVPlayerItem.accessLog()`는 실제 네트워크 전송이 있어야 엔트리가 채워지는데, 브리프 §5.3이 테스트에 실제 네트워크 URL 재생을 넣지 말라고 명시했다. 대신 (a) `ABAccessLogFolder`를 합성 엔트리로 전수 검증했고 (b) "detach 시점에 `player.avPlayerItem`이 이미 `nil`"이라는 R-1의 실제 위험을 별도 테스트로 실증해, 레코더가 `heldItems`(detach 이전에 캡처한 아이템)를 사용한다는 구조적 근거를 남겼다. 실제 accessLog 콘텐츠가 있는 상황에서의 end-to-end 증명은 결정적 단위 테스트로는 만들 수 없었다.

## 5. 파일 경계 준수

**수정한 파일 전체 목록**(모두 허용 경로 안):

- `Sources/ABPlayerKitMetrics/ABClock.swift`(수정)
- `Sources/ABPlayerKitMetrics/ABMetricEvent.swift`(수정)
- `Sources/ABPlayerKitMetrics/ABMetricsRecorder.swift`(수정)
- `Sources/ABPlayerKitMetrics/ABMetricsSink.swift`(수정)
- `Sources/ABPlayerKitMetrics/ABPlaybackStatistics.swift`(수정)
- `Sources/ABPlayerKitMetrics/ABPlayerKitMetrics.docc/ABPlayerKitMetrics.md`(수정)
- `Sources/ABPlayerKitMetrics/ABLatencyDistribution.swift`(신규)
- `Sources/ABPlayerKitMetrics/ABQoESummary.swift`(신규)
- `Sources/ABPlayerKitMetrics/Model/ABSessionAnchor.swift`(신규)
- `Sources/ABPlayerKitMetrics/Model/ABBufferingInterval.swift`(신규)
- `Sources/ABPlayerKitMetrics/Model/ABSessionSummary.swift`(신규)
- `Sources/ABPlayerKitMetrics/Model/ABFailureRecord.swift`(신규)
- `Sources/ABPlayerKitMetrics/Session/ABSessionInput.swift`(신규)
- `Sources/ABPlayerKitMetrics/Session/ABPlaybackSessionAccumulator.swift`(신규)
- `Sources/ABPlayerKitMetrics/Session/ABAccessLogFolder.swift`(신규)
- `Tests/ABPlayerKitMetricsTests/ABSessionAccumulatorTests.swift`(신규)
- `Tests/ABPlayerKitMetricsTests/ABQoEAggregationTests.swift`(신규)
- `Tests/ABPlayerKitMetricsTests/ABJSONLinesSinkTests.swift`(신규)
- `Examples/ABPlayerKitDemo/ABPlayerKitDemo/DemoModel.swift`(수정, 메트릭 관련 프로퍼티/메서드만)
- `Examples/ABPlayerKitDemo/ABPlayerKitDemo/MetricsScreen.swift`(수정)
- `CHANGELOG.md`(수정)

`Tests/ABPlayerKitMetricsTests/ABMetricsTests.swift`는 **한 줄도 수정하지 않았다**(기존 8개 테스트 전부 무수정 통과). `Sources/ABPlayerKit/**`, `Sources/ABPlayerKitControls/**`, `Sources/ABPlayerKitCache/**`, `Package.swift`, `.github/**`, 그 외 테스트 디렉터리는 diff 0줄이다(`git status`로 확인).

## 6. 게이트가 집중해서 볼 것

1. **§4의 벗어난 지점 3건**(`hasDisplayedFirstFrame` 필드 추가, 재-attach 시 세션 강제 종료, `segmentsDownloadedCount` 항상 0) — 설계 문서에 명시적 근거가 없어 제가 판단으로 채운 지점들이다. 특히 재-attach 처리(§4-3)는 실제 관측 가능한 이벤트 순서를 바꾸는 결정이므로, 데모/소비자 관점에서 "소스만 바뀌었는데 왜 세션이 두 개로 갈라지나"라는 질문이 나올 수 있다 — QoE 관점에서는 의도된 동작(영상별로 별도 세션)이라고 판단했다.
2. **`ABAccessLogFolder`의 `bitrateSwitchCount` 정의**(인접 엔트리만 비교, 값이 0 이하인 엔트리를 건너뛰지 않고 그 페어만 스킵)가 실제 HLS 스트림의 access log 패턴과 맞는지 — 합성 데이터로만 검증했고, 실 CDN 로그로는 검증하지 못했다.
3. **F-6w 데모 Metrics 탭의 실기기/시뮬레이터 인터랙션 미검증** — 컴파일 성공과 정적 스크린샷(Playback 탭)만 확인했다. 헤드리스 환경 제약으로 Metrics 탭 전환·카드 렌더링을 직접 눈으로 보지 못했다. 값 계산 로직 자체는 `ABQoEAggregationTests.swift`/`ABSessionAccumulatorTests.swift`가 커버한다.
