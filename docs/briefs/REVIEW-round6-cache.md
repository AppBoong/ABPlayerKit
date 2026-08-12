# REVIEW: 라운드6 트랙 E 최종 게이트 (E-6) — 캐시 무결성

리뷰어: Sonnet (E-6 게이트 역할 대행, 브리프상 Opus 담당 명시이나 모델만 교체). 대상: `round6/cache` 워크트리의 미커밋 작업 트리 diff 전체.
입력: `DESIGN-round6-cache.md`(승인 설계), `RESULT-round6-cache.md`(구현 자기보고), `ROADMAP-round6.md` §0·§6, `REVIEW-round6-portfolio-audit.md` §E.
방법: `git diff`/`git status` 전수 정독(자동화 스크립트 아님, 라인 단위 확인), `git log -p`로 사전 존재 코드와 신규 추가분 구분, `xcodebuild build-for-testing -scheme ABPlayerKitCache -destination 'generic/platform=iOS Simulator'` 재실행으로 RESULT의 빌드 성공 주장을 독립 재현. 시뮬레이터 미부팅 확인(`xcrun simctl list devices booted` → 전부 미부팅) 후 새 부팅은 금지 사항이므로 미실행 — 정적 리뷰로 판정.

---

## 1. 빌드 재검증

`xcodebuild build-for-testing -scheme ABPlayerKitCache -destination 'generic/platform=iOS Simulator'` 재실행 결과: **`TEST BUILD SUCCEEDED`**, `error:`/`warning:` 매치 0건. RESULT의 빌드 성공 주장을 독립적으로 재확인함. 테스트 스위트 실행 자체는 시뮬레이터 미부팅으로 이번에도 수행 불가(정책상 금지) — §7 잔여 리스크에 기재.

## 2. 설계 §6 무회귀 가드 표 — 불변식 9개 코드 레벨 검증

| # | 불변식 | 위치 | 검증 결과 |
|---|---|---|---|
| 1 | waiter 이중 resume 금지, `ABCacheProgressWaiter` 일체 수정 금지 | `ABCacheStore.swift:53-85`(구) | **PASS** — `git diff`에서 `ABCacheProgressWaiter`/`ABCacheProgressWaiterRegistry` 정의부는 단 한 줄도 변경되지 않음(신규 `ABCacheRevalidationRegistry`가 그 아래 별도 블록으로 추가됐을 뿐). 새 코드가 `resolve()`를 직접 호출하는 지점 없음(grep 확인) |
| 2 | 취소된 waiter의 즉시 제거(WP4) | `waitForProgress`/`resolveAll`/`remove` | **PASS** — 해당 함수들 자체는 diff에 없음. `resumeWaiters`/`resumeAllWaiters` 호출부는 신규 호출 추가(예: `removeAll`의 기존 위치)만 있고 로직 변경 없음 |
| 3 | UUID 동일성 기반 waiter 제거 | `ABCacheProgressWaiterRegistry` | **PASS** — 레지스트리 API 변경 없음(위와 동일 근거) |
| 4 | fill GET 코얼레싱의 동기 구간에 suspension point 미추가 | `startFillIfNeeded`/`launchFill` | **PASS** — `startFillIfNeeded`는 여전히 `async`가 아닌 동기 함수이고 `guard fills[key] == nil else { return }` 직후 `launchFill(...)`을 즉시(await 없이) 호출한다. `launchFill` 자체도 동기 함수이며 `httpFetcher.stream(for:)`은 `AsyncThrowingStream`을 즉시 반환하는 비-async 함수(`ABHTTPFetching.swift:49`, 이번 diff에서 미변경)이므로 `fills[key] = Task {...}` 대입까지 실제 suspension point가 없다. `prepareFill`의 206 불일치 분기가 재호출하는 `launchFill(source:key:metadata:offset:0)`도 동일하게 동기이며, 그 직후 `throw FillSuperseded()`까지 await이 없다 — 재시작 경로에서도 이 불변식이 유지된다 |
| 5 | HEAD 코얼레싱(M5), holder 설치가 첫 suspension point 이전 | `resolvedMetadata` | **PASS** — 신규 `claimPending(key)` 호출은 동기(`NSLock` 기반)이고, 설계 §2.1의 4단계 순서(`claimPending` → 인덱스/LRU 빠른 경로 → `pendingMetadataRequests` 코얼레싱 → holder 설치)가 코드에 정확히 그 순서로 고정되어 있다. holder(`PendingMetadataRequest`) 설치와 `Task` 생성 사이에 await 없음(기존 그대로) |
| 6 | holder 식별자 기반 정리(N12/mn-4), `finishMetadataRequest`의 `id` 비교 로직 수정 금지 | `finishMetadataRequest` | **PASS** — 함수 본문이 diff에 전혀 나타나지 않음(호출부만 그대로 재사용). 재검증 결과도 동일 함수를 경유해 캐싱됨 |
| 7 | reader 등록 해제 defer 범위 | `load(_:range:)` | **PASS** — `readerRegistry.retain(key)` 직후 `defer { readerRegistry.release(key) }`가 함수 최상단에 위치, 신규 추가된 조기 반환(purge 세대 불일치 분기 등) 전부 이 defer 범위 안에 있음(단일 함수 스코프이므로 구조적으로 보장) |
| 8 | 활성 reader/진행 중 fill의 eviction 제외 집합에 `fillHandles` 미개입 | `evictIfNeeded` | **PASS** — `excludedKeys`는 여전히 `readerRegistry.activeKeys ∪ fills.keys ∪ {protectedKey}`로만 계산됨(`ABCacheStore.swift:1147-1153`). `fillHandles`는 이 계산에 전혀 참조되지 않음 |
| 9 | 스토어 해제 시 waiter 정리, `deinit` 수정 금지 | `deinit` | **PASS** — `deinit` 관련 diff 없음 |

