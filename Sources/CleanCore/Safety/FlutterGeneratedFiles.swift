import Foundation

/// PLAN §4.2 "Flutter-generated" (added 11-09): files Flutter writes again on `flutter pub get` or a build,
/// harmless when ignored (§4.1 only; never light-clean targets). Paths are relative to a folder holding
/// `pubspec.yaml`: `android/local.properties`, `ios/Flutter/Generated.xcconfig`,
/// `ios/Flutter/flutter_export_environment.sh`, `{ios,macos}/Flutter/ephemeral/`, `{linux,windows}/flutter/ephemeral/`,
/// `ios/.symlinks/`, and `GeneratedPluginRegistrant.*` anywhere under the project.
///
/// Never harmless, wherever they are: `google-services.json`, `GoogleService-Info.plist`, `key.properties`,
/// `*.jks`, `*.keystore`, `.env*` (Flutter doesn't write them; they are the user's).
enum FlutterGeneratedFiles {
    static let files: Set<String> = [
        "android/local.properties", "ios/Flutter/Generated.xcconfig", "ios/Flutter/flutter_export_environment.sh",
    ]
    static let folders = [
        "ios/Flutter/ephemeral", "macos/Flutter/ephemeral", "linux/flutter/ephemeral", "windows/flutter/ephemeral",
        "ios/.symlinks",
    ]
    static let registrantPrefix = "GeneratedPluginRegistrant."

    /// A name that is the user's even when ignored and inside a generated folder.
    static func isNeverHarmless(_ name: String) -> Bool {
        ["google-services.json", "GoogleService-Info.plist", "key.properties"].contains(name)
            || name.hasSuffix(".jks") || name.hasSuffix(".keystore") || name.hasPrefix(".env")
    }

    /// `path` relative to a Flutter project (a trailing `/` marks a folder) is one Flutter generates, or is
    /// inside a generated folder.
    static func isGenerated(projectRelative path: String) -> Bool {
        let isFolder = path.hasSuffix("/")
        let trimmed = isFolder ? String(path.dropLast()) : path
        let name = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        if isNeverHarmless(name) { return false }
        if folders.contains(where: { trimmed == $0 || trimmed.hasPrefix($0 + "/") }) { return true }
        if isFolder { return false }
        return files.contains(trimmed) || (name.hasPrefix(registrantPrefix) && name.count > registrantPrefix.count)
    }

    /// `entry` (relative to `root`, a trailing `/` for a folder) is Flutter-generated for a Flutter project
    /// around it: a folder from `root` down to the entry's parent that holds a `pubspec.yaml` file.
    static func isGenerated(_ entry: String, in root: URL) -> Bool {
        let parts = entry.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let suffix = entry.hasSuffix("/") ? "/" : ""
        for depth in 0..<parts.count where isGenerated(projectRelative: parts[depth...].joined(separator: "/") + suffix) {
            let project = parts[..<depth].reduce(root) { $0.appending(path: $1, directoryHint: .isDirectory) }
            if DirectoryEntries.kind(ofItemAt: project.appending(path: "pubspec.yaml").path) == .other { return true }
        }
        return false
    }
}
