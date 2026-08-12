# RESULT: 라운드6 트랙 A — 코어 엔진 신뢰성 + 관찰성

담당: Sonnet (구현). 입력: `BRIEF-round6-core.md`, `DESIGN-round6-core.md`(승인된 설계, 그대로 구현), `ROADMAP-round6.md` §0·§2, `REVIEW-round6-portfolio-audit.md` §A·§B.
브랜치: `round6/core`. 기준 커밋 995bb6d. **커밋 없음 — 작업 트리 변경만 남김.**

WP A-1w~A-7w 전부 완료. 아래 WP별 요약, 검증 결과, 설계 이탈/게이트 문의, CHANGELOG 초안 순으로 기록한다.

---

## 1. WP별 변경 요약

### A-1w — 루프가 재생을 재개하지 않음 (A-1)

- `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift`
  - `setLooping(_:)`가 `avPlayer?.actionAtItemEnd`를 `isLooping ? .none : .pause`로 함께 설정. attach마다 `setLooping`이 재호출되므로(`ABPlayer.swift`의 `.attachItem` 액션) 아이템 교체 후에도 유지.
  - `didPlayToEnd` 핸들러: `.playedToEnd`를 먼저 방송한 뒤, looping이면 `seekToStart()` → `avPlayer.play()`(A-7w 적용 후 갱신, 최초 구현 시점엔 `rate = desiredRate`)로 재개. 재시작 경로에 stale-item 가드 추가(재attach 레이스 방지).
- 신규 테스트: `Tests/ABPlayerKitTests/ABLoopRestartTests.swift` (`actionAtItemEnd` 값, 루프 시 재생 재개, 비루프 시 재개 안 함, `.playedToEnd` 1회만 방송).

### A-2w — 포그라운드 복귀 오디오 세션 우회 + 배경 캡처 시점 (A-2, A-6)

- `Sources/ABPlayerKit/Policy/ABBackgroundPolicyMachine.swift`(신규): `ABAppLifecycleSignal`/`ABBackgroundAction`/순수 리듀서. `willResignActive`에서 `.pause`/`.pauseAndDetachLayer`만 `.capturePlaying`을 내고, `didEnterBackground`의 실제 부수효과(`pause`/레이어분리/demote)는 그대로, `willEnterForeground`는 항상 `.markAudioSessionDirty`를 먼저 낸 뒤 정책별 재개/복원 액션.
- `Sources/ABPlayerKit/Policy/ABApplicationStateObserver.swift`: `onWillResignActive` 콜백 + `UIApplication.willResignActiveNotification` 구독 추가(기존 2종 유지).
- `Sources/ABPlayerKit/Engine/ABPlayer.swift`: `handleWillResignActive`/`handleDidEnterBackground`/`handleWillEnterForeground`이 리듀서를 호출해 `interpretBackgroundActions(_:)`로 해석. `.resumePlay`는 `self.play()`로 해석(오디오 세션 재활성화 경유). `wasPlayingBeforeBackground`/`wasPlayingBeforeInterruption` 캡처는 `isPlaying` 미러가 아닌 `target.isPlaying`(라이브 값)을 직접 읽도록 함(캡처 시점의 진짜 값이 필요, 미러는 트리거 시점에만 갱신되는 값이므로).
- 신규 테스트: `ABBackgroundPolicyMachineTests.swift`(4정책×3시그널 표 테스트), `ABBackgroundLifecycleEngineTests.swift`(willResignActive에서 캡처 후 didEnterBackground에서 isPlaying이 이미 false여도 복귀 시 재개, 취소된 resign이 강제 재개를 남기지 않음, 관리형 오디오 세션 정책에서 foreground 복귀가 apply 후 target.play()로 이어짐).

### A-3w — `lastError` 라이프사이클 + 진단 채널 분리 (A-3)

