// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "clean-claude",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CleanCore", targets: ["CleanCore"]),
        .executable(name: "clean-claude", targets: ["clean-claude"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CleanCore"),
        .executableTarget(
            name: "clean-claude",
            dependencies: [
                "CleanCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "CleanTestSupport",
            dependencies: ["CleanCore"],
            path: "Tests/CleanTestSupport"
        ),
        .testTarget(
            name: "CleanCoreTests",
            dependencies: ["CleanCore", "CleanTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
