import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Test tools, limits and timeouts")
struct TestHarnessTests {
    /// With xcrun present, fixtures run the git and make the shims would start, not the shims.
    @Test func helpersRunTheRealGitAndMake() throws {
        let git = try #require(TestTools.paths.git)
        #expect(FileManager.default.isExecutableFile(atPath: git.path))
        #expect(FileManager.default.isExecutableFile(atPath: TestTools.make.path))
        if TestTools.paths.xcrun != nil {
            #expect(git.path != "/usr/bin/git")
            #expect(TestTools.make.path != "/usr/bin/make")
        }
        #expect(TestTools.paths.lsof == ToolPaths.resolve().lsof)
    }

    /// The fixture's git and everything built from `environment()` wait as long as the machine needs.
    @Test func fixturesGiveTheCodeUnderTestMinutes() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let environment = fixture.environment()
        #expect(environment.timeouts == ToolTimeouts(git: TestWait.limit, gitVersion: TestWait.limit, lsof: TestWait.limit))
        #expect(environment.tools.git == TestTools.paths.git)
        #expect(fixture.git.executable == TestTools.paths.git)
        #expect(fixture.git.timeout == TestWait.limit)
        #expect(WorktreeAssessor.git(for: environment)?.timeout == TestWait.limit)
    }

    @Test func helpersGetTwiceTheCoresAndAtLeastFour() {
        #expect(ProcessLimit.helpers.width == max(4, 2 * ProcessInfo.processInfo.activeProcessorCount))
        #expect(ProcessLimit(width: 0).width == 1)
    }

    /// Every caller runs, never more than `width` at once, and a body that throws frees its slot.
    @Test func processLimitRunsEveryCallerWithinItsWidth() async {
        let limit = ProcessLimit(width: 3)
        // The first three stay until all three slots are taken, however late the third starts.
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: TestWait.limit)
        let finished = await withTaskGroup(of: Int?.self) { group in
            for value in 0..<20 {
                group.addTask {
                    try? await limit.run {
                        while limit.mostAtOnce < 3, clock.now < end {
                            try? await Task.sleep(for: .milliseconds(1))
                        }
                        if value.isMultiple(of: 5) { throw CancellationError() }
                        return value
                    }
                }
            }
            return await group.reduce(into: [Int]()) { if let value = $1 { $0.append(value) } }
        }
        #expect(finished.sorted() == (0..<20).filter { !$0.isMultiple(of: 5) })
        #expect(limit.mostAtOnce == 3)
    }
}
