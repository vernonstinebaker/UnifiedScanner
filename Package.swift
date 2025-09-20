// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UnifiedScanner",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UnifiedScanner",
            targets: ["UnifiedScanner"]
        ),
    ],
    dependencies: [
        .package(path: "../SimplePingKit"),
    ],
    targets: [
        .target(
            name: "UnifiedScanner",
            dependencies: [
                .product(name: "SimplePingKit", package: "SimplePingKit")
            ],
            path: "UnifiedScanner"
        ),
    ]
)
