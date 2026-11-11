@testable import CleanAppModel
@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Direct branch map entry", .serialized)
@MainActor
struct BranchMapEntryTests {
    @Test(arguments: [false, true])
    func opensTheVisualTimelineOnFirstAndLaterVisits(alreadyConfigured: Bool) async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let app = makeApp(world.fixture, root: world.repo)
        await app.refresh()
        let model = CompareModel(app: app)
        if alreadyConfigured {
            await model.configure(repo: world.repo.path, base: "main", compare: .ref("c"))
        }
        #expect(!model.branches.isOpen && model.branches.snapshot == nil)
        #expect(await model.branches.cache.computations == 0)
        let directory = world.repo.appending(path: ".git")
        let before = try GitMetadataSnapshot(directory: directory)

        await model.openBranchMap()

        #expect(model.repository.map { CanonicalPath.same(URL(fileURLWithPath: $0), world.repo) } == true)
        #expect(model.problem == nil && model.branches.problem == nil)
        #expect(model.branches.isOpen && model.branches.layout == .timeline)
        #expect(model.branches.snapshot?.entries.count == 4)
        #expect(model.branches.family?.origins["refs/heads/c"]?.parent == "refs/heads/b")
        #expect(model.branches.timeline["refs/heads/c"]?.fork != nil)
        #expect(!model.branches.isLoading)
        #expect(try GitMetadataSnapshot(directory: directory) == before)
    }
}
