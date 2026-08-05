# RESULT: round4 후속 권장 항목 처리 (REVIEW-round3-final.md §"후속 권장")

- **범위**: `Sources/ABPlayerKit/Engine/ABPlayer.swift`, `Sources/ABPlayerKitCache/ABCacheStore.swift`, `Sources/ABPlayerKitCache/ABCacheConfiguration.swift`, `README.md`/`README.ko.md`, `CHANGELOG.md`, 관련 테스트
- **커밋**: 없음 (미커밋 지시 — 워킹 디렉토리에만 존재)
- **제외**: `Sources/ABPlayerKitControls/**`, `Tests/ABPlayerKitControlsTests/**` — 다른 에이전트가 병렬로 수정 중이라는 지시에 따라 전혀 건드리지 않았다.

## 항목별 처리 표

| # | 항목 | 판정 | 처리 내용 |
|---|---|---|---|
| N8 | passthrough 1MB 청킹 테스트 공백 (Major) | **해소** | `ABCacheStoreTests.swift`에 `distantOffsetPassthroughSplitsIntoOneMegabyteChunks` 추가 — 5.5MB 컨텐츠에서 3MB 오프셋(거리 gap → passthrough)부터 끝까지 요청해 1MB/1MB/0.5MB 3개 청크로 쪼개짐, 처음 두 청크는 `isEndOfResource == false`, 마지막만 `true`임을 단언. `min(fullUpperBound, lowerBound + chunk - 1)` 클램프와 `expectedCount` 재계산이 정확히 검증된다. |
| N6 | `configuration`/`lastError`의 `withObservationTracking` 케이스 부재 | **해소** | `ABPlayerObservationTests.swift`에 `configurationChangeFiresObservation`(`isMuted` 토글로 유발), `lastErrorChangeFiresObservation`(`target.emit(.failed(_))`로 유발) 2건 추가. 리뷰가 지목한 6개 프로퍼티 중 미검증이던 2개가 모두 커버된다. |
| N7 | 일시정지 중 인터럽션이 `.shouldResume`에도 재개하지 않음 미검증 | **해소** | `ABAudioInterruptionTests.swift`에 `interruptionWhilePausedDoesNotResumeEvenWithShouldResume` 추가 — `play()`를 한 번도 호출하지 않은 채(`wasPlayingBeforeInterruption == false`) 인터럽션 begin/end(`.shouldResume`)를 보내고, `.audioInterruptionEnded(resumed: false)` + `target.calls`에 `.play` 없음을 단언. `handleInterruptionEnded`의 4개 논리곱 중 유일하게 미검증이던 게이트. |
| N1 | `play()`마다의 동기 `setActive` IPC | **해소** | `ABPlayer`에 `audioSessionActivationDirty` 플래그 추가. `applyAudioSessionPolicyIfNeeded(force:)`로 시그니처 확장 — grade promotion(`.current` 승격)과 명시적 `audioSessionPolicy` 전환은 여전히 무조건 재적용(`force: true`, 기본값)하지만, `play()`만 `force: false`로 호출해 dirty할 때만 재적용한다. `handleInterruptionBegan`과 `handleWillEnterForeground`에서 플래그를 다시 세운다(세션이 실제로 비활성화될 수 있는 두 시점). 기존 `playReactivatesForInterruptionRecovery` 테스트를 실제 인터럽션 알림을 거치도록 재작성하고, 신규 `repeatPlayWithoutInterruptionDoesNotReactivate`로 "인터럽션 없이 반복 `play()` 시 재활성화 없음"을 직접 단언. |
| C2 잔여 | README에 호스트 세션 활성 상태 관련 단서 부재 | **해소** | `README.md`/`README.ko.md`의 "Audio Session and Interruptions"/"오디오 세션과 인터럽션" 절, `audioSessionPolicy` 항목에 "호스트가 이미 세션을 활성화한 상태였다면 마지막 release() 시 복원이 그 세션을 비활성화할 수 있고, `AVAudioSession`에 활성 상태 조회 API가 없어 원천적으로 구분 불가"라는 단서를 양쪽 언어로 추가. |
| N13 | CHANGELOG `.custom` 항목에 마이그레이션 한 줄 부재 | **해소** | `CHANGELOG.md`의 `.custom` `### Fixed` 항목에 "`.custom` 포매터가 elapsed만 반환하도록 작성돼 있었다면 이제 전체 라벨(예: elapsed+total)을 직접 합성해 반환해야 한다"는 마이그레이션 문장 추가. (부수적으로, N1 구현으로 실제와 달라진 기존 `### Changed`의 오디오 세션 재활성화 서술도 정확하게 갱신했다 — "always reactivates" → "reactivates only when it might actually be needed".) |
| m10 | 테스트 코멘트 오기 (`ABCacheStoreTests.swift:508-511`) | **재검토 후 변경 없음** | 리뷰는 "`fillRequest`가 httpMethod=`"GET"`을 명시(656)한다"고 주장하지만, 실제로 `fillRequest`(694)/`request(for:)`(702)는 httpMethod를 전혀 설정하지 않는다 — 656번 라인은 `remoteMetadata`의 **HEAD 실패 시에만 실행되는 폴백** GET이며, `concurrentLoadsForSameKeyDedupeToOneFill` 테스트는 HEAD가 항상 성공하므로(200 응답) 그 폴백 경로에 도달하지 않는다. `git log -p`로 히스토리를 확인해도 `httpMethod` 대입은 `remoteMetadata` 안 2곳(HEAD/폴백 GET)뿐, `fillRequest`에는 한 번도 존재한 적이 없다. 즉 테스트의 기존 코멘트("`fillRequest`/`stream(for:)` 요청은 method 미지정이라 GET 기본값")는 **현재 코드에서 정확**하다 — 리뷰가 656번 라인을 잘못된 함수(remoteMetadata)에 귀속시킨 오독으로 판단해 코멘트를 변경하지 않았다. (틀린 근거로 "고치는" 것은 오히려 코멘트를 사실과 어긋나게 만들 위험이 있어 보류함.) |
| N10 | `passthroughGapThreshold` 검증/클램핑 부재 | **해소 (문서화)** | `ABCacheConfiguration.swift`의 `passthroughGapThreshold` doc에 "`<= 0`이면 매 요청이 전량 passthrough된다(오프셋 0에서도 `gap >= threshold`가 항상 참)"는 경고를 추가했다. 값 자체를 `max(1, …)`로 클램핑하지는 않았다 — 호출자가 의도적으로 "캐시 완전 비활성" 모드를 원할 수도 있다는 리뷰의 대안("최소한 doc에 명시")을 택해 기존 동작/기본값을 바꾸지 않는 쪽으로 최소 침습 처리했다. |
| N12 | `pendingMetadataRequests` 취소 시 orphan Task | **해소** | `pendingMetadataRequests`의 값 타입을 `Task<RemoteMetadata, Error>` → 참조 타입 `PendingMetadataRequest` 홀더로 변경. `resolvedMetadata`의 cleanup(`defer`)이 `pendingMetadataRequests[key] === holder`일 때만 슬롯을 지우도록 해, `removeAll()`(reset)이나 이후 호출자가 이미 다른 홀더로 교체한 슬롯을 무조건 지워버리던 경로를 제거했다 — coalescing 보장이 "마지막에 끝난 쪽이 이긴다"가 아니라 "내가 설치한 홀더만 내가 지운다"로 정확해졌다. `removeAll()`의 취소 루프도 `pending.task.cancel()`로 갱신. |
| N14 | `formattedTime(_:referenceDuration:)` doc 주석의 stale `.custom` 서술 | **스킵** | `Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift`는 지시에 따라 건드리지 않는 Controls 모듈 소스다. 다른 에이전트가 병렬로 수정 중이므로 스킵. |
| m1 | 튜닝 가드 role 스코프 (REVIEW-round3-phase1-2.md m1) | **해소** | `ABPlayer.applyConfigurationChange`의 가드를 `previousConfiguration.currentTuning != configuration.currentTuning || previousConfiguration.preloadTuning != …`(OR) 대신, 해석된 role(`grade == .current ? .current : .preload`)에 해당하는 튜닝만 비교하도록 수정. `ABPlayerEngineTests.swift`에 `preloadTuningChangeWhileCurrentDoesNotReapply` 추가 — `.current` 상태에서 `preloadTuning`만 바꿔도 재적용/방송이 일어나지 않음을 단언(기존에는 무관한 `.tuningApplied(.current, 동일값)`이 스퓨리어스하게 방송됐다). |

