# ABPlayerKit

[English](README.md)

![iOS 17+](https://img.shields.io/badge/iOS-17%2B-000000?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![MIT](https://img.shields.io/badge/License-MIT-blue.svg)
[![CI](https://github.com/AppBoong/ABPlayerKit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AppBoong/ABPlayerKit/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2FAppBoong%2FABPlayerKit%2Fbadges%2Fcoverage.json)](https://github.com/AppBoong/ABPlayerKit/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/docs-DocC-blue)](https://appboong.github.io/ABPlayerKit/documentation/)

**SwiftUI에 바로 붙여 쓰는 `AVPlayer` 기반 영상 플레이어.**

한 줄이면 표준 컨트롤과 함께 영상이 재생됩니다. 몇 줄을 더하면 플레이어를 직접 소유하고, 재생 위치를 표시하고, 피드를 프리로드할 수 있습니다. 그동안에도 `AVPlayer`에는 언제든 직접 접근할 수 있습니다.

```swift
ABVideoPlayerWithControls(url: url)
```

<p align="center">
<img src="docs/assets/demo-controls.gif" width="380" alt="탭으로 나타난 컨트롤 오버레이, 1.5×를 선택하는 배속 메뉴, 저절로 사라지는 오버레이, HLS 스트림의 70% 지점으로의 스크럽"><br>
<sub>위 한 줄이 실제로 동작하는 모습. 탭하면 오버레이가 나타나고, 배속을 고르고, 스크럽하고 — 그리고 저절로 비켜섭니다.</sub>
</p>

## 설치

iOS 17+ · Swift 6 · Xcode 16+

Xcode에서 **File → Add Package Dependencies**를 열고 `https://github.com/AppBoong/ABPlayerKit.git`을 입력합니다. 또는 `Package.swift`에 추가합니다.

```swift
.package(url: "https://github.com/AppBoong/ABPlayerKit.git", from: "0.5.1")
```

`ABPlayerKit`을 링크하고, 표준 컨트롤이 필요하면 `ABPlayerKitControls`도 링크합니다.

## 빠른 시작

각 단계는 데모 앱의 **Usage** 탭에서 실행됩니다([`UsageScreen.swift`](Examples/ABPlayerKitDemo/ABPlayerKitDemo/UsageScreen.swift)).

<table>
<tr>
<td align="center" width="33%">
<img src="docs/assets/usage-one-line.png" width="220" alt="ABVideoPlayerWithControls(url:) playing an HLS stream above its one-line source"><br>
<sub>1. 한 줄</sub>
</td>
<td align="center" width="33%">
<img src="docs/assets/usage-own-player.png" width="220" alt="An owned ABPlayer with a progress bar and seconds label driven by player.position, and its grade, isPlaying and isBuffering state"><br>
<sub>2. 플레이어 소유, 재생 위치 표시</sub>
</td>
<td align="center" width="33%">
<img src="docs/assets/usage-feed.png" width="220" alt="A paging feed with one current player, both neighbours preloaded and the rest released"><br>
<sub>3. 피드: <code>.current</code> 하나, 이웃은 <code>.preloaded</code></sub>
</td>
</tr>
</table>

### 1. URL 재생

```swift
import ABPlayerKit
import ABPlayerKitControls
import SwiftUI

struct VideoScreen: View {
    let url: URL

    var body: some View {
        ABVideoPlayerWithControls(url: url)
            .aspectRatio(16 / 9, contentMode: .fit)
    }
}
```

뷰가 플레이어를 만들고 재생을 시작하며, SwiftUI가 뷰를 버릴 때 모든 자원을 해제합니다. 컨트롤 없이 쓰려면 코어 제품의 `ABVideoPlayer(url:)`를 씁니다.

### 2. 플레이어 직접 소유

화면에서 일시정지하거나, 상태를 관찰하거나, 플레이어를 공유해야 할 때 직접 소유합니다.

```swift
struct VideoScreen: View {
    let url: URL
    @State private var player = ABPlayer()

    var body: some View {
        VStack {
            ABVideoPlayerWithControls(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
            ProgressView(value: player.position.time.progress ?? 0)
        }
        .task { player.load(ABMediaSource(url: url)) }  // 다시 나타나도 아무 일도 하지 않음
        .onDisappear { player.pause() }               // 해제가 아니라 일시정지
    }
}
```

`ABPlayer`는 `@Observable`이라 `isPlaying`, `isBuffering`, `duration`을 SwiftUI에서 바로 쓸 수 있습니다. `player.position`은 별도의 관찰 객체라서, 시간이 흘러도 그 값을 읽는 뷰만 다시 그려집니다. Picture in Picture, Now Playing, 메트릭은 모두 이 단계에서 시작합니다.

### 3. 컨트롤 커스터마이징

```swift
var style = ABPlayerControlsStyle.default
style.progressColor = .systemPink

var controls = ABPlayerControlsConfiguration()
controls.skipInterval = 15

ABVideoPlayerWithControls(url: url)
    .playerControlsStyle(style)
    .playerControlsConfiguration(controls)
```

modifier는 그 아래의 모든 플레이어에 적용됩니다. 음소거·반복·배속·오디오 세션 같은 플레이어 설정은 `ABPlayerConfiguration`으로 넘깁니다: `ABVideoPlayerWithControls(url: url, playerConfiguration: configuration)`.

### 4. 피드와 프리로드

각 플레이어는 네 등급(`.released`, `.instanceOnly`, `.preloaded`, `.current`)을 오갑니다. 그래서 피드는 다음 영상을 넘기기 전에 미리 버퍼링하고, 멀어진 영상은 해제할 수 있습니다. 완성된 페이징 피드 예제는 [Choosing an Ownership Model](https://appboong.github.io/ABPlayerKit/documentation/abplayerkit/choosinganownershipmodel/)(영문)에 있습니다.

## 선택 제품

| 제품 | 추가되는 것 |
|---|---|
| [`ABPlayerKitControls`](https://appboong.github.io/ABPlayerKit/documentation/abplayerkitcontrols/) | SwiftUI·UIKit용 표준 컨트롤 오버레이 |
| [`ABPlayerKitMetrics`](https://appboong.github.io/ABPlayerKit/documentation/abplayerkitmetrics/) | 첫 프레임 표시 시간과 QoE 세션 요약 |
| [`ABPlayerKitCache`](https://appboong.github.io/ABPlayerKit/documentation/abplayerkitcache/) | 프로그레시브 MP4 캐싱과 명시적 HLS 프리페치 |
| [`ABPlayerKitNowPlaying`](https://appboong.github.io/ABPlayerKit/documentation/abplayerkitnowplaying/) | 잠금화면과 원격 커맨드 |

링크하지 않은 제품의 코드는 앱에 포함되지 않습니다.

## 더 알아보기

- [API 문서](https://appboong.github.io/ABPlayerKit/documentation/)(영문)에 UIKit, 백그라운드 오디오, Picture in Picture, AirPlay, 튜닝, [문제 해결](https://appboong.github.io/ABPlayerKit/documentation/abplayerkit/troubleshooting/)이 있습니다.
- 데모 앱은 `Examples/ABPlayerKitDemo/ABPlayerKitDemo.xcodeproj`이며 별도 설정 없이 열립니다.
- [How ABPlayerKit is built](docs/ARCHITECTURE.md)(영문)에서 설계 결정을 설명합니다. [Engineering Notes](docs/ENGINEERING-NOTES.md)(영문)는 그린이던 테스트가 놓친 AVFoundation 결함 3건을 다룹니다.

## 기여하기

이슈와 풀 리퀘스트를 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요. 보안 관련 이슈는 [SECURITY.md](SECURITY.md)의 절차를 따라 주세요.

## 라이선스

ABPlayerKit은 [MIT License](LICENSE)로 제공됩니다. Copyright © 2026 AppBoong.
