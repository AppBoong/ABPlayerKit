# BRIEF: 라운드6 트랙 E — PR #5 CI 실패 조사 (fix2)

PR #5의 `build-and-test`와 `thread-sanitizer`가 **같은 테스트 2건**으로 실패한다. 로컬에서는 반복 실행해도 재현되지 않는다(게이트가 5회, 구현자가 8회, 오케스트레이터가 4회 그린 확인).

## 관측 사실

두 잡 모두 동일:

```
✘ "removeAll while a fill is in flight closes its writer handle"
   ABCacheStoreTests.swift:1481: Caught error: ABWaitUntilTimedOut()
   (:1498 에서도 Issue recorded)
✘ "A store purge mid-service (removeAll) finishes the loading request without an error"
   ABLoadingRequestServicerTests.swift:268: Caught error: ABWaitUntilTimedOut()
   (:289 에서도 Issue recorded)
```

두 테스트 모두 **이번 라운드에 추가된 것**이고, 둘 다 `removeAll()`과 진행 중인 fill의 상호작용을 검증한다.

이전 라운드에서 이미 한 번 고쳤다: `waitUntilHandleCount` 헬퍼가 `Task.yield()` 바쁜 대기라 같은 협력 풀의 fill을 굶긴다고 보고 `Task.sleep(5ms)` 폴링 + 데드라인 5초로 바꿨다. **그 수정 이후에도 여전히 실패한다.** 즉 원인 진단이 틀렸거나 불완전하다.

## 조사 지침

1. **첫 대기가 무엇을 기다리는지부터 확정하라.** `ABCacheStoreTests:1481`의 실패는 `removeAll()` 호출 **이전**의
   `waitUntilHandleCount(store, equals: 1)`이다. 즉 fill이 5초 안에 writer 핸들조차 열지 못했다.
   `load()` 호출부터 `prepareFill`이 핸들을 여는 지점까지의 경로를 따라가며, CI처럼 자원이 부족할 때
   **어느 단계에서 멈출 수 있는지** 구체적으로 규명하라.
2. **`ABControlledHTTPFetcher`의 `stream(for:)` shim을 의심하라.** E-4w에서 "큐가 고갈되면 다음 `dataReplies` 항목을
   스트림 이벤트로 변환"하는 shim을 추가했다. 메타데이터 해석과 fill이 같은 `dataReplies` 큐를 소비할 때
   소비 순서가 어긋나면 fill이 응답 이벤트를 영원히 받지 못할 수 있다. 이것이 타이밍에 따라 갈리는지 확인하라.
3. **fix1 §2-1의 게이팅(`mustObserveFillProgressBeforeServing`)이 관여하는지** 확인하라. 이 두 테스트는 기존 prefix가
   없으므로 게이팅 대상이 아니어야 하는데, 실제로 그런지 코드로 확인하라.
4. 로컬 재현이 안 되면 **테스트에 진단을 심고 CI로 1회 반복**하는 것도 정당한 방법이다(무엇을 기다리다 멈췄는지
   `Issue.record`로 남기는 식). 추측으로 고치지 말 것.

## 금지 사항

- 데드라인을 더 늘리는 방식으로 덮지 말 것. 이미 2초 → 5초로 한 번 늘렸고 실패는 그대로다.
- 실패하는 테스트를 비활성화하거나 단언을 약화시키지 말 것. 이 두 테스트는 트랙 E의 핵심 기능(E-3w 강등)을 검증한다.
- 프로덕션 코드에 실제 결함이 있다면 그것을 고쳐라 — 테스트만 고쳐 통과시키지 말 것.

## 환경

부팅된 시뮬레이터 재사용(iPhone 17 Pro, UDID `55A3A4F3-3F02-43E6-9B23-116BD15D3345`). 새로 부팅·생성 금지.
로컬 검증은 전체 스킴으로 하되, 로컬이 그린이어도 그것만으로 해결됐다고 판단하지 말 것 — 지난 수정이 그렇게 실패했다.

## 산출물

`docs/briefs/RESULT-round6-cache-fix2.md` — 확정 원인(추측이면 추측이라고 명시), 적용한 수정, 검증 결과,
그리고 로컬에서 재현하지 못했다면 그 한계를 명시. **커밋 금지.**
