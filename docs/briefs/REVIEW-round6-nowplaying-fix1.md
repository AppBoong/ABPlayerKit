# REVIEW: 라운드6 트랙 G 게이트 재판정 (G-5, fix1)

## 판정
**APPROVE**

`REVIEW-round6-nowplaying.md` §7의 유일한 차단 사유(`@unchecked Sendable`)가 해소됐음을 직접 확인했다. 델타 중심 재검증이므로 §5·§6(이미 "인정, 비차단"으로 판정된 항목)과 §8(기기 확인 이월 항목)은 다시 열지 않았다 — RESULT-fix1도 그 항목들을 손대지 않았다고 밝혔고, 파일 경계 확인으로 그 주장이 사실임을 확인했다.

---

## 1. 위생 재스캔 — 직접 실행 (RESULT의 첨부 출력을 근거로 삼지 않음)

지난 게이트에서 "재스캔 결과 출력 없음"이라는 동일한 주장이 거짓이었던 전례가 있으므로, RESULT-fix1 §3에 붙은 출력을 그대로 믿지 않고 세 커맨드를 전부 이 세션에서 다시 실행했다.

```bash
$ git diff origin/main -U0 -- Sources Tests | grep '^+' | grep -nE '@unchecked Sendable|MainActor\.assumeIsolated|@available\(\*, deprecated'
(빈 출력, exit=1)

$ git diff origin/main -U0 -- Sources Tests | grep '^+' | grep -nE 'nonisolated\(unsafe\)'
(빈 출력, exit=1)

$ git diff origin/main -U0 -- Sources Tests Examples README.md README.ko.md CHANGELOG.md Package.swift \
    | grep '^+' | grep -nE '(([A-Z]-[0-9]+w?)|(I-G[0-9])|(WP[0-9])|(round[0-9])|(MJ-[0-9])|(§[0-9]))'
(빈 출력, exit=1)
```

세 스캔 모두 매치 0건을 이 세션에서 직접 재현했다. 추가로 리포 전체(`.dd`/`.build` 제외) 충돌 마커(`<<<<<<<`/`=======`/`>>>>>>>`) 재귀 검색도 0건 — fixup 리베이스가 충돌 잔재를 남기지 않았음을 확인했다.

`Tests/ABPlayerKitTests/ABPictureInPictureSessionTests.swift`를 전체 열람해 `ObservationFlag`가 실제로 다음과 같이 바뀌었음을 확인했다:

```swift
private final class ObservationFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    func markFired() { state.withLock { $0 = true } }
    var hasFired: Bool { state.withLock { $0 } }
}
```

`@unchecked` 키워드가 없고, 컴파일러가 검사하는 `Sendable` 준수다. `import os`가 파일 상단에 추가된 것도 확인했다.

---

## 2. 전체 스킴 3회 직접 재실행 — 부팅된 시뮬레이터, 신규 부팅 없음

`.dd`를 실행 전 삭제해 클린 상태에서, 브리프 §2.1과 동일한 커맨드를 이 세션에서 직접 3회 실행했다(로그를 파일로 전량 저장해 이전 게이트에서 `tail -80`으로 잘려 스위트 수를 놓쳤던 실수를 반복하지 않았다).

| 회차 | 결과 | Cache | Controls | Metrics | NowPlaying | 코어 | 합계 | 실패 |
|---|---|---|---|---|---|---|---|---|
| 1 | ✅ | 72 | 200 | 49 | 31 | 269 | **621** | 0 |
| 2 | ✅ | 72 | 200 | 49 | 31 | 269 | **621** | 0 |
| 3 | ✅ | 72 | 200 | 49 | 31 | 269 | **621** | 0 |

3회 전부 `xcodebuild` exit code 0, 스위트별 수까지 완전히 동일 — RESULT-fix1이 보고한 수치와 정확히 일치하며, fixup 리베이스로 커밋 히스토리가 재작성된 뒤에도 트리가 온전함을 실행으로 확인했다.

수정 대상이었던 `"Mirror discipline: reasserting the same isPossible/isActive value does not re-fire Observation"` 테스트와 그 상위 스위트 `"ABPictureInPictureSession binds to at most one view and mirrors state without redundant notifications"`가 3회 모두 개별적으로 통과 로그에 나타남을 로그에서 직접 grep으로 확인했다 — 락 프리미티브 교체가 이 테스트를 깨지 않았다.

빌드 경고: 1회차에 `appintentsmetadataprocessor`의 `No AppIntents.framework dependency found` 툴체인 안내 5건(clean 빌드에서 흔한 비-Swift 경고) 외 0건. `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`로 3회 모두 빌드가 성공했으므로 Swift 컴파일 경고는 0건임이 보장된다.

