# BRIEF: 라운드6 트랙 E 설계 게이트 (E-0) — Opus

당신은 라운드6 트랙 E(캐시 무결성)의 **설계 게이트**입니다. 코드를 수정하지 말고, 설계 문서만 산출하세요.

## 입력 (반드시 먼저 읽을 것)

1. `docs/briefs/ROADMAP-round6.md` — §0 컨벤션, §2 트랙 E, §6 리스크
2. `docs/briefs/REVIEW-round6-portfolio-audit.md` — 섹션 E(E-1~E-8), "강점" 목록(캐시 취소/coalescing 불변식은 라운드3~4 확립 — 건드리지 말 것)
3. 실제 소스: `Sources/ABPlayerKitCache/` 전체 — 특히 `ABCacheStore.swift`, `ABCacheIndex.swift`, `ABResourceLoaderDelegate.swift`, `ABCacheProgressWaiter`. 감사 항목의 위치(파일:라인)를 직접 확인할 것.

## 결정해야 할 사항 (ROADMAP §2 트랙 E-0)

1. **`If-Range`/`ETag` 재개 검증 프로토콜** (E-1): `bytes=N-` 재개 시 `Content-Range` 시작 검증 + `ETag`/`Last-Modified` 저장·`If-Range` 송신 설계. **검증 실패 시 prefix 폐기 후 재시작 vs 엔트리 무효화** 중 결정하고 근거 제시. 검증자(validator) 부재 원본의 처리 방침 포함.
2. **메타데이터 재검증 시점**: TTL vs 재생 시작 시 조건부 검증 vs 없음 — 결정과 근거.
3. **`removeAll`/`remove` vs reader 조정** (E-3): 지연 삭제(reader 종료 후 삭제) vs 실패 허용+문서화 중 결정. 데모 "캐시 비우기" 버튼 + 재생 중 시나리오를 기준으로.
4. E-2(FileHandle defer close + fill 수명 writer 핸들 유지), E-4 일부(청크당 open/close 제거), E-5(content-type 폴백), E-6(Range 무시 원본 메모리 상한), E-8(`ABResourceLoaderDelegate` 직접 테스트 전략)의 구현 방향을 WP(E-1w~E-5w) 단위로 요약.

**범위 제외**: sparse range(라운드5 트랙2)는 이번 라운드 아님. E-7(LRU 최적화)은 이월 — DocC 제약 문서화만 언급.

## 산출물

`docs/briefs/DESIGN-round6-cache.md` 생성. 구조:

- 결정 1~3 각각: 선택안, 기각안과 기각 사유, 실코드 근거(파일:라인)
- 저장 포맷/인덱스 변경이 있다면 마이그레이션 방침(기존 캐시 엔트리 처리)
- WP별(E-1w~E-5w) 구현 지침 요약 + 테스트 전략
- 무회귀 가드: 기존 취소/coalescing 불변식(`ABCacheProgressWaiter`, UUID 동일성) 보존 방법

## 제약

- **코드 수정 금지, 커밋 금지.** 산출물은 위 설계 문서 1개뿐.
- 시뮬레이터 부팅 금지, 빌드/테스트 실행 불필요(읽기 전용 분석).
- 설계 문서 작성 완료가 곧 작업 완료 신호입니다. 완료 후 추가 작업 없이 대기하세요.