- `Sources/ABPlayerKit/Model/ABPlayerError.swift`: `ABPlayerError.isTerminal`(`.itemErrorLogEntry`만 `false`), `ABErrorOrigin`, `ABPlayerFailure` 추가.
- `Sources/ABPlayerKit/Observation/ABPlayerEvent.swift`: `.failureReported(ABPlayerFailure)` 케이스 추가(9개 중 1번째).
- `Sources/ABPlayerKit/Engine/ABPlayer.swift`: `lastFailure`(저장)/`lastDiagnostic`(저장)/`lastError`(계산, `lastFailure?.kind`) 3층 도입. `routeFailure(_:)`가 `isTerminal`에 따라 라우팅 후 `.failed`+`.failureReported` 동시 방송. 리셋: `set(source:grade:)` 최상단(`sourceChanged || resolvedGrade == .released`)과 `interpret()`의 `.attachItem`/`.detachItem` 두 지점(액션 자체가 트리거인 경우, 예: `.instanceOnly → .preloaded`처럼 sourceChanged가 false인 신규 attach)에서 이중으로 커버해 설계가 명시한 4개 트리거(attach/sourceChanged/detach/release) 전부 충족.
- `surfaceAudioSessionFailure`가 `NSError.domain/code`를 `origin`으로 실어 `routeFailure`에 전달.
- **허용된 테스트 변경**: `ABPlayerEngineTests.swift`의 `itemErrorLogEntryUpdatesLastErrorAndBroadcasts` → `itemErrorLogEntryUpdatesLastDiagnosticAndBroadcasts`로 개명, 단언을 `lastDiagnostic`으로 이동 + `lastError == nil` 추가(설계 §5.3 명시 항목).
- 신규 테스트: `ABFailureLifecycleTests.swift` (attach/detach/release 각각의 리셋, 진단/실패 채널 분리, `.failed`→`.failureReported` 순서, 오디오 세션 실패의 origin).

### A-4w — TTFF 거짓 히트 + preroll TOCTOU + detach 방송 순서 (A-4, A-5, A-8)

- `Sources/ABPlayerKit/Engine/ABPlayer.swift`: `interpret()`의 `.detachItem` 액션에서 `hasDisplayedFirstFrame = false; reportedFirstFrameItem = nil` 추가(release()도 이 경로를 경유하므로 A-4 해소). `.detachItem` 순서를 `target.detachItem()` → `broadcast(.itemDetached(reason:))`로 교체(A-8) — 관찰자가 이벤트 수신 시점에 `player.avPlayerItem == nil`을 보장.
- `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift`: `waitUntilReady`의 상태 관찰을 `[.new]` → `[.initial, .new]`로 변경(TOCTOU 창 제거).
- `Tests/ABPlayerKitTests/Fakes/ABFakePlaybackTarget.swift`: `detachItem()`이 `avPlayerItem = nil`을 설정하도록 보강(실제 타깃과 동일한 동작 — `.itemDetached` 핸들러 안에서 `player.avPlayerItem == nil`을 단언하는 신규 테스트에 필요). 기존 테스트 중 이 필드에 의존하는 것 없음(확인됨).
- 신규 테스트: `ABDetachOrderingTests.swift` (release/demotion 후 `hasDisplayedFirstFrame` 리셋, 리셋 후 재attach에서 다시 보고 가능, `.itemDetached` 핸들러 안에서 `avPlayerItem == nil`, `waitUntilReady`가 이미 ready인 아이템에 즉시 응답).

### A-5w — 시크 통일 + skip 누적 (A-7, D-1 코어 절반)

