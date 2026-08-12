# REVIEW: 라운드6 트랙 G 게이트 (G-5)

## 판정
**REQUEST-CHANGES**

차단 사유는 단 하나, §7의 항목 1 (`@unchecked Sendable` 잔존)이다. 그 외 전 항목(전체 스킴 3회 그린, 리베이스 정합성, 파일 경계, 무회귀 불변식, §10/설계 이탈 판정)은 독립 실행으로 확인했고 모두 통과다.

---

## 1. 독립 실행 결과

부팅된 시뮬레이터(`60DA735B-87EC-4159-9BE3-EF981A127FAF`, iPhone 17 Pro Max)를 재사용해 브리프 §2.1 커맨드를 그대로 3회 직접 실행했다(신규 부팅 없음, `status=$?` 함정 회피). 최초 시도는 `tail -80`으로 출력을 잘라 스위트별 수를 못 봐서, 전체 로그를 파일로 저장하는 방식으로 즉시 재실행했다(`.dd`는 검증 종료 후 삭제 — 브리프가 지시한 파생 데이터 경로였을 뿐 소스 조작은 없음).

| 회차 | 결과 | Cache | Controls | Metrics | NowPlaying | 코어 | 합계 | 실패 |
|---|---|---|---|---|---|---|---|---|
| 1 | ✅ | 72 | 200 | **49** | 31 | 269 | 621 | 0 |
| 2 | ✅ | 72 | 200 | **49** | 31 | 269 | 621 | 0 |
| 3 | ✅ | 72 | 200 | **49** | 31 | 269 | 621 | 0 |

3회 연속, 스위트별 수까지 완전히 동일하게 그린. `xcodebuild` exit code 0 (3회 모두).

**Metrics 스위트 검증(브리프 지정 항목):** RESULT가 보고한 리베이스 이전 수치는 Metrics 8건이었다. 리베이스 후 직접 실행한 수치는 **49건**으로 대폭 증가 — 트랙 F의 세션/버퍼링/실패/summary 스위트가 실제로 살아 있음을 실행으로 확인했다. 리베이스가 제대로 반영됐다.

(참고: RESULT의 "580건" 합계는 트랙 F 병합 전 수치였고, 이번 게이트가 F+G 통합 상태의 첫 실행이라는 브리프의 전제와 일치한다. 실측 합계는 621건.)

### docbuild

`DOCC_WARNINGS_AS_ERRORS=YES`로 직접 실행 — `** BUILD DOCUMENTATION SUCCEEDED **`. 로그의 경고 12건은 전부 `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/*`(`View`/`EnvironmentValues` 미해결 심볼)에서 나오며, 이 파일들은 파일 경계 diff 0줄로 확인된 Controls 소유 파일이다 — 트랙 G 신규 심볼·아티클에서 나온 경고 0건.

### 데모 빌드

`Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj`를 동일 플래그로 직접 빌드 — `** BUILD SUCCEEDED **`. 로그의 유일한 "warning:" 라인은 `appintentsmetadataprocessor`의 툴체인 안내 메시지(`No AppIntents.framework dependency found`)이며 Swift 컴파일 경고가 아니다.

### SwiftLint

`swiftlint --strict` 직접 실행 — **0 violations, 0 serious, 166 files**.

---

## 2. 리베이스 정합성

### CHANGELOG

`git diff origin/main -- CHANGELOG.md`는 순수 추가(`+`)만이고 기존 라인 삭제가 0줄이다. `origin/main`의 `### Added`(트랙 S 3건 + 트랙 F 관련 6건)와 `### Migration notes`(트랙 F 4건)가 전부 그대로 남아 있고, 그 뒤에 트랙 G의 `### Added` 4건 + Migration notes 2건이 정확히 이어 붙었다. 충돌 마커(`<<<<<<<`/`=======`/`>>>>>>>`) 재귀 검색 결과 리포 전체에서 0건.

(사소한 참고: 브리프는 "F의 항목 7건"이라 했으나 `origin/main`의 `### Added` 절에서 F 귀속 불릿은 6건으로 셌다. 개수 표현의 사소한 불일치일 뿐 — diff가 순수 추가임을 직접 확인했으므로 내용 유실·중복·충돌은 없다. 차단 아님.)

### `DemoModel.swift`

`git diff origin/main -- Examples/ABPlayerKitDemo/ABPlayerKitDemo/DemoModel.swift`를 직접 확인: G가 추가한 것은 `nowPlayingEnabled`/`nowPlayingToken`/`setNowPlayingEnabled(_:)`와 `import ABPlayerKitNowPlaying` 뿐이다. F의 메트릭 멤버(`metricsSink`/`jsonlMetricsSink`/`metricsRecorder`/`metricsToken`/`metricsLogFileURL`/`flushMetricsLog()` 등)는 diff에 전혀 등장하지 않으며(즉 손대지 않음), 파일에 grep으로도 전부 살아 있음을 확인했다.