**결론: 9개 불변식 모두 코드 레벨에서 무회귀 확인.**

## 3. E-1w 재개 검증 4분기 정확성

`prepareFill`의 상태별 분기(설계 §1.2 표)를 코드와 대조:

- **200 폴백(원본이 `If-Range` 불일치로 전체 바디 반환)**: `priorSize > 0`이면 `truncateFile` 후 `entry.size = 0`으로 리셋하고 **같은 스트림을 계속 소비**(추가 fill 재시작 없음) — 설계와 일치. 신규 테스트 `ifRangeMismatchTruncatesAndRefillsFromScratch`가 실제로 이 경로를 실행해 최종 바이트가 전량 신버전임을 검증(구·신 혼합 없음).
- **206 정합**: `start == priorSize && !totalMismatch`이면 기존 append 경로로 낙하 — 변경 없음.
- **206 불일치(오프셋/길이)**: `truncateFile` → `entry.size = 0` → `index.upsert`/`markIndexDirty` → **동기** `launchFill(offset: 0)` 재설치 → `throw FillSuperseded()`. `launchFill`이 `fills[key]`를 새 Task로 교체하는 시점과 `throw` 사이에 await이 없으므로(§2 불변식4 참조), 원본 태스크의 `catch is FillSuperseded`가 실행될 때는 이미 새 Task가 `fills[key]`에 설치된 뒤이고, 원본 태스크는 `failFill`/`completeFill` 어느 쪽도 호출하지 않아 새로 설치된 `fills[key]`를 지우지 않는다. `fillResponses[key]`/`fillHandles[key]`도 원본 태스크가 이 실패 시점까지 아직 설치하지 않은 상태(둘 다 분기 통과 후에야 설치됨)라 정리할 게 없다 — **재시작 경로가 waiter/취소 시맨틱을 깨지 않음을 코드 레벨로 확인**. 신규 테스트 `noValidatorContentRangeStartMismatchTruncatesAndRefetches`/`totalLengthChangeTruncatesAndRefetches`가 각각 오프셋 불일치·총길이 불일치를 검증.
- **그 외 상태 코드**: `default: throw StoreError.invalidResponse` — 기존 동작 보존.

`resolvedMetadata`의 4단계 순서 고정도 §2 표 5행에서 확인 완료.

## 4. E-3w 세대 카운터

- `purgeGeneration`은 `remove`/`removeAll` **동기 함수** 내부에서 `resumeAllWaiters()`/waiter 재개보다 앞서 증가(`remove`: `:113`, `removeAll`: `:124` 상당) — 설계 그대로.
- `load()`의 강등 분기는 `fillErrors` 검사(§ `fills[key] == nil, let error = fillErrors[key]`)보다 **앞**에 배치되어 있다 — 설계·브리프 요구사항 충족.
- 기존 `:786`(non-2xx → `.invalidResponse`) 계열 에러 경로는 `index.entries[key] == nil`이 아니라 `fillErrors[key]`가 채워진 상태에서 도달하므로 세대 분기와 겹치지 않고 바이트 단위로 보존됨 — 신규 테스트가 이 무회귀를 소스 diff상 보장(§6 참조).

**다만 아래 §6-2에서 이 세대 카운터의 스코프(전역 vs 키별)에 대한 잔여 리스크를 별도로 보고한다.**

## 5. E-4w `boundedData`

- `.response` 이벤트에서 2xx 검증 후 skip 예산 결정(200→`lowerBound`, 206→0)은 설계 그대로.
- `for try await` 루프를 `break eventLoop`로 조기 종료하면 `AsyncThrowingStream`의 이터레이터가 해제되어 `onTermination`(`ABHTTPFetching.swift:86-89`, 이번 diff에서 미변경 확인)이 실행되고 내부 `URLSessionDataTask`가 `cancel()`된다 — 원본 코드를 재확인해 이 취소 경로 주장이 실제로 성립함을 확인.
- 8MB 상한(`unboundedPassthroughLimit`)은 `count == nil`일 때만 적용되고, `collected.count`가 `collectLimit`을 절대 초과하지 않도록 `remainingCapacity`로 정확히 클램프한 뒤에 상한 도달 시 `.entryTooLarge`를 던짐 — 정확.
- **픽스처 shim 무결성**: `git diff -- Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift`에서 `^-`(삭제) 라인은 diff 헤더를 빼면 **단 1줄**(`ABControlledHTTPFetcher.stream(for:)`의 리팩터링 중 들여쓰기 재구성 1줄)뿐이며, 그 1줄도 기존 `@Test`/`#expect` 어서션이 아니라 shim 자체의 구조 변경이다. 기존 테스트 어서션은 **한 글자도 삭제되지 않음** — RESULT의 "무수정" 주장을 diff 레벨에서 직접 재확인.

