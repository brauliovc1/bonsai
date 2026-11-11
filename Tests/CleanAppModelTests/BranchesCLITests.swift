import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Branches CLI", .serialized)
@MainActor
struct BranchesCLITests {
    @Test func mapJSONContainsDistancesAndOriginSourcesWithoutChangingTheRepo() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let before = try GitMetadataSnapshot(directory: world.repo.appending(path: ".git"))
        let result = try await CLIBinary.run(["branches", "--repo", world.repo.path, "--base", "main", "--json"], environment: variables(world))
        #expect(result.succeeded, "\(result.stderr)")
        let json = try #require(JSONSerialization.jsonObject(with: result.stdout) as? [String: Any])
        #expect(json["base"] as? String == "main")
        let rows = try #require(json["branches"] as? [[String: Any]])
        let row = try #require(rows.first { $0["name"] as? String == "c" })
        #expect((row["metrics"] as? [String: Any])?["ahead"] as? Int == 3)
        #expect((row["origin"] as? [String: Any])?["source"] as? String == "reflog")
        #expect((row["origin"] as? [String: Any])?["parent"] as? String == "refs/heads/b")
        #expect(try GitMetadataSnapshot(directory: world.repo.appending(path: ".git")) == before)
    }

    @Test func showJSONContainsTheHistoryCardAndRejectsUnknownBranches() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let folder = world.repo.appending(path: ".git")
        let before = try GitMetadataSnapshot(directory: folder)
        let result = try await CLIBinary.run(["branches", "show", "b", "--repo", world.repo.path, "--base", "main", "--json"], environment: variables(world))
        #expect(result.succeeded, "\(result.stderr)")
        let json = try #require(JSONSerialization.jsonObject(with: result.stdout) as? [String: Any])
        #expect(json["branch"] as? String == "refs/heads/b")
        #expect(json["children"] as? [String] == ["refs/heads/c"])
        #expect((json["merged"] as? [String: Any])?["state"] as? String == "notMerged")
        #expect((json["parentChain"] as? [String: Any])?["branches"] as? [String] == ["refs/heads/b", "refs/heads/a", "refs/heads/main"])
        let invalid = try await CLIBinary.run(["branches", "show", "no-such-branch", "--repo", world.repo.path, "--json"], environment: variables(world))
        #expect(!invalid.succeeded)
        #expect(try GitMetadataSnapshot(directory: folder) == before)
    }

    private func variables(_ world: BranchHistoryFixture) -> [String: String] {
        let settings = world.fixture.home.appending(path: "settings").path
        return ["BONSAI_SETTINGS_DIR": settings, "CLEAN_CLAUDE_SETTINGS_DIR": settings,
                "CLAUDE_CONFIG_DIR": world.fixture.home.appending(path: ".claude").path]
    }
}