- `Sources/ABPlayerKit/Observation/ABPlayerEvent.swift`: `.seekTargetChanged(CMTime?)` 추가(2번째).
- `Sources/ABPlayerKit/Engine/ABPlayer.swift`:
  - `pendingSeekTime`(저장, `@Observable` 추적) 추가.
  - `enqueueSeek(to:tolerance:)`/`clampToPlayableRange(_:)`/`awaitSeekSettled(generation:)` 신규 private 메서드. `enqueueSeek`이 클램프 + (스크럽 세션 밖일 때만) `pendingSeekTime` 갱신·방송 + 코얼레서 request + 워커 시작을 수행.
  - `runSeekWorker`가 루프 종료 후 코얼레서가 완전히 비고 스크럽 중이 아니면 `pendingSeekTime = nil` + `.seekTargetChanged(nil)` 방송.
  - `resetSeeking()`이 `pendingSeekTime`도 함께 무효화.
  - 진입점 재배선: `seek(to:tolerance:)`(duration 클램프 신규) / `skip(by:)`(기준점을 `pendingSeekTime ?? currentTime`으로, 스크럽 중이면 여전히 `scrub(to:)`로 위임해 await 없음 유지) / 세션 밖 `scrub(to:)`(per-call `Task` 제거, `enqueueSeek` 경유) / `.seekToStart` 플래너 액션(fire-and-forget `Task` 제거, `enqueueSeek` 경유) 전부 `enqueueSeek`을 통과. `endScrubbing()`의 standalone commit 구간에만 `seekGeneration` 캡처·재검증 가드 추가(구조는 보존).
- **금지 준수**: `ABSeekCoalescer.swift`, `ABSeekCoalescerTests.swift`, `ABScrubbingEngineTests.swift`, `ABPeriodicTimeEngineTests.swift` 무수정(diff에 없음, 아래 §3 확인).
- 신규 테스트: `ABSeekUnificationTests.swift` (정착 전 연속 skip 누적, `pendingSeekTime`/`seekTargetChanged` 두 시점만, duration 초과/음수 클램프, 소스 교체 후 stale 세션-밖 scrub 무시, 세션 밖 scrub 5연타 코얼레싱, 스크럽 중 skip이 await 안 함).

### A-6w — 관찰성 + 신규 이벤트 + 에러 프로비넌스 (B-1~B-5)

- `Sources/ABPlayerKit/Engine/ABPlaybackTarget.swift`: `isPlaybackLikelyToKeepUp`/`isPlaybackBufferEmpty`/`timeControlStatus`/`isWaitingWithNoItem`/`presentationSize` 프로토콜 요구사항 추가. `ABTargetEvent`에 `.bufferStateChanged`/`.durationChanged`/`.presentationSizeChanged(CGSize)` 추가, `.failed`를 `ABPlayerFailure` 페이로드로 교체(내부 seam, additive-only 정책 대상 아님).
- `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift`: 5개 신규 계산 프로퍼티. `observeItem`에 KVO 5종(`isPlaybackLikelyToKeepUp`/`isPlaybackBufferEmpty`/`duration`/`presentationSize` `[.initial,.new]`, `reasonForWaitingToPlay` `[.new]`) 등록 — 전부 `ABObservationBag` 수명 결속, `presentationSize`는 값 자체를 나르므로 stale-item 가드 추가(나머지는 재평가 트리거일 뿐이라 처리 시점에 라이브 상태를 다시 읽어 자기교정됨). 기존 3개 `.failed` 방송 지점이 각각 origin을 실음(상태 KVO/FailedToPlayToEndTime은 `NSError`에서, NewErrorLogEntry는 `errorLogEvent.errorDomain/.errorStatusCode`에서).
- `Sources/ABPlayerKit/StateMachine/ABBufferingEvaluator.swift`(신규): 순수 버퍼링 판정기.
- `Sources/ABPlayerKit/Observation/ABPlayerEvent.swift`: 나머지 7개 케이스(`ABRejectedCall`, `.itemAttached`, `.callRejected`, `.bufferingChanged`, `.durationAvailable`, `.stallEnded`, `.presentationSizeChanged`, `.mutedChanged`) — 총 9개.
- `Sources/ABPlayerKit/Engine/ABPlayer.swift`: `isPlaying`/`duration`/`isBuffering`을 저장 프로퍼티로 전환(재계산 미러). `desiresPlayback`/`isStallOutstanding`/`lastBroadcastFiniteDuration`/`lastBroadcastPresentationSize`(전부 `@ObservationIgnored`) 신규. `refreshPlaybackMirrors()`가 값 비교 후에만 대입·방송. 갱신 시점: `play()`/`pause()` 직후 동기, `interpret()`의 `.pause`/`.detachItem`, 배경/인터럽션/라우트체인지 pause 경로, `applyConfigurationChange`의 rate 반영, `set(source:grade:)` 말미(그레이드 전이 종료), `handle(_:)`의 `.itemStatusChanged`/`.timeControlStatusChanged`/`.playedToEnd`/`.bufferStateChanged`/`.durationChanged`. `.itemAttached`를 `.attachItem` 액션에서 `.tuningApplied` 직전에 방송. `.mutedChanged`를 `applyConfigurationChange`의 mute 반영 직후. `rejectCall(_:)` 헬퍼가 `.playbackRejected` 직후 `.callRejected`를 방송 — `play`/`pause`/`seek`/`skip`/`beginScrubbing`/`scrub`/`endScrubbing` 7개 지점 전부 교체.
- **허용된 테스트 변경**: `ABAVPlaybackTargetErrorEventsTests.swift` 6곳(`case .failed(.itemFailed(let d))` → `case .failed(let f), case .itemFailed(let d) = f.kind` 패턴, 기계적), `ABPlayerObservationTests.swift:123`(`.failed(.itemFailed(...))` → `.failed(.init(kind: .itemFailed(...)))`), `Fakes/ABFakePlaybackTarget.swift`(프로토콜 신규 멤버 구현 + `.emit` 유지) — 설계 §5.3에 사전 승인된 항목 그대로.
- 신규 테스트: `ABBufferingEvaluatorTests.swift`(전 조합 표 테스트), `ABObservabilityEventsTests.swift`(동기 `isPlaying`, `bufferingChanged` 값 변화시만, isPlaying+isBuffering 조합, durationAvailable 아이템당 1회+재attach 후 재발, itemAttached→tuningApplied 순서, callRejected 순서, mutedChanged 값 변화시만, stallEnded 1회, presentationSizeChanged zero/중복 억제), `ABAVPlaybackTargetObservabilityTests.swift`(실 `AVPlayerItem` 기반 KVO 통합), `ABPlayerObservationTests.swift`에 4종(+검증용 1종) 추가(isPlaying/duration/isBuffering/pendingSeekTime 발화, 동일값 재대입 무발화).

