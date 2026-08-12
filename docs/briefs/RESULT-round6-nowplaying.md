# RESULT: 라운드6 트랙 G

## 1. WP별 완료 상태

| WP | 상태 | 요약 |
|---|---|---|
| G-3w (`.continueAudioOnly`) | 완료 | 케이스 추가 + non-exhaustive 계약 주석, `detachesLayerInBackground` internal 확장, `ABBackgroundPolicyMachine` 3개 private 메서드 갱신, `ABBackgroundPolicyMachineTests` 사전 승인 범위 내 확장, 신규 `ABContinueAudioOnlyTests.swift`(3건 기본 시나리오) |
| G-2w (PiP + AirPlay) | 완료 | `ABPictureInPictureSession`(신규 파일) + `ABPlayerView.pictureInPictureSession` 바인딩(지연 언바인딩 포함) + `ABVideoPlayer.init(player:videoGravity:pictureInPicture:)`, `ABBackgroundPolicyMachine.actions(...isPictureInPictureActive:)` 억제 로직, `ABPlayer.setPictureInPictureActive`/복구 경로, AirPlay 3노브(`ABPlayerConfiguration` + `==` 갱신 + `ABPlaybackTarget`/`ABAVPlaybackTarget`/`ABFakePlaybackTarget` 구현), `ABPictureInPictureSessionTests`(8건) + `ABExternalPlaybackConfigurationTests`(6건) + `ABContinueAudioOnlyTests`에 PiP 상호작용 2건 추가 + `ABBackgroundPolicyMachineTests`에 매트릭스 A 전수 테스트 1건 추가 |
| G-1w (`ABPlayerKitNowPlaying` 신규 타깃) | 완료 | `Package.swift`에 product/target/testTarget 추가, 공개 표면(`ABNowPlayingMetadata`/`ABRemoteCommandSet`/`ABNowPlayingConfiguration`/`ABNowPlayingArtworkProviding`/`ABStaticArtworkProvider`/`ABNowPlayingCenter`) + internal 순수 리듀서 3종(`ABNowPlayingOwnership`/`ABNowPlayingInfoBuilder`/`ABRemoteCommandRouter`) + `ABNowPlayingSurface`(프로토콜+MediaPlayer 구현), `ABPlayerKitNowPlayingTests`(31건), 데모 연동(`DemoModel.nowPlayingEnabled`/`nowPlayingToken` + `PlaybackScreen`의 "Now Playing" GroupBox), `ABPlayerKitDemo.xcodeproj`에 패키지 제품 의존성 추가 |
| G-4w (README/DocC) | 완료 | README.md/README.ko.md에 Background Policy/Picture in Picture/AirPlay/Subtitles and Audio Tracks(코어 4절, `ABPlayerKit — Core` 하위) + `ABPlayerKitNowPlaying — Now Playing and Remote Commands`(신규 타깃 절) 5개 절을 동일 구성으로 추가, `ABPlayerKit.docc/ABPlayerKit.md`에 "Picture in Picture" 토픽 그룹 신설, 신규 article `BackgroundAndPictureInPicture.md`, `ABPlayerKitNowPlaying.docc` 카탈로그(Overview + `RemoteCommands.md` article), CHANGELOG `### Added` 4건 + Migration 노트 2건(신규) |

## 2. 검증 결과

### 전체 스킴 3회 연속 (`build test`, 공유 시뮬레이터 `60DA735B-87EC-4159-9BE3-EF981A127FAF`)

| 회차 | 결과 | 소요 시간 | 테스트 수 (스위트별) |
|---|---|---|---|
| 1 | 성공 | 21s | Cache 72 / Controls 200 / Metrics 8 / NowPlaying 31 / 코어 269 — 실패 0 |
| 2 | 성공 | 6s | 동일 — 실패 0 |
| 3 | 성공 | 6s | 동일 — 실패 0 |

