# DESIGN: 라운드6 트랙 E — 캐시 무결성 (E-0 설계 게이트)

기준 커밋 995bb6d. 입력: `ROADMAP-round6.md` §2 트랙 E·§6, `REVIEW-round6-portfolio-audit.md` 섹션 E(E-1~E-8)·"강점".
범위: `Sources/ABPlayerKitCache/`만. **sparse range(라운드5 트랙2)·E-7(LRU 최적화)은 제외** — E-7은 DocC 제약 문서화만.

---

## 0. 요약

| 결정 | 선택 | 한 줄 근거 |
|---|---|---|
| 1. 재개 검증 실패 처리 | **prefix 폐기 후 같은 응답 스트림으로 재시작**(truncate-and-refill) | `If-Range`를 쓰면 서버가 200으로 폴백해 주므로, 이미 존재하는 200-truncate 경로(`ABCacheStore.swift:541-546`)와 **같은 코드 경로로 수렴**한다. 엔트리 무효화는 재생 실패를 초래하고 새 조율 기계를 요구한다 |
| 2. 메타데이터 재검증 시점 | **TTL 없음. 에셋 세션(재생) 시작 시 1회 조건부 검증, best-effort** | TTL은 정답 없는 벽시계 노브를 공개 표면에 추가하고 E-7의 벽시계 약점을 가중시킨다. `If-Range`가 닿지 못하는 **완결 엔트리**의 stale 구멍을 세션당 왕복 1회로 막는 것이 최소 비용 최대 효과 |
| 3. `remove`/`removeAll` × reader | **즉시 삭제 + in-flight reader는 network passthrough로 강등** | 지연 삭제는 "디스크 비우기"라는 사용자 의도를 배신하고 tombstone 상태를 전 경로에 전파시킨다. 실패 허용은 현행 동작이며, 데모의 가장 눈에 띄는 버튼이 재생 실패를 정상 결과로 만든다. 강등은 ~10줄 |

공개 API 변경 **0건**(새 `ABCacheConfiguration` 노브 없음). 인덱스 포맷은 additive-optional 1필드 → **기존 캐시 무효화·마이그레이션 코드 불필요**.

---

## 1. 결정 1 — `If-Range`/`ETag` 재개 검증 프로토콜 (E-1)

### 1.1 현재 코드가 깨지는 지점

| 위치 | 사실 |
|---|---|
| `ABCacheStore.swift:763-769` | `fillRequest(for:offset:)`는 `offset > 0`이면 `Range: bytes=N-`만 보낸다. 검증자(validator) 헤더 없음 |
| `ABCacheStore.swift:520-522` | `prepareFill`은 `200...299`만 확인한다. 206의 `Content-Range` **시작 오프셋을 검증하지 않는다** |
| `ABCacheStore.swift:547` | 새 응답의 총 길이로 `entry.contentLength`를 **조용히 덮어쓴다**. 원본이 교체돼 길이가 달라져도 그대로 진행 |
| `ABCacheStore.swift:541-546` | 200 응답 + 기존 prefix면 파일을 0으로 truncate한다 — **Range 무시 서버에 대한 올바른 복구가 이미 존재한다** |
| `ABCacheIndex.swift:4-30` | `Entry`에 검증자 필드가 없다 |

결과: 앱 재실행 후 부분 엔트리를 이어받을 때(`init`의 디스크 정합 경로 `ABCacheStore.swift:234-247`) 원본이 교체돼 있으면 **구 버전 prefix + 신 버전 suffix**가 한 파일에 섞인다. 무음 손상이며, 감사가 "유일한 버그급"으로 분류한 이유가 이것이다.

### 1.2 선택: prefix 폐기 후 재시작 (truncate-and-refill)

**프로토콜 (E-1w 구현 계약)**

1. **저장** — `ABCacheIndex.Entry`에 `var validator: ABCacheValidator?` 추가.
   ```swift
   struct ABCacheValidator: Codable, Sendable, Equatable {
       var etag: String?          // ETag 헤더 원문 (W/ 접두사 보존)
       var lastModified: String?  // Last-Modified 헤더 원문
       var isStrongETag: Bool { etag.map { !$0.hasPrefix("W/") } ?? false }
   }
   ```
   기록 시점은 **바이트를 실제로 적재한 응답**, 즉 `prepareFill`의 fill 응답이다. HEAD 응답의 검증자는 저장하지 않는다(우리가 보관 중인 바이트를 만들어낸 응답이 아니므로 재개 판단의 권한이 없다).

2. **송신** — `fillRequest(for:offset:validator:)`가 `offset > 0`일 때:
   - `etag`가 있고 **strong**이면 → `If-Range: <etag>`
   - 아니고 `lastModified`가 있으면 → `If-Range: <last-modified>`
   - 둘 다 없으면 → `If-Range` 생략 (§1.4의 방어 검증으로 이관)

   **weak ETag(`W/"..."`)는 저장하되 `If-Range`로 절대 보내지 않는다.** RFC 9110은 range 요청에 weak 비교를 금지한다 — weak ETag를 보내면 서버가 200으로 폴백하거나 규격 위반 206을 돌려줄 수 있어 검증 자체가 무의미해진다. 저장은 하는 이유는 §2의 재검증이 **동등 비교**만 쓰기 때문이다.

