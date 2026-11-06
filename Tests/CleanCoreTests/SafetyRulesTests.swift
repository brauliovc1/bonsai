@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// PLAN §4.1, one test per row, asserting the manual and the auto column.
@Suite("Safety rules (§4.1)")
struct SafetyRulesTests {
    @Test func cleanIdleWorktreeIsAllowedForBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let report = try await world.check(try await world.sibling("clean"))
        #expect(report.blockers.isEmpty && report.notes.isEmpty, "\(report)")
        #expect(report.manualAllowed && report.autoEligible)
        #expect(report.status == .autoReady)
    }

    @Test func mainCheckoutIsNeverRemoved() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let report = try await world.check(world.repo)
        #expect(report.blockers == [.mainCheckout])
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func missingFolderOffersPruneInstead() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let gone = try await world.sibling("gone")
        try world.fixture.deleteFolder(gone)
        let report = try await world.check(gone)
        #expect(report.blockers == [.missingFolder])
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func lockedIsBlockedForBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let locked = try await world.sibling("locked")
        try await world.fixture.lock(locked, in: world.repo, reason: "on usb")
        let report = try await world.check(locked)
        #expect(report.blockers == [.locked(reason: "on usb")])
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func modifiedTrackedFileBlocksBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let dirty = try await world.sibling("dirty")
        try world.fixture.write("changed\n", to: "README.md", in: dirty)
        let report = try await world.check(dirty)
        #expect(report.blockers == [.uncommitted(count: 1)])
        #expect(!report.manualAllowed && !report.autoEligible)
        #expect(report.status == .blocked(.uncommitted(count: 1)))
        #expect(report.status.label == "BLOCKED: uncommitted (1)")
    }

    @Test func untrackedFileBlocksBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("untracked")
        try world.fixture.write("new\n", to: "notes/todo.txt", in: wt)
        try world.fixture.write("new\n", to: "notes/more.txt", in: wt)
        let report = try await world.check(wt)
        #expect(report.blockers == [.uncommitted(count: 2)])
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func submodulesBlockBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("subs")
        try world.fixture.write("[submodule \"lib\"]\n\tpath = lib\n\turl = ../lib\n", to: ".gitmodules", in: wt)
        try await world.fixture.commitAll(in: wt)
        try await world.fixture.run(["push", "--quiet", "-u", "origin", "subs"], in: wt)
        let report = try await world.check(wt)
        #expect(report.blockers == [.submodules])
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func localOnlyCommitsOnABranchAllowManualOnly() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("ahead")
        try world.fixture.write("work\n", to: "work.txt", in: wt)
        try await world.fixture.commitAll(in: wt)
        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty)
        #expect(report.notes == [.localOnlyCommits(count: 1, onBranch: true)])
        #expect(report.manualAllowed && !report.autoEligible)
        #expect(report.status == .safe)
    }

    @Test func detachedWithLocalOnlyCommitsBlocksBoth() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addWorktree(to: world.repo, at: world.fixture.url.appending(path: "det"), detached: true)
        try world.fixture.write("work\n", to: "work.txt", in: wt)
        try await world.fixture.commitAll(in: wt)
        let report = try await world.check(wt)
        #expect(report.blockers == [.localOnlyCommits(count: 1, onBranch: false), .reflogOnlyCommits(count: 1)])
        #expect(!report.manualAllowed && !report.autoEligible)
    }

    @Test func detachedWithoutLocalCommitsIsAllowed() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addWorktree(to: world.repo, at: world.fixture.url.appending(path: "det"), detached: true)
        let report = try await world.check(wt)
        #expect(report.manualAllowed && report.autoEligible, "\(report)")
    }

    @Test func stashForItsBranchBlocksAutoOnly() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("stashed")
        let other = try await world.sibling("other")
        try world.fixture.write("wip\n", to: "README.md", in: wt)
        try await world.fixture.run(["stash", "push", "--quiet"], in: wt)
        try world.fixture.write("wip\n", to: "README.md", in: other)
        try await world.fixture.run(["stash", "push", "--quiet", "-m", "parked"], in: other)

        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty)
        #expect(report.notes == [.stash(count: 1)])
        #expect(report.manualAllowed && !report.autoEligible)
    }

    @Test func ignoredEnvBlocksAutoAndIsListed() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("env")
        try world.fixture.write("SECRET=1\n", to: ".env", in: wt)
        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty)
        #expect(report.notes == [.ignoredUserFiles([".env"])])
        #expect(report.manualAllowed && !report.autoEligible)
    }

    @Test func ignoredNodeModulesAndLogsBlockNothing() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("deps")
        try world.fixture.write("module.exports = 1\n", to: "node_modules/pkg/index.js", in: wt)
        try world.fixture.write("module.exports = 1\n", to: "packages/app/node_modules/x/index.js", in: wt)
        try world.fixture.write("log\n", to: "debug.log", in: wt)
        let report = try await world.check(wt)
        #expect(report.blockers.isEmpty && report.notes.isEmpty, "\(report)")
        #expect(report.manualAllowed && report.autoEligible)
    }

    @Test func claudeWorktreeWarnsAndIsSkippedByAutoUnlessIncluded() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.fixture.addClaudeWorktree(to: world.repo, name: "task")
        let report = try await world.check(wt)
        #expect(report.notes == [.claudeSession])
        #expect(report.manualAllowed && !report.autoEligible)
        #expect(SafetyReason.claudeSession.sentence == SafetyReason.claudeSessionWarning)

        let included = try await world.check(wt, settings: Settings(includeClaudeInAuto: true))
        #expect(included.notes == [.claudeSession])
        #expect(included.manualAllowed && included.autoEligible)
    }

    @Test func idleBelowThresholdSkipsAutoOnly() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let wt = try await world.sibling("recent")
        let recent = try await world.check(wt, idle: .idle(days: 29))
        #expect(recent.notes == [.recentlyActive(days: 29)])
        #expect(recent.manualAllowed && !recent.autoEligible)
        let atThreshold = try await world.check(wt, idle: .idle(days: 30))
        #expect(atThreshold.autoEligible)
        let customThreshold = try await world.check(wt, idle: .idle(days: 30), settings: Settings(idleThresholdDays: 45))
        #expect(!customThreshold.autoEligible)
    }

    @Test func idleUnknownSkipsAutoOnly() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let report = try await world.check(try await world.sibling("unknown"), idle: .unknown)
        #expect(report.notes == [.idleUnknown])
        #expect(report.manualAllowed && !report.autoEligible)
    }

    @Test func repoWithoutRemoteIsNeverAutoEligible() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let local = try await world.fixture.makeLocalOnlyRepo("local")
        let onBranch = try await world.fixture.addSiblingWorktree(to: local, name: "feature")
        let report = try await world.check(onBranch, in: local, idle: .idle(days: 400))
        #expect(report.notes == [.localOnlyCommits(count: 1, onBranch: true)])
        #expect(report.manualAllowed && !report.autoEligible)

        let detached = try await world.fixture.addWorktree(to: local, at: world.fixture.url.appending(path: "ld"), detached: true)
        let detachedReport = try await world.check(detached, in: local, idle: .idle(days: 400))
        #expect(!detachedReport.manualAllowed && !detachedReport.autoEligible)
    }

    @Test func lsofUnavailableBlocksAutoOnly() async throws {
        let world = try await SafetyWorld.make()
        defer { world.remove() }
        let report = try await world.check(try await world.sibling("nolsof"), cwdIndex: .unavailable("test"))
        #expect(report.notes == [.inUseUnknown])
        #expect(report.manualAllowed && !report.autoEligible)
    }
}
