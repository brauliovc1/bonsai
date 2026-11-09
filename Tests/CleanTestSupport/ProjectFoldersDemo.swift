import CleanCore
import Foundation

/// Idle projects with build folders for the Project folders screen (PLAN §4.5), added next to `DemoWorld`'s
/// repos by `fixture-world` and the off-screen renders (DemoWorld itself stays as the other tests know it):
///
/// - `delta`, a Next.js app idle 60 days: ignored `node_modules` (3 MB) and `.next` (2 MB), `package-lock.json`
///   and `next.config.mjs`; inside it the Claude worktree `quiet-heron` (60 days, `node_modules` 1 MB), which
///   the screen leaves out and counts in its footer.
/// - `echo`, a Flutter app idle 45 days: `.dart_tool` (1 MB), `ios/Pods` (2 MB) and `build` (1 MB),
///   `pubspec.yaml` and `ios/Podfile`.
/// - `foxtrot`, a Python tool idle 90 days: `.venv` (1 MB).
public enum ProjectFoldersDemo {
    public static let gitignore = "node_modules/\n.next/\n.dart_tool/\nbuild/\nPods/\n.venv/\n/.claude/worktrees/\n"

    public struct Built: Sendable {
        /// The three main checkouts.
        public var repos: [URL]
        /// The linked worktrees, for `fixture-world`'s status check.
        public var items: [DemoWorld.Item]
    }

    @discardableResult
    public static func add(to fixture: GitFixture, now: Date = Date()) async throws -> Built {
        let builder = AgedRepos(fixture: fixture, now: now)
        let delta = try await builder.repo("delta", days: 60, gitignore: gitignore, files: [
            "package.json": "{ \"name\": \"delta\" }\n", "package-lock.json": "{}\n", "next.config.mjs": "export default {}\n",
        ])
        try builder.blob(in: delta, "node_modules/next/dist/blob.bin", megabytes: 3)
        try builder.blob(in: delta, ".next/cache/blob.bin", megabytes: 2)
        let heron = delta.appending(path: ".claude/worktrees/quiet-heron", directoryHint: .isDirectory)
        try await builder.git(["worktree", "add", "--quiet", "-b", "claude/quiet-heron", heron.path], in: delta, days: 60)
        try await builder.commitAndPush(heron, file: "notes/heron.md", branch: "claude/quiet-heron", days: 60)
        try builder.blob(in: heron, "node_modules/react/blob.bin", megabytes: 1)

        let echo = try await builder.repo("echo", days: 45, gitignore: gitignore, files: [
            "pubspec.yaml": "name: echo\n", "ios/Podfile": "platform :ios, '15.0'\n",
        ])
        try builder.blob(in: echo, ".dart_tool/package_config.bin", megabytes: 1)
        try builder.blob(in: echo, "ios/Pods/Firebase/blob.bin", megabytes: 2)
        try builder.blob(in: echo, "build/app/blob.bin", megabytes: 1)

        let foxtrot = try await builder.repo("foxtrot", days: 90, gitignore: gitignore, files: ["requirements.txt": "requests\n"])
        try builder.blob(in: foxtrot, ".venv/lib/blob.bin", megabytes: 1)

        // Last, so no later git command moves an mtime again.
        try await builder.age(heron, days: 60)
        try await builder.age(delta, days: 60)
        try await builder.age(echo, days: 45)
        try await builder.age(foxtrot, days: 90)
        let item = DemoWorld.Item(
            url: heron, repo: delta, purpose: "Claude worktree inside delta, node_modules, 60 days idle", idleDays: 60,
            status: "SAFE", notes: ["Claude session"]
        )
        return Built(repos: [delta, echo, foxtrot], items: [item])
    }
}