### `MetricsScreen.swift`

`git diff origin/main --stat`으로 직접 확인 — **diff 0줄**.

---

## 3. 파일 경계

아래 전부 `git diff origin/main --stat`으로 직접 확인, **전부 0줄**:
`Sources/ABPlayerKitControls/**`, `Sources/ABPlayerKitMetrics/**`, `Sources/ABPlayerKitCache/**`, `.github/**`, `Tests/ABPlayerKitControlsTests/**`, `Examples/.../MetricsScreen.swift`.

`ABPlayerEvent.swift`(`Sources/ABPlayerKit/Observation/ABPlayerEvent.swift`), `ABPlayerError.swift`도 diff 0줄 — 신규 케이스 추가 없음(I-G7).

---

## 4. 무회귀

- **매트릭스 A 전수 테스트**: `ABBackgroundPolicyMachineTests.matrixAAcrossPoliciesGradesSignalsAndPictureInPictureState()`를 직접 읽었다. 5정책 × 4grade × 3신호 × `wasPlaying`{false,true} × `hasCapturedGrade`{false,true} × PiP{false,true} 전수를 순회하며, `isPictureInPictureActive: false`(파라미터 생략 기본값)와 명시적 `false`가 바이트 동일함을 매 조합에서 단언한다. 이것이 곧 **I-G4의 실행 증거**다 — "PiP 파라미터가 없던 기존 4정책 호출부"와 "PiP 파라미터를 명시적으로 false로 넘긴 것"이 항상 같다는 것을 전수로 증명하므로, 기존 4정책의 동작이 바이트 동일하게 보존됨을 기계로 고정한다. 3회 실행 모두 이 테스트 통과.
- **§6.4 필수 수반 수정**: `ABPlayer.swift:840-841`이 `previousConfiguration.backgroundPolicy.detachesLayerInBackground` 기반으로 교체됐음을 직접 확인. `detachesLayerInBackground`(`ABBackgroundPolicy.swift:35-38`)는 `.pauseAndDetachLayer`/`.continueAudioOnly`에서 `true`. 회귀 테스트 `switchingAwayFromContinueAudioOnlyMidBackgroundReattachesLayer`(`ABContinueAudioOnlyTests.swift:40`) 존재 확인 + 3회 실행 전부 통과 로그 확인("Regression: switching away from .continueAudioOnly mid-background re-attaches the layer" passed).
- **절대 불변식 대응 테스트**: I-G1(`rejectNoHandler`류 라우터 테스트), I-G2(`ABNowPlayingCenterTests`의 "Before any attach, the surface is never touched (R6)"), I-G3(`ABPictureInPictureSessionTests`의 세션-뷰 1:1 바인딩/전환 테스트 3건), I-G6(`periodicTimeNeverTriggersExtraPublish`) — 전부 파일 내 존재를 직접 확인했고 3회 실행에서 통과 로그를 확인했다.
- **사전 승인 밖 기존 테스트 변경 여부**: `git diff origin/main -- Tests/ABPlayerKitTests/ABBackgroundPolicyMachineTests.swift`를 라인 단위로 직접 읽었다. `policies` 배열에 `.continueAudioOnly` 추가, `switch policy` 2곳에 신규 케이스 분기 추가, `willEnterForegroundResumesConditionally`의 정책 리터럴 배열에 추가, 그리고 신규 테스트 메서드 1개 — **기존 4정책에 대한 기존 `#expect` 단언은 문자 그대로 한 줄도 바뀌지 않았다**(순수 추가). `Tests/ABPlayerKitTests/Fakes/ABFakePlaybackTarget.swift`도 동일하게 확인 — `applyExternalPlayback` 케이스·필드·메서드 추가뿐, 기존 코드 변경 없음. §12.3 사전 승인 범위와 정확히 일치.
- `ABBackgroundPolicy` 기본값: `ABPlayerConfiguration`에서 `.pause` 유지 확인(설계 §6.3/§7.3, I-G10).
- 설계 §14 비범위 위반 없음: `init(url:)`/`init(source:)`에 `pictureInPicture` 파라미터 없음(명시 소유 `init(player:videoGravity:pictureInPicture:)`에만 존재), Controls 소스에 `PictureInPicture` 문자열 0건(PiP 버튼 미추가), `ABPlayerView`에 `public ... AVPlayerLayer` 프로퍼티 없음(기존 `layerClass` 오버라이드만 유지, 신규 아님).

