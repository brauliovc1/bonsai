@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.2 "Flutter-generated" (added 11-09, P12b): what Flutter writes again is not an ignored user file
/// (§4.1); the user's own ignored files still are.
/// Cases run one at a time: each builds real repos, and together they load the machine past what the timing tests
/// (ProcessRunner, lock timeouts) tolerate.
@Suite("Flutter-generated files", .serialized)
struct FlutterFilesTests {
    /// The ignore rules a Flutter project's template has, for the files below.
    static let flutterIgnores = """
        build/
        .dart_tool/
        .flutter-plugins-dependencies
        android/local.properties
        android/key.properties
        android/app/google-services.json
        **/GeneratedPluginRegistrant.java
        ios/Flutter/Generated.xcconfig
        ios/Flutter/flutter_export_environment.sh
        ios/Flutter/ephemeral/
        ios/.symlinks/
        ios/Runner/GeneratedPluginRegistrant.*
        .env

        """

    /// A worktree shaped like Braulio's Flutter apps: `pubspec.yaml` tracked, every generated file present.
    private func flutterWorktree(_ world: SafetyWorld) async throws -> URL {
        try world.fixture.write(Self.flutterIgnores, to: ".git/info/exclude", in: world.repo)
        try world.fixture.write("name: app\n", to: "pubspec.yaml", in: world.repo)
        // Tracked files beside the generated ones, as in a real app, so git lists those one by one.
        for tracked in ["ios/Flutter/AppFrameworkInfo.plist", "ios/Runner/AppDelegate.swift", "android/build.gradle",
                        "android/app/build.gradle", "android/app/src/main/AndroidManifest.xml"] {
            try world.fixture.write("tracked\n", to: tracked, in: world.repo)
        }
        try await world.fixture.commitAll(in: world.repo, message: "Flutter app")
        try await world.fixture.run(["push", "--quiet", "origin", "main"], in: world.repo)
        let wt = try await world.sibling("flutter")
        let generated = [
            "android/local.properties", "ios/Flutter/Generated.xcconfig", "ios/Flutter/flutter_export_environment.sh",
            "ios/Flutter/ephemeral/flutter_lldb_helper.py", "ios/Flutter/ephemeral/Packages/.packages/x/Package.swift",
            "ios/Runner/GeneratedPluginRegistrant.h", "ios/Runner/GeneratedPluginRegistrant.m",
            "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
            ".dart_tool/package_config.json", ".flutter-plugins-dependencies", "build/app/outputs/app.apk",
        ]
        for path in generated { try world.fixture.write("generated\n", to: path, in: wt) }
        let symlinks = wt.appending(path: "ios/.symlinks/plugins", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: symlinks, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinks.appending(path: "firebase_core"),
                                                   withDestinationURL: world.fixture.home)
        return wt
    }

    @Test func onlyFlutterGeneratedFilesIsNotHasIgnoredFiles() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await flutterWorktree(world)
        let report = try await world.check(wt)
        #expect(report.notes.isEmpty, "\(report)")
        #expect(report.status == .autoReady)
    }

    @Test(arguments: ["android/app/google-services.json", "android/key.properties", ".env", "ios/Flutter/ephemeral/.env"])
    func aUserFileMakesItHaveIgnoredFilesAgain(_ path: String) async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await flutterWorktree(world)
        try world.fixture.write("secret\n", to: path, in: wt)
        let report = try await world.check(wt)
        let listed = report.notes.flatMap { reason -> [String] in
            if case .ignoredUserFiles(let paths) = reason { return paths }
            return []
        }
        // A user file inside a generated folder makes git's collapsed folder entry a user file.
        let expected = path.hasPrefix("ios/Flutter/ephemeral/") ? "ios/Flutter/ephemeral/" : path
        #expect(listed == [expected], "\(report)")
        #expect(!report.autoEligible)
    }

    /// Without `pubspec.yaml` the same files are not Flutter's.
    @Test func withoutAPubspecTheyAreUserFiles() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        try world.fixture.write("android/local.properties\n", to: ".git/info/exclude", in: world.repo)
        let wt = try await world.sibling("plain")
        try world.fixture.write("sdk.dir=/x\n", to: "android/local.properties", in: wt)
        let report = try await world.check(wt)
        // git collapses android/ (everything in it is ignored); the walk inside finds a user file.
        #expect(report.notes == [.ignoredUserFiles(["android/"])], "\(report)")
    }

    @Test func theListFollowsPlan() {
        let generated = [
            "android/local.properties", "ios/Flutter/Generated.xcconfig", "ios/Flutter/flutter_export_environment.sh",
            "ios/Flutter/ephemeral/", "macos/Flutter/ephemeral/x", "linux/flutter/ephemeral/", "windows/flutter/ephemeral/a/b",
            "ios/.symlinks/", "ios/.symlinks/plugins/x", "lib/GeneratedPluginRegistrant.swift",
            "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
        ]
        for path in generated {
            #expect(FlutterGeneratedFiles.isGenerated(projectRelative: path), "\(path)")
        }
        let user = [
            "android/key.properties", "android/app/google-services.json", "ios/Runner/GoogleService-Info.plist",
            "upload.jks", "android/app/release.keystore", ".env", ".env.local", "ios/Flutter/ephemeral/.env",
            "ios/Flutter/ephemeral/key.properties", "lib/main.g.dart", "android/", "ios/Flutter/", "GeneratedPluginRegistrant.",
            "ios/Flutter/Generated.xcconfig/", "local.properties",
        ]
        for path in user {
            #expect(!FlutterGeneratedFiles.isGenerated(projectRelative: path), "\(path)")
        }
    }

    /// A nested Flutter project (an example app) has its own `pubspec.yaml`.
    @Test func aProjectBelowTheWorktreeCounts() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "flutter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "example"), withIntermediateDirectories: true)
        try Data("name: x\n".utf8).write(to: root.appending(path: "example/pubspec.yaml"))
        #expect(FlutterGeneratedFiles.isGenerated("example/android/local.properties", in: root))
        #expect(!FlutterGeneratedFiles.isGenerated("android/local.properties", in: root))
        #expect(!FlutterGeneratedFiles.isGenerated("other/android/local.properties", in: root))
    }
}