`-only-testing`으로 좁히지 않은 전체 스킴 결과이며, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`/`GCC_TREAT_WARNINGS_AS_ERRORS=YES`로 3회 연속 그린을 확인했다(`.dd` 파생 데이터는 매 실행 전 삭제해 클린 상태에서 재현).

### docbuild

`DOCC_WARNINGS_AS_ERRORS=YES`로 성공(`** BUILD DOCUMENTATION SUCCEEDED **`). 남은 경고는 `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/*`의 `View`/`EnvironmentValues` 미해결 심볼 경고뿐이며, 이 파일들은 트랙 G가 diff 0줄로 지키는 Controls 소유 파일이라 트랙 G가 만든 신규 경고가 아니다(트랙 G가 추가한 심볼·아티클에서 유래한 경고는 0건).

### 데모 빌드

`Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj`가 동일 플래그로 성공. `ABPlayerKitNowPlaying` 패키지 제품 의존성을 프로젝트에 추가했다.

### SwiftLint

`swiftlint --strict` — 0 violations, 0 serious (154 files).

### 신규 타깃 추가 후 전체 테스트 수 변화

- 신규 `ABPlayerKitNowPlayingTests`: 31건(신규 타깃).
- 기존 `ABPlayerKitTests`: 267 → 269건(§10-1/§10-8 검증용 2건 추가, 그 외 기존 파일에 매트릭스 A 전수 테스트 등도 추가됐으나 이는 `ABBackgroundPolicyMachineTests`/`ABContinueAudioOnlyTests` 신규 파일·기존 파일 확장에 포함된 수치).
- 전체 스킴 합계: 72(Cache) + 200(Controls) + 8(Metrics) + 31(NowPlaying) + 269(코어) = **580건**, 3회 연속 실패 0.

## 3. 설계 §10 "확인 불가" 10건 처리 결과

| # | 항목 | 처리 |
|---|---|---|
| 10-1 | `AVPictureInPictureController`가 `playerLayer`를 강하게 보유하는가 | **검증 시도함, 결과는 여전히 미확인.** `ABPictureInPictureSessionTests.controllerPlayerLayerRetentionCheck`를 실제로 작성해 실행했다. 이 세션의 시뮬레이터(iPhone 17 Pro Max, iOS 26.2)에서 `ABPictureInPictureSession.isSupported == false`로 확인되어 `AVPictureInPictureController(playerLayer:)` 자체가 생성되지 않아(failable init이 `nil` 반환) 실제 보유 여부는 검증하지 못했다. 다만 설계가 이미 이 결과에 의존하지 않도록 세션이 **뷰 자체**를 강하게 보유하는 구조를 채택했으므로(§4.4 B-5 대응), 재설계나 별도 필드 추가는 하지 않았다 — 기기에서 이 테스트가 재실행되면 결과가 자동으로 드러난다 |
| 10-2 | `UIView` 해제 후에도 백킹 레이어가 PiP로 계속 렌더링되는가 | **검증 불가, 설계상 해당 없음.** 세션이 뷰 자체를 보유하는 우회 설계를 택했으므로 이 질문에 의존하지 않는다(설계 문서의 판단을 그대로 따름) |
| 10-3 | `didEnterBackgroundNotification`과 PiP 자동 활성화 KVO의 순서 | **미검증, 기기 필요.** 복구 경로(`ABPlayer.setPictureInPictureActive(true)`)는 양쪽 순서 모두에서 수렴하도록 구현·단위 테스트(`pictureInPictureActivationRepairsADetachedLayer`)했으나, 실제 순서 자체는 시뮬레이터로 확인 불가 |
| 10-4 | `playerLayer.player = nil`/`replaceCurrentItem(nil)`이 PiP를 종료시키는지 정지시키는지 | **미검증, 기기 필요** |
| 10-5 | 시뮬레이터의 PiP 지원 여부 | **검증됨.** 이 세션의 시뮬레이터에서 `ABPictureInPictureSession.isSupported == false`임을 실제로 확인했다. `start()`가 크래시 없이 안전한 no-op임은 `unboundSessionStartIsSafeNoOp` 단위 테스트로 고정했다 |
| 10-6 | 테스트에서 `MPRemoteCommandEvent`를 직접 생성할 수 있는가 | **검증됨(불가로 확인).** 공개 이니셜라이저가 없어 순수 라우터(`ABRemoteCommandRouter`) 분리가 필수였고, 라우터·센터 로직을 페이크 `ABNowPlayingSurface`로 100% 단위 테스트했다 |
| 10-7 | 데모 앱에 배경 오디오 모드를 켜는 정확한 빌드 설정 키 | **미검증, 미적용.** 이번 라운드의 데모 연동 지시(§11.2)는 NowPlaying 토글만 명시했고 `.continueAudioOnly` 시연용 배경 오디오 모드 추가는 범위에 없어 손대지 않았다. Wave 3 이월 항목으로 남긴다 |
| 10-8 | `AVPlayer.externalPlaybackVideoGravity`의 실제 기본값 | **검증됨.** `avPlayerOwnDefaultMatchesTheChosenDefault` 테스트로 `AVPlayer()`를 직접 생성해 확인한 결과 `.resizeAspect`였다 — 설계가 상정한 값과 일치해 별도 조정 없음 |
| 10-9 | `.continueAudioOnly`가 레이어 detach만으로 실제 배경 오디오를 이어가는가 | **미검증, 기기 필요**(§6.2의 3조건을 갖춘 실제 환경에서만 확인 가능) |
| 10-10 | `MPNowPlayingInfoCenter.nowPlayingInfo`의 스냅숏/복원이 실제로 왕복하는가 | **부분 검증.** 왕복 *로직*은 페이크 surface로 단위 테스트했다(`lastTokenCancellingRestoresSnapshot` — 사전 시딩한 스냅숏 값이 마지막 토큰 해제 후 정확히 복원됨을 확인). 실제 시스템 `MPNowPlayingInfoCenter`와의 왕복은 기기 필요 |

검증하지 않은 항목(10-2·10-3·10-4·10-7·10-9, 10-10의 실기기 부분)은 "검증했다"고 기재하지 않았다.

## 4. §6.4 필수 수반 수반 수정

완료. `ABBackgroundPolicy`에 internal `detachesLayerInBackground` 계산 프로퍼티를 추가하고, `ABPlayer.applyConfigurationChange`의 `previousConfiguration.backgroundPolicy == .pauseAndDetachLayer` 문자열(케이스) 비교를 `previousConfiguration.backgroundPolicy.detachesLayerInBackground` 기반으로 교체했다.

회귀 테스트 존재: `ABContinueAudioOnlyTests.switchingAwayFromContinueAudioOnlyMidBackgroundReattachesLayer` — 배경 상태에서 `.continueAudioOnly → .ignore` 전환 시 `isLayerAttachmentEnabled`가 `true`로 복구됨을 확인한다.

## 5. 설계에서 벗어난 지점

- **`MediaPlayer` import 범위가 설계 문서의 "`ABNowPlayingSurface.swift` 한 파일" 지침보다 넓다.** `ABNowPlayingInfo.dictionary(artwork:)`(MediaPlayer 딕셔너리 변환)와 `MPMediaItemArtwork` 조립(`ABNowPlayingCenter.artworkResolved`)은 구조적으로 `MediaPlayer`가 필요해, `ABNowPlayingCenter.swift`도 `import MediaPlayer`한다. 순수 리듀서 3종(`ABNowPlayingOwnership`/`ABNowPlayingInfoBuilder`/`ABRemoteCommandRouter`)과 공개 데이터 타입(`ABNowPlayingMetadata`/`ABRemoteCommandSet`/`ABNowPlayingConfiguration`)은 전부 `MediaPlayer` 없이 컴파일·테스트되므로, 제약의 실질 목적(테스트 가능성)은 보존했다고 판단했다.
- **`ABNowPlayingSurface` 프로토콜에 설계 스니펫에 없던 메서드 2개(`setSkipInterval(_:)`, `setSupportedPlaybackRates(_:)`)를 추가했다.** `MPSkipIntervalCommand.preferredIntervals`/`MPChangePlaybackRateCommand.supportedPlaybackRates`를 설정할 지점이 프로토콜에 없어 필요했다. internal 프로토콜이라 공개 표면에는 영향 없다.
- **`ABBackgroundPolicyMachineTests`에 설계 §12.3의 사전 승인 목록(정책 배열, switch 블록 2곳, foreground 리터럴 배열) 밖의 신규 테스트 메서드 1개**(`matrixAAcrossPoliciesGradesSignalsAndPictureInPictureState`)를 추가했다. 완료 정의가 요구하는 "매트릭스 A(5정책×4grade×3신호×PiP 2상태) 전수 테이블 테스트"를 만족시키는 데 필요했고, 기존 테스트의 단언은 한 글자도 바꾸지 않았다 — 순수 추가.
- **§12.4 리스크 완화 권고("바인딩된 플레이어의 `avPlayer`가 `nil`이 되면 세션이 강제 `stop()`+언바인딩")는 구현하지 않았다.** §9 확정 API 시그니처에는 없는 추가 안전망 권고였고, 핵심 강한 보유/해제 계약(활성 중 뷰 보유, `isActive == false` 시 해제)은 구현·테스트(`sessionDropsItsHoldOnceInactive`)했다.
- **`Tests/ABPlayerKitNowPlayingTests/Fakes/ABFakePlaybackTarget.swift`를 새로 작성**했다 — `Tests/ABPlayerKitTests/Fakes/ABFakePlaybackTarget.swift`와 내용이 겹치지만, SPM 테스트 타깃은 서로 다른 테스트 타깃의 소스를 공유 import할 수 없어 불가피한 중복이다(둘 다 설계 §0.1의 파일 경계 안).

## 6. 파일 경계 준수

### 수정한 파일 (기존 파일, tracked)

```
CHANGELOG.md
Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj/project.pbxproj
Examples/ABPlayerKitDemo/ABPlayerKitDemo/DemoModel.swift
Examples/ABPlayerKitDemo/ABPlayerKitDemo/PlaybackScreen.swift
Package.swift
README.ko.md
README.md
Sources/ABPlayerKit/ABPlayerKit.docc/ABPlayerKit.md
Sources/ABPlayerKit/Engine/ABAVPlaybackTarget.swift
Sources/ABPlayerKit/Engine/ABPlaybackTarget.swift
Sources/ABPlayerKit/Engine/ABPlayer.swift
Sources/ABPlayerKit/Model/ABPlayerConfiguration.swift
Sources/ABPlayerKit/Policy/ABBackgroundPolicy.swift
Sources/ABPlayerKit/Policy/ABBackgroundPolicyMachine.swift
Sources/ABPlayerKit/SwiftUI/ABVideoPlayer.swift
Sources/ABPlayerKit/View/ABPlayerView.swift
Tests/ABPlayerKitTests/ABBackgroundPolicyMachineTests.swift
Tests/ABPlayerKitTests/Fakes/ABFakePlaybackTarget.swift
```

### 신규 파일

```
Sources/ABPlayerKit/ABPlayerKit.docc/BackgroundAndPictureInPicture.md
Sources/ABPlayerKit/View/ABPictureInPictureSession.swift
Sources/ABPlayerKitNowPlaying/**  (10개 소스 파일 + docc 카탈로그 2개)
Tests/ABPlayerKitNowPlayingTests/**  (4개 테스트 파일 + Fakes 2개)
Tests/ABPlayerKitTests/ABContinueAudioOnlyTests.swift
Tests/ABPlayerKitTests/ABExternalPlaybackConfigurationTests.swift
Tests/ABPlayerKitTests/ABPictureInPictureSessionTests.swift
```

### 프로젝트 경계 확인

```bash
git diff -U0 --stat -- Sources/ABPlayerKitControls Sources/ABPlayerKitMetrics Sources/ABPlayerKitCache .github \
  Tests/ABPlayerKitControlsTests Examples/ABPlayerKitDemo/ABPlayerKitDemo/MetricsScreen.swift
# 출력 없음 — diff 0줄
```

`Sources/ABPlayerKitControls/**`, `Sources/ABPlayerKitMetrics/**`, `Sources/ABPlayerKitCache/**`, `.github/**`, `Tests/ABPlayerKitControlsTests/**`, `Examples/.../MetricsScreen.swift` 전부 diff 0줄을 확인했다. `DemoModel.swift`/`PlaybackScreen.swift`는 비-메트릭 멤버(`nowPlayingEnabled`/`nowPlayingToken`/`setNowPlayingEnabled`, "Now Playing" `GroupBox`)만 추가했다.

`ABPlayerEvent`/`ABPlayerError`: diff 0줄(I-G7 상당 — 새 케이스 추가 없음).

### 신규 주석 ID 인용 재스캔

```bash
git diff -U0 -- . ':!.dd' ':!docs/briefs' | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(I-G[0-9])|(WP[0-9])|(round[0-9])|(MJ-[0-9])|(§[0-9]))'
# (신규 미추적 파일 포함 재검 결과) 출력 없음
```

최초 스캔에서 `I-G3`/`I-G4`/`I-G1`/`I-G6`/`§4.2`/`§4.5`/`§10-6`/`§2.4`/`§2.6`/`§6.4`/`§7.2`/`round6` 패턴 총 20여 건이 걸렸고, 전부 불변식 서술로 재작성해 제거했다. `docs/briefs/**`(오케스트레이터가 사전에 제공한 입력 브리프·설계 문서)는 이 스캔에서 제외했다 — 트랙 G가 작성한 산출물이 아니다.

## 7. Wave 3 / 후속 라운드 이월 항목

- **S-PiP-1~4**(편의 API + PiP): 이번 라운드에 구현하지 않았다. README/DocC에 "Picture in Picture는 명시 소유 경로에서만 지원된다"는 한계를 명시했다. v0.5.0 additive 이월을 권고한다.
- **TSan 잡(CI-2) 미포함**: `.github/**` 수정 금지 규칙에 따라 신규 `ABPlayerKitNowPlayingTests`를 TSan 잡 범위에 추가하지 않았다. 순수 리듀서 위주라 TSan에 안전할 것으로 보이나, Wave 3에서 CI 설정 변경을 판단해야 한다.
- **10-7 데모 배경 오디오 모드**: `.continueAudioOnly`를 데모에서 실제로 시연하려면 `UIBackgroundModes: audio` 추가가 필요하나, 이번 라운드의 데모 연동 범위(NowPlaying 토글)에는 포함하지 않았다.
- **§12.4 추가 안전망**(플레이어 `avPlayer`가 `nil`이 되면 세션 강제 `stop()`): 확정 API 시그니처 밖의 리스크 완화 권고라 이번 라운드에는 구현하지 않았다.
- **기기 수동 확인 전체 항목**(§10-3·10-4·10-7·10-9, PiP 실제 렌더링/시작/복원, NowPlaying 잠금화면 표시·커맨드 동작, AirPlay 실제 라우팅)은 이 세션이 물리 기기에 접근할 수 없어 전부 미확인이다. §8에 정직하게 기재한다.

## 8. 게이트가 집중해서 볼 것

1. **PiP 자동 검증 커버리지가 "정책 리듀서 + 바인딩 수명 + 설정 전달"까지이고, 실제 PiP 시작/렌더링/복원은 이 세션에서 전혀 검증되지 않았다**(시뮬레이터가 PiP 미지원). 그린 상태이지만 기능이 기기에서 죽어 있을 가능성이 가장 높은 지점이다 — §10-1·10-3·10-4·10-9의 기기 확인이 최우선이다.
2. **`MediaPlayer` import 범위가 설계 문서보다 넓어졌다**(`ABNowPlayingCenter.swift`도 아트워크 조립을 위해 import). §5에 사유를 남겼지만, 순수 리듀서의 MediaPlayer 무의존은 유지되는지 직접 확인해 달라 — `ABNowPlayingOwnership.swift`/`ABNowPlayingInfoBuilder.swift`/`ABRemoteCommandRouter.swift` 3개 파일에 `import MediaPlayer`가 없는지가 그 기준이다.
3. **`ABNowPlayingCenter`의 재발행 트리거 순서**: `.gradeChanged`로 소유권을 처음 얻는 시점에는 `player.duration` 미러가 아직 최신이 아닐 수 있어(같은 `set(source:grade:)` 호출 안에서 `refreshPlaybackMirrors()`가 이후에 실행됨), `changePlaybackPosition` 커맨드 활성화를 `durationAvailable`/`itemAttached`에서 재평가하도록 만들었다. 로직은 테스트로 고정했으나(`finiteDurationEnablesChangePlaybackPosition` 등), 실제 잠금화면에서 최초 노출 시 이 재평가가 사용자 눈에 보이는 지연으로 나타나는지는 기기에서만 확인 가능하다.
