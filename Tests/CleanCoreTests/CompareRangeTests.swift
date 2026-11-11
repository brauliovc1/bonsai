import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Compare ranges and file lists")
struct CompareRangeTests {
    @Test func threeDotAndFiles() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        let result = try await world.reader().load(base: "main", compare: .ref("feature/welcome"))
        #expect(result.range.ahead == 2)
        #expect(result.range.behind == 1)
        #expect(result.range.commits.map(\.subject) == ["Make the welcome personal", "Review files across languages"])
        #expect(!result.files.contains { $0.path == "base-only.txt" })
        let files = Dictionary(uniqueKeysWithValues: result.files.map { ($0.path, $0) })
        #expect(files["Sources/Welcome.swift"]?.status == .modified)
        #expect(files["deleted.txt"]?.status == .deleted)
        #expect(files["new name.txt"]?.status == .renamed)
        #expect(files["new name.txt"]?.oldPath == "old name.txt")
        #expect(files["new name.txt"]?.similarity == 100)
        #expect(files["copy target.txt"]?.status == .copied)
        #expect(files["image.bin"]?.isBinary == true)
        #expect(files["run.sh"]?.modeChanged == true)
        #expect(files["Sources/Long.swift"]?.additions == 5_000)
        #expect(files["Sources/Long.swift"]?.isLarge == true)
        for path in ["a path with spaces.txt", "日本語 café.txt", "line\nbreak.txt"] { #expect(files[path]?.status == .added) }
        #expect(files["package-lock.json"]?.isGenerated == true)
        #expect(files["lib/model.g.dart"]?.isGenerated == true)
        #expect(result.merge.state == .clean)
    }

    @Test func defaultsAndFetchTime() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        let catalog = try await RefCatalog.load(using: world.reader().git)
        #expect(catalog.defaultBase == "origin/main")
        #expect(catalog.lastFetch != nil)
        #expect(catalog.worktrees.contains { CanonicalPath.same($0.url, world.worktree) })
        try await world.fixture.run(["symbolic-ref", "--delete", "refs/remotes/origin/HEAD"], in: world.repo)
        #expect(try await RefCatalog.load(using: world.reader().git).defaultBase == "main")
        try await world.fixture.run(["branch", "-m", "main", "master"], in: world.repo)
        #expect(try await RefCatalog.load(using: world.reader().git).defaultBase == "master")
    }

    @Test func uncommittedAndUntracked() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        try world.fixture.write("let draft = true\n", to: "Sources/Welcome.swift", in: world.worktree)
        try world.fixture.write("new work\n", to: "new file.txt", in: world.worktree)
        let reader = try world.reader()
        let result = try await reader.load(base: "main", compare: .worktree(world.worktree.path))
        #expect(result.range.ahead == 2)
        let draft = try #require(result.files.first { $0.path == "Sources/Welcome.swift" })
        let added = try #require(result.files.first { $0.path == "new file.txt" })
        #expect(draft.notCommitted)
        #expect(added.notCommitted && added.status == .added && added.additions == 1)
        #expect(result.files.first { $0.path == "src/greet.ts" }?.notCommitted == false)
        let patch = try await reader.patch(file: added, range: result.range)
        #expect(String(decoding: patch, as: UTF8.self).contains("+new work"))
    }

    @Test func whitespaceAndSizes() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        let reader = try world.reader()
        let result = try await reader.load(base: "main", compare: .ref("feature/welcome"))
        let file = try #require(result.files.first { $0.path == "whitespace.txt" })
        let patch = try await reader.patch(file: file, range: result.range, whitespace: true)
        #expect(DiffParser.parse(patch).hunks.isEmpty)
        let binary = try #require(result.files.first { $0.isBinary })
        let detailed = try await reader.fileDetails(binary, range: result.range)
        #expect(detailed.oldBytes == 0 && detailed.newBytes == 4)
    }
}
