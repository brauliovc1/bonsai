@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Light cleanup admission", .serialized)
struct LightCleanAdmissionTests {
    @Test func admissionRunsAfterSlowChecksAndCanRefuse() async throws {
        let world = try await LightCleanWorld.make("quick-admission")
        defer { world.remove() }
        try world.file("node_modules/package/data", in: world.repo)
        let record = try await world.worktree(world.repo)
        let found = await world.finder().candidates(in: record)
        let candidates = try #require(found.candidates.nonEmpty)
        let signal = world.fixture.url.appending(path: "late-activity")
        var cleaner = world.cleaner()
        cleaner.afterRecheck = { _ in try? Data("active".utf8).write(to: signal) }
        cleaner.admission = { _, _ in
            FileManager.default.fileExists(atPath: signal.path) ? "It became active after inspection." : nil
        }

        let result = try await cleaner.clean(record, candidates: candidates)

        #expect(result.deleted.isEmpty && result.entries.isEmpty)
        #expect(result.refused.count == 1)
        #expect(world.exists("node_modules/package/data", in: world.repo))
        #expect(try world.log.entries().isEmpty)
    }

    @Test func admissionCannotBypassTheFinalPathIdentityCheck() async throws {
        let world = try await LightCleanWorld.make("quick-swap")
        defer { world.remove() }
        try world.file("node_modules/package/data", in: world.repo)
        let record = try await world.worktree(world.repo)
        let found = await world.finder().candidates(in: record)
        let candidates = try #require(found.candidates.nonEmpty)
        let outside = world.fixture.url.appending(path: "outside")
        try world.fixture.write("keep\n", to: "precious.txt", in: outside)
        let target = world.repo.appending(path: "node_modules")
        let moved = world.repo.appending(path: "reviewed-output")
        var cleaner = world.cleaner()
        cleaner.admission = { _, _ in
            do {
                try FileManager.default.moveItem(at: target, to: moved)
                try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
                return nil
            } catch { return "Probe setup failed: \(error)" }
        }

        let result = try await cleaner.clean(record, candidates: candidates)

        #expect(result.deleted.isEmpty && result.entries.isEmpty)
        #expect(result.refused.count == 1)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil)
        #expect(FileManager.default.fileExists(atPath: outside.appending(path: "precious.txt").path))
        #expect(try world.log.entries().isEmpty)
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