3. **판정 — `prepareFill` 내부, 상태별 분기**

   | 응답 | 의미 | 처리 |
   |---|---|---|
   | 206 + `Content-Range` 시작 == `entry.size` + 총길이 일치 | 검증 통과 | 기존대로 append |
   | 200 (`If-Range` 불일치로 서버가 전체 바디 폴백) | 원본 변경 | `entry.size = 0`, 파일 truncate, **같은 스트림을 계속 소비**해 처음부터 채운다 |
   | 206인데 시작 오프셋/총길이 불일치 | 규격 위반 또는 원본 변경 | truncate 후 **fill 재시작**(§1.3) |
   | 그 외 | 기존대로 | `StoreError.invalidResponse` |

   200 폴백이 `ABCacheStore.swift:541-546`의 기존 truncate 경로와 **정확히 동일한 상황**이라는 점이 이 설계의 핵심이다. `If-Range`는 검증을 서버에 위임하므로 **추가 왕복이 0**이고, 새 상태 기계 없이 이미 테스트된 경로(`ABCacheStoreTests.swift:418` "A server ignoring Range truncates the partial file before refilling")로 수렴한다.

4. **길이 방어** — 검증자가 아예 없는 원본에도 적용되는 무료 가드: `entry.size > 0`이고 새 총 길이(`Content-Range`의 `/T` 또는 200의 `Content-Length`)가 기존 `entry.contentLength`와 **다르면** 원본 변경으로 간주해 truncate한다. 현행 `ABCacheStore.swift:547`의 무조건 덮어쓰기를 이 검사 뒤로 옮긴다.

5. **`Content-Range` 파서** — `totalLength(from:)`(`ABCacheStore.swift:924-931`)은 `/` 뒤 총길이만 본다. 시작 오프셋이 필요하므로 `ABContentRange { start, end, total }` 값 타입을 신설하고 `totalLength`도 이를 경유하게 한다. `bytes */1234`(총길이만), `bytes 0-9/*`(총길이 미상) 형태를 모두 nil-안전하게 파싱할 것. 순수 값 타입이므로 `ABCachePrimitiveTests`에서 단위 테스트한다.

### 1.3 기각안과 기각 사유

**기각 A — 엔트리 무효화(remove + 에러 반환).**
- 재생 중인 `load` 호출자가 이미 `waitForProgress`에 매달려 있다. 무효화는 그 호출자에게 에러를 전파하고 → `ABResourceLoaderDelegate.swift:103` `finishLoading(with:)` → `AVPlayerItem` 실패로 이어진다. **정확한 바이트를 얻을 방법이 명백히 존재하는데 캐시 내부 사정으로 재생을 죽이는 것**은 투명 캐시의 계약 위반이다. truncate-and-refill은 지연만 추가하고 올바른 바이트를 돌려준다.
- 비용도 더 크다. `removeCachedEntry`(`ABCacheStore.swift:818-822`)를 fill 도중 호출하면 진행 중인 fill 태스크의 `append`(`:566`)가 `index.entries[key]` 부재로 `.invalidResponse`를 던져 `failFill`로 빠진다. 즉 무효화를 하려면 "무효화 후 fill 재시작"이라는 조율을 새로 써야 한다 — truncate보다 **엄격히 더 많은 기계**를 요구하면서 결과는 더 나쁘다.

**기각 B — 재개 자체를 포기(항상 offset 0부터).**
- 무결성은 확보되지만 부분 캐시의 존재 이유(앱 재실행 후 이어받기)를 없앤다. `If-Range`가 표준으로 해결하는 문제를 기능 삭제로 회피하는 것.

### 1.4 검증자 부재 원본의 처리 방침

`ETag`도 `Last-Modified`도 주지 않는 원본(사설 미디어 서버에서 드물지 않음)에서는 `If-Range`를 쓸 수 없다. 방침:

1. **캐시 자체는 계속 허용한다.** 검증자 부재를 캐시 불가 사유로 삼으면 그런 원본에서 캐시가 전면 무력화된다 — 과잉 대응.
2. **재개 시 방어 검증을 강제한다**: 206의 `Content-Range` 시작이 `entry.size`와 정확히 일치할 것, 총길이가 기존 `contentLength`와 일치할 것. 하나라도 어긋나면 truncate 후 **fill 재시작** — 이 경우는 서버가 이미 오프셋 N부터 보내고 있어 같은 스트림을 처음부터 소비할 수 없으므로, 현재 fill을 실패 처리(`failFill`)하지 않고 `fills[key]`를 교체해 `Range` 없는 새 fill을 건다. 이 경로에서만 왕복이 1회 추가된다(희귀 경로).
3. **탐지 불가능한 잔여 구멍을 명시적으로 문서화한다**: 검증자가 없고 총길이도 동일한 채로 내용만 바뀐 원본은 재개 시 탐지할 수 없다. 완화 수단은 §2의 세션 시작 재검증(그조차 검증자가 없으면 `Content-Length` 비교로 축소된다)뿐이며, 최종 방어선은 소비자가 URL을 버전닝하는 것이다. DocC `ABPlayerKitCache.md`에 이 한계를 한 문단으로 적는다 — 감추지 않는 것이 설계 품질의 일부다.

### 1.5 passthrough에서 얻은 검증자 활용 (E-1w 소항목)

`passthrough`/`rawPassthrough`(`ABCacheStore.swift:621-715`)는 네트워크에서 직접 서빙하므로 그 응답 자체는 자기정합적이지만, **같은 재생 세션에서 캐시 prefix로 서빙된 다른 range와 섞인다.** 응답의 검증자가 `index.entries[key]?.validator`와 불일치하면 캐시된 prefix가 stale임이 확정된다.

규칙: **`fills[key] == nil`일 때에 한해** `removeCachedEntry(for: key)`를 호출한다. fill이 진행 중이면 그 fill의 자체 검증(§1.2)이 권한을 가지므로 건드리지 않는다 — 새 경합을 만들지 않기 위한 제약이다.

