# RESULT: 라운드6 트랙 E 구현 — 캐시 무결성

담당: Sonnet. 브랜치 `round6/cache`. 입력: `DESIGN-round6-cache.md`(승인된 설계), `BRIEF-round6-cache.md`, `ROADMAP-round6.md` §0·§2, `REVIEW-round6-portfolio-audit.md` §E.
구현 순서: E-2w → E-1w → E-3w → E-4w → E-5w (설계 §5 권장 순서 준수). 커밋 없음 — 작업 트리 변경만.

---

## 1. WP별 변경 요약

### E-2w — `FileHandle` 수명
- `ABCacheStore`에 `private var fillHandles: [String: FileHandle]` 신설. `prepareFill`에서 파일 생성/truncate 직후 1회 열어 `seekToEnd()`, 이후 `append`는 `handle.write(contentsOf:)`만 호출(청크당 open/close 제거).
- 해제는 단일 `closeFillHandle(for:)`로 일원화하고 `completeFill`/`failFill`/`cancelFill`/`removeAll`(전 키 순회) 4곳에서만 호출.
- 기존 truncate(`:542-544` 상당)·append(`:572-575` 상당) 누수 지점은 `truncateFile(at:)`(`defer { try? handle.close() }`)와 위 통합 핸들 관리로 해소.
- `entry.size`는 여전히 `write` 반환 **이후에만** 증가(reader 가시성 계약 보존).
- 테스트 전용 접근자 `fillHandleCount()` 추가(신규 `public` 아님, 액터 내부 `func`).

### E-1w — 재개 검증 + 세션 시작 재검증 (결정 1·2)
- `ABCacheIndex.Entry`에 `var validator: ABCacheValidator?` 추가(additive-optional). `ABCacheValidator{ etag, lastModified, isStrongETag }` 신설.
- `ABContentRange` 값 타입 신설(신규 파일 `ABContentRange.swift`) — `bytes <start>-<end>/<total>`, `bytes */<total>`, `bytes <start>-<end>/*` 모두 nil-안전 파싱. `totalLength(from:)`이 이를 경유.
- `fillRequest(for:offset:validator:)`: strong ETag만 `If-Range`로 송신, weak ETag는 저장만 하고 미송신(RFC 9110 준수). `Last-Modified`는 ETag 부재/weak 시 폴백.
- `prepareFill`에 설계 §1.2 표의 4분기 구현: 200(from-scratch 또는 폴백 truncate-and-continue) / 206 정합 / 206 불일치(길이 방어 포함, truncate 후 `launchFill(offset:0)`으로 재시작 — `FillSuperseded` 내부 에러로 원 fill task는 `failFill` 없이 조용히 종료) / 그 외 `.invalidResponse`.
- `entry.validator`는 fill 응답(바이트를 실제로 적재한 응답)에서만 기록, HEAD 응답에서는 기록하지 않음.
- `ABCacheRevalidationRegistry`(락 보호 `nonisolated`, 기존 두 레지스트리와 동일 규율) + `nonisolated func beginAssetSession(for:)` 신설.
- `resolvedMetadata`를 설계 §2.1의 4단계 순서로 고정: `claimPending`(동기, test-and-clear) → 인덱스/LRU 빠른 경로 → `pendingMetadataRequests` 코얼레싱 → holder 설치. 기존 M5/N12/mn-4 불변식(홀더 설치가 첫 suspension point 이전) 보존.
- `revalidatedMetadata(for:key:)`: 조건부 HEAD(`If-None-Match`/`If-Modified-Since`), 304→캐시 유지, 200+검증자(또는 길이) 상이→`cancelFill`+`removeCachedEntry`, 네트워크 실패/비2xx→fail-open(캐시 유지).
- `passthrough`/`rawPassthrough`에 `reconcilePassthroughValidator(key:response:)` 추가 — `fills[key] == nil`일 때만, 검증자 불일치 시 엔트리 폐기.
- `remove`/`removeAll`이 `revalidationRegistry.clearPending`/`clearAll` 호출.

### E-3w — `remove`/`removeAll` reader 조정 (결정 3)
- `private var purgeGeneration: UInt64`을 `remove`/`removeAll` **동기 함수** 안에서 `resumeAllWaiters()`/waiter 재개보다 먼저 증가.
- `load()`의 대기 루프에 `if purgeGeneration != entryGeneration, index.entries[key] == nil { return try await passthrough(...) }`를 `fillErrors` 검사보다 앞에 배치. `entryGeneration`은 메타데이터 해석 직후 스냅샷 — 세대 카운터이므로 "삭제로 인한 부재"만 정확히 골라내고 기존 `entryTooLarge`/에러 경로는 바이트 단위로 보존.

