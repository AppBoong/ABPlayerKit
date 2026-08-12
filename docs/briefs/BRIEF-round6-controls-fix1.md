# BRIEF: 트랙 C 후속 작업 (fix1)

C-8 게이트는 **APPROVE**를 냈다(차단 지적 0건). 당신의 구현은 통과했다. 이 브리프는 게이트가 남긴 **비차단 항목 2건**을 닫기 위한 후속 작업이다.

트랙 C는 병합 순서상 마지막(F → G → C)이고 지금 트랙 G의 게이트를 기다리는 중이라, 이 작업은 **일정에 영향을 주지 않는다.** 서두르지 말고 정확히 하라.

먼저 `docs/briefs/REVIEW-round6-controls.md`를 읽어라 — 게이트의 판정 근거와 두 항목의 상세가 거기 있다.

---

## 작업 1 — VoiceOver 조정 스트리크의 배지 델타 (게이트 §5 비차단 1번)

### 확인된 결함

게이트가 코드 추적으로 실재를 확인했다. `.accessibilityAdjusted` 분기(`ABControlsPresenter.swift:181-195`)가 `currentPlaybackTime`을 **동기적으로 먼저** 전진시킨 뒤 `.send(.skip(by:))`를 반환하는데, `handleSeekTargetChanged`(`ABPlayerControlsView.swift:623-624`)의 앵커 스냅샷이 그 **전진된 값**을 잡는다.

결과: `currentTime=100s`, `skipInterval=10s`에서 VoiceOver로 순방향 2연타 시 실제 위치는 120s로 가지만 배지는 "+0s" → "+10s"를 표시한다(실제 누적 +20s). 매 탭의 배지 델타가 실제보다 정확히 한 `skipInterval`만큼 적다.

이것은 설계 §4 C-2w의 서면 완료 기준("VoiceOver 조정 2연타 후 표시 시간 == 프리젠터 계산값 **== 배지 델타**")을 배지 델타 부분에서 충족하지 못한 것이다. 현재 테스트 2건(`ABPlayerControlsSeekFeedbackTests.swift:107,120`)은 `displayedElapsedText`만 단언하고 배지 델타는 단언하지 않는다.

### 요구사항

1. **배지 델타가 실제 누적 이동량과 일치하도록 고쳐라.** 게이트의 권고는 앵커 스냅샷을 `.accessibilityAdjusted`의 낙관적 렌더 **이전** 값으로 캡처하는 것이다(뷰 쪽 호출 순서 조정, 또는 프리젠터가 조정 전 시각을 effect에 함께 실어 보내는 방식). **어느 쪽을 택할지는 당신이 판단하라** — 다만 아래 제약을 지켜야 한다.
2. **설계 §5.1의 I-C9를 깨지 마라**: "앵커는 스트리크당 1회만 스냅샷하고, Controls는 자체 누적기를 두지 않는다." 스킵 누적의 진실원은 코어의 `pendingSeekTime`이다. 배지 델타를 Controls가 자체적으로 더해 만들어 내는 방식은 **금지**다.
3. **스킵 버튼·더블탭 경로의 현재 동작을 바꾸지 마라.** 이 두 경로는 낙관적 사전 렌더가 없어 지금 정상이다. 회귀가 나면 안 된다.
4. **배지 델타를 단언하는 테스트를 추가하라.** 위 실패 시나리오(VoiceOver 2연타 → 배지 "+20s")를 재현하는 형태여야 한다. 스킵 버튼·더블탭 경로에도 델타 단언이 있는지 확인하고, 없으면 함께 추가하라 — 세 경로가 같은 불변식을 공유한다.

수정 실패 시나리오가 명확하지 않거나, 고치는 것이 I-C9를 깨지 않고는 불가능하다고 판단되면 **고치지 말고 그 분석을 보고하라.** 잘못된 수정보다 정직한 보고가 낫다.

---

## 작업 2 — D-10(Style `Sendable`화) 재시도

당신은 이것을 이월했고, 사유(로컬에 Xcode 16.4 부재)는 오케스트레이터가 독립 확인해 타당하다고 인정했다. 게이트도 참고 데이터를 확보하려 했으나 권한 제약으로 실패했다.

