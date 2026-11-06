// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "clean-claude",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CleanCore", targets: ["CleanCore"]),
        .executable(name: "clean-claude", targets: ["clean-claude"]),
        .executable(name: "CleanClaudeApp", targets: ["CleanClaudeApp"]),
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
        // Foundation + Observation only: the app's logic, testable without a window.
        .target(
            name: "CleanAppModel",
            dependencies: ["CleanCore"]
        ),
        // SwiftUI + AppKit views; `make app` wraps the binary in "Bonsai.app".
        .executableTarget(
            name: "CleanClaudeApp",
            dependencies: ["CleanAppModel"]
        ),
        // Dev tool: builds a demo world of repos and worktrees in a temp folder. Never installed.
        .executableTarget(
            name: "fixture-world",
            dependencies: ["CleanCore", "CleanTestSupport"]
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
        .testTarget(
            name: "CleanAppModelTests",
            // clean-claude: so its binary is built for the test that compares app rows with `scan --json`.
            dependencies: ["CleanAppModel", "CleanTestSupport", "clean-claude"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
