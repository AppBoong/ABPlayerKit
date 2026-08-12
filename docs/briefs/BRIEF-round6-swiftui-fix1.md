# BRIEF: 라운드6 트랙 S — PR #4 CI 실패 수정 (fix1)

PR #4(`round6/swiftui`)의 `build-and-test`가 실패했다. `lint`와 `thread-sanitizer`는 통과했다.

## 관측 사실

`ABPlayerKitControlsTests`의 SwiftUI 호스팅 테스트 **11개가 전부 180초 스위트 제한을 초과**했다. 목록:

- `ABPlayerControlsSwiftUITests`: `:10`, `:25`, `:46`, `:64`, `:77`, `:88`, `:103` — **전부 이번 브랜치 이전부터 있던 기존 테스트**
- `ABVideoPlayerWithControlsTests`: `:10`, `:38`, `:61`, `:124` — `:124`는 이번에 추가한 `url:` 마운트 + `.playerControlsStyle` 테스트

**핵심 단서**: 기존 테스트까지 함께 멎었다. 즉 개별 테스트의 로직 오류가 아니라, **누군가 메인 액터를 오래 점유해 형제 테스트들이 굶고 있다**는 뜻이다. Swift Testing은 스위트를 병렬 실행하고 이 테스트들은 전부 `@MainActor`다.

로컬(부팅된 시뮬레이터, 10코어)에서는 두 타깃 385개가 1.4초에 전부 통과한다 — CI 러너(3 vCPU)에서만 드러나는 문제다.

## 유력 가설 (검증하고, 틀리면 그대로 보고할 것)

이번에 추가한 `url:`/`source:` 편의 생성자는 **`autoplay` 기본값이 `true`**다. 이 테스트들이 `UIHostingController` +
`UIWindow`로 뷰를 마운트하면 실제 `AVPlayer`가 생성되고 재생이 시작된다. 실제 디코딩·IO가 도는 동안 메인 액터가
점유되면, 같은 액터에서 병렬 실행되는 다른 모든 테스트가 굶는다. 로컬에서는 자원이 넉넉해 눈에 띄지 않는다.

이 가설이 맞다면 문제는 **테스트가 실제 재생을 시작한다**는 점이지 제품 코드의 결함이 아니다.

## 과제

1. **원인 규명**: 위 가설을 실제로 검증하라. 신규 테스트가 어떤 URL을 쓰는지, 재생이 실제로 시작되는지,
   그리고 그 테스트만 제외했을 때 나머지가 정상 속도로 도는지 확인하라. 가설이 틀리면 다른 원인을 찾아 그대로 보고하라.
2. **수정**: 원인에 맞게 고쳐라. 가설이 맞다면 신규 테스트가 **실제 재생을 시작하지 않도록** 하는 것이 방향이다
   (예: `autoplay: false`로 마운트해 소유권·modifier 전파라는 **검증 대상 자체**는 그대로 확인). 다만
   `autoplay: true` 기본값이 실제로 재생을 시작하는지 확인하는 테스트가 필요하다면, 그 한 건만 격리하는 방법을 택하라.
   - **주의**: 검증 의도를 훼손하지 말 것. 이 테스트들은 "URL 마운트가 플레이어를 만들고 소유하며 modifier가
     합성 뷰를 관통한다"를 검증한다 — 재생 여부는 대부분의 경우 그 검증의 본질이 아니다.
   - 타임아웃 숫자를 키우는 방식은 금지.
3. **파일 경계**: `Sources/ABPlayerKit/Engine/ABPlayer.swift`·`ABAVPlaybackTarget.swift`·
   `Sources/ABPlayerKitControls/View/ABPlayerControlsView.swift`는 여전히 수정 금지.
   테스트 파일과 이번 트랙이 만든 SwiftUI 파일만 손대라.

## 검증

부팅된 시뮬레이터 재사용(iPhone 17 Pro, UDID `55A3A4F3-3F02-43E6-9B23-116BD15D3345`, 새로 부팅·생성 금지).

- **전체 스킴 테스트**를 실행하라(`-only-testing` 금지). 4개 타깃 전부, **3회 연속 그린**.
- 각 실행에서 `ABPlayerControlsTests` 스위트의 **소요 시간**을 기록하라 — 수정 전후 비교가 이번 수정의 근거다.
- Swift 6 zero-warning, `swiftlint lint --strict` 0 violations 유지.

## 산출물

`docs/briefs/RESULT-round6-swiftui-fix1.md` — 가설 검증 결과(맞았는지 틀렸는지), 확정 원인, 적용한 수정과 그것이
검증 의도를 어떻게 보존하는지, 3회 실행 결과와 소요 시간 비교. **커밋 금지.** 이 파일 작성이 완료 신호다.