## 6. E-5w `ABLoadingRequestServicer` 추출

- `ABResourceLoaderDelegate.swift`의 옛 Task 본문(계약정보 설정 → dataRequest 루프 → `finishLoading`/`finishLoading(with:)` → 취소 가드)을 `ABLoadingRequestServicer.service(_:source:store:)`와 라인 단위로 대조한 결과 **로직 동일**(변수명·분기·가드 순서 100% 일치, 순수 이동). `LoadingRequestBox`의 격리 근거 주석이 새 어댑터 `ABAVLoadingRequestAdapter`로 이동한 것도 확인.
- `beginAssetSession(for:)` 호출은 `shouldWaitForLoadingOfRequestedResource`에서 **스폰된 `Task` 밖**, once-플래그(`hasBegunSession`, `NSLock` 보호) 체크 직후 동기적으로 실행됨 — 설계 요구사항(첫 로딩 요청이 재검증 등록 이전에 스테일 메타데이터를 읽는 인터리빙 방지) 충족.
- 신규 `ABLoadingRequestServicerTests.swift` 7개 테스트가 설계 §5 E-5w 테스트 목록(contentInformation/미상 길이/청크 분할/`requestsAllDataToEndOfResource`/스토어 에러/취소/`removeAll` 중 서비스 완주)을 전부 커버.

## 7. `fillHandles` 불변식

- `fillResponses[key] != nil ⟺ fillHandles[key] != nil`은 정상 경로(성공적인 `prepareFill` 완주)에서 성립. 해제는 `completeFill`/`failFill`/`cancelFill`/`removeAll`(전 키 순회) **네 곳**으로 일원화되어 있고, 전부 `closeFillHandle(for:)`를 경유(단, `removeAll`은 자체 루프로 별도 처리 — 기능적으로 동일).
- **아주 좁은 예외**: `prepareFill`에서 `fillResponses[key] = response` 대입 직후 `FileHandle(forWritingTo:)` 생성자가 던지면(파일시스템 레벨 드문 실패), 두 딕셔너리가 짧게 불일치하는 순간이 이론상 존재한다. 그러나 이 구간은 액터의 단일 동기 실행(await 없음) 안에서 일어나고, 예외가 곧바로 `launchFill`의 `catch { failFill(...) }`로 전파되어 `fillResponses[key] = nil`을 포함한 정리가 뒤따르므로 관측 가능한 부작용은 극히 좁고(다음 Task 재개 틈 사이 한 번), append 쪽도 `fillHandles[key]`가 nil이면 안전하게 `.invalidResponse`를 던진다. 데이터 손상이나 크래시로 이어지지 않으므로 별도 finding으로 격상하지 않음(참고 기록만 남김).
- eviction 제외 집합에 `fillHandles`가 개입하지 않음은 §2-8에서 확인 완료.

## 8. 공개 API / 주석 위생 / 문서

- **공개 API diff 0건** 재확인: `git diff -- Sources/ | grep '\bpublic\b'`의 매치는 전부 산문 언급(`public.data` UTI 문자열, "public initializer" 주석)이며 `public` 키워드 신규 선언 없음.
- **DocC 정확성**: "Known constraints" 절이 설계 §7의 5개 항목(재개 검증/재검증/삭제 의미론/LRU 이월/액터 내 I/O 이월)을 정확히 반영해 추가됨 — 양호.
- **CHANGELOG — 미반영 (finding, 아래 §9-1)**.
- **주석 위생 — 리뷰 ID 인용 1건 발견 (finding, 아래 §9-2)**.

## 9. Findings

### 9-1. [MEDIUM] CHANGELOG.md가 실제로는 갱신되지 않음 — RESULT의 완료 체크와 불일치

`CHANGELOG.md`의 `## [Unreleased]` 섹션은 현재 비어 있다(`git status`/`git diff`에 `CHANGELOG.md`가 아예 등장하지 않음). 그런데 `RESULT-round6-cache.md` §5는 "CHANGELOG 초안"으로 `### Fixed` 2건 + `### Migration` 1건의 완성된 텍스트를 제시하고, §4 완료 정의 체크리스트는 "[x] CHANGELOG `### Fixed` 2건 + `removeAll` 동작 변경 Migration 노트 1줄 — 아래 §5"로 **완료 표시**되어 있다. 실제로는 그 텍스트가 `CHANGELOG.md` 파일에 한 글자도 반영되지 않았다.

- **파급**: 데이터 손상·회귀 위험은 없음(순수 문서 누락). 그러나 DESIGN §8 완료 정의의 명시적 항목이 미이행 상태이고, 브리프 자체가 "CHANGELOG/DocC 정확성"을 이 게이트의 점검 항목으로 명시했다. RESULT의 자기 체크리스트가 실제 작업 트리 상태와 어긋난다는 점도 그 자체로 신뢰도 문제다.
- **조치**: `CHANGELOG.md`의 `## [Unreleased]`에 RESULT §5가 이미 작성해 둔 `### Fixed`/`### Migration` 텍스트를 그대로 옮겨 붙이면 된다. 코드 변경도, 테스트 변경도 필요 없는 기계적 수정.