검증 종료 후 `.dd`는 다시 삭제했다.

---

## 3. 동기화 프리미티브 교체가 테스트 불변식을 약화시켰는가

**약화하지 않았다.**

- `OSAllocatedUnfairLock<Bool>`은 그 자체가 `Sendable`이므로(`State: Sendable`일 때), `let state`로 감싼 `ObservationFlag`는 컴파일러가 실제로 검사하는 `Sendable`이 된다 — `@unchecked`로 컴파일러 검사를 우회하던 것과 달리, 이번엔 검사를 통과한다.
- `markFired()`/`hasFired`의 관측 가능한 동작(스레드-안전 쓰기 1회 후 `true` 고정, 스레드-안전 읽기)은 `NSLock` 버전과 동일하다 — `withLock` 클로저 안에서 값을 읽거나 쓰는 것은 이전의 `lock()`/`unlock()` 쌍과 임계구역 범위가 같다.
- 이 헬퍼가 지키는 실제 불변식(`sameValueReassignmentDoesNotRefireObservation` — 동일 값 재대입이 `withObservationTracking`의 `onChange`를 재발화하지 않음)의 테스트 본문·`#expect` 단언은 `git diff`로 직접 대조한 결과 한 글자도 바뀌지 않았다.
- `Mutex`(iOS 18+)를 쓰지 않고 `OSAllocatedUnfairLock`(iOS 16+)을 택한 근거도 확인했다: `Package.swift:8`이 `.iOS(.v17)`을 최소 배포 대상으로 선언하고 있어, `OSAllocatedUnfairLock`은 이 조건을 만족하지만 `Mutex`는 이 패키지에서 컴파일조차 되지 않았을 것이다. `actor` 기각 사유(`hasFired`가 `async`가 되어 "재발화하지 않았다"를 동기적으로 즉시 단언하는 현재 테스트 형태와 충돌)도 타당하다.

---

## 4. 변경 범위 — `git diff`로 직접 확인

```
git diff origin/main --stat -- Sources Tests
```

이전 게이트(REQUEST-CHANGES 판정 시점)의 diffstat과 파일별 줄 수를 라인 단위로 대조한 결과, **`Tests/ABPlayerKitTests/ABPictureInPictureSessionTests.swift` 한 파일만 156줄로 바뀌었고(이전 157줄, 순net -1로 RESULT-fix1의 "+8 -9" 보고와 일치)**, 그 외 32개 파일은 전부 이전과 바이트 단위로 동일한 변경 줄 수를 유지했다. `Sources/`에는 이번 fix1로 인한 변경이 전혀 없다 — 프로덕션 로직 무영향이라는 RESULT-fix1의 주장과 일치한다.

fixup이 원래 `feat(core): expose picture in picture as a bindable session` 커밋(현재 해시 `2341bf1`)에 흡수됐다는 사실도 `git log`로 확인했고, 그 뒤에 게이트 산출물(BRIEF/RESULT/REVIEW 3종 + 이번 게이트의 BRIEF)을 담은 문서 커밋(`9bc64c6`) 1개가 이어졌다. 충돌 마커·중복·누락 없음(§1의 재스캔이 이를 포함해 확인).

---

## 5. 재검증하지 않은 항목 (의도적으로, 델타 범위 밖)

- `REVIEW-round6-nowplaying.md` §5(리베이스 정합성)·§6(설계 이탈 5건)·§8(기기 확인 이월)은 이번 fix1이 건드리지 않았고, §4의 diffstat 대조로 그 파일들이 이전 게이트 시점과 완전히 동일함을 확인했으므로 재검증할 근거가 없다.
- docbuild·데모 빌드는 이번 fix1이 프로덕션 코드를 건드리지 않았으므로(§4) 재실행하지 않았다 — 테스트 타깃만 재빌드되며, 이는 §2의 `build test` 3회 실행에 이미 포함되어 있다.

---

## 6. 결론

차단 사유였던 `@unchecked Sendable`이 실제로 제거됐고(§1), 대체 프리미티브가 이 패키지의 최소 배포 대상(iOS 17)과 호환되며(§3), 교체가 테스트의 관측 가능한 동작이나 단언을 바꾸지 않았고(§3), 변경 범위가 정확히 그 테스트 파일 1개로 국한됐으며(§4), fixup 리베이스 이후에도 전체 스킴이 3회 연속 621건 무결로 그린임을 직접 실행으로 확인했다(§2). **APPROVE.**