### A-7w — 소형 정리 (B-6, B-7, B-8, H-6)

1. **httpHeaders(B-6)**: `ABDefaultAssetFactory.makeAsset`이 `httpHeaders`가 비어있지 않으면 `AVURLAssetHTTPHeaderFieldsKey` 옵션으로 `AVURLAsset` 생성. `ABMediaSource.swift`의 "Phase 2 코어는 적용 안 함" 주석을 갱신(HLS 하위 요청 미보장 + Cache 타깃이 지원 경로임을 명시).
2. **`UIScreen.main`(B-7)**: `ABAVPlaybackTarget`에서 `currentScreenNativeSize()`/`UIScreen`/`UIKit` import 제거. `ABPlayer`에 `displaySize`(`@ObservationIgnored`, 기본 `.zero`) + `reportDisplaySize(_:)`(값 변화 시에만 재적용) + `resolvedTuning(for:)`(`tuning(for:).resolved(displaySize:)`) 추가 — target에 전달되는 tuning은 항상 이미 해상된 값. `ABPlayerView.layoutSubviews()`가 `bounds.size × traitCollection.displayScale`을 보고. **`.tuningApplied` 이벤트는 계속 미해상 값을 방송**(기존 동작 보존 — 아래 §2 게이트 문의 참조).
3. **rate(B-8)**: `ABAVPlaybackTarget.play()`가 `avPlayer?.play()` 사용(직접 rate 대입 대신), `setRate(_:)`가 `avPlayer.defaultRate`에도 미러링. `ABPlaybackTuning`에 `audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm?`(기본 `nil`, init 파라미터 목록 맨 끝) 추가, `apply(_:to:)`에서 non-nil일 때만 적용. A-1w의 루프 재시작 코드도 `avPlayer?.play()`로 갱신(이제 defaultRate 미러링 덕에 올바른 배속으로 재개).
4. **레지스트리 통합(H-6)**: `ABObserverRegistry`/`ABLayerAttachmentObserverRegistry` 삭제, `Observation/ABHandlerRegistry.swift`(제네릭 `ABHandlerRegistry<Payload>`)로 대체(~55줄 감소). `ABPlayer.addObserver(_ observer:)`가 `[weak self, weak observer]`를 캡처해 `observer?.player(self, didEmit:)` 호출.
5. **`ABAudioSession.activate` 중복(H-6)**: `nonisolated func abActivateAudioSession(_:)` 자유 함수를 두고 `ABAudioSession.activate`(`@MainActor` 파사드)와 `ABAudioSessionAdapter.activate`(격리 없음 유지)가 함께 호출.
- **허용 범위 밖 테스트 수정**(§3에서 사유 정리): `ABPlayerEngineTests.swift`의 `ABObservationTokenLifecycleTests` 2곳이 삭제된 레지스트리 타입을 직접 참조 — `ABHandlerRegistry<Bool>`/`ABHandlerRegistry<ABPlayerEvent>` + 단일 인자 클로저로 기계적 치환. `ABDefaultAssetFactoryTests`의 기존 테스트명·설명이 "core는 헤더를 무시한다"는 이제 틀린 전제를 담고 있어 갱신 + 헤더 없음 케이스 추가.
- 신규 테스트: `ABDisplaySizeTuningTests.swift`(뷰 없으면 무캡, reportDisplaySize 재적용/재적용 안 함, tuningApplied 미해상값 유지), `ABPlaybackTuningTests.swift`에 2종 추가(audioTimePitchAlgorithm 기본값/보존), `ABRateTuningTargetTests.swift`(defaultRate 미러링, audioTimePitchAlgorithm 실제 아이템 반영/nil이면 AVFoundation 기본값 유지).

