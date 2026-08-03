// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ABPlayerKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "ABPlayerKit", targets: ["ABPlayerKit"]),
        .library(name: "ABPlayerKitMetrics", targets: ["ABPlayerKitMetrics"])
    ],
    targets: [
        .target(
            name: "ABPlayerKit"
        ),
        .target(
            name: "ABPlayerKitMetrics",
            dependencies: ["ABPlayerKit"]
        ),
        .testTarget(
            name: "ABPlayerKitTests",
            dependencies: ["ABPlayerKit"]
        ),
        .testTarget(
            name: "ABPlayerKitMetricsTests",
            dependencies: ["ABPlayerKitMetrics", "ABPlayerKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
