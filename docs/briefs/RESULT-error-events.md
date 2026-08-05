# RESULT: 재생 중 오류 알림 구현

- **범위**: `Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift`, `Sources/ABPlayerKit/Model/ABPlayerError.swift`, 테스트 신규/보강
- **커밋**: 없음 (사용자 지시에 따라 미커밋 — 워킹 디렉토리에만 존재)

## 배경

`ABAVPlaybackTarget.observeItem`은 기존에 `AVPlayerItem.status` KVO(`.initial`/`.new`)만으로 실패를 감지했다. 이는 **초기 로드 실패**는 잡지만, 재생이 이미 시작된 뒤 스트림이 끊기는 등 **재생 도중 실패**는 놓칠 수 있다 — Apple 문서상 `AVPlayerItemFailedToPlayToEndTime` 알림이 바로 이 케이스를 위한 것이다. 또한 소비자가 "무한 로딩(단순 버퍼링)"과 "실제로 문제가 생긴 상태"를 구분할 방법이 `.playbackStalled` 하나뿐이어서, 진단 정보가 부족했다.

## 변경 사항

### 1. `ABPlayerError`에 신규 case 추가 (`Model/ABPlayerError.swift`)

```swift
case itemErrorLogEntry(description: String)
```

- `AVPlayerItem.errorLog()`에 새 엔트리가 쌓였다는 **비종결(non-terminal)** 진단 신호. 기존 `.itemFailed`(종결)와 구분해, 소비자가 "아직 로딩 중이지만 이미 뭔가 잘못됐다"를 "확실히 실패했다"와 구별할 수 있게 한다.
- `ABPlayerError`는 이미 non-exhaustive 컨벤션이 문서화된 public enum(round3 리뷰 m9에서 정리된 규칙)이라, 기존 주석 패턴("Added in a minor release — see the non-exhaustive convention…")을 그대로 따랐다.

### 2. `ABAVPlaybackTarget.observeItem`에 두 알림 구독 추가

기존 `.AVPlayerItemDidPlayToEndTime`/`.AVPlayerItemPlaybackStalled` 옵저버와 동일한 `observations.add { center.removeObserver(token) }` 백(bag) 패턴을 그대로 따른다.

- **`AVPlayerItemFailedToPlayToEndTime`**: `userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]`를 우선 사용하고, 없으면 `item.error`로 폴백해 `ABPlayerError.itemFailed(description:)`로 승격 → 기존 `ABTargetEvent.failed` 경로로 전달(신규 이벤트 케이스 없이 기존 경로 재사용).
- **`AVPlayerItemNewErrorLogEntry`**: `item.errorLog()?.events.last`를 `ABPlayerError.itemErrorLogEntry(description:)`로 요약해 **같은** `.failed` 경로로 전달. 로그가 아직 없으면(guard) 아무 것도 방출하지 않는 안전한 no-op.
- 두 옵저버 모두 **stale-item 가드** 유지: `setPeriodicTimeObserver`의 `onTick`과 동일하게, 메인 큐 콜백 이후 `Task { @MainActor in guard self.avPlayerItem === item else { return } }`로 감싼다 — 콜백이 큐잉된 뒤, `Task` 훅이 실행되기 전에 새 아이템으로 교체될 수 있는 레이스를 막는다.
- **Swift 6 strict concurrency 대응**: `Notification`/`AVPlayerItemErrorLogEvent`는 `Sendable`이 아니므로(이 파일은 `@preconcurrency import AVFoundation`이지만 `Foundation`은 아님), `description: String` 계산은 `Task` 훅으로 넘어가기 **전**, non-isolated 콜백 안에서 동기적으로 끝낸다 — `ABAudioInterruptionObserver`가 이미 쓰던 것과 같은 패턴("먼저 원시값으로 추출 후 hop").

### 3. `lastError` 갱신 (goal 3)

새 코드는 별도 처리 없이 기존 `ABPlayer.handle(_:)`의 `.failed` 분기를 그대로 탄다:

```swift
case .failed(let error):
    lastError = error
    broadcast(.failed(error))
```

즉 `.itemFailed`든 `.itemErrorLogEntry`든 동일하게 `lastError`가 갱신되고 `.failed` 이벤트가 방송된다 — 소비자는 `lastError`를 패턴 매치해 "종결 실패"와 "비종결 진단 신호"를 구분할 수 있다.

## 테스트

### 신규 파일: `Tests/ABPlayerKitTests/ABAVPlaybackTargetErrorEventsTests.swift`