---

## 5. §10 확인 불가 10건 처리 판정

RESULT §3의 각 항목을 코드로 직접 대조했다.

- **10-1**: "세션이 뷰를 보유"하는 우회 설계가 실제로 구현됐음을 `ABPictureInPictureSession.swift`에서 직접 확인했다(`retainedView` 필드, `updateIsActive`에서 `isActive`가 true가 될 때만 대입하고 false로 돌아가면 즉시 해제). `sessionDropsItsHoldOnceInactive`(weak 참조 생존 확인) 테스트 존재·통과 확인. `controllerPlayerLayerRetentionCheck`도 존재하며, `isSupported == false`일 때 판정 불가로 조용히 리턴하는 정직한 형태로 작성돼 있음을 확인했다 — 주장대로다.
- **10-2·10-3·10-4·10-7·10-9**: RESULT가 미검증으로 정직하게 남긴 항목들이며, 물리 기기 없이는 확인 불가한 항목들이 맞다. 브리프 지침대로 이 항목들로는 REQUEST-CHANGES하지 않는다.
- **10-5**: `isSupported == false`에서 `start()`가 안전한 no-op임을 보이는 `unboundSessionStartIsSafeNoOp` 확인, 3회 실행 통과.
- **10-6**: `ABFakeNowPlayingSurface` 기반 순수 라우터 테스트 존재 확인. `MPRemoteCommandEvent` 미생성 사실과 일치.
- **10-8**: `avPlayerOwnDefaultMatchesTheChosenDefault` 테스트 존재·통과 확인.
- **10-10**: `lastTokenCancellingRestoresSnapshot` 테스트 존재·통과 확인.

전 항목이 RESULT의 주장과 실제 코드가 일치한다.

---

## 6. 설계 이탈 5건 판정

1. **`MediaPlayer` import 범위 확대**: `grep -rl "import MediaPlayer" Sources/ABPlayerKitNowPlaying/`로 직접 확인 — `ABNowPlayingCenter.swift`, `ABNowPlayingSurface.swift` 2개 파일에 존재. 순수 리듀서 3종(`ABNowPlayingOwnership.swift`/`ABNowPlayingInfoBuilder.swift`/`ABRemoteCommandRouter.swift`)에 `import MediaPlayer`가 **0건**임을 직접 grep으로 확인했다 — 제약의 실질 목적(테스트 가능성)은 보존됨. **인정.**
2. **§12.4 리스크 완화 권고 미구현**: `avPlayer == nil` 강제 stop 코드가 없음을 직접 확인했다. 확정 API 시그니처(§9) 밖의 권고였고, 핵심 계약(`isActive`가 false로 전이하면 뷰 보유 해제)은 테스트로 고정돼 있다(§5). 안전망 부재가 실제로 깨지는 구체적 실패 시나리오(예: `release()` 경로에서 세션이 뷰를 영구 보유)를 코드에서 찾지 못했다 — `release()`는 `.detachItem`을 거쳐 최종적으로 PiP 컨트롤러의 `isPictureInPictureActive`가 KVO로 false가 되고 `updateIsActive(false)`가 뷰 보유를 정상 해제하는 경로이므로 안전. **인정, 비차단.** (§8의 기기 확인 이월 항목으로 유지 권고.)
3. **`ABNowPlayingSurface` 프로토콜 메서드 2개 추가**: internal 프로토콜, 공개 표면 영향 없음 직접 확인. **인정.**
4. **매트릭스 테스트 메서드 1개 추가**(§12.3 사전 승인 밖): §4에서 직접 diff 검증 — 기존 단언 무변경, 순수 추가. 오히려 설계 §15 완료 정의가 요구하는 항목을 충족시키는 데 필요했다. **인정.**
5. **`ABFakePlaybackTarget` 중복**: SPM 테스트 타깃 간 소스 공유 불가라는 제약이 실제이므로(별도 테스트 타깃), 불가피한 중복이라는 논거가 타당하다. **인정.**

---

## 7. 지적 사항

### [차단] `@unchecked Sendable`이 신규 코드에 남아 있다 — RESULT의 재확인 주장과 불일치

**파일:라인**: `Tests/ABPlayerKitTests/ABPictureInPictureSessionTests.swift:141`

```swift
private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    ...
}
```

