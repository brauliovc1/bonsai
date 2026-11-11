import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Compare model and CLI") @MainActor
struct CompareModelTests {
    @Test func actionsAreReadOnly() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        let app = makeApp(world.fixture)
        let model = CompareModel(app: app)
        let gitDir = world.repo.appending(path: ".git")
        let before = try GitMetadataSnapshot(directory: gitDir)
        await model.configure(repo: world.repo.path, base: "main", compare: .ref("feature/welcome"))
        #expect(model.problem == nil)
        #expect(model.snapshot?.range.ahead == 2)
        #expect(!model.visibleFiles.contains { $0.isGenerated })
        for file in model.visibleFiles.prefix(4) {
            await model.selectFile(file.path)
            model.toggleViewed(file.path)
            #expect(model.isViewed(file.path))
            _ = try await model.copyPatch(wholeCompare: false)
            await model.showMoreContext()
            #expect(try GitMetadataSnapshot(directory: gitDir) == before)
        }
        model.filter = "greet"; #expect(model.visibleFiles.count == 1); model.filter = ""
        model.flatList = true; model.sideBySide = true; model.ignoresWhitespace = true
        await model.changeWhitespace()
        model.showsGenerated = true
        await model.selectFile("package-lock.json")
        #expect(model.diffIsCollapsed)
        await model.showAnyway(); #expect(model.document != nil)
        if let commit = model.snapshot?.range.commits.first { await model.selectCommit(commit.sha) }
        #expect(model.files.count == 1)
        await model.selectCommit(nil)
        _ = try await model.copyPatch(wholeCompare: true)
        await model.swap()
        #expect(model.snapshot?.range.ahead == 1)
        #expect(try GitMetadataSnapshot(directory: gitDir) == before)
    }

    @Test func worktreeCommitNavigationPreservesDrafts() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        try world.fixture.write("draft\tvalue\r\n", to: "draft.txt", in: world.worktree)
        let model = CompareModel(app: makeApp(world.fixture))
        let directory = world.repo.appending(path: ".git")
        let before = try GitMetadataSnapshot(directory: directory)
        await model.configure(repo: world.repo.path, base: "main", compare: .worktree(world.worktree.path))
        let commit = try #require(model.snapshot?.range.commits.first)
        await model.selectCommit(commit.sha)
        await model.selectCommit(nil)
        #expect(model.files.contains { $0.path == "draft.txt" && $0.notCommitted })
        await model.selectFile("draft.txt")
        let patch = try await model.copyPatch(wholeCompare: false)
        #expect(patch.contains("+draft\tvalue\r\n"))
        #expect(try GitMetadataSnapshot(directory: directory) == before)
    }

    @Test func preselectionAndCLI() async throws {
        let world = try await CompareFixture.make(); defer { world.fixture.remove() }
        let navigation = NavigationModel()
        navigation.openCompare(repo: world.repo.path, base: "main", compare: .worktree(world.worktree.path))
        #expect(navigation.section == .compare)
        #expect(navigation.compareRequest?.compare == .worktree(world.worktree.path))
        #expect(SidebarSection.Group.review.sections == [.compare])
        let before = try GitMetadataSnapshot(directory: world.repo.appending(path: ".git"))
        let settings = world.fixture.home.appending(path: "settings").path
        let result = try await CLIBinary.run(["compare", "--repo", world.repo.path, "main", "feature/welcome", "--json"], environment: [
            "BONSAI_SETTINGS_DIR": settings, "CLEAN_CLAUDE_SETTINGS_DIR": settings,
            "CLAUDE_CONFIG_DIR": world.fixture.home.appending(path: "claude").path,
        ])
        #expect(result.succeeded)
        let object = try #require(JSONSerialization.jsonObject(with: result.stdout) as? [String: Any])
        let range = try #require(object["range"] as? [String: Any])
        #expect(range["ahead"] as? Int == 2)
        #expect((object["files"] as? [[String: Any]])?.isEmpty == false)
        #expect(try GitMetadataSnapshot(directory: world.repo.appending(path: ".git")) == before)
    }
}