### 9-2. [LOW] 신규 코드 주석에 리뷰 ID 인용 1건 — ROADMAP §0/브리프 규약 위반

`ABCacheStore.swift`의 `resolvedMetadata` 함수 상단, 이번 diff로 **신규 추가된** 주석(`git diff` `+` 라인)에 다음 문구가 있다:

> `// coalesces via pendingMetadataRequests at step 3 below (round3 M5 / round4 N12·mn-4 invariant — this order is fixed, see the type's doc comment above pendingMetadataRequests).`

`ROADMAP-round6.md` §0은 "새 코드 주석에 리뷰 ID 인용 금지(불변식만 서술 — H-2 재발 방지)"를 모든 브리프에 명시된 구현 규칙으로 못 박고 있고, 이 게이트의 브리프 자체도 "주석 위생(리뷰 ID 인용 0건)"을 명시적 점검 항목으로 요구한다. 전체 diff(모든 신규/변경 파일)를 review-ID 패턴(`round[0-9]`, `M5`, `N1[0-9]`, `mn-[0-9]`, `WP[0-9]`, 트랙 ID 등)으로 전수 스캔한 결과 이 1건 외에는 발견되지 않음(같은 함수 근처의 "round4 N12" 언급 1곳은 `git log -p`로 대조한 결과 **이번 브랜치 이전부터 이미 존재하던** 주석이라 이번 diff의 책임 범위 밖이며, H-1w의 전수 정리 대상으로 남아 있음).

- **파급**: 기능 영향 없음. 순수 텍스트 위생 문제이며, 정확히 이 패턴의 재발을 막기 위해 라운드6 전체가 규약을 세운 것(H-2 재발 방지)이므로 게이트에서 걸러야 할 성격.
- **조치**: 해당 문장에서 "(round3 M5 / round4 N12·mn-4 invariant — ...)" 괄호를 제거하고 불변식 자체("이 순서는 고정이며 `pendingMetadataRequests` 타입 주석을 참고")만 남기면 된다. 1줄 수정.

### 9-3. [LOW, 비차단] `purgeGeneration`이 키별이 아닌 스토어 전역 스칼라 — 무관한 키의 진행 중 fill을 스푸리어스하게 passthrough로 강등시킬 수 있는 좁은 경합 창

`private var purgeGeneration: UInt64`은 스토어 전체에 하나뿐이며 `remove(_:)`(단일 키 삭제)도 이를 증가시킨다. `load()`의 강등 분기는 `purgeGeneration != entryGeneration && index.entries[key] == nil`을 보는데, 후자는 키별이지만 전자는 전역이다.

재현 시나리오: 키 A의 `load()`가 막 시작해 `entryGeneration`을 스냅샷한 직후 — 아직 A의 fill이 첫 `.response`를 받지 못해 `index.entries[A]`가 존재하지 않는 짧은 창(네트워크 TTFB 대기 구간) — 그 사이 어떤 호출자가 **키 B**에 대해 `remove(B)`를 호출하면 `purgeGeneration`이 증가한다. A의 `load()` 루프가 다음 반복에 진입하면 `purgeGeneration != entryGeneration`(참, B의 삭제 때문)과 `index.entries[A] == nil`(참, A의 fill이 아직 응답을 못 받아서)이 **둘 다** 참이 되어, A는 실제로는 전혀 삭제된 적이 없는데도 그 요청 1건이 즉시 passthrough로 강등된다.

- **파급**: 데이터 정확성 문제는 아님(passthrough는 네트워크에서 올바른 바이트를 그대로 가져온다) — 이번 `load()` 호출 1건만 캐시를 우회하는 성능/의미론적 부작용이며, A의 백그라운드 fill 자체는 계속 진행되고 다음 `load()` 호출은 정상적으로 캐시를 사용한다(자가 치유). 단일 소스만 다루는 데모 시나리오에서는 재현되지 않고, 여러 `ABMediaSource`를 동시에 캐싱하는 사용(멀티 플레이어 피드 등)에서만 노출된다.
- **범위 판단**: 이 스칼라 설계는 `DESIGN-round6-cache.md` §3.2에서 승인된 그대로 구현된 것(구현자가 임의로 단순화한 게 아님) — 즉 이번 구현의 일탈이 아니라 **이미 승인된 설계의 특성**이다. 신규 회귀 테스트 `freshLoadUnaffectedByEarlierRemoveAll`은 두 `load()` 호출을 완전히 순차적으로만 구성해(첫 호출 완료 → `removeAll()` → 두 번째 호출 시작) 이 경합 창을 실제로 검증하지 못한다.
- **조치 권고**: 이번 게이트에서 코드 수정은 금지되어 있고, 데이터 손상이 없는 좁은 경합이므로 **차단 사유로 삼지 않음**. 다만 다중 동시 소스 사용을 제품 목표로 유지한다면 후속 라운드에서 (a) `purgeGeneration`을 `[String: UInt64]`로 키별 스코프로 좁히거나, (b) 최소한 DocC "Known constraints"에 "동시에 여러 소스를 캐싱 중일 때 한 소스의 `remove`/`removeAll` 호출이 다른 소스의 갓 시작된 fill을 1회 한정으로 네트워크 패스스루로 우회시킬 수 있다"는 한 문단을 남길 것을 권고.

