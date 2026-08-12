# RESULT: 라운드6 트랙 E — PR #5 CI 실패 재진단 (fix2)

담당: Sonnet. 대상: `fillHandleClosesOnRemoveAll`(`ABCacheStoreTests.swift`), `removeAllDuringServiceFinishesWithoutError`(`ABLoadingRequestServicerTests.swift`)의 CI 전용 타임아웃. 커밋 없음 — 작업 트리 변경만.

**결론 먼저**: 프로덕션 코드에서 결함을 찾지 못했다 — 정적 추적으로도, 실행 재현으로도. 대신 두 테스트가 **불필요하게 깊은 비동기 의존 사슬**(각각 별도의 스케줄링이 필요한 unstructured `Task` 2~3개, actor 홉 5개 안팎)을 거쳐야만 첫 동기화 지점에 도달하도록 짜여 있었다는 것을 확인했고, 그 사슬에서 테스트의 목적과 무관한 구간(메타데이터 HEAD 왕복)을 제거해 사슬 길이를 줄였다. 이것이 CI 실패의 **확정 원인**은 아니다 — 로컬에서 재현이 안 되는 한 확정할 방법이 없다. 아래 §4에 이 한계를 명시한다.

---

## 1. 재진단 — 기존 진단("yield 대기가 fill을 굶긴다")이 틀렸거나 불완전한 이유

지난 수정은 `waitUntilHandleCount`가 `Task.yield()`로 바쁜 대기를 하면서 같은 협력 풀의 fill 태스크를 굶긴다고 보고 `Task.sleep(5ms)` 폴링 + 데드라인 5초로 바꿨다. 이 진단은 **`waitUntilHandleCount`가 스스로 만드는 경합**만 다뤘다. 하지만 두 실패 테스트를 코드로 추적한 결과, 첫 대기 지점에 도달하기까지 **테스트의 폴링 루프와 무관하게 이미 여러 개의 별도 스케줄링 지점**이 존재했다 — 즉 설령 폴링 루프가 CPU를 전혀 쓰지 않았더라도, 그 자체로 여러 단계의 비동기 홉이 필요했다.

### 1-1. `fillHandleClosesOnRemoveAll` — 첫 대기(`waitUntilHandleCount(store, equals: 1)`)까지의 경로 (수정 전)

| # | 단계 | 필요한 것 |
|---|---|---|
| 1 | `Task { try? await store.load(...) }` 생성 | 협력 풀이 이 태스크를 처음 실행할 스케줄링 슬롯 |
| 2 | `load()` 진입 | actor 홉 (load는 actor-isolated) |
| 3 | `resolvedMetadata`: 콜드 키라 캐시/인덱스 미스 → 메타데이터 코얼레싱용 별도 `Task {}` 생성 | **별도 unstructured Task** — 협력 풀 슬롯 |
| 4 | 코얼레싱 태스크가 `remoteMetadata` 호출 | actor 홉 |
| 5 | `httpFetcher.data(for:)`(HEAD) 응답 → `finishMetadataRequest` | actor 홉 |
| 6 | `load()`의 `await request.value` 재개 | actor 홉(재획득) |
| 7 | `startFillIfNeeded` → `launchFill` → `httpFetcher.stream(for:)`(동기) → `fills[key] = Task {}` 생성 | **별도 unstructured Task** |
| 8 | `load()`가 `while` 루프 진입, 모든 분기 실패 → `await waitForProgress` | (여기서 `load()`는 정지 — 테스트가 기다리는 `fillHandleCount()`는 **아직도 도달 전**) |
| 9 | fill 태스크가 처음 실행되어 `.response` 소비 → `prepareFill` | actor 홉, **협력 풀 슬롯 필요** |
| 10 | `prepareFill`이 핸들을 염 | — 여기서 비로소 `fillHandleCount() == 1` |

**태스크 3개(`loadTask`, 메타데이터 코얼레싱 태스크, fill 태스크), actor 홉 6곳 이상**이 이 지점까지 필요하다. 이 중 어느 하나라도 CI처럼 협력 풀 스레드가 부족한 환경에서 스케줄링 슬롯을 늦게 받으면 5초를 넘길 수 있다 — 그리고 이 중 **fill 태스크(단계 7·9)만이 테스트가 실제로 검증하려는 것**(진행 중인 fill의 핸들)과 관련이 있다. 나머지(단계 3~6, 메타데이터 코얼레싱)는 이 테스트가 "콜드 키라서" 우연히 딸려온 부수 비용이다.

### 1-2. `removeAllDuringServiceFinishesWithoutError` — 첫 대기(`waitUntil { !store.activeReaderKeys().isEmpty }`)까지의 경로 (수정 전)