---

## 2. 결정 2 — 메타데이터 재검증 시점

### 2.1 선택: TTL 없음 + 에셋 세션 시작 시 1회 조건부 검증(best-effort)

**왜 필요한가.** `resolvedMetadata`(`ABCacheStore.swift:418-423`)는 인덱스 엔트리에 `contentLength`와 `contentType`이 있으면 **영구히** 그것을 돌려준다. 완결(`isComplete`) 엔트리는 재개하지 않으므로 §1의 `If-Range`가 **영원히 발동하지 않는다.** 원본이 바뀌어도 LRU가 밀어낼 때까지 stale 바이트를 서빙한다. 이것이 `If-Range`만으로는 닫히지 않는 잔여 구멍이다.

**메커니즘 (E-1w에 포함)**

1. `nonisolated` 락 보호 레지스트리를 하나 추가한다 — 파일 내 기존 패턴(`ABCacheReaderRegistry:18-44`, `ABCacheProgressWaiterRegistry:95-134`)과 동일한 이유(액터 밖에서 동기적으로 표시해야 함).
   ```swift
   private final class ABCacheRevalidationRegistry: @unchecked Sendable {
       func markPending(_ key: String)          // 세션 시작 표시
       func claimPending(_ key: String) -> Bool // test-and-clear, 1회만 true
   }
   nonisolated func beginAssetSession(for source: ABMediaSource)  // internal
   ```
2. `ABResourceLoaderDelegate`가 **`shouldWaitForLoadingOfRequestedResource`에서 동기적으로**(스폰한 `Task` 안이 아니라) 자기 인스턴스의 once-플래그를 보고 `store.beginAssetSession(for: source)`를 호출한다. 동기 호출이어야 하는 이유: `Task` 안에서 호출하면 **첫 로딩 요청이 stale 바이트를 이미 받아간 뒤** 재검증이 도는 인터리빙이 가능하다. 에셋 1개 = 델리게이트 1개(`ABMediaCache.swift:64-66`)이므로 "새 에셋 = 새 세션"이 정확히 성립하고, 데모의 "Replay MP4 through cache"(`CacheScreen.swift:14-17`)도 새 에셋을 만들므로 재검증 대상이 된다.
3. `resolvedMetadata` 진입 시 `claimPending(key)`가 true면 인덱스/LRU 빠른 경로를 **건너뛰고** 조건부 요청 경로로 간다:
   - `If-None-Match: <etag>` (weak 포함 — 여기서는 동등 비교라 weak도 유효) 또는 `If-Modified-Since: <last-modified>`
   - **304** → 엔트리 유효. 캐시된 메타데이터 사용
   - **200 + 검증자 상이(또는 `Content-Length` 상이)** → `cancelFill(for:)` + `removeCachedEntry(for:)` 후 새 메타데이터 사용. 이후 `load`가 새 fill을 건다
   - **네트워크 실패/타임아웃** → **fail-open**: 캐시된 메타데이터를 그대로 쓴다. 재검증 실패가 이미 보유한 바이트의 재생을 막아서는 안 된다(오프라인 재생 보존)
   - 검증자가 없는 엔트리 → `Content-Length` 비교만 수행

**코얼레싱 보존이 이 설계의 제약 조건이다.** `claimPending`은 **동기**이고 test-and-clear이므로, 재검증을 실제로 개시하는 호출자는 항상 정확히 1명이다. 나머지 동시 호출자는 기존 `pendingMetadataRequests[key]` 체크(`ABCacheStore.swift:432-434`)에 걸려 같은 태스크에 합류한다. 검사 순서는 다음으로 **고정**한다(라운드3 M5 / 라운드4 N12·mn-4 불변식 보존):

```
1) needsRevalidation = revalidation.claimPending(key)        // 동기, 부작용 1회
2) if !needsRevalidation { <기존 인덱스 빠른 경로> ; <기존 LRU 빠른 경로> }
3) if let pending = pendingMetadataRequests[key] { return await pending.task.value }   // 변경 없음
4) <holder 설치 → Task 생성>   // 첫 suspension point 이전 설치 유지
```
`claimPending`이 이미 false를 반환했다면(다른 호출자가 선점) 그 호출자는 3)에서 합류하므로 재검증 결과를 공유한다. 실패한 재검증은 플래그가 이미 소거돼 재시도 폭주가 없다.

**`remove`/`removeAll`은 해당 키(전체)의 pending 플래그를 지운다.**

### 2.2 기각안

**기각 A — TTL.** `ABCacheConfiguration`에 `metadataTTL` 노브가 생기고 영구 지원 대상이 된다. 정답 기본값이 없다(미디어 URL은 대개 불변/버전닝 → 왕복 낭비, 아니면 TTL을 짧게 잡아도 변경을 놓친다). 게다가 `lastAccessedAt`이 이미 벽시계이고 감사 E-7이 이를 약점으로 지목했는데, 두 번째 벽시계 의존(기기 시각 변경·클럭 스큐)을 추가하는 것은 같은 결함을 복리로 키우는 일이다.

**기각 B — 재검증 없음(현행 유지).** §2.1 첫 문단의 완결 엔트리 구멍이 그대로 남는다. E-1을 "재개만" 고치고 끝내면 "캐시 무결성" 트랙의 목표를 절반만 달성한다.

**기각 C — 모든 `load`마다 조건부 검증.** range 요청마다 왕복 1회 → TTFF 붕괴. 세션당 1회로 충분하다.