**새로운 판단**: 이 트랙의 PR CI가 **정확히 Xcode 16.4로 돌아간다.** 따라서 CI가 이 질문의 최종 심판이다. 로컬에서 확정할 수 없다는 이유로 이월하는 대신, **붙여서 PR CI에 물어보자.** 실패하면 그 커밋만 되돌리면 된다 — 되돌리기 어려운 리스크가 아니다.

### 요구사항

1. 설계 §5.2가 지정한 5개 타입(`ABPlayerControlsStyle`, `ABControlIcon`, `ABControlsBackgroundStyle`, `ABTrackCornerRadius`, `ABRateLabelStyle`)에 `Sendable`을 부착하라.
2. `@unchecked Sendable`은 **금지**다(설계 §0). 순수 `Sendable`로 성립하지 않으면 그 사실 자체가 답이다 — 부착하지 말고 보고하라.
3. 설계 §5.2가 D-10에 딸린 후속으로 지정한 것(스타일 프리셋 `default`/`minimal`/`tinted`의 `@MainActor` 격리 제거)도 성립하면 함께 하라. 성립하지 않으면 `Sendable` 부착만 하고 사유를 보고하라.
4. **작업 1과 분리해서 진행하라.** 이 변경이 CI에서 거부되면 이 부분만 들어내야 하므로, 작업 1의 수정과 파일·논리가 뒤엉키지 않게 하라.
5. CHANGELOG에 `### Changed` 항목을 추가하라(설계 §7이 요구한 Sendable 관련 항목). 성립하지 않아 부착하지 못했다면 추가하지 마라.

**로컬 Xcode 26.2에서 컴파일되는 것은 필요조건일 뿐 충분조건이 아니다**(CI는 16.4, SDK가 다르면 `UIColor`/`UIFont`/`UIImage`의 `NS_SWIFT_SENDABLE` 노출이 다를 수 있다). 로컬 성공을 "확정"으로 보고하지 마라 — "26.2에서는 컴파일됨, 16.4는 CI가 판정"이라고 쓰라.

---

## 검증 (두 작업 모두 끝난 뒤)

**전체 스킴 3회 연속 그린.** `-only-testing` 결과는 근거로 인정하지 않는다.

```bash
cd /Users/jymac/orca/workspaces/ABPlayerKit/round6-controls
DEST='platform=iOS Simulator,id=60DA735B-87EC-4159-9BE3-EF981A127FAF'
for i in 1 2 3; do
  echo "=== RUN $i ==="
  xcodebuild -scheme ABPlayerKit-Package -destination "$DEST" -derivedDataPath .dd \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    EXTRACT_APP_INTENTS_METADATA=NO build test || { echo "RUN $i FAILED"; break; }
done
```

기존 641건이 **전부 그대로 통과**해야 한다(신규 추가분만큼 늘어난 수치로). 한 건이라도 줄거나 실패하면 그것은 회귀다.

docbuild / 데모 빌드 / SwiftLint도 재실행하라. 위생 규칙(신규 주석 ID 인용 금지, `@unchecked Sendable`·`MainActor.assumeIsolated`·신규 `deprecated` 0건)은 그대로 적용된다.

**커밋하지 마라.** 파일 경계도 그대로다 — `Sources/ABPlayerKitControls/SwiftUI/` 4파일 diff 0줄, Controls 밖 diff 0줄.

---

## 완료 보고

`docs/briefs/RESULT-round6-controls-fix1.md`를 새로 만들어 담아라. 이 파일의 생성이 완료 신호다.

```markdown
# RESULT: 트랙 C fix1

## 1. 작업 1 — VoiceOver 배지 델타
(택한 접근과 이유 / I-C9를 어떻게 지켰는지 / 추가한 테스트 / 스킵·더블탭 경로 무회귀 확인)
(고치지 않기로 했다면 그 분석)

## 2. 작업 2 — D-10 Sendable
(5개 타입 각각 부착 성공/실패 / 프리셋 @MainActor 제거 여부 / Xcode 26.2 컴파일 결과)
(부착하지 못했다면 어느 타입의 무엇이 막았는지 구체적으로)

## 3. 검증
(전체 스킴 3회: 회차별 테스트 수·실패 수 / docbuild / 데모 / SwiftLint)

## 4. 회귀 여부
(기존 641건이 전부 통과하는지)

## 5. 파일 경계
(수정한 파일 목록)
```