### Examples/ (최소 수정, 컴파일 깨짐 확인 후)

- `Examples/ABPlayerKitDemo/ABPlayerKitDemo/DemoModel.swift`: `ABPlayerEvent.title`의 `switch`가 `@unknown default`였는데, 데모가 패키지를 소스로 함께 빌드하므로(라이브러리 버전 경계가 아님) 신규 9개 케이스에 대해 컴파일러가 완전 열거를 요구해 `switch must be exhaustive` 에러 발생. `@unknown default` → `default`로 교체(신규 케이스는 공통 라벨로 폴백, 개별 라벨링은 이번 수정 범위 밖). 이 한 줄 변경 외 데모 로직 변경 없음. `xcodebuild -project .../ABPlayerKitDemo.xcodeproj -scheme ABPlayerKitDemo -destination "generic/platform=iOS Simulator" ... build`로 그린 확인.

---

## 2. 게이트 문의 (설계와 실코드 충돌 지점 — 보수적으로 해석한 결정)

이하는 설계 §5.5(인터페이스 동결)를 존중해 **가장 보수적인 선택**을 한 지점이다. A-8 게이트에서 다른 선택이 맞다고 판단되면 알려달라.

1. **`.tuningApplied` 이벤트 페이로드가 미해상(unresolved) 값인지 해상(resolved) 값인지, 설계 문서가 명시하지 않음.** A-7w의 `displaySize` 도입으로 target에 실제로 적용되는 tuning은 이제 `displaySizeSentinel`이 `displaySize`로 치환된 해상 값이다. 두 가지 해석이 가능했다:
   - (채택) `.tuningApplied`는 계속 "무엇을 요청했는가"(미해상 프리셋)를 방송 — 기존 테스트(`ABPlayerEngineTests.swift`의 `promotionBroadcastsEvents` 등 `.tuningApplied(.current, .displayCapped)` 다수)가 무수정 통과, 이벤트가 나르는 정보의 성격이 A-7w 이전과 동일.
   - (기각) `.tuningApplied`가 해상된 실제 적용값을 방송 — `displaySize` 도입 취지에는 더 부합하지만, `.displayCapped`를 리터럴로 비교하는 기존 테스트 다수가 깨지고(§5.3 밖의 광범위한 수정 필요), Wave 2가 이 이벤트를 어떤 의미로 소비할지 불확실.
   현재 코드는 채택안대로 구현됨. Wave 2(C/F)가 `.tuningApplied`에서 실제 픽셀 캡을 읽어야 하는 요구가 있다면 해상값 방송으로 전환이 필요하며, 그 경우 위 테스트들의 리터럴 비교를 전부 갱신해야 한다.