## 10. 잔여 리스크

- **테스트 스위트 실제 그린 실행 미확인**: 이번 세션도 부팅된 iOS 시뮬레이터가 없어 `xcodebuild test`를 실행하지 못했다(정책상 새 부팅 금지). `build-for-testing`이 zero-warning으로 성공하는 것은 이번 리뷰에서 독립 재현했고, `git diff`로 기존 테스트 소스가 어서션 단위로 무수정임을 직접 확인했지만, **런타임 그린 여부(특히 신규 33건 테스트의 타이밍/경합 정확성)는 병합 후 PR CI(TSan 포함)가 최초로 실증**하게 된다 — `ROADMAP-round6.md` §2 CI-2와 이 브리프의 부기 사항대로.
- 위 §9-3은 승인된 설계의 특성이므로 별도 설계 재승인 없이는 이 게이트 범위에서 해소 불가 — 문서화 권고로 남김.

---

## 결론 (1차 게이트, 정적 리뷰 기준)

핵심 임무인 "기존 취소/coalescing 불변식 9개 무회귀"는 코드 레벨에서 전부 PASS다. E-1w의 재개 검증 4분기(200 폴백/206 정합/206 불일치 재시작/기타)와 `FillSuperseded` 기반 `fills[key]` 교체 경로도 waiter·취소 시맨틱을 깨지 않음을 확인했다. E-4w `boundedData`의 메모리 상한과 스트림 조기 종료·취소 경로, E-5w의 순수 추출도 코드 대조로 검증했다. 기존 테스트는 정말로 어서션 단위로 무수정이다(diff 직접 확인).

다만 이 게이트가 명시적으로 점검하도록 요구받은 두 항목 — **CHANGELOG 갱신**(§9-1)과 **신규 코드의 리뷰 ID 인용 0건**(§9-2) — 이 실제로는 미이행 상태이며, RESULT의 자기 체크리스트가 이를 완료로 잘못 표시하고 있다. 둘 다 코드 로직이나 테스트를 건드리지 않는 기계적 수정(문서 텍스트 삽입 1건, 주석 1줄 정리)이지만, 그 상태로는 DESIGN §8의 완료 정의를 충족하지 못하고 라운드6 전체가 재발 방지를 위해 세운 규약(H-2)을 이 브랜치가 그대로 어기게 된다. §9-3은 참고용 잔여 리스크로 남기며 이번 판정에는 반영하지 않았다.

(1차 게이트 시점의 판정: REQUEST-CHANGES — 아래 §11에서 재게이트)

---

## 11. 재게이트(fix1 확인)

리뷰어: Sonnet (재게이트 역할 대행). 입력: `RESULT-round6-cache-fix1.md` §2(회귀 2건과 수정), 위 §9(1차 게이트 지적 3건), `DESIGN-round6-cache.md` §6(무회귀 가드 표), 작업 트리 `git diff` 전체.
방법: 1차 게이트와 달리 **부팅된 시뮬레이터**(iPhone 17 Pro, UDID `55A3A4F3-3F02-43E6-9B23-116BD15D3345`)가 있어, RESULT-fix1의 "8회 연속 그린" 주장을 그대로 신뢰하지 않고 **직접 재현**했다. 아울러 신규 프로덕션 로직 변경 2건(§2-1 `load()` 게이팅, §2-2 `prepareFill`/`append`의 `Task.checkCancellation()`)을 함수 본문 라인 단위로 정독해 교착·원자성 주장을 코드 레벨로 재검증했다. 새 시뮬레이터 부팅·생성은 하지 않았다.

### 11.1 실제 테스트 실행 — 5회 독립 실행, 전부 그린

`xcodebuild build-for-testing -scheme ABPlayerKit-Package -only-testing:ABPlayerKitCacheTests -destination 'id=55A3A4F3-...'` → **TEST BUILD SUCCEEDED**, 경고 0·에러 0.

이어서 `xcodebuild test-without-building`을 **동일 빌드 산출물로 5회 연속** 실행(브리프가 요구한 최소 3회를 초과):

| 실행 | 결과 |
|---|---|
| 1 | `Test run with 72 tests in 8 suites passed` |
| 2 | `Test run with 72 tests in 8 suites passed` |
| 3 | `Test run with 72 tests in 8 suites passed` |
| 4 | `Test run with 72 tests in 8 suites passed` |
| 5 | `Test run with 72 tests in 8 suites passed` |

5회 전부 `recorded an issue` 매치 0건. RESULT-fix1 §2-2가 "약 1/3~1/2 확률로 간헐 실패"라고 보고한 바로 그 테스트 3건(`removeAllDemotesStalledLoadToPassthrough` → `"Removing all cached media while a load is stalled on a fill lets that load finish via passthrough instead of failing"`, `removeOnlyDemotesTargetedKey`, `loadAfterRemoveStartsFreshFillAndRefills` → `"Playback that continues after a delete starts a fresh fill and the cache refills"`)와 §2-1이 고친 3건(`ifRangeMismatchTruncatesAndRefillsFromScratch`, `noValidatorContentRangeStartMismatchTruncatesAndRefetches`, `totalLengthChangeTruncatesAndRefetches`에 대응하는 테스트명)이 **5회 모두 개별적으로 통과 로그에 등장**함을 각 실행 로그에서 직접 확인했다(표본 추출이 아니라 grep 전수 확인). 전체 빌드(`xcodebuild build -scheme ABPlayerKitCache -destination 'generic/platform=iOS'`)도 재확인: **BUILD SUCCEEDED**, 경고 0.

