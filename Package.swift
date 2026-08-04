// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ABPlayerKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "ABPlayerKit", targets: ["ABPlayerKit"]),
        .library(name: "ABPlayerKitControls", targets: ["ABPlayerKitControls"]),
        .library(name: "ABPlayerKitMetrics", targets: ["ABPlayerKitMetrics"]),
        .library(name: "ABPlayerKitCache", targets: ["ABPlayerKitCache"])
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
        .testTarget(
            name: "ABPlayerKitTests",
            dependencies: ["ABPlayerKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ABPlayerKitControlsTests",
            dependencies: ["ABPlayerKitControls", "ABPlayerKit"]
        ),
        .testTarget(
            name: "ABPlayerKitMetricsTests",
            dependencies: ["ABPlayerKitMetrics", "ABPlayerKit"]
        ),
        .testTarget(
            name: "ABPlayerKitCacheTests",
            dependencies: ["ABPlayerKitCache", "ABPlayerKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