---

## 3. 결정 3 — `remove`/`removeAll` × reader 조정 (E-3)

### 3.1 현재 동작과 정확한 실패 지점

`remove`(`ABCacheStore.swift:300-309`)와 `removeAll`(`:311-337`)은 `readerRegistry`를 보지 않는다. 데모 시나리오(재생 중 "Remove all cached media" → `CacheScreen.swift:19-24` → `DemoModel.swift:287-291` → `ABMediaCache.swift:30-32`)에서:

1. `removeAll`이 fill 취소 + 디렉터리 삭제 + `resumeAllWaiters()` (`:325`)
2. 깨어난 `load`가 루프(`:376-415`)를 돌아 엔트리 부재 → `fills[key] == nil` → **`:412`에서 `StoreError.shortRead`**
3. `ABResourceLoaderDelegate.swift:103` `finishLoading(with:)` → 재생 실패

두 가지 사실이 설계를 단순하게 만든다:
- `remove`/`removeAll`은 **`async`가 아니다.** 액터 안에서 suspension 없이 완주하므로 다른 액터 코드가 "엔트리는 있는데 파일은 없음" 중간 상태를 관측할 수 없다. 따라서 `resource(from:)`(`:734-761`)에 경합 창이 없다.
- 이미 열려 있는 read 핸들은 unlink 후에도 유효하다(POSIX: inode가 fd로 유지). 크래시 경로가 아니라 **다음 read**가 실패하는 것이다.

그러므로 고칠 지점은 루프 가드 **한 곳**이다.

### 3.2 선택: 즉시 삭제 + reader의 passthrough 강등

`load`의 대기 루프에 삭제 감지를 넣는다:

```swift
// load() 진입부, 메타데이터 해석 직후
let entryGeneration = purgeGeneration          // private var purgeGeneration: UInt64 = 0

// 루프 안, fillErrors 검사(:405)보다 앞
if purgeGeneration != entryGeneration, index.entries[key] == nil {
    return try await passthrough(source, range: resolvedRange, metadata: metadata)
}
```

`purgeGeneration`은 `remove`/`removeAll`에서 **`resumeAllWaiters()` 호출 전에** 증가시킨다(둘 다 동기 함수이므로 함수 내 순서만 지키면 된다).

**왜 세대 카운터인가 — "엔트리 부재면 무조건 passthrough"로 단순화하지 않는 이유.** `entryTooLarge`가 아닌 일반 실패도 "엔트리 부재 + `fillErrors` 존재" 상태를 만든다(`prepareFill`이 upsert 전에 throw). 부재만으로 분기하면 기존 테스트 `ABCacheStoreTests.swift:786`("A non-2xx fill response throws StoreError.invalidResponse")가 passthrough를 먼저 시도하게 되어 다른 에러로 실패한다. 세대 카운터는 **삭제에 의한 부재만** 정확히 골라내므로 기존 에러 경로가 바이트 단위로 보존된다. 이것이 무회귀 요구를 만족시키는 최소 장치다.

**부수 효과와 그 수용 근거.** 강등된 reader는 이번 요청만 네트워크로 해결한다. 델리게이트의 다음 `load`는 `index.entries[key]?.isComplete != true`이므로 **새 fill을 시작한다** → 재생이 계속되면서 현재 위치부터 캐시가 다시 찬다. "비웠는데 다시 찬다"로 보일 수 있으나, 활성 재생의 캐시로서 정확한 의미론이며(모든 HTTP 캐시가 동일) `totalSize()`는 즉시 0으로 떨어져 사용자 의도(디스크 회수)는 즉시 이행된다. DocC에 한 줄 기술한다.

또한 삭제 직후 다음 `load`는 메타데이터를 다시 해석한다(인덱스 엔트리·`metadataCache` 모두 소거됨) → HEAD 1회 추가. 세션당 1회 수준이므로 수용한다.

### 3.3 기각안

**기각 A — 지연 삭제(reader 종료 후 삭제).**
- `removeAll()`은 "지금 디스크를 비워라"는 사용자 명령이다. 지연하면 `totalSize()`가 떨어지지 않아 데모의 `disabled(model.cacheSize == 0)` 버튼이 계속 활성 상태로 남고, 사용자는 버튼이 동작하지 않았다고 인식한다. 의도를 조용히 거부하는 설계.
- reader는 재생 세션 내내 사실상 상주한다(`load`가 연속 호출됨) → "reader 종료"는 재생 종료와 같다. 즉 실질적으로 "삭제하지 않음"이다.
- tombstone 상태(인덱스에서는 제거됐지만 디스크에는 남아 삭제 대기)를 `init` 정합(`:234-247`), `evictIfNeeded`, `totalSize`, `flushIndexNow`가 전부 이해해야 한다. 릴리스되지 않는 reader가 하나라도 있으면 파일이 영구 잔류한다.

**기각 B — 실패 허용 + 문서화.**
- 이는 **현행 동작**이다. 즉 이 선택지는 트랙 E에서 E-3 항목을 삭제하는 것과 같다.
- 공개 API 중 가장 눈에 띄는 `removeAll()`이 "재생 중 호출하면 재생이 깨진다"는 각주를 달게 된다. 10줄로 고칠 수 있는 함정을 문서로 봉인하는 것은 포트폴리오 관점에서도 잘못된 거래다.

---

## 4. 저장 포맷·인덱스 변경과 마이그레이션 방침

**변경**: `ABCacheIndex.Entry`에 `var validator: ABCacheValidator?` 1개 추가(§1.2). 그 외 없음.