### 11.2 §2-1 `load()`의 재개-검증 게이팅 — 교착 가능성 검토

`ABCacheStore.swift:434-536`(`load()`)를 직접 정독.

- **게이팅 조건**: `mustObserveFillProgressBeforeServing = isStartingFreshFill && hadExistingPrefix && !entryWasComplete`. 세 조건 전부 이번 호출이 "기존 prefix가 있는 키의 fill을 방금 처음 시작시켰다"는 좁은 경우로 정확히 수렴한다.
- **(a) 완결 엔트리 제외**: `entryWasComplete`가 `mustObserveFillProgressBeforeServing`을 게이팅에서 명시적으로 제외하며(`!entryWasComplete` 조건), 그 위 `if !entryWasComplete { startFillIfNeeded(...) }`에서 애초에 fill을 시작시키지 않으므로 완결 엔트리에 대해서는 대기 신호가 영원히 오지 않을 걱정 자체가 성립하지 않는다. **PASS**.
- **(b) 신선한 다운로드·합류 경로 무영향**: 신선한 다운로드는 `hadExistingPrefix == false`(size 0)라 게이팅되지 않는다. 이미 진행 중인 fill에 합류하는 후속 호출은 `isStartingFreshFill == false`(actor의 비선점 실행 덕분에 `fills[key]` 체크-후-설치 구간에 다른 호출이 끼어들 수 없어 이 판정이 정확함, 기존 불변식 4와 동일 근거)라 게이팅되지 않는다. **PASS**.
- **(c) `FillSuperseded` 재시작 경로에서 게이팅 해제**: `prepareFill`의 206 불일치 분기는 `resumeWaiters`를 호출하지 않고 `launchFill(offset: 0)`으로 새 Task를 설치한 뒤 `FillSuperseded`를 던진다(`:791-796`). 원본 Task는 이를 실패로 취급하지 않고 조용히 종료한다(`catch is FillSuperseded { }`, `:709-711`). 이 경로 자체는 `hasObservedFillProgress`를 갱신하지 않지만, 교착으로 이어지지 않는 이유는: 새로 설치된 대체 fill이 결국 (i) 검증에 통과해 `prepareFill`의 성공 경로 끝에서 `resumeWaiters`를 호출하거나(`:823`), (ii) 다시 불일치를 만나 한 번 더 재시작하거나(유한 재귀, 매 반복이 새 네트워크 응답에 의존), (iii) 실패하면 `catch let error as StoreError` 등을 거쳐 `failFill`이 `resumeWaiters`를 호출한다(`:845`, `:881`) — 즉 **모든 종단 경로가 결국 `resumeWaiters(for: key)`를 호출**하므로 `load()`의 `await waitForProgress(key:)`는 유한 시간 내 반드시 깨어난다. `append()`도 매 청크마다 `resumeWaiters`를 호출하므로(`:845`, 이번 diff는 최상단 `checkCancellation` 1줄만 추가) 대기가 필요 이상으로 늘어지지도 않는다. **PASS — 교착 시나리오를 찾지 못했다.**
- **부가 확인**: 서빙 체크(`entry.size > resolvedRange.lowerBound`)와 게이팅 플래그 갱신(`hasObservedFillProgress = true`)이 루프의 서로 다른 지점(전자는 루프 상단, 후자는 `waitForProgress` 직후)에 있어 신호 도착 시점과 실제 서빙 재시도 시점 사이에 정확히 1회의 추가 루프 반복이 끼는데, 이는 지연이지 교착이 아니며 §2-1의 "왕복 1회 분량의 대기가 추가된다"는 자기 설명과 정확히 일치한다.

### 11.3 §2-2 `prepareFill`/`append`의 `Task.checkCancellation()` — 원자성 재검증

RESULT-fix1의 "검사 통과 후 원자적 완주" 주장을 직접 검증하기 위해 두 함수 본문을 전부 읽었다(`prepareFill`: `:722-824`, `append`: `:826-846`).

