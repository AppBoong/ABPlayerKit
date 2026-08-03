// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ABPlayerKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "ABPlayerKit", targets: ["ABPlayerKit"])
    ],
    targets: [
        .target(
            name: "ABPlayerKit"
        ),
        .testTarget(
            name: "ABPlayerKitTests",
            dependencies: ["ABPlayerKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
