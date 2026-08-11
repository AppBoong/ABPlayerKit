# RESULT: 라운드6 트랙 CI — 픽스 라운드 3 (커버리지 요약 Python SyntaxError 대응)

담당: Sonnet, worktree `round6/ci`. 커밋 없음(작업 트리 변경만). 기준: 픽스2 이후 `lint` PASS, `thread-sanitizer` PASS(실제 테스트 실행, 데이터 경합 0), `build-and-test`의 테스트도 통과했으나 `Summarize coverage` 스텝이 Python `SyntaxError`로 실패.

## 원인

`.github/workflows/ci.yml`의 `Summarize coverage` 스텝에서 `python3 -c '...'`를 **bash single-quote 문자열**로 감쌌는데, 그 안의 f-string에서 `report[\"lineCoverage\"]`처럼 백슬래시로 큰따옴표를 이스케이프했다. bash single-quote 안에서는 백슬래시가 전혀 특수 문자가 아니므로 `\"`가 글자 그대로(백슬래시 포함) Python으로 전달되고, f-string의 `{}` 표현식 내부에 백슬래시가 들어간 형태가 되어 `SyntaxError: f-string expression part cannot include a backslash`(3.12 미만) 가 발생함. 애초에 single-quote 안이라 이스케이프 자체가 불필요했다.

## 조치

- `.github/workflows/ci.yml`: `print(f"{report[\"lineCoverage\"] * 100:.1f}")` → `print(round(report["lineCoverage"] * 100, 1))`로 교체. 사용자 권고안(백슬래시 제거 + f-string 중첩 따옴표 회피)을 그대로 채택 — f-string 자체를 없애 3.12 미만 호환성 문제의 근본 원인을 제거.
- `.github/scripts/prepare-simulator.sh`의 인라인 Python 3곳(`runtime_id`/`device_type_id`/`name` 조회, 모두 `python3 -c '...'`)과 `select_udid` 함수의 heredoc(`<<'PY'`)을 전수 재검토: `\"` 패턴 없음 확인(`grep -rn '\\\\"' .github` 결과 0건). 애초에 이 파일은 큰따옴표만 사용하고 있어 동일 버그 클래스에 해당하지 않음 — 수정 불필요.

## 검증 결과 (요청대로 셸 문자열을 그대로 복사해 로컬 bash로 실행)

| 대상 | 방법 | 결과 |
|---|---|---|
| `Summarize coverage`의 수정된 Python (YAML 블록 스칼라 디덴트 후 실제 bash가 보는 형태로 재구성) | 샘플 JSON(`{"lineCoverage": 0.0}` ~ `0.803456789` 등 7종, 0/1/60%대/80%대/소수점 경계 포함) 파이프 실행 | **PASS** — 전부 `NN.N` 형태로 정확히 출력(`0.0`, `100.0`, `66.7`, `99.5`, `60.0`, `80.0`, `80.3`), 에러 없음 |
| 동일 값들을 `Write coverage badge data`의 `awk` 임계치 로직에 통과 | 7개 값 모두 색상 분기 확인 | **PASS** — 0.0→red, 60.0/66.7→yellow, 80.0 이상→brightgreen (기존 의도와 동일) |
| `prepare-simulator.sh`의 `runtime_id` 조회 Python | 샘플 `simctl list runtimes available -j`(iOS 17.5/18.2 + tvOS 18.2 혼합) | **PASS** — iOS만 필터링 후 최신 버전(18.2) identifier 정확히 선택 |
| `prepare-simulator.sh`의 `device_type_id` 조회 Python | 샘플 `simctl list devicetypes -j`(iPhone SE/16/16 Pro/16 Pro Max + iPad) | **PASS** — iPhone만 필터링, `Pro` 포함 중 마지막 항목(iPhone 16 Pro Max) 선택 — 기존에 문서화된 휴리스틱과 일치, 새 버그 아님 |
| `prepare-simulator.sh`의 UDID→이름 조회 Python | 샘플 `simctl list devices -j`(iOS/tvOS 혼합, 대상 UDID 포함) | **PASS** — 정확한 디바이스 이름 반환 |
| `python3 -c yaml.safe_load(...)` | `.github/workflows/ci.yml` 전체 재파싱 | **PASS** — 4개 잡 확인 |
| `actionlint` (1.7.12) | `.github/workflows/ci.yml` | **PASS** — 0 findings (임베디드 `run:` 블록의 shellcheck 검사 포함) |
| `shellcheck` | `.github/scripts/prepare-simulator.sh`(무변경, 재확인) | **PASS** — 0 findings |

**주의**: 로컬 검증 시 YAML의 `run: \|` 블록 스칼라가 모든 라인을 동일 폭으로 디덴트한다는 점을 반영해, 실제 bash가 받는(선행 공백 없는) 형태로 스크립트를 재구성한 뒤 테스트했다. 파일에 적힌 그대로(10칸 들여쓰기 유지)의 텍스트를 그대로 복붙해 실행하면 `IndentationError`가 발생하는데, 이는 로컬 재현 방법의 문제일 뿐 실제 CI 실행 경로에서는 발생하지 않는 현상임을 확인했다(YAML 디덴트가 사전에 제거하기 때문).

## 남은 리스크

- CI-1/2/3/4에 걸쳐 이번이 세 번째 픽스 라운드다. 실패 유형이 매번 "로컬 검증 범위 밖의 실행 경로"(테스트 컴파일, 인라인 스크립트의 실제 셸 해석 결과)였던 점을 감안하면, 다음에 유사한 인라인 스크립트를 CI 워크플로에 추가할 때는 이번처럼 **YAML 디덴트 후 형태로 재구성해 로컬에서 실행**하는 것을 표준 절차로 삼는 편이 안전하다. 별도 문서화는 이번 픽스 범위 밖이라 수행하지 않음.
- 이 라운드 이후 남은 것으로 파악된 CI 이슈는 없음(사용자 보고 기준 "마지막 하나"). `coverage-badge` 잡(≠`build-and-test`)은 `main` push에서만 실행되므로 이번 PR 실행에서는 여전히 검증되지 않은 상태 — RESULT-round6-ci.md/-fix1.md에서 이미 문서화한 리스크와 동일, 추가 조치 없음.

## 변경 파일 목록

```
M  .github/workflows/ci.yml
```
