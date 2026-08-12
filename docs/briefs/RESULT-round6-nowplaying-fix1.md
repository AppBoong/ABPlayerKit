# RESULT: 라운드6 트랙 G — G-5 REQUEST-CHANGES 대응 (fix1)

## 1. 차단 사유와 수정 내용

`docs/briefs/REVIEW-round6-nowplaying.md` §7의 유일한 차단 사유: `Tests/ABPlayerKitTests/ABPictureInPictureSessionTests.swift:141`의 `ObservationFlag`가 `@unchecked Sendable`로 선언되어 있었다.

### 수정

`NSLock` 기반 수동 동기화 + `@unchecked Sendable`을 제거하고, `os.OSAllocatedUnfairLock<Bool>`(iOS 16+, 이 패키지의 최소 지원 iOS 17을 만족)로 교체했다. `OSAllocatedUnfairLock`은 `State: Sendable`일 때 그 자체가 `Sendable`이므로, 이를 `let` 저장 프로퍼티 하나로만 감싼 `ObservationFlag`는 `@unchecked` 없이 컴파일러가 검사하는 `Sendable`로 선언할 수 있었다.

```diff
+import os
...
-    private final class ObservationFlag: @unchecked Sendable {
-        private let lock = NSLock()
-        private var fired = false
+    private final class ObservationFlag: Sendable {
+        private let state = OSAllocatedUnfairLock(initialState: false)

         func markFired() {
-            lock.lock()
-            fired = true
-            lock.unlock()
+            state.withLock { $0 = true }
         }

         var hasFired: Bool {
-            lock.lock()
-            defer { lock.unlock() }
-            return fired
+            state.withLock { $0 }
         }
     }
```

### 선택 근거 (검토했던 대안과 기각 사유)

| 대안 | 채택 여부 | 사유 |
|---|---|---|
| `os.OSAllocatedUnfairLock` | **채택** | iOS 16+ (패키지 최소 iOS 17 충족), 그 자체가 `Sendable`이라 래퍼를 순수 `Sendable`로 만들 수 있다. `withLock` 클로저 기반 API라 락 해제 누락 위험이 `NSLock` 수동 lock/unlock보다 낮다 |
| `Synchronization.Mutex` | 기각 | iOS 18+ 요구 — 이 패키지의 최소 지원 대상(iOS 17)에서 컴파일 자체가 안 된다 |
| `actor` | 기각 | `hasFired`가 `async` 프로퍼티가 되어, 이 테스트가 검증하는 "`withObservationTracking`의 `onChange` 콜백이 재발화하지 **않았다**"는 것을 동기적으로 즉시 단언하는 형태(`#expect(!possibleFlag.hasFired)`)와 맞지 않는다. `await`로 우회하면 그 사이 타이밍이 벌어져 같은 강도로 부정 사실을 증명하기 어려워진다 |
| `nonisolated(unsafe)` | 기각 | 사용자 지시로 명시 금지 |
| `@unchecked Sendable` 유지 | 기각 | 차단 사유 그 자체 |

## 2. 불변식 약화 여부

**약화하지 않았다.** `ObservationFlag`가 검증하는 불변식(`sameValueReassignmentDoesNotRefireObservation` 테스트 — 동일 값 재대입이 `@Observable`의 `withObservationTracking` 변경 알림을 재발화하지 않음)은 그대로다. `markFired()`/`hasFired`의 동작(스레드-안전 쓰기 1회, 스레드-안전 읽기)은 `NSLock` 버전과 완전히 동일하며, 테스트 본문·단언(`#expect`)은 한 글자도 바꾸지 않았다. 바뀐 것은 내부 동기화 프리미티브뿐이다.

## 3. 검증 결과

### 위생 재스캔 (실제 실행, 원본 출력 근거)

```bash
$ git diff origin/main -U0 -- Sources Tests | grep '^+' | grep -nE '@unchecked Sendable|MainActor\.assumeIsolated|@available\(\*, deprecated'
$ echo "exit=$?"
exit=1

$ git diff origin/main -U0 -- Sources Tests | grep '^+' | grep -nE 'nonisolated\(unsafe\)'
$ echo "exit=$?"
exit=1

$ git diff origin/main -U0 -- Sources Tests Examples README.md README.ko.md CHANGELOG.md Package.swift \
    | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(I-G[0-9])|(WP[0-9])|(round[0-9])|(MJ-[0-9])|(§[0-9]))'
$ echo "exit=$?"
exit=1
```

세 스캔 모두 `grep` 매치 0건(`exit=1`)을 실제로 실행해 확인했다 — 리뷰가 지적한 "재확인 없이 결과만 주장하는" 실수를 반복하지 않기 위해 이번에는 각 명령의 원본 출력을 그대로 위에 붙였다.

### SwiftLint

```
$ swiftlint --strict
Done linting! Found 0 violations, 0 serious in 166 files.
```

### 전체 스킴 3회 연속 (`build test`, 공유 시뮬레이터 `60DA735B-87EC-4159-9BE3-EF981A127FAF`, `-only-testing` 미사용)

| 회차 | 결과 | 소요 시간 | Cache | Controls | Metrics | NowPlaying | 코어 | 합계 | 실패 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | ✅ | 27s | 72 | 200 | 49 | 31 | 269 | **621** | 0 |
| 2 | ✅ | 7s | 72 | 200 | 49 | 31 | 269 | **621** | 0 |
| 3 | ✅ | 6s | 72 | 200 | 49 | 31 | 269 | **621** | 0 |

3회 모두 스위트별 수까지 완전히 동일하게 그린이며, 리뷰가 보고한 621건과 정확히 일치한다. `.dd` 파생 데이터는 이 3회 실행 시작 전에 삭제해 클린 상태에서 재현했고, 실행 종료 후 다시 삭제했다.

### docbuild

`DOCC_WARNINGS_AS_ERRORS=YES`로 실행 — `** BUILD DOCUMENTATION SUCCEEDED **`(`exit=0`). 남은 경고 12건은 전부 `Sources/ABPlayerKitControls/ABPlayerKitControls.docc/*`(`View`/`EnvironmentValues` 미해결 심볼)에서 나오며, 이 파일들은 파일 경계상 diff 0줄인 Controls 소유 파일이다 — fix1이 만든 신규 경고는 0건.

### 데모 빌드

`Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj`를 동일 플래그로 빌드 — `** BUILD SUCCEEDED **`(`exit=0`). 유일한 "warning:" 라인은 `appintentsmetadataprocessor`의 툴체인 안내 메시지이며 Swift 컴파일 경고가 아니다.

## 4. 변경 파일

```
Tests/ABPlayerKitTests/ABPictureInPictureSessionTests.swift   (+8 -9, import os 추가 1줄 포함)
```

그 외 파일은 이번 fix1에서 손대지 않았다. 커밋하지 않았다 — working tree에 수정만 남겼다(`git log` 최신 커밋은 여전히 `bdb5cd4`).

## 5. 남은 항목

REVIEW §8의 기기 확인 이월 항목(PiP 실동작, `.continueAudioOnly` 배경 오디오, NowPlaying 잠금화면/커맨드, AirPlay 라우팅)은 이번 fix1의 범위가 아니며 물리 기기 없이는 여전히 확인 불가하다. REVIEW §6의 "인정, 비차단" 판정 5건도 이번 fix1에서 다시 손대지 않았다.