- 두 함수 모두 **`async`가 아닌 동기 `throws` 함수**다(`private func prepareFill(...) throws`, `private func append(...) throws`). 호출부는 `try await self.prepareFill(...)`/`try await self.append(...)`로 actor 홉을 위해 `await`를 쓰지만, 일단 액터에 도달하면 함수 본문 자체에는 `await` 키워드가 **단 한 곳도 없다** — `fileManager` 호출, `FileHandle` 생성/`seekToEnd()`/`write(contentsOf:)`, `index.upsert`, `truncateFile(at:)`(자체도 동기) 전부 동기 API다. 따라서 "검사 통과 이후 다른 어떤 actor-isolated 호출도 끼어들 수 없다"는 주장은 Swift 액터의 비선점 실행 모델상 정확히 성립한다. **PASS**.
- **취소 시 정리 경로**: `checkCancellation()`이 던지는 `CancellationError`는 두 함수 모두에서 그 어떤 딕셔너리(`fills`/`fillHandles`/`fillErrors`)도 건드리기 전에(정확히는 `prepareFill`은 `guard (200...299)...` 이전, `append`는 `guard !data.isEmpty` 이전) 발생하므로 부분 상태 변경 없이 그대로 전파된다. 호출 스택을 따라가면 `launchFill`의 `for try await event in stream` 루프를 감싼 `do/catch`가 이를 잡아 `catch is CancellationError { await self?.failFill(key: key, error: .requestFailed) }`로 흐른다(`:714-715`) — 기존 실패 경로와 동일하게 `fills[key] = nil`, `fillResponses[key] = nil`, `closeFillHandle(for:)`, `fillErrors[key] = error`, `resumeWaiters(for: key)`가 수행된다. RESULT-fix1이 보고한 "취소된 Task가 `removeAll` 직후 엔트리를 부활시키는" 시나리오는 이 가드가 정확히 막는다: 가드가 없었다면 `index.upsert(entry)`(`:816`)까지 도달해 막 비워진 인덱스에 엔트리를 다시 써넣었을 것이나, 가드가 그 이전에 취소를 발견해 함수를 통째로 건너뛴다. **PASS**.
- **`removeAll` 이후의 부수 효과 확인**: 취소된 Task의 `failFill` 콜백이 `removeAll`이 이미 완료된 뒤 뒤늦게 실행되면 `fillErrors[key]`가 일시적으로 다시 채워질 수 있음을 직접 추적했다. 그러나 `load()`의 루프는 `purgeGeneration != entryGeneration && index.entries[key] == nil` 분기(§2-2가 아니라 §2-1이 아니라 §3.2/E-3w 원 설계, `:521`)를 `fillErrors` 검사(`:524`)보다 **먼저** 평가하므로, 이 뒤늦은 `fillErrors` 재설정이 관측되기 전에 이미 passthrough로 분기해 반환한다 — 실제 동작에 영향 없음을 코드 경로로 확인했다(런타임 재현은 하지 않았으나, `entryGeneration`이 `load()` 진입 시 1회만 스냅샷되고 이후 변하지 않는다는 점에서 이 순서는 구조적으로 보장된다).

### 11.4 설계 §6 무회귀 가드 9개 — 이번 로직 변경 이후 재확인

1차 게이트가 PASS 판정한 9개 항목을 이번 fix1 diff와 대조:

- **waiter 이중 resume 금지/UUID 동일성/취소 즉시 제거(1~3)**: `ABCacheProgressWaiter`/`ABCacheProgressWaiterRegistry` 정의부는 fix1 diff에도 등장하지 않는다(grep 확인). `load()`의 신규 코드는 기존 `waitForProgress(key:)` 호출 지점 자체를 옮기거나 바꾸지 않았고, `resolve()`를 직접 호출하는 신규 지점도 없다. **PASS 유지**.
- **fill GET 코얼레싱(4)**: `startFillIfNeeded`는 여전히 동기 함수이고 `guard fills[key] == nil else { return }` 직후 `launchFill(...)`을 await 없이 호출한다. `launchFill` 신설로 코드가 재구성됐지만 `httpFetcher.stream(for:)` 호출과 `fills[key] = Task {...}` 대입 사이에 suspension point가 없다는 성질은 그대로다(§11.2에서 이미 이 무-suspension 성질에 의존해 재시작 경로의 정확성을 검증했다). **PASS 유지**.
- **HEAD 코얼레싱(5)/holder 정리(6)**: `resolvedMetadata`에 `claimPending` 분기가 추가됐지만 fix1 diff는 이 함수를 건드리지 않았다(§2-1·§2-2 모두 `load()`/`prepareFill`/`append`만 수정). `finishMetadataRequest` 자체도 fix1 diff에 없음. **PASS 유지**.
- **reader 등록 해제(7)**: `defer { readerRegistry.release(key) }`는 `load()` 최상단(`:437`)에 그대로 있고, §2-1이 추가한 신규 지역 변수·분기(`entryGeneration`, 게이팅 플래그, purgeGeneration демotion 분기)는 전부 같은 함수 스코프 안이라 defer 범위를 벗어날 수 없다(단일 함수이므로 구조적으로 보장, 1차 게이트 때와 동일 근거). **PASS 유지**.
- **eviction 제외 집합에 `fillHandles` 미개입(8)**: `evictIfNeeded`의 `excludedKeys` 계산(`:1182-1184`, `readerRegistry.activeKeys ∪ fills.keys ∪ {protectedKey}`)은 fix1 diff에 등장하지 않고, `fillHandles`를 여전히 참조하지 않는다(grep 재확인). **PASS 유지**.
- **`deinit` 수정 금지(9)**: fix1 diff에 `deinit` 관련 라인 없음. **PASS 유지**.

**결론: 9개 불변식 모두 fix1의 2건 로직 변경 이후에도 무회귀.**

### 11.5 §9-1·§9-2·§9-3 조치 확인

