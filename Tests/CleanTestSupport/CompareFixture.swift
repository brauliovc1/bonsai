import CleanCore
import Foundation

/// Review fixture: forked branches, real origin/HEAD, renames, modes, generated and binary files.
public struct CompareFixture: Sendable {
    public let fixture: GitFixture
    public let repo: URL
    public let worktree: URL

    public static func make() async throws -> CompareFixture {
        let f = try GitFixture()
        let repo = try await f.makeRepo("review")
        try f.write("import Foundation\n\nstruct Welcome {\n    let title = \"Hello\"\n    func greet() -> String {\n        return title\n    }\n}\n", to: "Sources/Welcome.swift", in: repo)
        try f.write("class Welcome {\n  final title = 'Hello';\n  String greet() => title;\n}\n", to: "lib/welcome.dart", in: repo)
        try f.write("export function greet(name: string): string {\n  return `Hello ${name}`;\n}\n", to: "src/greet.ts", in: repo)
        try f.write("rename me\nunchanged\n", to: "old name.txt", in: repo)
        try f.write("copy me\nunchanged\n", to: "copy source.txt", in: repo)
        try f.write("delete me\n", to: "deleted.txt", in: repo)
        try f.write("#!/bin/sh\necho hello\n", to: "run.sh", in: repo)
        try f.write("space\n", to: "whitespace.txt", in: repo)
        try await f.commitAll(in: repo, message: "Add welcome screens")
        try await f.run(["push", "--quiet", "origin", "main"], in: repo)
        try await f.run(["remote", "set-head", "origin", "main"], in: repo)
        try await f.run(["fetch", "--quiet", "origin"], in: repo)
        let work = try await f.addSiblingWorktree(to: repo, name: "feature", branch: "feature/welcome")
        try f.write("import Foundation\n\nstruct Welcome {\n    let title = \"Welcome back\"\n    func greet() -> String {\n        return title.uppercased()\n    }\n}\n", to: "Sources/Welcome.swift", in: work)
        try await f.commitAll(in: work, message: "Make the welcome personal")
        try f.write("class Welcome {\n  final title = 'Welcome back';\n  String greet() => title.toUpperCase();\n}\n", to: "lib/welcome.dart", in: work)
        try f.write("export function greet(name: string): string {\n  // Keep the greeting personal.\n  return `Welcome back ${name}`;\n}\n", to: "src/greet.ts", in: work)
        try await f.run(["mv", "old name.txt", "new name.txt"], in: work)
        try f.write("copy me\nunchanged\n", to: "copy target.txt", in: work)
        try await f.run(["rm", "deleted.txt"], in: work)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.appending(path: "run.sh").path)
        try f.write("space   \n", to: "whitespace.txt", in: work)
        for name in ["a path with spaces.txt", "日本語 café.txt", "café🌿.txt", "line\nbreak.txt"] { try f.write("Added text\n", to: name, in: work) }
        try f.write("{\"lockfileVersion\":3}\n", to: "package-lock.json", in: work)
        try f.write("// Generated code\nfinal value = 42;\n", to: "lib/model.g.dart", in: work)
        try Data([0, 1, 2, 255]).write(to: work.appending(path: "image.bin"))
        try f.write((1...5_000).map { "let line\($0) = \($0)" }.joined(separator: "\n") + "\n", to: "Sources/Long.swift", in: work)
        try await f.commitAll(in: work, message: "Review files across languages")
        try f.write("Only the base has this change.\n", to: "base-only.txt", in: repo)
        try await f.commitAll(in: repo, message: "Advance the base after the fork")
        return CompareFixture(fixture: f, repo: repo, worktree: work)
    }

    public func reader() throws -> CompareReader {
        CompareReader(git: try GitReadOnly(repository: repo, executable: fixture.git.executable, timeout: TestWait.limit))
    }
}