### E-4w — content-type 폴백 + 메모리 상한
- `contentType(from:fallback:)`: 응답 MIME이 `{.data,.content,.item}` 제네릭 supertype이고 fallback이 그 서브타입일 때만 fallback 우선, 그 외에는 서버 값 우선. `;charset=` 등 파라미터 방어적 제거.
- 호출부(`prepareFill`/`passthrough`/`rawPassthrough`)의 fallback을 `metadata.contentType`(HEAD 단계 열화 가능)에서 `Self.fallbackContentType(for: source)`(확장자 유래)로 교체.
- `boundedData(for:lowerBound:count:)` 신설 — 응답을 스트리밍하며 `lowerBound`만큼 skip 후 `count`(또는 미상 시 `unboundedPassthroughLimit`=8MB)까지만 수집하고 스트림 종료(반복자 조기 해제 → `onTermination` → 네트워크 태스크 취소). `count == nil`이고 8MB에 도달하면 `.entryTooLarge`.
- 적용 3곳: `passthrough`, `rawPassthrough`, `remoteMetadata`의 `bytes=0-0` GET 프로브(count=1).
- **픽스처 shim(설계 §E-4w 명시 허용)**: `ABFakeHTTPFetcher.stream(for:)`와 `ABControlledHTTPFetcher.stream(for:)`에 "큐가 고갈되면 다음 `dataReplies` 항목을 `.response`+`.data` 스트림으로 변환" 로직 추가 — 기존 어서션은 **한 줄도 변경하지 않음**(git diff로 확인, 아래 §3).

### E-5w — `ABResourceLoaderDelegate` 직접 테스트
- `ABLoadingRequesting`/`ABLoadingContentInformation`/`ABLoadingDataRequesting` internal 프로토콜 신설(신규 파일 `ABLoadingRequestServicer.swift`) + `ABAVLoadingRequestAdapter`/`ABAVLoadingContentInformationAdapter`/`ABAVLoadingDataRequestAdapter`(AVFoundation 어댑터).
- 태스크 본문을 `ABLoadingRequestServicer.service(_:source:store:) async`로 순수 추출(동작 변경 0). `ABResourceLoaderDelegate`는 어댑터를 만들어 위임하는 얇은 wiring만 남음.
- 델리게이트에 `hasBegunSession`(락 보호) once-플래그 추가 — 첫 로딩 요청에서 **동기적으로**(스폰한 `Task` 밖에서) `store.beginAssetSession(for: source)` 호출.

---

## 2. 신규 파일

- `Sources/ABPlayerKitCache/ABContentRange.swift`
- `Sources/ABPlayerKitCache/ABLoadingRequestServicer.swift`
- `Tests/ABPlayerKitCacheTests/ABLoadingRequestServicerTests.swift`

## 3. 검증 결과

- **빌드**: `xcodebuild build -scheme ABPlayerKitCache -destination 'generic/platform=iOS'` → **BUILD SUCCEEDED**, 경고 0건 · 에러 0건.
- **테스트 빌드**: `xcodebuild build-for-testing -scheme ABPlayerKitCache -destination 'generic/platform=iOS'` → **TEST BUILD SUCCEEDED**, 경고 0건 · 에러 0건.
- **테스트 실행**: 부팅된 시뮬레이터 없음(`xcrun simctl list devices booted` 확인, 새 시뮬레이터 부팅은 브리프 금지 사항) → **실행하지 못함**. 빌드 검증까지만 완료. 다음 세션에서 부팅된 시뮬레이터로 `xcodebuild test -scheme ABPlayerKitCache -destination 'platform=iOS Simulator,...'` 실행 필요.
- **무수정 통과 확인(정적)**: `git diff Tests/ABPlayerKitCacheTests/ABCacheStoreTests.swift`의 삭제 라인을 전수 확인 — 두 픽스처의 `stream(for:)` 구현 교체 1곳씩(§E-4w에서 명시적으로 허용된 shim) 외에 기존 `@Test`/`#expect` 코드는 **한 줄도 삭제되지 않음**(순수 추가만 발생). §6 표에 열거된 무수정 통과 강제 테스트(`:540`, `:583`, `:975`, `:638`/`:679`, `:709`, `:786`/`:847`/`:864`, `:934` 상당)는 소스 레벨에서 변경 없음 — 단, 시뮬레이터 미부팅으로 실제 그린 실행은 다음 세션 확인 필요.
- **공개 API diff**: `git diff -- Sources/ABPlayerKitCache/ | grep '\bpublic\b'` → 매치 0건(주석 내 "public.data" UTI 문자열 언급 1건은 오탐, `public` 키워드 아님). 신규 `public` 심볼 없음 확인.
- **마이그레이션 무결성**: `ABCacheIndex.Entry.validator`는 옵셔널 additive 필드 — 기존 인덱스 JSON에 키가 없으면 `nil`로 디코드(코드 변경 없이 `Codable` 기본 동작). 별도 백필/버전 코드 불필요(설계 §4 그대로 적용, 구현 중 추가 변경 없음).