- **§9-1 (CHANGELOG)**: `CHANGELOG.md`의 `## [Unreleased]`에 `### Fixed` 2건 + `### Migration notes` 1개 하위 섹션이 실제로 반영되어 있음을 `git diff -- CHANGELOG.md`로 직접 확인. 내용도 RESULT §5 초안 그대로다. **해소**.
- **§9-2 (리뷰 ID 인용)**: `resolvedMetadata` 상단 주석에서 지적됐던 `"(round3 M5 / round4 N12·mn-4 invariant — ...)"` 괄호가 제거되고 `"— this order is fixed, see the type's doc comment above pendingMetadataRequests."`로 정리된 것을 확인. 파일 전체를 `round[0-9]|M[0-9]+|N[0-9]+|mn-[0-9]|WP[0-9]`로 재스캔한 결과 남은 3건(`:241`, `:574`, `:660` 부근)은 전부 `git diff`에 등장하지 않는 — 즉 이번 fix1은 물론 이번 브랜치 전체에서도 신규 추가가 아닌 — 사전 존재 주석이었다(1차 게이트 §9-2가 이미 "책임 범위 밖"으로 확인한 것과 동일 부류). 신규 인용 0건. **해소**.
- **§9-3 (DocC, 비차단 권고)**: "Known constraints" 절에 "Delete scope when caching several sources at once" 문단이 추가되어 §9-3이 기술한 경합 창(전역 `purgeGeneration`이 무관한 키의 fill을 스푸리어스하게 강등시킬 수 있음)을 정확히 문서화하고 있음을 확인. 원래 비차단 권고였고 문서화 옵션(b)을 채택한 것도 1차 게이트가 승인한 대안 중 하나. **해소**.

### 11.6 테스트 동기화 보강 — 약화가 아닌 강화인지 확인

`registeredStreamCount`(`ABControlledHTTPFetcher`, `:143-147`)와 이를 쓰는 3개 테스트(`removeAllDemotesStalledLoadToPassthrough`, `removeOnlyDemotesTargetedKey`, `loadAfterRemoveStartsFreshFillAndRefills`)의 diff를 라인 단위로 대조했다.

- 세 테스트 모두 **기존의 `try await waitUntil { !store.activeReaderKeys().isEmpty }` 대기를 삭제하지 않고 그대로 둔 채, 그 뒤에 `try await waitUntil { fetcher.registeredStreamCount >= 1 }`를 추가로 얹었다** — 대기 조건을 완화한 게 아니라 더 늦은 시점까지 대기하도록 엄격화했다. `registeredStreamCount`는 `stream(for:)`가 실제로 호출되어 continuation이 등록된 횟수인데, 이는 `resolvedMetadata`가 이미 완료되고 `launchFill`이 실행된 뒤에만 증가할 수 있다(`readerRegistry.retain`은 메타데이터 해석보다 먼저 일어나므로 `activeReaderKeys` 단독 대기로는 이 시점을 보장하지 못한다는 게 RESULT-fix1 §2-2의 근본 원인 설명과 정확히 일치). 즉 이 변경은 "테스트가 검증하려는 경합 창을 실제로 열리게 만드는" 방향이지, 검증 대상을 우회하거나 타이밍을 인위적으로 벌려 실패를 숨기는 방향이 아니다.
- **어서션 자체는 세 테스트 모두 무수정**이다(`#expect(outcome == .succeeded(...))`, `#expect(removedResult.data == ...)`, `#expect(refilled == ...)` — diff에 어서션 라인 변경 없음, 대기 조건 라인만 추가). §6의 "어서션을 고쳐야 한다면 회귀 신호"라는 기준은 대기 조건 강화에는 해당하지 않는다.
- §11.1에서 5회 연속 실행 모두 이 3개 테스트가 개별적으로 통과 로그에 등장함을 확인했으므로, 이 강화가 실제로 이전의 간헐적 실패를 없앴다는 것도 실행으로 뒷받침된다.

**결론: 테스트 동기화 보강은 검증을 약화시키지 않았다. 오히려 이전에는 우연에 의존해 통과하던 경로를 결정론적으로 만들었다.**

### 11.7 종합 판정

fix1이 추가한 프로덕션 로직 변경 2건(§2-1 게이팅, §2-2 취소 검사) 모두 코드 레벨로 정확성을 재확인했고, 특히 §2-1의 교착 가능성과 §2-2의 원자성 주장은 이번 재게이트의 핵심 검증 대상이었던 만큼 함수 본문을 전부 정독해 별도로 재추적했다 — 두 곳 모두 문제를 찾지 못했다. 1차 게이트가 PASS 판정했던 무회귀 가드 9개도 이번 diff 범위에서 재확인 결과 그대로 유지된다. 1차 게이트의 REQUEST-CHANGES 사유였던 §9-1(CHANGELOG)·§9-2(리뷰 ID)는 실제로 해소됐고, §9-3(DocC 권고)도 반영됐다. 지시 범위 밖이었던 테스트 동기화 보강도 검증을 우회하는 방향이 아니라 강화하는 방향임을 확인했다. 무엇보다, 1차 게이트가 실행하지 못했던 실제 테스트 스위트를 이번에는 5회 독립 실행해 매번 72/72 그린을 직접 확인했다 — RESULT-fix1의 "8회 연속 그린" 주장을 별도 실행으로 재현한 셈이다.

차단 사유를 발견하지 못했다.

FINAL-VERDICT: APPROVE