2. **`ABBackgroundPolicyMachine`의 액션 세분화 수준.** 설계는 액션 8종(`capturePlaying`/`pause`/`setLayerAttachment`/`demoteToInstance`/`restoreCapturedGrade`/`resumePlay`/`markAudioSessionDirty`/`clearCapture`)을 제시했으나, `demoteToInstance`/`restoreCapturedGrade`의 "grade 캡처 자체"와 "실제 데모트/복원"이 원래 로직에서는 조건부로 얽혀 있었다(`gradeBeforeBackground = grade`는 무조건, 실제 데모트는 `holdsItem`일 때만). 리듀서가 액션을 무조건 1개(`[.demoteToInstance]`/`[.restoreCapturedGrade]`)만 내고, `ABPlayer.interpretBackgroundActions`의 해석 함수 안에서 원본과 동일한 조건부 로직을 유지하는 방식을 택했다 — 순수 리듀서의 표 테스트 가능성은 유지하면서 기존 동작을 1비트도 바꾸지 않기 위함. `ABBackgroundPolicyMachine`은 `internal`(Wave 2 동결 대상 아님)이라 이 결정은 트랙 A 내부에만 영향.
3. **`ABAVPlaybackTarget`의 5개 신규 KVO 중 `duration`/`isPlaybackLikelyToKeepUp`/`isPlaybackBufferEmpty`/`reasonForWaitingToPlay`에는 stale-item 가드를 달지 않았다** (`presentationSize`만 값 자체를 나르므로 가드함). 이 네 개는 값을 나르지 않고 "재평가하라"는 신호만 보내며, `ABPlayer.refreshPlaybackMirrors()`가 처리 시점에 `target`의 라이브 상태를 다시 읽으므로 아이템이 이미 교체됐어도 새 아이템의 값을 정확히 읽어 자기교정된다 — 설계 I-7("hop 후 stale-item 가드")의 문언보다는 좁게 해석했다. 관찰 가능한 오동작은 없다고 판단했으나, I-7을 문자 그대로 모든 KVO에 적용해야 한다면 이 네 곳에도 가드를 추가해야 한다.

---

## 3. 검증