## 4. §8 완료 정의 체크리스트

- [x] 감사 E-1, E-2, E-3, E-5, E-6, E-8 해소. E-4는 부분 해소(청크당 open/close 제거) + 잔여 문서화(DocC). E-7은 문서화만.
- [x] §6의 기존 테스트 무수정(소스 diff로 확인) — **단, 시뮬레이터 미부팅으로 실제 실행 그린은 미확인**(빌드 성공만 확인).
- [x] Swift 6 zero-warning(빌드/테스트빌드 둘 다 확인).
- [x] 신규 테스트: E-1w 9건, E-2w 3건, E-3w 5건, E-4w 5건, E-5w 7건 = 29건 + `ABContentRange` 파서 단위 테스트 4건(보너스, 설계 §1.2-5 "순수 값 타입이므로 `ABCachePrimitiveTests`에서 단위 테스트" 명시 반영) = **총 33건 순증**.
- [x] 공개 API 변경 0건 확인(diff에 `public` 신규 심볼 없음).
- [x] 기존 캐시 디렉터리를 가진 상태로 시작해도 인덱스가 폐기되지 않음(마이그레이션 무결성 — 코드 근거로 확인, 별도 통합 테스트는 작성하지 않음. `corruptedIndexRecoversAsEmpty`/`indexEntryWithMissingFileIsDropped` 기존 테스트가 인접 경로를 이미 커버).
- [x] CHANGELOG `### Fixed` 2건 + `removeAll` 동작 변경 Migration 노트 1줄 — 아래 §5.
- [x] DocC "Known constraints" 절 존재(`ABPlayerKitCache.docc/ABPlayerKitCache.md`).

## 5. CHANGELOG 초안

```markdown
### Fixed
- Progressive cache: resuming a partial download now validates the origin
  hasn't changed (`If-Range`/`ETag`/`Last-Modified`, with a defensive
  `Content-Range` offset/length check for origins with no validator)
  before appending to the cached prefix, instead of silently mixing bytes
  from two different versions of the resource.
- `ABMediaCache.removeAll()`/`remove(_:)` no longer fail playback that's
  in progress for the deleted key — the current read completes over the
  network and the cache refills as playback continues.

### Migration
- Calling `removeAll()`/`remove(_:)` during active playback for the
  affected source no longer interrupts that playback; it continues over
  the network instead of failing. No code changes required.
```

## 6. 게이트 문의 사항

없음. 설계 §5의 테스트 목록을 전부 구현했고, §6의 무회귀 가드(락 기반 `nonisolated` 레지스트리 신규 도입 1개로 제한, 기존 취소/coalescing 코드 미수정, `fillHandles` 도입이 eviction 제외 집합 계산에 개입하지 않음)를 코드 레벨에서 준수했습니다.

**단, 검증 한계 1건을 명시적으로 보고합니다**: 이 세션에는 부팅된 iOS 시뮬레이터가 없어 `xcodebuild test`를 실행하지 못했습니다. 빌드/테스트-빌드 zero-warning은 확인했고, §6 무수정 통과 대상 테스트의 소스 코드가 손대지지 않았음도 diff로 확인했지만, **실제 테스트 스위트 그린 실행은 다음 세션(시뮬레이터 부팅 후)에서 확인이 필요**합니다. E-6 최종 게이트(Opus) 진행 전 이 실행 확인을 권장합니다.