**마이그레이션: 불필요.** 근거:
- `Codable`의 optional 필드는 **키가 없으면 nil로 디코드**된다 → 기존 인덱스 JSON이 그대로 읽힌다. 기존 캐시 엔트리는 폐기하지 않는다.
- `JSONDecoder`는 알 수 없는 키를 무시한다 → 구버전 바이너리가 신버전 인덱스를 읽어도 안전(다운그레이드 내성).
- 검증자가 nil인 레거시 엔트리는 **"검증자 부재 원본"과 동일하게** 취급된다(§1.4의 방어 검증 경로). 다음 fill이 완료되는 시점에 검증자가 자연히 기록되며 별도 백필 코드가 없다.

**버전 필드를 도입하지 않는다.** 현재 `ABCacheIndex`에 버전 개념이 없고, 이번 변경은 양방향으로 안전하게 열화되므로 버전 분기는 순수한 부채다. 미래에 **파괴적** 포맷 변경이 필요해지면 탈출구는 이미 존재한다 — 디코드 실패 시 빈 인덱스로 폴백하는 `ABCacheStore.swift:228-233`(테스트: `ABCacheStoreTests.swift:888`). 즉 "포맷을 바꾸고 구버전 인덱스를 못 읽게 두면 자동 폐기"가 안전하게 성립한다.

**공개 표면**: 변경 0. 새 `ABCacheConfiguration` 프로퍼티를 만들지 않는다 — 재검증은 세션당 1회로 고정, 메모리 상한은 `passthroughChunkSize`(`:911`)처럼 정책이 아닌 구현 상수로 둔다. POLICY-api-stability 상 additive 판단이 필요한 항목 자체가 없다.

**CHANGELOG**: `### Fixed`에 (a) 재개 시 원본 변경 무음 손상, (b) 재생 중 `removeAll()`이 재생을 중단시키던 문제. (b)는 관측 가능한 동작 변경이므로 POLICY 규칙에 따라 한 줄 Migration 노트를 붙인다("재생 중 캐시 삭제 시 해당 재생은 네트워크로 계속되며 실패하지 않음").

---

## 5. WP별 구현 지침

**권장 순서: E-2w → E-1w → E-3w → E-4w → E-5w.** E-2w(핸들 수명)를 먼저 넣어야 E-1w의 truncate-on-mismatch가 유지 핸들 위에서 한 번에 작성된다(반대 순서면 같은 코드를 두 번 쓴다). 트랙 E는 단일 파일 집중이므로 내부 병렬화 없음.

### E-2w — `FileHandle` 수명 (E-2, E-4 일부)

- **누수 2곳 즉시 수정**: `ABCacheStore.swift:542-544`(truncate), `:572-575`(append). throw 경로에서 `close()`가 보장되지 않는다. 올바른 패턴은 같은 파일 안에 이미 있다 — `resource(from:)`의 `defer { try? handle.close() }`(`:749-750`).
- **fill 수명 동안 writer 핸들 유지**: `private var fillHandles: [String: FileHandle]`. `prepareFill`에서 파일 생성/truncate 직후 열고 `seekToEnd()` 1회, 이후 `append`는 `write(contentsOf:)`만 호출한다(청크당 open/close 제거).
- **불변식**: `fillHandles[key] != nil` ⟺ `fillResponses[key] != nil`. 둘 다 `prepareFill`에서 설치되고 `completeFill`(`:587`)·`failFill`(`:609`)·`cancelFill`(`:811`) **세 곳에서만** 해제된다. 해제는 단일 private `closeFillHandle(for:)`로 일원화하고 이 세 함수와 `removeAll`(전 키 순회)에서 호출한다. fill 생명주기 전이가 이 세 함수로만 흐르므로 누락 경로가 없다.
- **`deinit` 우려 없음**: 액터의 `deinit`은 nonisolated라 `fillHandles`에 접근할 수 없지만, `FileHandle`은 dealloc 시 fd를 닫는다. 이를 주석으로 남긴다(불변식 서술 형태로 — 리뷰 ID 인용 금지).
- **동시 read 가시성 보존**: `FileHandle.write`는 버퍼링 없는 `write(2)`이므로, 별도 read 핸들을 여는 reader는 write 직후 그 바이트를 본다. `entry.size`는 write가 반환한 **뒤에만** 증가시킨다(현행 `:576` 유지). 이것이 "prefix가 reader에게 즉시 보인다"는 기존 계약의 근거이므로 리팩터 중 순서를 바꾸지 말 것.
- **범위 밖(문서화만)**: 액터 내부 동기 디스크 I/O 자체(E-4 나머지)는 이번 라운드에서 제거하지 않는다. 별도 I/O 액터 또는 `DispatchIO` 기반 writer 직렬화 설계가 선행돼야 하며, 청크 크기가 유계이고 정확성 문제는 없다. E-7과 함께 DocC "Known constraints"에 기록한다.

**테스트**: (1) `truncate` 실패를 주입해 throw 후에도 후속 fill이 성공(핸들 누수 없음)하는지 — 파일 권한/경로 조작보다는 `fillHandles` 비어 있음을 test-only 접근자로 단언하는 편이 결정적이다. (2) 청크 N개 fill 후 `fillHandles`가 완료·실패·취소 각 경로에서 비는지. (3) fill 진행 중 reader가 최신 prefix를 읽는 기존 테스트(`ABCacheStoreTests.swift:266`) 무수정 통과.

### E-1w — 재개 검증 + 세션 시작 재검증 (E-1, 결정 1·2)

