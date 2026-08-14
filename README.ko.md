# ABPlayerKit

[English](README.md)

![iOS 17+](https://img.shields.io/badge/iOS-17%2B-000000?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![MIT](https://img.shields.io/badge/License-MIT-blue.svg)
[![CI](https://github.com/AppBoong/ABPlayerKit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AppBoong/ABPlayerKit/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2FAppBoong%2FABPlayerKit%2Fbadges%2Fcoverage.json)](https://github.com/AppBoong/ABPlayerKit/actions/workflows/ci.yml)

**`AVPlayer`를 얇게 감싸면서 재생 자원의 소유권을 명시하는, 측정 가능한 래퍼입니다.**

한 줄로 영상을 재생하거나, 화면에 들어오기 전에 미디어를 미리 준비하고 벗어나면 디코더를 모두 반납하는 피드를 직접 제어할 수 있습니다 — 그 아래의 AVFoundation을 가리지 않으면서요.

```swift
ABVideoPlayerWithControls(url: url)
```

### 주요 기능

- **한 줄 재생.** 표준 컨트롤 오버레이를 그대로 쓰거나, 직접 만든 UI를 얹을 수 있습니다.
- **네 단계 소유권 모델**(`.released` → `.instanceOnly` → `.preloaded` → `.current`). 피드가 인접 미디어를 미리 준비하면서도, 화면 밖 셀의 네트워크 활동이 0임을 보장합니다. 강등은 승격의 정확한 역연산입니다.
- **정확한 첫 프레임 표시 시간(TTFF).** 현재 아이템에 대해 `AVPlayerLayer.isReadyForDisplay`와 `AVPlayerItem.status == .readyToPlay`가 **모두** 참일 때만 첫 프레임이 표시된 것으로 봅니다 — 단순히 재생이 시작된 시점이 아닙니다.
- **커스터마이즈 가능한 컨트롤** — 색상, 아이콘, 스킵 간격, 더블탭 시크, 액세서리 슬롯, 배속 메뉴. 뷰마다 지정하거나 view modifier로 화면 전체에 한 번에 적용합니다.
- **백그라운드·PiP·AirPlay·잠금화면 재생**을 명시적인 옵트인 정책으로 제공합니다.
- **선택형 메트릭과 캐시**를 별도 링크 타겟으로 분리했습니다. QoE 세션 요약, 프로그레시브 MP4 캐싱, 명시적 HLS 프리페치.
- **Swift 6 언어 모드**, `@MainActor`로 격리된 UI, `Sendable` 설정 값.

<table>
<tr>
<td align="center" width="50%">
<img src="docs/assets/playback-screen.png" width="240" alt="실제 디코딩된 영상 프레임이 보이는 재생 화면"><br>
<sub>재생 화면</sub>
</td>
<td align="center" width="50%">
<img src="docs/assets/controls-overlay.png" width="240" alt="트랜스포트, 스크러버, 배속 메뉴가 있는 컨트롤 오버레이"><br>
<sub>컨트롤 오버레이</sub>
</td>
</tr>
<tr>
<td align="center" width="50%">
<img src="docs/assets/style-tinted.png" width="240" alt="Tinted 컨트롤 스타일 변형"><br>
<sub>Tinted 스타일 변형</sub>
</td>
<td align="center" width="50%">
<img src="docs/assets/cache-screen.png" width="240" alt="디스크 사용량과 HLS 프리페치 상태를 보여주는 캐시 화면"><br>
<sub>캐시 화면</sub>
</td>
</tr>
</table>

스크린샷은 `Examples/ABPlayerKitDemo` 앱에서 Apple HLS bipbop 테스트 스트림을 재생한 화면입니다.

## 왜 ABPlayerKit인가

**`AVKit.VideoPlayer`와 비교하면** — AVKit은 플레이어와 시스템 컨트롤을 한 줄로 제공하며, 상세 화면에 영상 하나를 띄우는 경우라면 그게 정답입니다. 다만 자원 소유권을 통제할 수단이 없고, 화면에 나타나기 전에 미디어를 준비할 방법도, 시스템 외형을 벗어난 스타일링도, 측정 훅도 없습니다. ABPlayerKit은 한 줄짜리 사용법을 유지하면서 그 네 가지를 더합니다.

**`AVPlayer`를 직접 쓰는 것과 비교하면** — 같은 `AVPlayer`를 그대로 쓰되(`player.avPlayer`로 계속 접근 가능합니다), 미묘하게 틀리기 쉬운 부분을 매번 손으로 짜지 않아도 됩니다. 아이템 상태와 레이어 준비 여부에 대한 KVO, 아이템 해제 순서, 여러 플레이어가 공유하는 오디오 세션 활성화, 백그라운드/포그라운드 부작용, 그리고 "재생이 시작됐다"와 "화면에 프레임이 떴다"의 차이 같은 것들입니다.

**필요하지 않을 수도 있는 경우** — 영상 하나, 시스템 컨트롤, 프리로드 없음, 측정 없음. 그렇다면 `AVKit.VideoPlayer`가 코드도 적고 의존성도 하나 줄어듭니다.

이 라이브러리는 의도적으로 얇게 유지됩니다. AVFoundation을 추상화해 감추지 않고, 큐/재생목록 모델을 제공하지 않으며, 자막 선택 상태를 관리하지 않습니다 — [설계 근거](#설계-근거)를 참고하세요.

## 목차

- [요구 사항](#요구-사항)
- [설치](#설치)
- [빠른 시작](#빠른-시작)
  - [커스터마이징](#커스터마이징)
  - [플레이어를 직접 소유하기](#플레이어를-직접-소유하기)
  - [UIKit과 `ABPlayerView`](#uikit과-abplayerview)
  - [고급 — 등급과 프리로드](#고급--등급과-프리로드)
- [타겟별 사용법](#타겟별-사용법)
  - [`ABPlayerKit` — 코어](#abplayerkit--코어)
  - [`ABPlayerKitControls` — 재생 컨트롤](#abplayerkitcontrols--재생-컨트롤)
  - [`ABPlayerKitMetrics` — TTFF와 QoE](#abplayerkitmetrics--ttff와-qoe)
  - [`ABPlayerKitCache` — 캐시와 HLS 프리페치](#abplayerkitcache--캐시와-hls-프리페치)
  - [`ABPlayerKitNowPlaying` — 잠금화면과 원격 커맨드](#abplayerkitnowplaying--잠금화면과-원격-커맨드)
- [튜닝](#튜닝)
- [문제 해결](#문제-해결)
- [데모 앱](#데모-앱)
- [아키텍처](#아키텍처)
- [설계 근거](#설계-근거)
- [API 안정성](#api-안정성)
- [기여하기](#기여하기)
- [라이선스](#라이선스)

## 요구 사항

- iOS 17+
- Swift 6 언어 모드
- Xcode 16+

## 설치

Xcode에서 **File → Add Package Dependencies**를 선택하고 다음 주소를 추가합니다.

```text
https://github.com/AppBoong/ABPlayerKit.git
```

또는 `Package.swift`에 추가합니다.

```swift
dependencies: [
    .package(
        url: "https://github.com/AppBoong/ABPlayerKit.git",
        from: "0.4.0"
    )
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "ABPlayerKit", package: "ABPlayerKit"),
            // 필요할 때만 링크합니다.
            .product(name: "ABPlayerKitControls", package: "ABPlayerKit"),
            .product(name: "ABPlayerKitMetrics", package: "ABPlayerKit"),
            .product(name: "ABPlayerKitCache", package: "ABPlayerKit"),
            .product(name: "ABPlayerKitNowPlaying", package: "ABPlayerKit")
        ]
    )
]
```

릴리스 전 개발 버전을 사용하려면 `from: "0.4.0"`을 `branch: "main"`으로 바꾸세요. 애플리케이션에서는 위의 버전 조건 사용을 권장합니다.

필수는 `ABPlayerKit` 하나뿐입니다. 나머지 선택 제품은 링크하지 않으면 코드 자체가 앱에 포함되지 않습니다 — [타겟별 사용법](#타겟별-사용법)을 참고하세요.

## 빠른 시작

URL 하나로 표준 컨트롤까지 재생합니다 — 이게 통합의 전부입니다.

```swift
import ABPlayerKit
import ABPlayerKitControls
import SwiftUI

struct VideoScreen: View {
    var body: some View {
        ABVideoPlayerWithControls(url: URL(string: "https://example.com/video.m3u8")!)
            .aspectRatio(16 / 9, contentMode: .fit)
    }
}
```

이 뷰는 스스로 `ABPlayer`를 만들고, 재생을 시작하며, SwiftUI가 뷰를 폐기할 때 모든 재생 자원을 해제합니다. 미디어 종류는 URL에서 추론됩니다(`.m3u8` → HLS, 그 외 → progressive).

컨트롤 오버레이 없이 코어 타겟만 쓰려면:

```swift
import ABPlayerKit
import SwiftUI

ABVideoPlayer(url: url, videoGravity: .resizeAspect)
```

> **왜 어떤 예제 끝에는 `{}`가 붙나요?**
> 위의 `url:`/`source:` 이니셜라이저는 트레일링 클로저를 받지 않습니다. 반면 `player:` 이니셜라이저는 받습니다 — `ABVideoPlayerWithControls(player: player) {}` 처럼요. 배열 기반의 구형 `accessoryViews:` 이니셜라이저가 아직 deprecated 상태로 남아 있어서, 클로저 없이 호출하면 그쪽으로 해석되어 경고가 나기 때문입니다. 빈 중괄호는 현재 이니셜라이저를 고르게 합니다. `{}` 자리에 실제 뷰를 넣으면 직접 만든 컨트롤을 오버레이할 수 있습니다. [API 안정성](#api-안정성)을 참고하세요.

### 커스터마이징

컨트롤의 외형과 동작은 view modifier로 설정하므로, modifier 하나로 화면 전체의 플레이어를 한 번에 다룰 수 있습니다.

```swift
var style = ABPlayerControlsStyle.default
style.progressColor = .systemPink

var controls = ABPlayerControlsConfiguration()
controls.skipInterval = 15

ABVideoPlayerWithControls(url: url)
    .playerControlsStyle(style)
    .playerControlsConfiguration(controls)
```

플레이어 단 설정(음소거, 반복, 오디오 세션, 배속)은 생성 시점에 `ABPlayerConfiguration`으로 전달합니다.

```swift
var configuration = ABPlayerConfiguration()
configuration.isMuted = true
configuration.audioSessionPolicy = .playback(mixWithOthers: false)

ABVideoPlayerWithControls(url: url, playerConfiguration: configuration)
```

> 뷰가 화면 밖으로 나가도 살아 있는 동안에는 재생이 계속됩니다. 화면 전환에 따라 일시정지가 필요한 화면은 아래처럼 플레이어를 직접 소유하세요.

### 플레이어를 직접 소유하기

여러 뷰가 플레이어를 공유하거나, 재생이 뷰 하나보다 오래 유지되어야 하거나, 피드 전반에 걸쳐 프리로드를 직접 제어해야 할 때는 `ABPlayer`를 직접 소유합니다.

```swift
struct VideoScreen: View {
    @State private var player = ABPlayer()

    var body: some View {
        ABVideoPlayerWithControls(player: player, videoGravity: .resizeAspect) {}
            .aspectRatio(16 / 9, contentMode: .fit)
            .task {
                player.set(source: ABMediaSource(url: url), grade: .current)
                player.play()
            }
            .onDisappear {
                player.release()
            }
    }
}
```

Picture in Picture는 이 경로에서만 동작합니다 — [Picture in Picture](#picture-in-picture)를 참고하세요.

### UIKit과 `ABPlayerView`

```swift
import ABPlayerKit
import UIKit

@MainActor
final class PlayerViewController: UIViewController {
    private let player = ABPlayer()
    private let playerView = ABPlayerView()

    override func viewDidLoad() {
        super.viewDidLoad()

        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.player = player
        view.addSubview(playerView)

        let source = ABMediaSource(url: URL(string: "https://example.com/video.mp4")!)
        player.set(source: source, grade: .current)
        player.play()
    }
}
```

### 고급 — 등급과 프리로드

화면이 아직 보이지 않는 미디어를 미리 준비해야 할 때(예: 몇 줄 아래 있는 피드 셀) 플레이어 하나를 만들고 모든 소스/등급 변경을 `set(source:grade:)`로 처리합니다.

```swift
import ABPlayerKit

let source = ABMediaSource(
    url: URL(string: "https://example.com/video.m3u8")!,
    kind: .hls
)

let player = ABPlayer()
player.set(source: source, grade: .preloaded)

// 미디어가 화면에 표시될 때
player.set(source: source, grade: .current)
player.play()

// 프리로드 윈도우를 벗어날 때
player.set(source: source, grade: .instanceOnly)
```

| 등급 | 보유 자원 | 용도 |
|---|---|---|
| `.released` | 없음 | 모든 재생 자원 반환 |
| `.instanceOnly` | `AVPlayer`, 아이템 없음 | 플레이어 식별성은 유지하면서 아이템 네트워크 활동을 0으로 보장 |
| `.preloaded` | 플레이어 + 아이템, 프리로드 튜닝 | `play()`를 허용하지 않고 인접 미디어 준비 |
| `.current` | 플레이어 + 아이템, 현재 재생 튜닝 | 화면에 보이는 미디어이며 재생 제어 허용 |

- 아이템을 보유한 모든 해제 경로는 `detachItem`을 거칩니다.
- `.preloaded`와 `.current` 사이를 이동할 때 대응하는 튜닝 역할을 다시 적용하므로 강등은 승격의 정확한 역연산입니다.
- 재생 제어 호출은 `.current`에서만 받아들여집니다 — [거부된 호출](#실패-진단-거부된-호출)을 참고하세요.
- `ABMediaSource`의 `kind:`는 URL의 확장자에서 추론됩니다(`.m3u8` → `.hls`, 그 외 → `.progressive`). 이 추론이 틀릴 수 있는 서명된/확장자 없는 URL일 때만 명시적으로 지정하세요.

## 타겟별 사용법

| 제품 | 추가 기능 | 링크 시점 |
|---|---|---|
| `ABPlayerKit` | 재생 엔진, UIKit 렌더링, SwiftUI 비디오 래퍼 | 항상 |
| `ABPlayerKitControls` | 타임라인, 버튼, 배속 선택, 자동 숨김, UIKit/SwiftUI 컨트롤 | 표준 컨트롤 레이어가 필요할 때 |
| `ABPlayerKitMetrics` | TTFF 기록, QoE 세션, sink, 집계 | 재생을 측정할 때 |
| `ABPlayerKitCache` | 프로그레시브 캐시와 명시적 HLS 프리페치 | 오프라인/캐시 동작을 소유할 때 |
| `ABPlayerKitNowPlaying` | 잠금화면/제어 센터 연동(`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`) | 원격 커맨드/잠금화면 재생을 원할 때 |

각 타겟은 전체 API 레퍼런스를 담은 DocC 카탈로그도 함께 제공합니다 — Xcode의 **Product → Build Documentation**으로 빌드하세요.

### `ABPlayerKit` — 코어

코어 타겟은 재생 상태 머신, UIKit 뷰, SwiftUI 래퍼, 튜닝, 백그라운드/오디오 정책, 토큰 기반 이벤트를 소유합니다. 등급은 [고급 — 등급과 프리로드](#고급--등급과-프리로드)에서 다룹니다.

#### 이벤트

이벤트에는 여러 소비자가 독립적으로 연결할 수 있습니다.

```swift
let token = player.addObserver { event in
    if case .firstFrameDisplayed(let timestamp) = event {
        print("첫 프레임 표시 시각: \(timestamp)")
    }
}

// 관찰이 필요한 동안 token을 보관합니다.
token.cancel()
```

`ABPlayerEvent`는 비전수(non-exhaustive) 열거형으로 취급하세요. 마이너 릴리스에서 케이스가 추가될 수 있으므로 소비자 코드의 `switch`에는 반드시 `default` 분기를 두어야 합니다.

#### 실패, 진단, 거부된 호출

정상적인 진단이 실제 실패로 오인되지 않도록 실패를 두 프로퍼티로 분리했습니다.

| 프로퍼티 | 담는 것 | 초기화 시점 |
|---|---|---|
| `lastFailure` | 가장 최근의 **종료성(terminal)** 실패 | 다음 attach·소스 교체·detach·release |
| `lastDiagnostic` | 유일한 **비종료성** 케이스 `.itemErrorLogEntry` | 동일 |
| `lastError` | `lastFailure?.kind`를 계산하는 프로퍼티. `lastFailure` 이전에 작성된 코드와의 호환용 | 동일 |

- `ABPlayerFailure`는 기존 `ABPlayerError` 분류에, 알려진 경우 기반 `NSError`의 `domain`/`code`를 담은 `ABErrorOrigin`을 더한 값입니다. 분류만으로 충분하지 않은 경우를 위한 것입니다.
- 아직 로딩 중이거나 재생 중인 스트림은 `.itemErrorLogEntry`를 스스로 내놓고 회복하는 일이 흔하므로 `lastFailure`와 분리했습니다.
- **케이스를 직접 매칭하지 말고 `ABPlayerError.isTerminal`**(`ABPlayerFailure.isTerminal`로도 투영됨)로 분기하세요. 향후 릴리스가 새 케이스를 추가해도 처리가 깨지지 않습니다.
- 두 채널 모두 이벤트 스트림으로도 통지됩니다. 기존 `.failed(ABPlayerError)`와 같은 지점에서 `.failureReported(ABPlayerFailure)`가 함께 방송되며, 새 코드는 원인 정보를 담은 `.failureReported`를 우선 사용해야 합니다.

`grade != .current`인 상태에서의 재생 제어 호출(`play`/`pause`/`seek`/`skip`/스크러빙)은 **예외를 던지지 않고 무시됩니다.** `.playbackRejected`는 기존 신호로 남아 있고, `.callRejected(ABRejectedCall, grade:)`가 같은 지점에서 함께 방송되어 어떤 호출이 어떤 등급에서 무시됐는지 식별합니다.

#### 오디오 세션과 인터럽션

`ABPlayer`는 명시적으로 옵트인하지 않는 한 프로세스 전역 `AVAudioSession`을 절대 건드리지 않습니다 — 두 정책 모두 기본값이 꺼짐입니다.

```swift
var configuration = ABPlayerConfiguration()
configuration.audioSessionPolicy = .playback(mixWithOthers: false)
configuration.interruptionPolicy = .pauseAndResume
player.configuration = configuration
```

**`audioSessionPolicy`**(기본값 `.unmanaged`)

- `.playback` 또는 `.ambient`로 설정하면 이 플레이어가 `.current`가 되는 순간(또는 `play()` 시작 시) 카테고리가 적용되고, 자동으로 복원됩니다.
- 여러 플레이어가 동시에 존재하는 경우(피드의 `.preloaded`/`.current` 셀들) 프로세스 전역 `ABAudioSessionCoordinator` 하나를 공유합니다. 카테고리는 *최초* 참여 플레이어가 적용하기 직전에만 캡처되고 *마지막* 참여 플레이어가 해제될 때만 복원되므로, 한 플레이어의 `release()`가 세션을 여전히 사용 중인 다른 플레이어를 방해하지 않습니다.
- **주의**: 호스트 앱이 이 플레이어의 첫 참여자가 정책을 적용하기 전에 이미 `AVAudioSession`을 스스로 활성화해 둔 상태였다면, 마지막 해제 시점의 복원이 호스트가 활성화해 둔 세션을 그대로 비활성화할 수 있습니다. `AVAudioSession`은 "이미 활성 상태였는지"를 조회할 공개 API를 제공하지 않아 "우리가 활성화했다"와 구분할 수 없습니다 — 세션을 공유하는 호스트 앱이라면 이 점을 감안해 자체 세션 처리를 설계하세요.

**`interruptionPolicy`**(기본값 `.ignore`)

- `.pauseAndResume`으로 설정하면 전화, Siri, 다른 앱이 재생을 중단시켰을 때 자동으로 일시 정지하고, 인터럽션이 끝나면 재개합니다.
- 단, 시스템이 `AVAudioSessionInterruptionOptionKey.shouldResume`을 보고하고 **그리고** 이 플레이어가 실제로 재생 중이었을 때만 재개합니다.
- 재개 시 `audioSessionPolicy`가 사용하는 것과 동일한 coordinator를 통해 오디오 세션을 재활성화하므로 두 기능이 자동으로 함께 작동합니다.

**`pausesOnRouteChangeDeviceUnavailable`**(기본값 `true`, `interruptionPolicy`와 무관)은 현재 출력 장치가 사라지면(예: 헤드폰 분리) 일시 정지합니다 — 플랫폼 HIG 기대에 부합합니다. 원치 않으면 `false`로 설정하세요.

셋 모두 동일한 `ABPlayerEvent` 스트림으로 통지됩니다: `.audioInterruptionBegan`, `.audioInterruptionEnded(resumed:)`, `.audioRouteChangedDeviceUnavailable`.

#### 백그라운드 정책

`ABPlayerConfiguration.backgroundPolicy`는 `.current` 플레이어가 앱이 포그라운드를 벗어날 때 어떻게 반응할지 결정합니다. 기본값은 `.pause`입니다.

| 정책 | 백그라운드 진입 시 | 포그라운드 복귀 시 |
|---|---|---|
| `.ignore` | 아무것도 하지 않음 | 아무것도 하지 않음(오디오 세션을 재활성화 대상으로 표시하는 것 제외) |
| `.pause` (기본값) | `.current`면 일시정지 | 재생 중이었다면 재개 |
| `.pauseAndDetachLayer` | `.current`면 일시정지, `AVPlayerLayer.player`를 뗌(디코더 해제) | 레이어 재부착, 재생 중이었다면 재개 |
| `.demoteToInstance` | `.instanceOnly`로 강등(아이템 폐기, 네트워크 완전 차단) | 이전 등급 복원 |
| `.continueAudioOnly` | `AVPlayerLayer.player`만 뗌 — 재생은 계속됨 | 레이어 재부착, 시스템이 재생을 멈췄을 때만 재개 — 명시적 `pause()`는 절대 덮어쓰지 않음 |

`.continueAudioOnly`는 백그라운드 상태에서도 재생이 계속되는 유일한 정책이라, 사용자가 그 상태에서 일시정지할 수 있는 유일한 정책이기도 합니다 — 잠금 화면, Now Playing Center, 또는 Controls를 통해서요. 백그라운드 중 명시적으로 호출된 `pause()`는 그대로 우선하며 포그라운드 복귀 시에도 재개되지 않습니다. 위의 안전망 재개는 그 사이에 `pause()` 호출 없이 시스템이 스스로 재생을 멈춘 경우에만 적용됩니다.

아래 **세 조건이 모두** 갖춰져야 하며, 하나라도 빠지면 `.pause`처럼 조용히 동작합니다.

| # | 조건 | 설정 주체 |
|---|---|---|
| 1 | `UIBackgroundModes`에 `audio` 포함 | 호스트 앱의 `Info.plist` — 라이브러리가 대신 해 줄 수 없음 |
| 2 | `configuration.audioSessionPolicy = .playback(mixWithOthers: false)`(또는 `.ambient`) | 앱이 `ABPlayerConfiguration`으로 설정 |
| 3 | `configuration.backgroundPolicy = .continueAudioOnly` | 앱이 `ABPlayerConfiguration`으로 설정 |

`ABBackgroundPolicy`는 비전수(non-exhaustive)입니다 — 라이브러리 밖에서 이 타입을 `switch`할 때는 `default` 분기를 포함해야 합니다.

#### Picture in Picture

`ABPictureInPictureSession`을 `ABPlayerView`에 바인딩하거나, `ABVideoPlayer`의 **명시 소유** 이니셜라이저에 전달합니다.

```swift
import ABPlayerKit
import SwiftUI

struct VideoScreen: View {
    let player: ABPlayer
    @State private var pictureInPicture = ABPictureInPictureSession()

    var body: some View {
        ABVideoPlayer(player: player, pictureInPicture: pictureInPicture)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if pictureInPicture.isPossible {
                    Button(pictureInPicture.isActive ? "PiP 종료" : "PiP 시작") {
                        pictureInPicture.isActive ? pictureInPicture.stop() : pictureInPicture.start()
                    }
                }
            }
    }
}
```

세션이 활성인 동안에는 그 플레이어에 대해 모든 `ABBackgroundPolicy`의 자동 백그라운드/포그라운드 부작용이 억제됩니다 — PiP가 자기 자신에 의해 일시정지되거나 레이어가 떨어져 나가지 않고 계속 렌더링·재생됩니다. 억제되는 것은 *자동* 부작용뿐이며, `release()` 같은 명시적 호출은 여전히 PiP를 종료시킵니다.

| 전제조건 | 제공 주체 |
|---|---|
| `UIBackgroundModes`에 `audio` 포함(PiP가 백그라운드에서도 유지되어야 한다면) | 호스트 앱의 `Info.plist` — 라이브러리가 대신 해 줄 수 없음 |
| `configuration.audioSessionPolicy != .unmanaged` | 앱이 `ABPlayerConfiguration`으로 설정 |
| 기기/OS가 Picture in Picture 지원 | `ABPictureInPictureSession.isSupported` 확인 — 시뮬레이터에서는 대체로 `false` |
| 바인딩된 레이어가 표시 준비됨 | `session.isPossible`에 반영됨 |

**Picture in Picture는 명시 소유 경로(`player:` 이니셜라이저)에서만 지원됩니다.** `url:`/`source:` 편의 이니셜라이저는 SwiftUI identity가 폐기될 때 소유한 플레이어를 해제하므로 PiP가 도중에 끊길 수 있습니다 — 그래서 이 이니셜라이저들은 `pictureInPicture:` 파라미터를 받지 않습니다.

#### AirPlay

`ABPlayerConfiguration`의 세 프로퍼티가 대응하는 `AVPlayer` 프로퍼티로 그대로 전달되며, 모두 `AVPlayer` 자체 기본값과 동일합니다(기존 소비자의 동작이 바뀌지 않습니다).

```swift
var configuration = ABPlayerConfiguration()
configuration.allowsExternalPlayback = true                          // 기본값
configuration.usesExternalPlaybackWhileExternalScreenIsActive = false // 기본값
configuration.externalPlaybackVideoGravity = .resizeAspect            // 기본값
```

AirPlay가 현재 활성인지는 `player.isExternalPlaybackActive`로 확인합니다 — 매번 `AVPlayer`를 다시 읽는 평범한 computed 프로퍼티이며 `@Observable` 추적 대상이 아닙니다. 반응형 신호가 필요하면 `player.avPlayer`를 직접 KVO하거나 `AVRoutePickerView`가 자체 관리하는 상태를 사용하세요.

```swift
import AVKit
import SwiftUI

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
```

여러 플레이어가 동시에 살아 있는 화면(피드)에서는 현재 셀을 제외한 나머지 인스턴스에 `allowsExternalPlayback = false`를 설정하세요.

#### 자막과 오디오 트랙

자막/오디오 트랙 선택 UI와 상태 관리는 이 라이브러리가 **제공하지 않습니다.** 탈출구를 통해 `AVMediaSelectionGroup`에 직접 접근하세요 — `loadMediaSelectionGroup(for:)`는 `async`이므로 async 컨텍스트가 필요합니다.

```swift
if let item = player.avPlayerItem,
   let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
    let options = group.options
    // options를 표시한 뒤:
    item.select(options[0], in: group)
}
```

세 가지 제약이 있습니다.

1. `player.avPlayerItem`은 `.preloaded` 이상 등급에서만 `nil`이 아닙니다(`ABPlaybackGrade.holdsItem`).
2. 소스 교체·강등·`release()`마다 아이템이 **새로** 만들어집니다(`ABAVPlaybackTarget`이 처음부터 다시 attach). 이전 아이템에서 선택한 값은 이어지지 않습니다 — 매 `.itemAttached(source:)` 이벤트마다 다시 적용하세요.
3. 이 라이브러리는 attach 사이에 선택 상태를 기억하지 않습니다. 그 책임은 전적으로 소비자에게 있습니다.

### `ABPlayerKitControls` — 재생 컨트롤

UIKit 앱에서는 `ABPlayerControlsView`를 `ABPlayerView` 위에 배치하고 같은 플레이어를 연결합니다.

```swift
import ABPlayerKit
import ABPlayerKitControls

let videoView = ABPlayerView()
videoView.player = player

let controlsView = ABPlayerControlsView()
controlsView.player = player
```

SwiftUI 앱에서는 미리 조립된 편의 뷰를 사용할 수 있습니다.

```swift
ABVideoPlayerWithControls(player: player, videoGravity: .resizeAspect) {}
    .aspectRatio(16 / 9, contentMode: .fit)
```

표준 오버레이에서는 뒤로 건너뛰기, 재생/일시 정지, 앞으로 건너뛰기 버튼이 영상 중앙에 놓입니다. 탐색 막대는 하단에 붙고, `HH:mm:ss/HH:mm:ss` 형식의 경과/전체 시간은 탐색 막대의 보이는 트랙 바로 아래 왼쪽에, 재생 속도는 오른쪽 하단에 놓입니다. 기본 흰색/회색 컨트롤은 불투명도가 낮은 어두운 스크림을 사용해 영상이 선명하게 비치도록 합니다.

#### 스타일

스타일은 기존 컨트롤 뷰에 즉시 반영됩니다. 뒷편 트랙, 재생 완료 구간, 썸 외형, 아이콘을 각각 바꿀 수 있습니다.

```swift
var style = ABPlayerControlsStyle.default
style.trackColor = .white.withAlphaComponent(0.2)
style.progressColor = .systemPink
style.thumbColor = .systemPink
style.thumbSize = CGSize(width: 14, height: 14)
style.playIcon = .system("play.circle.fill")
style.pauseIcon = .system("pause.circle.fill")

controlsView.style = style
```

연속 시크의 누적 피드백 배지(`"+20s"`/`"-10s"`)는 `seekFeedbackTextColor`/`seekFeedbackBackgroundColor`/`seekFeedbackFont`로, 버퍼링 스피너는 `bufferingIndicatorColor`(기본값 `nil`, `tintColor`를 따름)로 스타일을 지정합니다.

#### 동작

```swift
var configuration = ABPlayerControlsConfiguration()
configuration.showsBufferingIndicator = true
configuration.touchPassthrough = .whenControlsHidden
configuration.doubleTapSeek = .edges(edgeWidthFraction: 0.3)
configuration.providesHapticFeedback = true
configuration.rateLabelFormat = .automatic
configuration.timeLabelSeparator = "/"

controlsView.configuration = configuration
```

| 프로퍼티 | 기본값 | 효과 |
|---|---|---|
| `touchPassthrough`<br/>(`ABControlsTouchPassthrough`) | `.never` | 어떤 컨트롤에도 맞지 않은 터치를 오버레이 뒤 뷰로 통과시킬지 결정합니다. `.whenControlsHidden`, `.always`도 있습니다. 기존 히트 테스트 우선순위를 덮어쓰지 않으며, 다른 무언가가 이미 그 터치를 처리하지 않았을 때만 적용됩니다. |
| `doubleTapSeek`<br/>(`ABDoubleTapSeek`) | `.disabled` | `.edges(edgeWidthFraction:)`로 좌우 가장자리 밴드를 더블탭하면 `skipInterval`만큼 시크합니다. 비율은 오버레이 전체 너비 대비 각 밴드의 너비이며 `0.1...0.5`로 클램프됩니다. 옵트인하지 않은 소비자가 매 싱글탭마다 더블탭 타임아웃을 기다리지 않도록 기본값은 비활성화입니다. |
| `providesHapticFeedback` | `true` | 더블탭 시크가 인정될 때 가벼운 햅틱을 울립니다. |
| `rateLabelFormat`<br/>(`ABPlayerControlsConfiguration.RateLabelFormat`) | `.automatic` | `.automatic`은 로케일을 인식하는 `NumberFormatter`로 배속을 표시합니다(`en`에서 `"1.5"`, `de`에서 `"1,5"`). `.custom { rate in ... }`은 레이블 전체 텍스트를 직접 제공합니다. |
| `timeLabelSeparator` | `"/"` | 시간 레이블의 경과 필드와 보조 필드 사이에 놓는 문자열입니다. |
| `showsPlayPauseButton` / `showsSeekBar` | `true` | 레이아웃 코드를 건드리지 않고 개별 컨트롤을 숨깁니다 — 기존 `showsSkipButtons`와 같은 방식입니다. 탐색 막대를 숨기면 그 막대가 차지하던 행이 접힙니다. |
| `showsBufferingIndicator` | `true` | `ABPlayer.isBuffering` 동안 재생/일시정지 아이콘 위에 스피너를 겹칩니다. 멈춘 상태에서도 일시정지는 가능해야 하므로 버튼은 계속 활성화된 채 히트 테스트가 가능합니다. 버퍼링 중에는 컨트롤을 강제로 보이게 하지 않으면서 자동 숨김만 억제합니다. |

그 밖의 기본 동작: 주기 UI 갱신 간격은 0.25초, 지원되는 스킵 간격에 맞춰 아이콘을 동기화하며, 배속 선택은 메뉴·순환·숨김 모드를 지원합니다. VoiceOver 실행 중에는 자동 숨김을 억제하고 Reduce Motion에서는 페이드를 제거합니다. 재생이 끝에 도달한 뒤 재생 버튼을 누르면(끝에서는 아무 일도 하지 않는 단순 `play()` 대신) 처음으로 되감은 뒤 재생합니다(replay-from-start).

스킵/더블탭/VoiceOver 조정 시크가 연속으로 발생하는 동안에는 누적 피드백 배지가 표시됩니다. 이는 전적으로 코어의 `pendingSeekTime`/`seekTargetChanged`가 구동하며, Controls가 직접 델타를 누적하지 않습니다.

#### 액세서리 슬롯

`ABControlsSlot`(`.topTrailing`, `.transportTrailing`, `.bottomTrailing`)을 사용하면 `ABPlayerControlsView.accessoryViews(in:)`/`setAccessoryViews(_:in:)`를 통해 소비자 뷰를 오버레이의 다른 위치에 배치할 수 있습니다. 기존 `accessoryViews` 프로퍼티는 `.bottomTrailing`의 별칭이며 동작은 동일합니다.

```swift
controlsView.setAccessoryViews([captionsButton], in: .topTrailing)
controlsView.setAccessoryViews([fullscreenButton], in: .transportTrailing)
```

컨트롤을 별도 제품으로 둔 이유는 피드나 백그라운드 플레이어가 자체 제스처를 제공하거나 UI가 전혀 없는 경우가 많기 때문입니다. 그런 소비자는 작은 코어만 링크하고, 표준 플레이어 화면만 UIKit 컨트롤과 SwiftUI 래퍼를 import 한 줄로 선택합니다.

### `ABPlayerKitMetrics` — TTFF와 QoE

`ABPlayerKitMetrics` 제품을 링크하지 않으면 메트릭 코드는 앱에 포함되지 않습니다. `ABMetricsRecorder`는 관찰 토큰으로 연결되고, sink가 이벤트의 목적지를 결정합니다. 메모리, 내부 직렬 큐를 사용하는 JSON Lines, OSLog 구현을 제공합니다.

```swift
import ABPlayerKit
import ABPlayerKitMetrics

@MainActor
final class PlaybackSession {
    let player = ABPlayer()

    private let sink: ABInMemoryMetricsSink
    private let recorder: ABMetricsRecorder
    private var tokens: Set<ABObservationToken> = []

    init() {
        let sink = ABInMemoryMetricsSink()
        self.sink = sink
        self.recorder = ABMetricsRecorder(sink: sink)

        recorder.attach(to: player).store(in: &tokens)
        player.addObserver { [weak self] event in
            guard case .firstFrameDisplayed = event else { return }
            Task { @MainActor [weak self] in
                self?.refreshStatistics()
            }
        }.store(in: &tokens)
    }

    func play(_ source: ABMediaSource) {
        let startedAt = ABMonotonicClock().now
        player.set(source: source, grade: .current)
        recorder.beginTTFF(for: player, at: startedAt)
        player.play()
    }

    private func refreshStatistics() {
        let samples = sink.events.compactMap { event -> ABMetricSample? in
            guard case .ttff(let sample) = event else { return nil }
            return sample
        }
        let statistics = ABPlaybackStatistics.aggregate(samples)
        print(statistics.p50, statistics.p95, statistics.hitRate)
    }
}
```

`PlaybackSession`은 측정이 끝날 때까지 화면이나 코디네이터의 프로퍼티로 보관하세요 — sink, recorder, 관찰 토큰은 모두 비동기 첫 프레임 이벤트보다 오래 유지되어야 합니다. 중도 이탈한 TTFF 표본은 `hitRate`와 `abandonRate`의 분모에 남으며, 측정에서 조용히 제외하지 않습니다.

#### QoE 세션

같은 `attach(to:)`가 TTFF뿐 아니라 재생 세션 전체도 추적합니다 — 별도의 세션 식별자가 없으므로 `(playerID, sessionStartedAt)`을 키로 사용합니다. 세션은 `.itemAttached(source:)`에서 열리고 `.itemDetached(reason:)`에서 닫히며, 각각 `ABMetricEvent.sessionStarted(_:)`와 `.sessionSummary(_:)`를 방출합니다.

```swift
recorder.attach(to: player).store(in: &tokens)

// 토큰을 취소하기 전에 최종 요약이 필요하다면:
recorder.endSession(for: player)

// 또는 언제든 아직 열려 있는 실시간 요약을 읽으려면:
let inProgress = recorder.snapshot(for: player)
```

- `attach(to:)`가 반환하는 토큰에는 recorder가 관찰할 수 있는 취소 훅이 없으므로, 토큰만 취소해서는 최종 `.sessionSummary`가 **생성되지 않습니다.** 필요하면 먼저 `endSession(for:)`을 호출하세요.
- `snapshot(for:)`은 아직 열려 있는 세션의 실시간, 미확정 `ABSessionSummary`를 반환합니다.
- `rebufferRatio`는 `rebufferMilliseconds / (rebufferMilliseconds + watchedMilliseconds)`이며 둘 다 `0`이면 `nil`입니다. 첫 프레임 이전의 버퍼링은 `rebufferMilliseconds`가 아니라 `startupBufferMilliseconds`에 집계됩니다 — TTFF가 이미 그 대기 시간을 측정하므로, 리버퍼로도 집계하면 같은 지연을 이중으로 계산하게 됩니다.
- `completionRatio`의 정밀도는 `ABPlayerConfiguration.periodicTimeInterval`을 설정하면 향상됩니다. `watchedMilliseconds`는 주기적 위치 샘플이 아니라 `.timeControlStatusChanged(_:)` 전이에서 유도되므로 설정과 무관하게 정확합니다.
- `ABSessionAnchor.sourceURL`/`ABSessionSummary.sourceURL`은 서버 측 로그와 조인하기 위한 미디어 URL을 담습니다. **서명되거나 토큰이 포함된 URL이라면 `ABMetricsRecorder.init(sink:clock:includesSourceURL:)`에 `includesSourceURL: false`를 전달하거나 커스텀 `ABMetricsSink`에서 마스킹해야 합니다** — 이 패키지는 자체 마스킹 정책을 내장하지 않습니다.

뒷받침 타입: `ABSessionAnchor`(세션 식별), `ABBufferingInterval`/`ABFailureRecord`(세션별 원시 기록), `ABSessionSummary`(세션 하나의 롤업), `ABQoESummary`(세션 전체 집계), `ABLatencyDistribution`(p50/p95/max/waited 분포). `ABPlaybackStatistics.waited`는 `.waited` TTFF 표본만을 대상으로 한 같은 형태이며, `.hit`를 `0`ms로 접어 넣는 레거시 `p50`/`p95`/`max`와 나란히 있습니다.

`ABMetricEvent`는 `ABPlayerEvent`와 같은 관례로 비전수(non-exhaustive)입니다 — 이 패키지 밖의 `switch`에는 `default` 분기를 두어야 합니다.

`ABAccessSnapshot`은 마지막 항목뿐 아니라 접근 로그 *전체*에 걸쳐 필드를 접어 넣습니다: `totalBytesTransferred`, `totalStallCount`, `droppedVideoFrameCount`, `bitrateSwitchCount`, `mediaRequestCount`, `durationWatchedSeconds`, `observedBitrateAverage`, `initialStartupTimeSeconds`, `entryCount`. `segmentsDownloadedCount`는 항상 `0`을 반환합니다 — `AVPlayerItemAccessLogEvent.numberOfSegmentsDownloaded`가 iOS 7부터 Swift에서 API 사용 불가 상태이며, 향후 호환을 위해 스키마에는 남겨 둡니다. `ABClock.wallClockEpoch`(기본값 `Date().timeIntervalSince1970`)는 세션이 열리는 시점에 한 번, 세션의 단조 시간축을 벽시계 시각에 대응시킵니다.

`ABJSONLinesMetricsSink.flush()`는 `public`입니다. `init(fileURL:maxFileSizeBytes:maxRotatedFiles:)`를 전달하면 파일이 `maxFileSizeBytes`를 넘는 순간 로테이션하며 `maxRotatedFiles`개의 회전된 사본(`.1`, `.2`, …)을 유지합니다. 영구적인 쓰기 실패는 조용히 무시되지 않습니다 — `writeFailureCount`/`lastWriteErrorDescription`을 확인하세요.

### `ABPlayerKitCache` — 캐시와 HLS 프리페치

캐시 타겟은 의도적으로 서로 다른 두 범위를 가집니다.

| 미디어 | 동작 |
|---|---|
| 프로그레시브 MP4 | 커스텀 스킴을 사용하는 투명한 `AVAssetResourceLoader` 가로채기, HTTP Range 처리, 순차 디스크 채움, LRU 축출 |
| HLS | `AVAssetDownloadURLSession`을 통한 명시적 전체 자산 프리페치. 완료된 다운로드만 로컬 재생에 사용 |

```swift
import ABPlayerKitCache

let cache = try ABMediaCache()
let hlsPrefetcher = ABHLSPrefetcher()

// 이 팩토리는 한 번 만들고 보관합니다. 교체 전에는 현재 아이템을 release해야 합니다.
let assetFactory = cache.makeAssetFactory(hlsPrefetcher: hlsPrefetcher)
player.release()
var configuration = player.configuration
configuration.assetFactory = assetFactory
player.configuration = configuration

let handle = hlsPrefetcher.prefetch(hlsSource)
if await handle.result == .completed {
    player.set(source: hlsSource, grade: .current)
    player.play() // 팩토리가 완료된 로컬 HLS 자산을 선택합니다.
}
```

**투명한 HLS 세그먼트 캐싱은 의도적으로 범위에서 제외했습니다.** `AVAssetResourceLoader`는 일반 HTTP(S) HLS 마스터/미디어 플레이리스트를 가로챌 수 없습니다. 투명 캐싱에는 플레이리스트를 재작성하고 상대 URL, 암호화 키, 백그라운드 수명을 처리하는 로컬 리버스 프록시가 필요합니다. 이는 훨씬 크고 다른 실패 영역이므로 확정된 [Q1 설계 결정](docs/DESIGN-OPEN-QUESTIONS.md)에 따라 별도 범위로 둡니다. [DESIGN-ABPlayerKit §9](docs/DESIGN-ABPlayerKit.md)도 참고하세요.

**프로그레시브 MP4 캐싱은 선형 prefix이지 sparse range가 아닙니다.** 하나의 순차 fill이 파일을 0바이트부터 앞으로 채워나가며, `load(_:range:)`는 일반적으로 그 fill이 요청된 오프셋에 도달할 때까지 기다립니다 — 그래서 non-faststart 파일에서 멀리 떨어진 위치로 시크하면 fill이 그곳까지 기어갈 때까지 기다리게 됩니다. 이를 제한하기 위해, 요청 오프셋이 현재 fill prefix보다 `ABCacheConfiguration.passthroughGapThreshold`(기본 2MB) 이상 앞서 있으면 대기 없이 곧바로 네트워크 직행 passthrough로 처리하며, 한 번의 왕복당 최대 1MB로 제한해 간격 전체를 메모리에 적재하지 않고 청크 단위로 스트리밍합니다. 백그라운드 fill은 건드리지 않고 계속 앞으로 진행합니다 — 이는 해당 요청 하나를 위한 일회성 폴백일 뿐, 캐시 자체를 그 위치로 재시작하는 것이 아닙니다.

### `ABPlayerKitNowPlaying` — 잠금화면과 원격 커맨드

이 타겟은 `ABPlayer`를 `MPNowPlayingInfoCenter`와 `MPRemoteCommandCenter`에 연결합니다. `audioSessionPolicy`와 마찬가지로 프로세스 전역 자원이며, 첫 `attach` 호출 전까지는 이 라이브러리가 아무것도 읽거나 쓰지 않습니다.

```swift
import ABPlayerKit
import ABPlayerKitNowPlaying

let token = ABNowPlayingCenter.shared.attach(
    player,
    metadata: ABNowPlayingMetadata(title: "12화", artist: "내 프로그램"),
    configuration: ABNowPlayingConfiguration(skipInterval: 15),
    artwork: ABStaticArtworkProvider(image: episodeArtwork)
)

// 이 플레이어가 Now Playing을 소유할 자격을 유지하는 동안 token을 보관하세요.
// 취소하거나(또는 deinit되면) 반납됩니다.
```

소유권은 배타적이며 규칙 하나로 자동 결정됩니다: **`.current`인 플레이어만 소유할 수 있고, 가장 최근에 그 자격을 얻은 플레이어가 소유합니다**(last-eligible-wins, LIFO). 여러 `ABPlayer` 인스턴스가 있는 피드에서 중요합니다.

- 플레이어는 `.current`가 되는 순간 자격을 얻고, `.current`를 벗어나는 순간 자격을 잃습니다.
- 두 플레이어가 동시에 `.current`이면 더 나중에 `.current`가 된 쪽이 Now Playing을 소유하고, 다른 쪽은 스택에서 대기합니다.
- 현재 소유자가 자격을 잃거나, 토큰이 취소되거나, 인스턴스 자체가 소멸하면 스택에서 가장 최근에 자격을 얻은 다음 플레이어가 자동으로 이어받습니다.
- 마지막 자격 있는 플레이어가 반납하면, 첫 `attach` 이전에 존재하던 상태가 정확히 복원됩니다 — 아무도 쓰지 않는 동안에는 이 라이브러리가 흔적을 남기지 않습니다.

원격 커맨드는 **두 조건이 모두** 충족될 때만 잠금화면에 나타납니다: (a) `ABNowPlayingConfiguration.commands`(`ABRemoteCommandSet`)에 포함되어 있을 것, (b) 그 커맨드가 매핑하는 동작이 실제로 존재할 것 — 눌러도 아무 일도 안 일어나는 잠금화면 버튼은 버튼이 없는 것보다 나쁩니다.

| 커맨드 | `.default`에 포함? | 추가로 필요한 것 |
|---|---|---|
| 재생 / 일시정지 / 토글 | 예 | 없음 — 항상 활성화 |
| 앞으로/뒤로 건너뛰기 | 예 | 없음 — 간격은 `ABNowPlayingConfiguration.skipInterval` |
| 재생 위치 변경 | 예 | 현재 아이템의 duration이 유한할 것 |
| 재생 속도 변경 | **아니오** | `commands`가 `.changePlaybackRate`를 포함해야 **하고**, `supportedPlaybackRates`가 비어 있지 않아야 함 |
| 다음/이전 트랙 | **아니오** | `commands`가 `.nextTrack`/`.previousTrack`를 포함해야 **하고**, `setTrackNavigationHandlers(next:previous:for:)`로 핸들러가 설치돼야 함 |

`commands`의 기본값은 `[.play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePlaybackPosition]`입니다. `ABNowPlayingConfiguration()`을 그대로 둔 채 핸들러나 배속 목록만 추가하는 것으로는 위 표의 마지막 두 행을 켤 수 **없습니다** — `commands`를 명시적으로 확장해야 합니다.

```swift
var configuration = ABNowPlayingConfiguration()
configuration.commands = .default.union([.nextTrack, .previousTrack, .changePlaybackRate])
configuration.supportedPlaybackRates = [1, 1.5, 2] // 위 표대로 여전히 필요합니다

let token = ABNowPlayingCenter.shared.attach(player, metadata: metadata, configuration: configuration)
ABNowPlayingCenter.shared.setTrackNavigationHandlers(
    // 이 라이브러리에는 큐/재생목록 개념이 없습니다 — 두 클로저의 내용은
    // 소비자가 채웁니다. 보통 자체 큐를 넘긴 뒤 다음 플레이어를 attach합니다.
    next: { /* 큐를 다음으로 */ },
    previous: { /* 큐를 이전으로 */ },
    for: player
)
```

메타데이터를 갱신할 때(예: 트랙 변경)는 `ABNowPlayingCenter.shared.update(_:for:)`를 사용하세요 — 그 플레이어가 현재 Now Playing을 소유하고 있으면 즉시 재발행되고, 아니면 다음에 소유권을 얻을 때 반영됩니다.

## 튜닝

ABPlayerKit은 프리로드와 현재 재생을 서로 다른 두 튜닝 역할로 모델링합니다. `preloadTuning`은 보수적으로 유지하고, 화면에 보이는 재생에는 `currentTuning`을 선택한 뒤 모든 등급 전환에서 올바른 역할이 적용되도록 합니다.

| 프리셋 | 최대 비트레이트 | 전방 버퍼 | 해상도 | 권장 역할 |
|---|---:|---:|---|---|
| `.conservativePreload` | 2 Mbps | 5초(AVFoundation의 soft hint) | 제한 없음 | `preloadTuning` |
| `.displayCapped` | 무제한 | 자동 | 현재 디스플레이 픽셀 크기 | 기본 `currentTuning` |
| `.resolutionCapped` | 2 Mbps | 5초 | 960×540 | 셀룰러용 `currentTuning` |
| `.unrestricted` | 무제한 | 자동 | 제한 없음 | 제한이 필요 없을 때 명시적으로 선택 |

```swift
var configuration = ABPlayerConfiguration()
configuration.preloadTuning = .conservativePreload
configuration.currentTuning = .displayCapped

let player = ABPlayer(configuration: configuration)
player.set(source: source, grade: .preloaded) // preloadTuning 적용
player.set(source: source, grade: .current)   // currentTuning 적용
player.set(source: source, grade: .preloaded) // preloadTuning 복원
```

이 대칭성은 강등된 아이템에 unrestricted/current 정책이 실수로 남는 것을 막습니다.

`ABPlaybackTuning.audioTimePitchAlgorithm`(기본값 `nil` — AVFoundation의 기본 알고리즘을 그대로 둠)은 `AVPlayerItem.audioTimePitchAlgorithm`으로 그대로 전달됩니다 — 1.0이 아닌 `ABPlaybackRate` 값을 쓰면서 타임피치 보정을 켜거나(또는 명시적으로 끄고) 싶다면 역할별로 설정하세요.

## 문제 해결

**영상 영역이 검은 화면이고 아무것도 재생되지 않습니다.**
플레이어는 아이템을 보유해야만 미디어를 로드합니다. `player.set(source:grade:)`를 `.current`로(또는 `.preloaded` 후 승격으로) 호출했는지 확인하세요 — `.instanceOnly`에 머문 플레이어는 의도적으로 아이템을 보유하지 않고 네트워크 요청도 하지 않습니다. 그다음 `player.lastFailure`에서 종료성 실패를 확인하세요. `lastDiagnostic`에 `.itemErrorLogEntry`가 담기는 것은 정상 스트림에서도 흔한 일이며 원인이 아닙니다.

**`play()`, `pause()`, `seek()`가 아무 반응이 없습니다.**
재생 제어 호출은 `grade != .current`인 동안 예외를 던지지 않고 무시됩니다. `.callRejected(ABRejectedCall, grade:)`를 관찰하면 어떤 호출이 어떤 등급에서 버려졌는지 알 수 있습니다.

**소리가 안 나거나, 무음 스위치를 켜면 소리가 멈춥니다.**
`audioSessionPolicy`의 기본값은 `.unmanaged`이며, 이 상태에서는 라이브러리가 `AVAudioSession`을 전혀 건드리지 않습니다. 무음 스위치와 무관하게 재생하려면 `configuration.audioSessionPolicy = .playback(mixWithOthers: false)`로 설정하세요.

**플레이어를 해제하니 호스트 앱 자체의 오디오가 멈춥니다.**
첫 관리 플레이어가 정책을 적용하기 전에 앱이 이미 `AVAudioSession`을 활성화해 뒀다면, 마지막 해제 시점의 복원이 세션을 비활성화할 수 있습니다. `AVAudioSession`에는 "이미 활성 상태였는지"를 조회할 공개 API가 없어 감지할 수 없습니다 — [오디오 세션과 인터럽션](#오디오-세션과-인터럽션)을 참고하세요.

**앱이 백그라운드로 가자마자 오디오가 멈춥니다.**
`.continueAudioOnly`는 [백그라운드 정책](#백그라운드-정책)의 세 조건이 모두 필요하며, 여기에는 **호스트 앱**의 `Info.plist`에 `UIBackgroundModes`로 `audio`가 포함되는 것도 들어갑니다. 하나라도 빠지면 조용히 `.pause`처럼 동작합니다.

**백그라운드에서 돌아왔는데 계속 일시정지 상태입니다.**
백그라운드 중에 `pause()`를 호출했다면 의도된 동작입니다 — 명시적 일시정지가 우선합니다. 자동 재개는 시스템이 스스로 재생을 멈춘 경우만 대상으로 합니다.

**Picture in Picture 버튼을 눌러도 아무 일도 없습니다.**
`ABPictureInPictureSession.isSupported`(시뮬레이터에서는 대체로 `false` — 실기기에서 확인하세요)와, 바인딩된 레이어가 표시 준비되어야 하는 `session.isPossible`을 확인하세요. PiP는 `audioSessionPolicy != .unmanaged`도 필요하며, `player:` 명시 소유 이니셜라이저에서**만** 동작합니다.

**잠금화면 컨트롤이 안 뜨거나 일부 버튼이 없습니다.**
`ABPlayerKitNowPlaying`을 링크하고 `attach`를 호출한 뒤 반환된 토큰을 보관해야 합니다. `.current` 플레이어만 자격이 있습니다. 배속 변경과 다음/이전 트랙은 `ABRemoteCommandSet.default`에 **포함되지 않아** 명시적 옵트인이 필요합니다 — 위의 커맨드 표를 참고하세요.

**`ABVideoPlayerWithControls(player:)` 호출에서 deprecated 이니셜라이저 경고가 납니다.**
빈 트레일링 클로저를 붙이세요: `ABVideoPlayerWithControls(player: player) {}`. [API 안정성](#api-안정성)을 참고하세요.

**업데이트 후 `ABPlayerEvent`·`ABMetricEvent`·`ABBackgroundPolicy`에 대한 `switch`가 컴파일되지 않습니다.**
이 타입들은 정책상 비전수(non-exhaustive)이며 마이너 릴리스에서 케이스가 추가될 수 있습니다. `default` 분기를 추가하세요.

**자막이나 오디오 트랙 선택이 사라집니다.**
소스 교체·강등·`release()`마다 **새** `AVPlayerItem`이 attach됩니다. 매 `.itemAttached(source:)` 이벤트마다 선택을 다시 적용하세요 — 이 라이브러리는 선택 상태를 저장하지 않습니다.

**플레이어가 여러 개 살아 있는 피드에서 재생이 끊깁니다.**
화면 밖 셀은 `.current`가 아니라 `.preloaded`나 `.instanceOnly`로 두고, `preloadTuning`을 보수적으로 유지하며, 현재 셀을 제외한 인스턴스에는 `allowsExternalPlayback = false`를 설정하세요.

## 데모 앱

독립 iOS 17 데모는 HLS/MP4 재생, 네 등급, 튜닝 역할, TTFF 통계, 프로그레시브 캐싱, 명시적 HLS 프리페치, Picture in Picture, 백그라운드 오디오를 실행합니다.

```bash
open Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj
```

**ABPlayerKitDemo** 스킴을 선택하고 iOS 시뮬레이터에서 실행하세요. 프로젝트가 `../..` 상대 경로로 이 패키지를 참조하므로 클론한 뒤 별도 경로 설정 없이 열립니다.

명령줄 빌드:

```bash
xcodebuild \
  -project Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj \
  -scheme ABPlayerKitDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

Picture in Picture, 백그라운드 오디오, 잠금화면 컨트롤, AirPlay는 시뮬레이터에서 검증할 수 없습니다. [`docs/CHECKLIST-device-verification.md`](docs/CHECKLIST-device-verification.md)가 릴리스 전 실기기에서 수행하는 수동 확인 목록입니다.

세로 숏폼 피드와 프리로드 윈도우 오케스트레이션은 [ABShortsKit](https://github.com/AppBoong/ABShortsKit)을 참고하세요.

## 아키텍처

```mermaid
flowchart TD
    Consumer[소비자] --> PlayerView[ABPlayerView]
    Consumer --> VideoPlayer[ABVideoPlayer]
    Consumer --> Controls[ABPlayerKitControls]
    PlayerView --> Player[ABPlayer]
    VideoPlayer --> Player
    Controls --> Player
    Player --> Planner[ABGradePlanner<br/>순수 상태 머신]
    Player --> Target[ABPlaybackTarget<br/>internal 테스트 이음매]
    Target --> AVTarget[ABAVPlaybackTarget]
    Metrics[ABPlayerKitMetrics] -. 관찰 토큰 .-> Player
    Cache[ABPlayerKitCache] -. ABAssetFactory .-> Player
```

- UI와 `ABPlayer`는 `@MainActor`로 격리됩니다.
- 등급 계획과 설정은 `Sendable` 값입니다.
- AVFoundation 콜백은 콜백 경계에서 시간을 캡처한 뒤 메인 액터로 이동하고 아이템 식별성을 다시 검증합니다.
- 메트릭과 캐시는 독립적인 소유권과 실패 모드를 가진 선택 제품입니다.

## 설계 근거

### delegate나 `AsyncStream` 대신 옵저버와 토큰을 선택한 이유

delegate 슬롯 하나를 사용하면 앱 동작과 메트릭이 소유권을 놓고 경쟁합니다. 다중 옵저버는 두 소비자가 독립적으로 연결되게 하고, `ABObservationToken`은 명시적 취소와 deinit 자동 취소를 보장합니다. `AsyncStream`은 팬아웃, 버퍼/드롭 정책, 백프레셔, `for await` 태스크 수명 결정을 추가합니다. 스케줄링 때문에 TTFF가 의존하는 콜백 경계 타임스탬프가 흐려질 수도 있습니다. 스트림은 나중에 토큰 API를 깨지 않고 추가할 수 있습니다.

### DI 컨테이너를 사용하지 않는 이유

패키지는 initializer 주입과 `ABPlayerConfiguration`을 사용합니다. 자원 상태를 보이게 만드는 것이 핵심인 라이브러리에서 컨테이너는 소유권과 생명주기를 숨깁니다.

### 테스트 이음매에만 protocol을 두는 이유

ABPlayerKit은 의도적으로 얇은 AVFoundation 래퍼입니다. 대체가 유용한 재생 타겟, 에셋 팩토리, 옵저버, 메트릭 sink, clock에만 protocol을 두고 `avPlayer`와 `avPlayerItem`은 탈출구로 공개합니다. AVFoundation 이름만 바꾸는 추상화 계층을 피하기 위한 선택입니다.

전체 근거는 [DESIGN-ABPlayerKit](docs/DESIGN-ABPlayerKit.md)과 [DESIGN-OPEN-QUESTIONS](docs/DESIGN-OPEN-QUESTIONS.md)에 기록되어 있습니다.

## API 안정성

이 패키지가 `0.x`인 동안 대체 API는 항상 additive로 먼저 추가되고, 같은 마이너 릴리스에서 deprecate됩니다(조용히 제거하지 않음). 제거 전 최소 한 개 마이너의 중첩 기간을 보장하며, `1.0.0` 이전에는 아무것도 제거하지 않습니다. `ABPlayerEvent`/`ABPlayerError`가 비전수(non-exhaustive) `enum`으로 남아 있는 것도 같은 이유입니다 — 소비자의 `switch`는 `default` 분기를 포함해야 합니다. 전체 정책은 [POLICY-api-stability](docs/POLICY-api-stability.md)에 있고, 모든 릴리스는 [CHANGELOG](CHANGELOG.md)에 기록됩니다.

> **deprecated된 `accessoryViews:` 이니셜라이저.** `ABPlayerControls(player: player)` / `ABVideoPlayerWithControls(player: player)` 그대로의 호출은 배열 기반의 deprecated 이니셜라이저로 해석되어 경고가 납니다. 빈 트레일링 클로저 `ABPlayerControls(player: player) {}`를 추가해 현재의 `@ViewBuilder accessories:` 쪽으로 이관하세요. 이걸 피할 기본값이 없는 이유는 CHANGELOG의 [`[0.3.0]` Migration notes](CHANGELOG.md#030---2026-08-05)를 참고하세요.

## 기여하기

이슈와 풀 리퀘스트를 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)에 개발 환경, 코드·커밋 규약, 풀 리퀘스트 규칙이 정리돼 있습니다 — 모든 변경은 PR을 거쳐 메인테이너 승인과 CI 그린을 받아야 하며, 빌드는 경고가 0이어야 합니다.

PR을 열기 전에 전체 테스트를 실행하세요.

```bash
xcodebuild -scheme ABPlayerKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

보안 관련 이슈는 공개 이슈 대신 [SECURITY.md](SECURITY.md)의 절차를 따라 주세요.

## 라이선스

ABPlayerKit은 [MIT License](LICENSE)로 제공됩니다. Copyright © 2026 AppBoong.