`ABLoadingRequestServicer.service`는 **`store.metadata(for:)`를 먼저 완전히 기다린 뒤에만** `store.load(...)`를 호출한다. 즉 "reader가 등록됐다"는 가장 얕아 보이는 체크포인트조차, `store.load`의 `readerRegistry.retain`(진짜 첫 줄, 즉시 실행)에 도달하기 **전에** `store.metadata(for:)`의 메타데이터 코얼레싱 태스크(§1-1의 단계 3~6과 동일한 구조)가 **먼저 완주**해야 한다. 구조적으로 §1-1과 거의 같은 깊이의 의존 사슬이다 — "얕은 체크포인트"라는 이름과 달리 실제로는 그렇지 않았다.

### 1-3. 브리프의 조사 지침 3개 항목 — 확인 결과

1. **첫 대기가 무엇을 기다리는지**: 위 §1-1·1-2에 단계별로 규명했다.
2. **`ABControlledHTTPFetcher`/`ABServicerFakeFetcher`의 `stream(for:)` shim이 `dataReplies` 소비 순서를 어긋나게 하는지**: 코드로 재확인한 결과 **아니다**. 두 테스트 모두 HEAD는 정확히 한 번만 `data(for:)`를 통해 소비되고(`stream(for:)`은 관여하지 않음), `remoteMetadata`의 GET 폴백(있었다면 `stream(for:)`을 경유해 shim과 충돌했을 경로)은 HEAD가 항상 성공하므로 트리거되지 않는다. shim 자체의 로직도 다시 읽었고 락 사용에 이상이 없다.
3. **fix1 §2-1의 게이팅(`mustObserveFillProgressBeforeServing`)**: 두 테스트 모두 콜드 키(기존 prefix 없음)이므로 `hadExistingPrefix == false` → 게이팅은 `false`로 비활성 상태임을 코드로 확인했다. 관여하지 않는다.

---

## 2. 로컬 재현 시도 (실패)

다음을 모두 시도했으나 **단 한 번도 재현되지 않았다**:

- `-only-testing:ABPlayerKitCacheTests` 단독 8회 연속.
- **CI의 `build-and-test`와 동일하게** `-only-testing:` 없이 전체 스킴(`build test`, 모든 타깃 동시 실행) 2회.
- **CI의 `thread-sanitizer`와 동일하게** `-enableThreadSanitizer YES -only-testing:ABPlayerKitTests -only-testing:ABPlayerKitCacheTests` 1회.
- `yes` 프로세스 10개를 백그라운드로 띄워 CPU를 인위적으로 포화시킨(부하 평균 23, CPU 사용률 78%+ sys) 상태에서 캐시 테스트 3회.

모두 그린이었다.

---

## 3. 적용한 수정 — 비동기 의존 사슬 축소 (프로덕션 코드 변경 없음)

두 테스트가 검증하려는 것은 각각 "진행 중인 fill이 열어둔 핸들을 `removeAll`이 닫는다"와 "서비스 도중 purge가 나도 요청이 에러 없이 끝난다"이며, **어느 쪽도 메타데이터가 HEAD로 얻어졌는지 여부와 무관하다**. §1의 경로 분석에서 메타데이터 코얼레싱 태스크(단계 3~6)가 테스트 목적과 무관한 부가 비용임을 확인했으므로, 이를 제거했다:

- **`fillHandleClosesOnRemoveAll`**: `dataReplies: [metadataReply(length: 8)]` 대신 `seed(source:data: Data(), contentLength: 8, ...)`로 크기 0·미완결 엔트리를 인덱스에 직접 심었다. `resolvedMetadata`의 인덱스 빠른 경로가 즉시 히트하므로 HEAD 왕복과 그 코얼레싱 태스크가 통째로 사라진다. `isComplete: false`이므로 `startFillIfNeeded`는 그대로 정상 호출된다.
- **`removeAllDuringServiceFinishesWithoutError`**: 같은 방식의 `seedMetadataOnly(source:contentLength:directory:)` 헬퍼를 신설해 동일하게 적용했다. `dataReplies`에서 HEAD용 첫 항목을 제거했다(강등된 passthrough용 `"network!"` 항목만 남김).

이 변경 후 §1-1의 경로에서 **태스크 3개 → 2개(`loadTask` + fill 태스크만)**, §1-2에서 **별도 코얼레싱 태스크가 완전히 사라져 `serviceTask` 자신의 두 actor 홉만 남는다.** 남은 의존(fill 태스크 자신의 스케줄링)은 테스트가 검증하는 "진행 중인 fill"의 본질이므로 제거할 수 없고 제거해서도 안 된다.