- `ABCacheValidator`(§1.2), `ABContentRange` 파서(§1.2-5), `ABCacheRevalidationRegistry`(§2.1) 신설.
- `fillRequest`에 `If-Range` 송신, `prepareFill`에 §1.2 표의 4분기, §1.2-4 길이 방어.
- `resolvedMetadata` 검사 순서를 §2.1의 4단계로 **정확히** 고정. holder 설치가 첫 suspension point보다 앞에 온다는 기존 불변식을 깨지 말 것.
- `ABResourceLoaderDelegate`에 once-플래그 + 동기 `beginAssetSession` 호출.
- passthrough 검증자 불일치 시 `fills[key] == nil`에 한해 엔트리 폐기(§1.5).

**테스트**:
1. 검증자 있는 부분 엔트리 재개 → 요청에 `If-Range: "v1"`과 `Range: bytes=3-`이 함께 실린다.
2. weak ETag 저장 엔트리 → `If-Range`가 **실리지 않는다**(strong만 송신).
3. `If-Range` 불일치 → 서버 200 전체 바디 → 파일이 truncate되고 최종 바이트가 **전부 신 버전**(구·신 혼합 0바이트). 기존 `:418` 테스트의 확장형.
4. 검증자 없는 원본 + 206 `Content-Range: bytes 5-9/10`인데 `entry.size == 3` → truncate 후 `Range` 없는 재요청이 발생하고 결과가 신 버전 전체.
5. 총길이 변경(6 → 8) 감지 → truncate.
6. 완결 엔트리 + 새 에셋 세션 → 조건부 요청 1회 발생, **304면 네트워크 바이트 0으로 캐시 서빙**.
7. 세션 시작 재검증 200 + 검증자 상이 → 엔트리 폐기 후 새 fill.
8. 재검증 요청이 네트워크 에러 → **fail-open**, 캐시 바이트로 재생 성공(오프라인 시나리오).
9. 동시 10개 `load`의 세션 시작 → 조건부 요청이 **정확히 1회**(`ABCacheStoreTests.swift:540` 계열의 재검증판).

### E-3w — `remove`/`removeAll` reader 조정 (E-3, 결정 3)

- `purgeGeneration` 도입, `remove`/`removeAll`에서 `resumeAllWaiters()` **앞에** 증가.
- `load` 루프에 §3.2의 강등 분기를 `fillErrors` 검사(`:405`)보다 **앞에** 배치.
- `remove`/`removeAll`이 revalidation pending 플래그도 소거.

**테스트**:
1. **데모 시나리오 재현**: 스톨된 fill에 매달린 `load`가 진행 중 → `removeAll()` → 그 `load`가 **에러 없이** passthrough 바이트를 반환한다. 실패 시 서스펜드로 스위트가 멎지 않도록 기존 `:975` 테스트의 타임아웃 레이스 패턴을 재사용할 것.
2. `removeAll()` 직후 `totalSize() == 0`(즉시성 확인) — 지연 삭제가 아님을 고정.
3. `remove(_:)` 대상 키의 reader만 강등되고, 다른 키의 reader는 정상 캐시 경로 유지.
4. 삭제 후 계속되는 재생이 새 fill을 시작해 캐시가 다시 찬다.
5. **무회귀**: `:786`(non-2xx → `.invalidResponse`), `:847`/`:864`(스트림 throw → `.requestFailed`)가 **무수정** 통과.

### E-4w — content-type 폴백 + 메모리 상한 (E-5, E-6)

**content-type (E-5).** `contentType(from:fallback:)`(`:933-938`)은 응답 MIME이 UTType으로 변환되기만 하면 무조건 이긴다 → `application/octet-stream` → `public.data`가 확장자 폴백(`:940-945`)을 가로챈다.

규칙:
```
responseType = UTType(mimeType: response.mimeType)            // 파라미터(;charset=) 방어적 제거
if responseType == nil                                   → fallback
if responseType ∈ {.data, .content, .item}                    // 제네릭 supertype일 때만
   && fallbackType conforms to responseType
   && fallbackType != responseType                       → fallback
else                                                     → responseType.identifier
```
제네릭 집합에 한정하는 것이 핵심이다. 서버가 **구체적인** 타입을 말했다면 URL 확장자 추측보다 서버가 옳다.

**호출부 수정이 함께 필요하다.** `prepareFill`(`:548-551`)은 fallback으로 `metadata.contentType`을 넘기는데, 그 값은 이미 HEAD 단계에서 `public.data`로 열화된 값일 수 있다. `startFillIfNeeded`가 `source`를 갖고 있으므로 `Self.fallbackContentType(for: source)`를 계산해 `prepareFill`에 인자로 전달한다. `passthrough`/`rawPassthrough`도 동일하게 확장자 유래 fallback을 넘긴다. `resource(from:)`의 `entry.contentType ?? metadata.contentType`은 이미 수정된 로직으로 저장된 값이므로 변경 불필요.

**메모리 상한 (E-6).** `httpFetcher.data(for:)`는 바디 전체를 RAM에 담는다. Range를 무시하는 원본이 200으로 500MB를 보내면 그대로 500MB다. 응답을 받은 뒤에는 이미 늦으므로 **전송 중** 제한해야 한다 → `stream(for:)` 기반 헬퍼를 스토어에 신설한다:

```swift
/// 응답을 스트리밍하며 `skipping` 바이트를 버리고 최대 `count` 바이트만 모은 뒤
/// 전송을 종료한다. 피크 메모리는 `count`로 유계.
private func boundedData(for request: URLRequest, lowerBound: Int64, count: Int?) async throws -> (Data, ABHTTPResponse)
```
- `.response` 이벤트에서 2xx 검증 후 skip 예산 결정: 200이면 `lowerBound`, 206이면 0.
- `.data` 이벤트를 skip 예산 → collect 예산 순으로 소비하고, 목표치를 채우면 `break`. `AsyncThrowingStream`이 종료되면 `onTermination`(`ABHTTPFetching.swift:86-89`)이 URLSession 태스크를 취소하므로 잔여 바디는 전송되지 않는다.
- `count`가 미상인 경우(`rawPassthrough`의 upperBound nil)는 고정 상한(8MB 권장, `passthroughChunkSize`와 같은 급의 구현 상수)을 두고 초과 시 `StoreError.entryTooLarge`.
- 적용 대상 3곳: `passthrough`(`:646`), `rawPassthrough`(`:681`), `remoteMetadata`의 `bytes=0-0` GET 프로브(`:725-727` — count=1이므로 첫 바이트 직후 중단된다. HEAD 미지원 원본에서 전체 바디를 받던 최악 경로가 여기다).

**기존 테스트 픽스처 보호**: 위 3곳이 `data(for:)`에서 `stream(for:)`으로 옮겨가면 `dataReplies`로 세팅된 기존 테스트가 깨진다. **어서션을 고치지 말고**, `ABFakeHTTPFetcher.stream(for:)`이 `streamReplies` 고갈 시 다음 `dataReplies` 항목을 `.response` + `.data` 이벤트로 변환해 서빙하도록 테스트 지원 코드에 shim을 넣는다. 새 E-6 테스트만 명시적으로 대용량 스트림을 큐잉한다.

**테스트**: (1) `application/octet-stream` + `.mp4` URL → `public.mpeg-4`. (2) 서버가 `video/quicktime`을 말하고 URL이 `.mp4` → **서버 값 유지**. (3) 확장자 없는 URL + octet-stream → `public.data`(현행 유지). (4) Range 무시 200으로 상한 초과 바디를 흘리면 수집 바이트가 `count`에서 멈추고 스트림이 조기 종료된다. (5) 상한 초과 + 길이 미상 → `.entryTooLarge`.

### E-5w — `ABResourceLoaderDelegate` 직접 테스트 (E-8)

`AVAssetResourceLoadingRequest`는 공개 이니셜라이저가 없다. 실제 `AVURLAsset`로 로더를 구동하는 방식은 실 미디어 페이로드와 AVFoundation 타이밍에 의존해 느리고 불안정하므로 **채택하지 않는다.**

**선택: 내부 프로토콜 추출 + 어댑터.**
```swift
protocol ABLoadingRequesting: AnyObject {          // internal
    var isCancelled: Bool { get }
    var contentInformation: (any ABLoadingContentInformation)? { get }
    var dataRequest: (any ABLoadingDataRequesting)? { get }
    func finishLoading()
    func finishLoading(with error: (any Error)?)
}
protocol ABLoadingContentInformation: AnyObject {  // contentType/contentLength/isByteRangeAccessSupported 세터
protocol ABLoadingDataRequesting: AnyObject {      // currentOffset/requestedLength/requestsAllDataToEndOfResource/respond(with:)
```
`ABResourceLoaderDelegate.swift:43-105`의 태스크 본문을 `ABLoadingRequestServicer.service(_:source:store:) async`로 그대로 옮기고, AVFoundation 델리게이트는 실제 요청을 감싼 어댑터를 넘긴다. **동작 변경 0** — 순수 추출이다. `LoadingRequestBox`(`:8-14`)의 `@unchecked Sendable` 격리 근거는 어댑터로 이동한다.

**테스트**(가짜 요청 + 기존 `ABFakeHTTPFetcher` 백엔드):
1. contentInformation 경로: `contentType`/`contentLength`/`isByteRangeAccessSupported = true` 설정 확인.
2. contentLength 미상 → `isByteRangeAccessSupported = false` + 단발 응답 후 `finishLoading()`.
3. 데이터 루프: 청크 분할 응답이 여러 번 `respond(with:)`로 들어오고 합계가 요청 범위와 일치, 마지막에 `finishLoading()` 1회.
4. `requestsAllDataToEndOfResource = true` → `contentLength - 1`까지 서빙.
5. 스토어 에러 → `finishLoading(with:)` 호출, 정상 `finishLoading()`은 호출되지 않음.
6. 요청 취소(`isCancelled = true`) → 어떤 `finishLoading*`도 호출되지 않음(현행 `:102` 가드 보존).
7. E-3w 연동: 서빙 도중 `removeAll()` → 델리게이트가 에러 없이 완료(결정 3의 종단 검증).

---

## 6. 무회귀 가드 — 기존 취소/coalescing 불변식 보존

라운드3~4에서 확립된 것들(감사 "강점" 목록: `ABCacheProgressWaiter`, UUID 동일성)은 **건드리지 않는다.** 구현자는 아래를 체크리스트로 사용할 것.