실제 `AVPlayerItem`(로컬 번들 `tiny.mp4` / 존재하지 않는 로컬 파일 경로)에 `ABAVPlaybackTarget`을 붙이고, `NotificationCenter.default.post`로 두 알림을 직접 발사해 검증한다. `sleep` 없이 전부 `ABWaitUntil.waitUntil` 또는 완전히 동기적인 guard(가드가 `Task`조차 만들지 않는 경로)로 단언한다.

1. **`failedToPlayToEndTimeWithUserInfoErrorPromotesToItemFailed`** — `userInfo`의 에러가 `.itemFailed`로 승격됨을 확인.
2. **`failedToPlayToEndTimeWithoutUserInfoFallsBackToItemError`** — `userInfo` 없이 posting했을 때 `item.error`로 폴백함을, 존재하지 않는 로컬 파일로 실제 `.failed` 상태를 만든 뒤 확인.
3. **`newErrorLogEntryWithoutLogDataIsNoop`** — `errorLog()`가 비어 있을 때 크래시 없이 아무 이벤트도 안 남을 확인. **카나리 알림**(같은 아이템에 대한 두 번째, 검증 가능한 `FailedToPlayToEndTime`)을 곧바로 posting해 `waitUntil`로 대기 — 고정 횟수 yield 폴링(round3 리뷰 m6가 지적한 패턴) 없이 "먼저 posting된 알림이 크래시 없이 처리됐다"를 결정론적으로 증명한다.
4. **`staleItemNotificationIsDropped`** — 오래된 아이템에 대해 posting한 직후(딜리버리가 큐잉만 되고 아직 실행 안 된 시점) `attachItem`으로 아이템을 교체 → stale-item 가드가 큐잉된 알림을 드롭함을, 새 아이템에 대한 카나리 알림으로 결정론적으로 확인.

### 기존 파일 보강: `Tests/ABPlayerKitTests/ABPlayerEngineTests.swift`

`ABPlayerHandleTargetEventTests`에 `.failed(.itemErrorLogEntry)` 케이스 추가 — `ABAVPlaybackTarget` 레벨이 아니라 `ABPlayer.handle(_:)` 레벨에서 `lastError` 갱신 + `.failed` 방송을 확인(기존 `.itemFailed` 커버리지와 대칭).

### 알려진 커버리지 한계

`AVPlayerItemErrorLogEvent`는 public 이니셜라이저가 없어 테스트 코드에서 가짜 로그 이벤트를 만들 수 없다. 따라서 `describe(errorLogEvent:)` 포매팅 로직 자체(도메인/코드/코멘트 조합)는 실제 네트워크 실패로 진짜 로그 엔트리를 만들지 않는 한 유닛 테스트로 검증 불가 — 이 스위트의 기존 컨벤션(로컬 파일로 실네트워크 왕복을 피함)과 상충해 스코프 밖으로 남겼다. `newErrorLogEntryWithoutLogDataIsNoop`은 guard 분기(로그 없음)만 커버한다.

## 검증

```
xcodebuild build -scheme ABPlayerKit-Package -destination 'id=65CDD0F3-DEE7-4132-B823-E86003329F5E'
→ BUILD SUCCEEDED, 컴파일러 경고 0건

xcodebuild test -scheme ABPlayerKit-Package -destination 'id=65CDD0F3-DEE7-4132-B823-E86003329F5E'
→ 전 타깃 TEST SUCCEEDED, 0 failures (신규 5개 테스트 포함)
```

시뮬레이터는 기존에 부팅되어 있던 `iPhone Air (65CDD0F3-DEE7-4132-B823-E86003329F5E, iOS 26.4)`만 사용했다(신규 부팅 없음).

## 후속 제안 (스코프 밖)

- `describe(errorLogEvent:)` 포매팅 로직에 대한 실제 네트워크 기반 통합 테스트(선택적, CI 안정성과 트레이드오프).
- README "Audio Session and Interruptions" 인근에 이 두 알림 경로에 대한 소비자 가이드 한 줄 추가 여부는 사용자 확인 필요(round3 최종 리뷰의 C2 잔여 권고와 유사한 성격).

## 참고: 워킹 디렉토리의 동시 변경

이 작업을 시작하기 직전 `git status`는 `(clean)`이었으나, 작업 완료 시점에 `README.md`/`README.ko.md` 수정과 `docs/assets/`, `docs/briefs/RESULT-screenshots.md`, `docs/briefs/ROADMAP-round4.md`가 이미 워킹 디렉토리에 존재했다 — 이번 작업에서 건드리지 않았다. 병렬로 실행 중인 다른 에이전트/터미널의 산출물로 보이며, 커밋 시 함께 스테이징되지 않도록 주의가 필요하다.