## 설계 메모: N1과 M1 테스트의 충돌

`playReactivatesForInterruptionRecovery`는 원래 `set(source:grade:.current)` 직후 `play()`를 호출하는 것만으로 2번째 `.activate`를 기대했다 — 즉 "인터럽션 없이 단순히 두 번 호출"을 "재활성화가 필요한 상황"의 대리로 삼고 있었다. N1의 dirty 플래그는 정확히 이 대리 시나리오를 없애는 것이 목적이므로 그대로 두면 회귀 테스트가 깨진다. 실제 M1이 보장해야 하는 것(인터럽션 이후 재개 시 재활성화)은 그대로 유지되므로, 테스트를 실제 `NotificationCenter` 기반 인터럽션 begin/end를 거치도록 재작성해 계약을 정확하게 만들었다 — `ABAudioInterruptionTests.swift`의 기존 패턴(`postInterruption` 헬퍼)을 그대로 미러링했다(m7의 "의도적 복제" 컨벤션과 일치).

## 검증

```
xcodebuild test -scheme ABPlayerKit-Package -destination 'id=65CDD0F3-DEE7-4132-B823-E86003329F5E'
→ ** TEST SUCCEEDED **
→ 4개 타깃 합계 330 tests, 0 failures
→ 컴파일러 warning/error 0건 (grep ": warning:" / ": error:" 매치 없음)
```

시뮬레이터는 기존에 부팅되어 있던 `iPhone Air (65CDD0F3-DEE7-4132-B823-E86003329F5E, iOS 26.4)`만 사용했다(신규 부팅 없음). `sleep` 미사용, 커밋 없음.

## 후속으로 남는 것 (이번 스코프 밖)

- N14 (Controls 모듈의 stale doc 주석) — Controls 작업이 끝난 뒤 별도로 처리 필요.
- N2/N3/N4/N5/N9/N11 등 REVIEW-round3-final.md의 나머지 Minor 항목들은 이번 지시 범위에 포함되지 않아 손대지 않았다.
- N10을 doc 경고 대신 실제 `max(1, …)` 클램프로 갈지는 API 계약 변경(호출자가 0/음수를 의도적으로 넘길 가능성) 문제라 별도 논의 필요.
