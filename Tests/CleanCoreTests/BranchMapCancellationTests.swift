@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

struct BranchMapCancellationTests {
    @Test func completedCancellationCannotPoisonAnImmediateRefresh() async throws {
        let world = try await BranchHistoryFixture.make()
        defer { world.remove() }
        let git = try world.git()
        let base = try await git.resolve("main"), tip = try await git.resolve("a")
        let map = BranchMap()
        let cancelled = Task { BranchMapMetrics(ahead: nil, behind: nil, fork: nil, tip: nil, problem: "Cancelled work") }
        cancelled.cancel()
        _ = await cancelled.value
        #expect(cancelled.isCancelled)
        // Model the interval after a cancelled query finishes and before its original caller clears it.
        await map.installCancelledForTest(base: base, tip: tip, git: git, task: cancelled)
        let fresh = await map.metrics(base: base, tip: tip, git: git)
        #expect(fresh.problem == nil && fresh.ahead == 1 && fresh.behind == 0)
        #expect(await map.computations == 1)
    }
}

private extension BranchMap {
    func installCancelledForTest(base: String, tip: String, git: GitReadOnly, task: Task<BranchMapMetrics, Never>) {
        let graph = Self.graphVisibility(git)
        visibility = graph
        pending[Key(visibility: graph, base: base, tip: tip)] = Pending(token: UUID(), task: task)
    }
}