| 불변식 | 위치 | 보존 방법 |
|---|---|---|
| waiter 이중 resume 금지, 취소가 설치보다 먼저 와도 안전 | `ABCacheStore.swift:53-85` | `ABCacheProgressWaiter`는 **일체 수정 금지**. 새 코드가 `resolve()`를 직접 호출하지 않는다 |
| 취소된 waiter의 즉시 제거(WP4) | `:786-801` | `waitForProgress`의 `resolve()` → `remove(key:id:)` 순서와 정상 완료 후 재-remove를 그대로 둔다 |
| UUID 동일성 기반 waiter 제거 | `:95-134` | 레지스트리 API 변경 없음 |
| fill GET 코얼레싱 | `:484` `guard fills[key] == nil` | `startFillIfNeeded`의 동기 구간에 **suspension point를 추가하지 않는다.** `fills[key] = Task {...}` 설치 전 `await` 금지 |
| HEAD 코얼레싱 (M5) | `:432-444` | holder 설치를 첫 suspension point 앞에 유지. §2.1의 재검증 분기는 `claimPending`(동기)만 추가하고 순서를 §2.1 4단계로 고정 |
| holder 식별자 기반 정리 (N12/mn-4) | `:463-477` | `finishMetadataRequest`의 `id` 비교 로직 수정 금지. 재검증 결과 캐싱도 이 함수를 경유한다 |
| reader 등록 해제 보장 | `:347-348` | 새 early-return이 전부 `defer { readerRegistry.release(key) }` 범위 안임을 확인(현재 함수 전체 커버) |
| 활성 reader/진행 중 fill의 eviction 제외 | `:826-828` | 변경 없음. `fillHandles` 도입이 이 집합 계산에 개입하지 않게 할 것 |
| 스토어 해제 시 waiter 정리 | `:266-268` | `deinit` 수정 금지 |

**무수정 통과가 강제되는 기존 테스트**(브랜치 병합 게이트 E-6에서 확인):
`ABCacheStoreTests.swift:540`(10 동시 로드 → HEAD 1 + GET 1), `:583`(취소된 첫 호출자의 코얼레싱, mn-4), `:975`(취소가 즉시 풀리고 reader가 해제됨), `:638`/`:679`(passthrough gap 임계), `:709`(1MB 청크 분할), `:786`/`:847`/`:864`(에러 매핑), `:934`(메타데이터 LRU 재터치).
픽스처 배관(§E-4w의 fake shim) 외에 **어서션을 고쳐야 한다면 그것은 회귀 신호**로 간주하고 게이트에서 REQUEST-CHANGES 사유가 된다.

**동시성 가드**: CI-4의 TSan 잡이 이 트랙과 병렬로 들어온다(`ROADMAP-round6.md` §2 CI-2). `fillHandles`는 액터 격리 상태, 새 revalidation 레지스트리는 락 보호 `nonisolated` — 기존 두 레지스트리와 동일한 규율이다. `@unchecked Sendable` 신규 도입은 이 레지스트리 1개로 제한하고, 그 정당화 주석은 **불변식 서술만**(리뷰 ID 인용 금지, `ROADMAP-round6.md` §0).

**파일 경계**: 트랙 E는 `Sources/ABPlayerKitCache/` + `Tests/ABPlayerKitCacheTests/`만 수정한다. `Tests/*/Support/ABWaitUntil.swift`는 CI-4(트랙 CI)의 통합 대상이므로 **손대지 않는다**(병합 순서 CI → E에서 충돌 방지). 데모(`Examples/`)도 수정 불필요 — 결정 3은 라이브러리 내부에서 해결된다.

---

## 7. DocC에 남길 문서화 (E-7 이월분 포함)

`Sources/ABPlayerKitCache/ABPlayerKitCache.docc/ABPlayerKitCache.md`에 "Known constraints" 절 신설:

- **재개 검증**: `If-Range`로 부분 캐시를 검증하며, 원본 변경이 감지되면 부분 파일을 폐기하고 처음부터 다시 채운다. 검증자를 제공하지 않는 원본은 `Content-Range` 시작·총 길이 일치로만 방어되며, **길이가 같은 내용 변경은 탐지할 수 없다**(§1.4).
- **재검증**: 에셋마다 최초 1회 조건부 검증을 수행한다. 실패 시 캐시된 바이트로 계속 재생한다(fail-open).
- **삭제 의미론**: `removeAll()`/`remove(_:)`는 즉시 삭제한다. 진행 중인 재생은 실패하지 않고 네트워크로 계속되며, 재생이 이어지는 동안 캐시가 다시 찬다.
- **E-7 (이월)**: LRU 축출이 축출마다 전체 엔트리를 정렬하고(O(n log n)), recency를 벽시계 기준으로 판단하며, 쓰기도 접근으로 계수한다(`ABCacheIndex.swift:55-76`). 현재 규모에서 무해하므로 최적화를 의도적으로 이월한다.
- **E-4 잔여 (이월)**: 디스크 I/O가 액터 내부에서 동기적으로 수행된다. 청크당 핸들 open/close는 제거했으나, I/O 자체의 오프로딩은 writer 직렬화 설계가 선행돼야 한다.

---

## 8. 완료 정의 (E-6 최종 게이트 체크리스트)

- [ ] 감사 E-1, E-2, E-3, E-5, E-6, E-8 해소. E-4는 부분 해소(청크당 open/close 제거) + 잔여 문서화. E-7은 문서화만
- [ ] §6의 기존 테스트 전부 **무수정** 통과(픽스처 shim 제외), Swift 6 zero-warning
- [ ] 신규 테스트: E-1w 9건, E-2w 3건, E-3w 5건, E-4w 5건, E-5w 7건 (총 ~29건 순증)
- [ ] 공개 API 변경 0건 확인(diff에 `public` 신규 심볼 없음)
- [ ] 기존 캐시 디렉터리를 가진 상태로 시작해도 인덱스가 폐기되지 않음(마이그레이션 무결성)
- [ ] CHANGELOG `### Fixed` 2건 + `removeAll` 동작 변경 Migration 노트 1줄
- [ ] DocC "Known constraints" 절 존재
