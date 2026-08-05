# RESULT: README 스크린샷 추가

`Examples/ABPlayerKitDemo`를 부팅된 시뮬레이터(iPhone Air, 새 시뮬레이터 부팅 없음)에 빌드·설치·실행하여 스크린샷 4장을 캡처하고 README.md / README.ko.md에 삽입했다. 커밋은 하지 않았다.

## 환경

- 기기: iPhone Air (UDID `65CDD0F3-DEE7-4132-B823-E86003329F5E`), 작업 시작 전부터 Booted 상태였던 기기 그대로 사용.
- 빌드: `xcodebuild -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj -scheme ABPlayerKitDemo -destination "id=<UDID>"` (BUILD SUCCEEDED).
- 설치/실행: `xcrun simctl install` + `xcrun simctl launch com.appboong.ABPlayerKitDemo`.
- 조작: `orca emulator tap <x> <y>` (0–1 정규화 좌표, orca-cli 스킬 경유). 좌표는 `xcrun simctl io screenshot`으로 캡처한 프레임을 기준으로 픽셀 위치를 확인한 뒤 화면 비율로 환산했다.
- 캡처: `xcrun simctl io <UDID> screenshot`.

## 캡처 파일 (docs/assets/)

| 파일 | 내용 | 조작 시퀀스 |
|---|---|---|
| `playback-screen.png` | 재생 화면 — Apple HLS bipbop 테스트 스트림의 실제 디코딩 프레임(NTSC 테스트 카드, 타임코드 진행 중), 컨트롤 자동 숨김 상태 | Playback grade를 Preload → Current로 전환 후 재생, 수 초 대기 |
| `controls-overlay.png` | 컨트롤 오버레이 — 재생/일시정지, ±20s 스킵, 스크러버, 액세서리(★), 배속(1×) 전부 노출된 상태 | 재생 중 영상 영역 탭 → 오버레이 재노출 |
| `style-tinted.png` | 스타일 변형 — Controls 피커에서 Tinted 선택, 파란색 틴트가 적용된 트랜스포트/스크러버/배속 | Tinted 세그먼트 탭 → 영상 탭으로 오버레이 노출 |
| `cache-screen.png` | 캐시 화면 — Progressive MP4 트랜스페어런트 캐시 토글/디스크 사용량, HLS prefetch 상태 및 액션 버튼 | 하단 탭바에서 Cache 탭 전환 |

각 이미지는 원본 시뮬레이터 스크린샷(1260×2736)에서 위쪽 핵심 영역만 크롭했다(재생 3종은 상태바+타이틀+영상, 캐시는 헤더+두 카드 섹션까지). 파일명은 소문자-하이픈 규칙을 따른다.

Metrics 탭도 확인했으나 이번 세션에서 TTFF 샘플이 기록되지 않아 전 항목이 0으로 표시되어(p50/p95/Hit rate/Abandon rate/Samples 전부 0) 스크린샷 가치가 낮다고 판단, 대신 실제 데이터가 있는 Cache 탭을 4번째 스크린샷으로 채택했다.

## README 변경 요약

- `README.md`, `README.ko.md` 각각 인트로 문단(패키지 설명) 바로 다음, `## Requirements` / `## 요구 사항` 섹션 바로 앞에 2×2 `<table>` 스크린샷 갤러리를 삽입했다.
- 각 셀은 `width="240"` `<img>` + `<sub>` 캡션으로 구성 (재생 화면 / 컨트롤 오버레이 / Tinted 스타일 변형 / 캐시 화면 — 한국어판은 국문 캡션).
- 갤러리 아래에 출처 한 줄(`Examples/ABPlayerKitDemo`, Apple HLS bipbop 테스트 스트림)을 명시했다.
- 이미지 경로는 `docs/assets/*.png` 상대 경로(레포 루트 기준)를 사용했다.

## 참고 / 후속

- 시뮬레이터는 캡처 종료 시점 상태(Cache 탭, Tinted 스타일 선택)로 남아 있다. 별도 정리는 하지 않았다.
- Metrics 탭에 실제 TTFF 샘플이 쌓인 스크린샷이 필요하면, 재생을 여러 번 완주시키거나 grade를 Preloaded로 되돌렸다가 Current로 재전환하는 시퀀스를 추가로 밟아야 한다.