- **빌드**: `xcodebuild -scheme ABPlayerKit-Package -destination "generic/platform=iOS" SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES EXTRACT_APP_INTENTS_METADATA=NO build` → **BUILD SUCCEEDED**, 경고 0건.
- **테스트 빌드**: `xcodebuild -scheme ABPlayerKit-Package -destination "generic/platform=iOS Simulator" ... build-for-testing` → **TEST BUILD SUCCEEDED**, 경고 0건(4개 타깃: `ABPlayerKit`, `ABPlayerKitControls`, `ABPlayerKitMetrics`, `ABPlayerKitCache` 및 4개 테스트 타깃 전부 컴파일).
- **데모**: `xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj -scheme ABPlayerKitDemo -destination "generic/platform=iOS Simulator" ... build` → **BUILD SUCCEEDED**(위 §1 한 줄 수정 후).
- **테스트 실행**: `xcrun simctl list devices | grep -i booted`가 빈 결과 — 부팅된 시뮬레이터 없음. 브리프 지시("새 시뮬레이터 부팅 금지")에 따라 **테스트 스위트를 실행하지 않았다.** 빌드 검증까지만 완료.
- **§5.2 수정 금지 테스트 파일 diff 없음 확인**: `git status --porcelain`에 `ABSeekCoalescerTests.swift`/`ABScrubbingEngineTests.swift`/`ABPeriodicTimeEngineTests.swift`/`Tests/ABPlayerKitControlsTests/`/`Support/ABWaitUntil.swift` 없음(확인 완료).
- **파일 경계 확인**: 변경 파일 전부 `Sources/ABPlayerKit/`, `Tests/ABPlayerKitTests/`, `Examples/`(위 1줄) 내부. `Sources/ABPlayerKitControls|Cache|Metrics/`, `Tests/ABPlayerKitControlsTests/` 무변경.
- **§5.3 외 기존 테스트 수정 전체 목록**(사유는 §1 각 WP 섹션에 병기):
  - `Tests/ABPlayerKitTests/ABPlayerEngineTests.swift`: `ABDefaultAssetFactoryTests`(개명+케이스 추가, A-7w), `ABPlayerHandleTargetEventTests`의 `target.emit(.failed(error))` 2곳 → `.failed(.init(kind: error))`(A-6w, `ABTargetEvent.failed` 페이로드 타입 변경에 따른 기계적 수정, §5.3에 명시된 `ABPlayerObservationTests.swift:123`과 동일 성격), `ABObservationTokenLifecycleTests`의 레지스트리 타입 참조 2곳(A-7w).
  - `Tests/ABPlayerKitTests/Fakes/ABFakePlaybackTarget.swift`: `detachItem()`의 `avPlayerItem = nil` 추가(§5.3이 "프로토콜 신규 멤버 구현 추가"만 명시했으나, A-4/A-8 순서 보장 테스트에 필요한 최소 보강).
  - `Tests/ABPlayerKitTests/ABPlaybackTuningTests.swift`: 파일 말미에 신규 테스트 2종 추가(수정 아님).
  - 나머지는 전부 신규 파일(§5.3 대상 아님) 또는 §5.3에 사전 승인된 항목.

## 4. 불변식(§5.1) 자체 점검

I-1(동기 isPlaying) / I-2(isPlaying 의미 불변) / I-3(스크럽 중 skip 비대기) / I-4(`ABSeekCoalescer` 무수정) / I-5(스크럽 종료 순서) / I-6(release당 detachItem 1회) / I-7(신규 KVO 수명결속, 값-전달 이벤트에 stale 가드 — 범위 해석은 §2-3 참조) / I-8(`deinit` 접근 프로퍼티 `@ObservationIgnored` 유지, 신규 프로퍼티 전부 `deinit`에서 미접근) — 전부 코드 리뷰로 확인. 실 시뮬레이터 테스트 실행으로 실증하지 못한 점은 §3에 명시.

---

## 5. CHANGELOG 초안 (Unreleased)

### Added

- `ABPlayer.lastFailure`/`lastDiagnostic`(저장, `@Observable`) — 종료성 실패와 비종료 진단(`.itemErrorLogEntry`)을 분리된 채널로 노출.
- `ABPlayer.isBuffering`/`pendingSeekTime`(저장, `@Observable`). `isPlaying`/`duration`이 계산 프로퍼티에서 저장 프로퍼티로 전환(의미 불변, target에서 재계산되는 미러).
- `ABPlayerEvent` 9개 신규 케이스: `.failureReported(ABPlayerFailure)`, `.seekTargetChanged(CMTime?)`, `.itemAttached(source:)`, `.callRejected(ABRejectedCall, grade:)`, `.bufferingChanged(Bool)`, `.durationAvailable(CMTime)`, `.stallEnded`, `.presentationSizeChanged(CGSize)`, `.mutedChanged(Bool)`.
- `ABErrorOrigin`, `ABPlayerFailure`, `ABRejectedCall`(신규 공개 타입). `ABPlayerError.isTerminal`.
- `ABPlaybackTuning.audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm?`(기본 `nil`).
- `ABDefaultAssetFactory`가 `ABMediaSource.httpHeaders`를 초기 요청에 적용(`AVURLAssetHTTPHeaderFieldsKey`).

### Fixed

