# RESULT: 라운드6 트랙 CI — 픽스 라운드 1 (PR #1 첫 CI 실행 실패 대응)

담당: Sonnet, worktree `round6/ci`. 커밋 없음(작업 트리 변경만). 기준: PR #1 첫 CI 실행에서 `build-and-test`/`thread-sanitizer`/`lint` 3개 잡 전부 실패.

## 변경 요약

### (1) `lint` 잡 — `swiftlint: command not found`

`.github/workflows/ci.yml`의 `lint` 잡에 설치 스텝 추가:

```yaml
- name: Install SwiftLint if missing
  run: |
    if ! command -v swiftlint >/dev/null 2>&1; then
      brew install swiftlint
    fi
```

`command -v` 가드로 이미 사전 설치된 러너 이미지에서는 즉시 스킵하고, 없는 이미지에서는 `brew install`로 설치. RESULT-round6-ci.md에서 이미 경고했던 리스크가 실제로 발생한 케이스.

### (2) `build-and-test` / `thread-sanitizer` 잡 — 'iPhone 16 Pro' 시뮬레이터 없음

**근본 원인**: 핀된 Xcode 16.4의 러너 이미지에 iOS 시뮬레이터 런타임(따라서 구체 디바이스)이 아예 없는 상태로 추정(요청에서 언급된 이미지 드리프트). 하드코딩된 `-destination "platform=iOS Simulator,name=iPhone 16 Pro"`가 매칭 디바이스를 찾지 못해 실패.

**조치**: 신규 스크립트 `.github/scripts/prepare-simulator.sh` 추가, 두 잡 모두 `Resolve toolchain` 스텝(기존 Xcode 핀 폴백 로직) 바로 뒤에 `Prepare iOS simulator` 스텝으로 실행:

1. `xcrun simctl list devices available -j`를 JSON 파싱(Python)해 이름이 `iPhone 16 Pro`(환경변수 `PREFERRED_SIMULATOR_NAME`)인 사용 가능한 디바이스를 탐색.
2. 정확히 일치하는 디바이스가 없으면, 가장 최신 iOS 런타임의 아무 `iPhone*` 디바이스로 폴백.
3. 후보가 전혀 없으면(= iOS 런타임 자체가 없는 상태) `xcrun simctl list runtimes available`로 재확인 후, iOS 런타임이 없을 때만 `xcodebuild -downloadPlatform iOS` 실행 → 최신 iOS 런타임 + `iPhone` 계열 디바이스 타입(가급적 `Pro`) 조합으로 `xcrun simctl create`.
4. 최종 선택된 디바이스의 UDID로 `DESTINATION=platform=iOS Simulator,id=<udid>`를 `$GITHUB_ENV`에 기록 — 이후 스텝의 `-destination "$DESTINATION"`이 그대로 이를 사용.

`id=`(UDID) 기반 destination을 사용해 이름 매칭 실패 문제를 근본적으로 우회. 두 잡의 `env:`에서 정적 `DESTINATION`을 제거하고 `PREFERRED_SIMULATOR_NAME: iPhone 16 Pro`로 대체.

**참고**: 이 스크립트는 시뮬레이터를 "찾아서 쓰거나, 없을 때만 새로 만든다" — 사용자 안내대로 "새 시뮬레이터 부팅 금지" 규칙은 로컬 환경(이 세션)에 적용되는 것이고 CI 러너(매번 새 macOS 인스턴스)에는 적용되지 않는다는 전제로 구현했다. `simctl create`는 디바이스를 "생성"만 하고 부팅하지 않으며, 부팅 자체는 이후 `xcodebuild test`가 필요 시 수행한다(기존 워크플로도 동일하게 동작해왔음 — 이번 변경으로 새로 생긴 동작이 아님).

**부수 조치**: `-downloadPlatform iOS` 경로가 실제로 타면 수 분~수십 분 걸릴 수 있어 두 잡의 `timeout-minutes`를 30 → 45로 상향.

## 검증 결과

| 항목 | 결과 |
|---|---|
| `python3 -c 'yaml.safe_load(...)'` | **PASS** — `.github/workflows/ci.yml` 파싱 성공, 4개 잡(`build-and-test`, `lint`, `thread-sanitizer`, `coverage-badge`) 확인 |
| `actionlint` (Homebrew로 로컬 설치, 1.7.12) | **PASS** — 0 findings (임베디드 `run:` 스크립트의 shellcheck 통합 검사 포함) |
| `shellcheck .github/scripts/prepare-simulator.sh` | **PASS** — 0 findings |
| `prepare-simulator.sh` 로컬 드라이런(이 macOS 호스트, 실제 `simctl` 데이터 대상) | **PASS(선택 로직만)** — `iPhone 16 Pro`는 이 호스트에 없어 폴백 경로로 진입, 사용 가능한 최신 런타임의 `iPhone 17 Pro`를 정상 선택하고 `DESTINATION=platform=iOS Simulator,id=<udid>`를 가짜 `$GITHUB_ENV` 파일에 정확히 기록함을 확인. **다운로드/생성 분기(`-downloadPlatform`, `simctl create`)는 로컬에 이미 런타임이 있어 실행되지 않음 — 미검증** |
| `xcodebuild ... test` 실 실행 | **미실행** — 이전 라운드와 동일 사유(부팅된 시뮬레이터 없음, 로컬 신규 부팅 금지 유지). 이번 스크립트가 실제 GitHub Actions 러너에서 처음 실행되는 것이 최초 실검증이 됨 |

## 남은 리스크

1. **`-downloadPlatform iOS` 분기 미검증**: 로컬에 이미 iOS 런타임이 있어 이 코드 경로를 한 번도 실행해보지 못했다. 만약 핀된 Xcode 16.4 이미지에 정말 iOS 런타임이 0개라면 이 분기가 실제로 타게 되는데, 러너의 네트워크/디스크 상황에 따라 다운로드가 45분 타임아웃을 넘길 가능성이 있다. 첫 실행에서 타임아웃 발생 시 `timeout-minutes`를 더 올리거나, 핀된 Xcode 버전 자체를 러너 이미지에 실제로 존재하는 버전으로 재조정하는 근본 대응이 필요.
2. **디바이스 타입 자동 선택**: `Pro` 포함 최신 `iPhone*` 디바이스 타입을 고르는 휴리스틱이라, 러너에 따라 `iPhone 16 Pro`와 화면 크기·기능이 다른 기기가 선택될 수 있음(스냅샷/픽셀 단위 UI 테스트가 있다면 흔들릴 수 있음 — 현재 스위트에는 없는 것으로 파악되나 재확인 권장).
3. **`swiftlint` brew install 소요 시간**: 최초 실행 시 몇십 초~1-2분 추가 소요(캐시 없음). 반복 실행 비용이 누적되면 `actions/cache`로 Homebrew 캐시를 도입하는 것을 다음 라운드 후보로 남김(이번 라운드 범위 밖).
4. **`badges` 브랜치 미생성 상태는 이전 RESULT와 동일하게 유지** — `main` 병합 후 최초 성공 실행 전까지 커버리지 배지가 "invalid"로 보일 수 있음.

## 변경 파일 목록

```
M  .github/workflows/ci.yml
A  .github/scripts/prepare-simulator.sh
```