`git diff origin/main -U0 -- Sources Tests | grep '^+' | grep -nE '@unchecked Sendable|MainActor\.assumeIsolated|@available\(\*, deprecated'`를 직접 실행해 발견했다. 브리프 §2.6이 정확히 이 재스캔을 "구현자가 20여 건을 걸러 전부 제거했다고 보고했다. 직접 재확인하라"고 지시한 지점인데, 재확인 결과 **1건이 실제로 남아 있다.**

**실패 시나리오**: 이것 자체가 런타임 크래시를 일으키는 코드는 아니다(`NSLock`으로 실제 동기화는 되어 있다). 문제는 이것이 설계 문서 §0의 "전역 제약 (모든 결정에 선행)" 표에 있는 **"`@unchecked Sendable` / `MainActor.assumeIsolated` 금지 — 코드베이스 확립된 금지"** 조항과, 완료 정의(§15) 체크리스트의 "`@unchecked Sendable`·`MainActor.assumeIsolated`·신규 `deprecated` **0건**"을 문자 그대로 위반한다는 것이다. 예외 조항이 없고("코드베이스 확립된 금지"라고 절대적으로 서술), 테스트 파일이라는 이유로 면제되지 않는다. 게다가 RESULT §6이 "재스캔 결과 출력 없음"이라고 명시적으로 주장한 항목이 실제로는 거짓이었다 — 이번 게이트의 제1 원칙("구현자의 보고를 근거로 인정하지 마라")이 정확히 이 자리에서 값어치를 했다.

**근본 원인**: `withObservationTracking(_:onChange:)`의 `onChange` 클로저가 `@Sendable`을 요구하기 때문에, 클로저가 캡처하는 플래그 타입도 `Sendable`이어야 한다. `NSLock` 기반 수동 동기화 대신 `actor`나 `Synchronization.Mutex` 등 이 코드베이스가 이미 다른 곳에서 안전하다고 인정한 패턴으로 대체하면 `@unchecked` 없이 해결 가능한, 범위가 좁은 수정이다.

**차단 여부**: 차단. 다만 수정 범위는 테스트 파일 1개, 헬퍼 클래스 1개로 국한되며 프로덕션 로직·공개 API에는 영향이 없다.

### [비차단] CHANGELOG "F의 항목 7건" 표현과 실측 불일치

브리프 §2.3은 "F의 항목 7건"이라 했으나, `origin/main`의 `### Added`에서 F 귀속으로 셀 수 있는 불릿은 6건이다(트랙 S 3건 제외). `git diff origin/main -- CHANGELOG.md`가 순수 추가만임을 직접 확인했으므로 내용 유실은 없다 — 개수 표현의 오차일 뿐 실질 문제는 없다. 정보 제공 목적으로만 기재.

---

## 8. 기기 확인이 필요한 이월 항목

RESULT §7·§8과 대조해 직접 검증 가능한 부분은 이미 위에서 확인했다. v0.4.0 출하 전 사람이 실기기에서 반드시 확인해야 할 항목(RESULT의 정직한 미검증 목록과 일치):

1. **PiP 실동작**: 시작/렌더링/배경 지속/복원(§10-1·10-2·10-4·10-9). 자동 검증 커버리지는 "정책 리듀서 + 바인딩 수명 + 설정 전달"까지이며, 이 범위 밖은 이번 게이트로도 검증 불가능한 플랫폼 영역이다.
2. **`didEnterBackgroundNotification`과 PiP 자동 활성화 KVO의 순서**(§10-3) — 복구 경로 자체는 단위 테스트로 고정돼 있으나 실제 순서는 기기 전용.
3. **`.continueAudioOnly`의 실제 배경 오디오 지속**(§10-9) — §6.2 3조건(Info.plist `UIBackgroundModes: audio`, `audioSessionPolicy != .unmanaged`, `.continueAudioOnly`)을 갖춘 데모에서 확인 필요. 데모 앱은 현재 이 중 Info.plist 배경 모드가 빠져 있음(RESULT 10-7, 이번 라운드 범위 밖으로 정직하게 이월).
4. **NowPlaying 잠금화면 표시 및 리모트 커맨드 실동작**(헤드셋 버튼, 컨트롤 센터) — `MPRemoteCommandEvent`를 테스트에서 생성할 수 없어 순수 라우터까지만 자동 검증됨(§10-6).
5. **AirPlay 실제 라우팅과 `isExternalPlaybackActive == true` 관측** — 실제 AirPlay 수신기 필요, 시뮬레이터 불가.
6. **§12.4 안전망 부재가 실제로 문제를 일으키는지** — 코드 경로 분석상 안전해 보이나(§6), PiP 활성 중 플레이어가 예기치 않게 소멸하는 실사용 시나리오가 있다면 기기에서 재현해 볼 가치가 있다.