- 루프(`isLooping == true`)가 끝에 도달한 뒤 실제로 재생을 재개하지 않던 문제(처음 위치에서 정지 상태로 멈춤).
- 포그라운드 복귀 시 관리형 오디오 세션 재활성화를 우회하던 문제(무음 재생 가능성).
- 백그라운드 진입 시 `isPlaying` 캡처 시점이 늦어(`didEnterBackground`) iOS가 이미 디코드를 멈춘 뒤라 자동 재개가 무산되던 문제 — `willResignActive`로 이관.
- `lastError`가 attach/소스 교체/release 후에도 영구 잔존하던 문제, 그리고 비종료 진단(`.itemErrorLogEntry`)이 종료성 실패와 같은 채널을 오염시키던 문제.
- `release()` 후 `hasDisplayedFirstFrame`이 `true`로 남아 다음 세션의 `beginTTFF`가 거짓 캐시 히트를 기록하던 문제.
- `waitUntilReady`의 TOCTOU 창(상태 확인과 KVO 등록 사이 전이 시 10초 타임아웃까지 대기).
- `.itemDetached`가 실제 detach 이전에 방송되어 관찰자가 낡은 아이템을 읽고 리바인드하던 문제.
- 시크 진입점 4곳 중 1곳만 세대 가드를 갖고 있어 소스 교체 후 stale `.seekCompleted`가 도착할 수 있던 문제.
- `UIScreen.main` 사용 — 피드 셀의 올바른 해상도 캡은 셀 크기이지 디바이스 화면 크기가 아님.

### Migration Notes

1. `seek(to:)`/`seek(to:tolerance:)`가 이제 목적 시간을 `0...duration`으로 클램프한다(duration이 유한할 때). 이전에는 그대로 전달되어 `AVPlayer`에 위임됐다.
2. `configuration.rewindOnDemotion == true`일 때 데모션 시 `.seekCompleted(to: .zero)`가 새로 방송된다(이전에는 무음).
3. 스크럽 세션 밖에서 연속으로 호출한 `scrub(to:)`가 이제 코얼레싱된다(이전에는 호출 수만큼 개별 시크가 발행됐다).
4. 연속된 `skip(by:)` 호출이 이제 `pendingSeekTime`(요청된 목적지) 기준으로 누적된다(이전에는 아직 갱신되지 않은 `currentTime` 기준이라 사실상 단발성이었다).
5. `.itemErrorLogEntry` 실패가 더 이상 `lastError`를 갱신하지 않는다 — `lastDiagnostic`을 대신 읽어야 한다. `lastError`는 이제 `lastFailure?.kind`의 계산 프로퍼티다.
6. `.itemDetached` 수신 시점에 `player.avPlayerItem`/`player.avPlayer`(레이어 attach 관점)가 이미 갱신 이전 상태를 반영하지 않는다 — 순서가 "detach 먼저, 방송 나중"으로 바뀌었다.
7. `ABPlayerView`에 부착되지 않은(또는 아직 첫 레이아웃 패스 전인) 플레이어의 `ABPlaybackTuning.displaySizeSentinel`은 이제 디바이스 화면 크기가 아니라 "캡 없음"으로 해석된다.
8. `.tuningApplied`가 여전히 미해상 프리셋 값을 방송한다(§2-1 참조) — 실제로 target에 적용되는 `preferredMaximumResolution`은 `ABPlayerView`가 보고한 크기로 별도 해상된다.

---

## 6. 다음 단계

- **A-8 최종 게이트(Opus)**: 전체 diff 리뷰, 특히 A-5w의 스크럽 회귀 여부와 A-6w의 `@Observable` 매크로 상호작용(동일값 재대입 무발화가 실제 시뮬레이터에서도 성립하는지) 집중 검토 요청. 위 §2 게이트 문의 2건에 대한 판단도 요청.
- 실 시뮬레이터에서의 테스트 스위트 실행은 CI 또는 시뮬레이터가 이미 부팅된 환경에서 별도로 수행 필요(§3).
