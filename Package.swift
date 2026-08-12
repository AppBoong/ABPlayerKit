// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ABPlayerKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ABPlayerKit", targets: ["ABPlayerKit"]),
        .library(name: "ABPlayerKitControls", targets: ["ABPlayerKitControls"]),
        .library(name: "ABPlayerKitMetrics", targets: ["ABPlayerKitMetrics"]),
        .library(name: "ABPlayerKitCache", targets: ["ABPlayerKitCache"]),
        .library(name: "ABPlayerKitNowPlaying", targets: ["ABPlayerKitNowPlaying"])
    ],
    targets: [
        // The shared ABPlayerKit-Package scheme runs every test target below.
        .target(
            name: "ABPlayerKit"
        ),
        .target(
            name: "ABPlayerKitControls",
            dependencies: ["ABPlayerKit"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "ABPlayerKitMetrics",
            dependencies: ["ABPlayerKit"]
        ),
        .target(
            name: "ABPlayerKitCache",
            dependencies: ["ABPlayerKit"]
        ),
        .target(
            name: "ABPlayerKitNowPlaying",
            dependencies: ["ABPlayerKit"]
        ),
        // Test-only support code shared across the test targets below.
        // Not referenced by any `products` entry, so it never ships as
        // part of the library.
        .target(
            name: "ABTestSupport",
            path: "Tests/ABTestSupport"
        ),
        .testTarget(
            name: "ABPlayerKitTests",
            dependencies: ["ABPlayerKit", "ABTestSupport"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ABPlayerKitControlsTests",
            dependencies: ["ABPlayerKitControls", "ABPlayerKit", "ABTestSupport"]
        ),
        .testTarget(
            name: "ABPlayerKitMetricsTests",
            dependencies: ["ABPlayerKitMetrics", "ABPlayerKit", "ABTestSupport"]
        ),
        .testTarget(
            name: "ABPlayerKitCacheTests",
            dependencies: ["ABPlayerKitCache", "ABPlayerKit", "ABTestSupport"]
        ),
        .testTarget(
            name: "ABPlayerKitNowPlayingTests",
            dependencies: ["ABPlayerKitNowPlaying", "ABPlayerKit", "ABTestSupport"]
        )
    ],
    swiftLanguageModes: [.v6]
)