**부가 조치**: `waitUntilHandleCount`의 타임아웃 메시지에 `activeReaderKeys()` 개수를 추가했다(데드라인 자체는 5초로 그대로). 재발 시 "fill 태스크가 아예 스케줄되지 못했다"(reader도 0)와 "거기까진 갔는데 그 뒤에서 멈췄다"(reader는 있음)를 구분할 수 있게 하기 위함이며, 순수 진단 정보 추가이지 데드라인 연장이 아니다.

**하지 않은 것**: 데드라인을 늘리지 않았다(금지 사항). 어느 쪽 테스트도 비활성화하거나 단언을 약화시키지 않았다 — 두 테스트 모두 원래 검증하던 것을 그대로 검증한다(어서션 문자 하나 바뀌지 않았다). 공유 헬퍼 `Tests/ABTestSupport/ABWaitUntil.swift`는 건드리지 않았다(다른 트랙 소관이자 여러 타깃이 공유).

---

## 4. 검증 결과와 한계

### 검증
- `xcodebuild build-for-testing -scheme ABPlayerKitCache -destination 'generic/platform=iOS'` → 경고 0 · 에러 0.
- `-only-testing:ABPlayerKitCacheTests` **8회 연속** 그린.
- 전체 스킴(`build test`, CI의 `build-and-test`와 동일한 무필터 호출) **2회** 그린.
- `-enableThreadSanitizer YES -only-testing:ABPlayerKitTests -only-testing:ABPlayerKitCacheTests`(CI의 `thread-sanitizer`와 동일) **1회** 그린.
- `swiftlint lint --strict`로 변경 파일 2개 린트 — 위반 0건.

### 한계 (정직하게 명시)
- **로컬에서 원래 실패를 한 번도 재현하지 못했다** — 이번 세션의 수정이 CI에서 실제로 통과하는지는 다음 CI 실행에서만 확인 가능하다.
- **툴체인 격차**: CI는 `Xcode_16.4`(Swift 6.0대)를 고정 사용하고 `iPhone 16 Pro` 시뮬레이터를 쓴다. 이 세션에서 사용 가능한 것은 `Xcode 26.2`(Swift 6.2대 추정)와 `iPhone 17 Pro` 시뮬레이터뿐이며, 브리프의 "새로 부팅·생성 금지" 제약과 세션 시간 내에 별도 Xcode 버전을 설치하는 것은 범위 밖이라 판단해 시도하지 않았다. 두 버전 간 Swift Concurrency 협력 풀의 스케줄링/공정성 동작에 알려진 차이가 있을 수 있으나 이 세션에서 직접 검증할 수 없었다.
- 따라서 §3의 조치가 **원인을 제거했다**고 확정할 수 없다 — **원인일 가능성이 높은 요인(불필요한 태스크 홉)을 하나 줄였다**는 것이 정확한 표현이다. 남아 있는 의존(fill 태스크 자신의 스케줄링)이 CI에서 여전히 5초를 넘긴다면, 이번 조치만으로는 재발할 수 있다.

---

## 5. 다음 실패 시 권고

이번 조치 이후에도 CI에서 재발한다면:
1. `fillHandleClosesOnRemoveAll`의 실패 메시지에 이제 `activeReaderKeys` 카운트가 함께 찍히므로, "fill 태스크가 아예 시작도 못 했다"(0)인지 "시작은 했는데 핸들을 여는 데까지 못 갔다"(1 이상)인지 1차 구분이 가능하다.
2. 후자라면, 이 저장소의 protocol/production 설계(fill을 unstructured `Task`로 백그라운드 실행하는 것 자체)가 CI 환경에서 근본적으로 5초 안에 첫 스케줄링을 보장하지 못한다는 뜻이므로, 데드라인 자체보다 **CI 잡의 병렬성 설정**(`-parallel-testing-enabled`, 동시 시뮬레이터 클론 수)이나 **협력 풀 크기**(CI 러너의 실제 vCPU 수) 쪽을 조사하는 것이 다음 단계로 적절해 보인다 — 이는 트랙 E의 범위(캐시 로직)를 벗어나 CI 트랙(CI-2/CI-4) 또는 오케스트레이터가 다룰 문제일 가능성이 크다.
3. `Xcode_16.4`를 확보할 수 있다면(별도 승인 하에), 동일 툴체인으로 로컬 재현을 재시도하는 것이 가장 확실한 다음 수순이다.

## 6. 변경 파일

- `Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift` — `fillHandleClosesOnRemoveAll`의 메타데이터 시딩 전환, `waitUntilHandleCount` 진단 메시지 보강.
- `Tests/ABPlayerKitCacheTests/ABLoadingRequestServicerTests.swift` — `removeAllDuringServiceFinishesWithoutError`의 메타데이터 시딩 전환, `seedMetadataOnly` 헬퍼 신설.

프로덕션 코드(`Sources/ABPlayerKitCache/`) 변경 없음 — 결함을 찾지 못했으므로 건드리지 않았다.
