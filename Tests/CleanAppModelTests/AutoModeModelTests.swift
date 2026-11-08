@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// Auto mode on the demo world (plus a 29-day worktree), with a fake clock and a recording notifier.
@Suite("Auto mode runs")
@MainActor
struct AutoModeModelTests {
    /// The worktrees that must survive every run with default settings: uncommitted changes, a Claude
    /// worktree (setting off), one idle a day short of the threshold, an ignored .env (local work).
    static let keepers = ["atlas-wip", "tidy-otter", "atlas-edge", "beacon-env", "atlas-review", "beacon-spike"]

    @Test func enablingStartsTheReportOnlyWeekAndAsksForNotificationsOnlyThen() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: nil)
        defer { world.remove() }
        try SettingsStore(environment: world.environment).save(Settings(idleThresholdDays: 45))
        world.app.reloadSettings()
        #expect(world.notifier.authorizationRequests == 0, "not at launch")
        #expect(world.autoMode.statusText == "Auto mode: off")

        await world.autoMode.enable()
        var saved = try world.saved()
        #expect(saved.autoEnabled && saved.autoEnabledAt == world.clock.now)
        #expect(saved.idleThresholdDays == 45, "other keys are kept")
        #expect(world.notifier.authorizationRequests == 1)
        let end = world.clock.now.addingTimeInterval(7 * 86_400)
        #expect(world.autoMode.statusText == "Auto mode: report-only until \(end.formatted(date: .abbreviated, time: .shortened))")
        #expect(world.autoMode.reportOnlyText?.hasPrefix("Report-only until ") == true)

        world.clock.advance(by: 3_600)
        await world.autoMode.enable()
        #expect(try world.saved().autoEnabledAt == saved.autoEnabledAt, "already on: the week doesn't restart")
        #expect(world.notifier.authorizationRequests == 1)

        world.autoMode.disable()
        #expect(try world.saved().autoEnabled == false)
        world.clock.advance(by: 8 * 86_400)
        await world.autoMode.enable()
        saved = try world.saved()
        #expect(saved.autoEnabledAt == world.clock.now, "off and on again restarts the report-only week")
        #expect(world.autoMode.isReportOnly)
    }

    @Test func aReportOnlyRunRemovesNothingAndSaysWhatItWouldDo() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 1)
        defer { world.remove() }

        let summary = try #require(await world.autoMode.runNow())
        #expect(summary.reportOnly && summary.removedCount == 0)
        #expect(summary.plannedCount == 1, "atlas-archive would go")
        #expect(summary.notifiedCount == 1, "beacon-env has local work")
        #expect(try world.exists("atlas-archive"))
        #expect(try Self.keepers.allSatisfy(world.exists))
        #expect(try world.logEntries().isEmpty)
        #expect(try world.saved().lastAutoRun == summary, "lastAutoRun is saved")
        #expect(summary.date == world.clock.now)

        let size = ByteFormatting.string(summary.estimatedBytes)
        #expect(summary.estimatedBytes > 0)
        #expect(world.notifier.posted == [NotificationContent(
            identifier: "auto-run",
            title: "Bonsai",
            body: "Auto mode (report only): would remove 1 worktree, about \(size). 1 idle worktree has local work. "
                + "Nothing was deleted.",
            opens: .overview
        )])
        #expect(world.autoMode.lastRunText.hasSuffix("report only: would remove 1 worktree (about \(size)), 1 with local work."))
    }

    @Test func afterTheWeekItRemovesExactlyTheAutoEligibleWorktrees() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8)
        defer { world.remove() }

        let summary = try #require(await world.autoMode.runNow())
        #expect(!summary.reportOnly)
        #expect(try world.removedNames() == ["atlas-archive"])
        #expect(try !world.exists("atlas-archive"))
        #expect(try Self.keepers.allSatisfy(world.exists), "dirty, Claude, 29-day and local-work worktrees stay")
        #expect(await world.branchExists("archive"), "the branch is kept")
        #expect(try world.logEntries().allSatisfy { $0.mode == .auto })
        #expect(summary.removedCount == 1 && summary.notifiedCount == 1 && summary.refused.isEmpty && summary.failures.isEmpty)
        #expect(try world.saved().lastAutoRun == summary)
        #expect(!world.app.assessments.contains { $0.worktree.url.lastPathComponent == "atlas-archive" }, "rescanned")

        let freed = ByteFormatting.string(summary.freedBytes)
        #expect(world.notifier.posted.map(\.body) == ["Removed 1 worktree, freed \(freed). 1 idle worktree has local work."])
        #expect(world.notifier.posted.map(\.opens) == [.recentlyRemoved])
    }

    @Test func withClaudeWorktreesIncludedTheIdleCleanOneGoesToo() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8)
        defer { world.remove() }
        await world.autoMode.setIncludesClaudeWorktrees(true)
        #expect(try world.saved().includeClaudeInAuto)

        let summary = try #require(await world.autoMode.runNow())
        #expect(try Set(world.removedNames()) == ["atlas-archive", "tidy-otter"])
        #expect(summary.removedCount == 2)
        #expect(await world.branchExists("claude/tidy-otter"))
        #expect(try ["atlas-wip", "atlas-edge", "beacon-env"].allSatisfy(world.exists))
    }

    @Test func aWorktreeThatChangesAfterThePlanIsRefusedAndTheRunGoesOn() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8, includeClaude: true)
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        world.autoMode.afterPlanning = {
            _ = try? world.demo.fixture.write("new\n", to: "late.txt", in: archive)
        }

        let summary = try #require(await world.autoMode.runNow())
        #expect(try world.removedNames() == ["tidy-otter"])
        #expect(FileManager.default.fileExists(atPath: archive.appending(path: "late.txt").path), "refused, not removed")
        #expect(summary.refused.count == 1)
        #expect(summary.refused.first?.contains("atlas-archive: changed since the plan") == true, "\(summary.refused)")
        #expect(world.autoMode.lastRunDetails.first?.hasPrefix("Left alone: ") == true)
        #expect(world.notifier.posted.first?.body.hasSuffix("1 worktree was left alone after a last check.") == true)
    }

    @Test func turningItOffDuringARunStopsBeforeTheNextRemoval() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8, includeClaude: true)
        defer { world.remove() }
        world.autoMode.afterPlanning = { world.autoMode.disable() }

        let summary = try #require(await world.autoMode.runNow())
        #expect(summary.removedCount == 0)
        #expect(summary.refused.count == 2 && summary.refused.allSatisfy { $0.hasSuffix("the run was stopped before its turn") })
        #expect(try world.exists("atlas-archive") && world.exists("tidy-otter"))
        #expect(try world.logEntries().isEmpty)
    }

    /// The rules the plan used change on disk during the run (the CLI or the General tab): it stops.
    @Test func changedRulesDuringARunStopIt() async throws {
        for change in [{ (settings: inout Settings) in settings.includeClaudeInAuto = false },
                       { (settings: inout Settings) in settings.idleThresholdDays = 60 },
                       { (settings: inout Settings) in settings.autoEnabledAt = Date() }] {
            let world = try await AutoWorld.make(enabledDaysAgo: 8, includeClaude: true)
            defer { world.remove() }
            let store = SettingsStore(environment: world.environment)
            world.autoMode.afterPlanning = {
                var settings = (try? store.load()) ?? Settings()
                change(&settings)
                try? store.save(settings)
            }
            let summary = try #require(await world.autoMode.runNow())
            #expect(summary.removedCount == 0 && summary.refused.count == 2)
            #expect(try world.logEntries().isEmpty)
        }
    }

    @Test func twoOverlappingRunsRunOnce() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8)
        defer { world.remove() }

        async let first = world.autoMode.runNow()
        async let second = world.autoMode.runNow()
        let results = await [first, second]
        #expect(results.compactMap { $0 }.count == 1)
        #expect(try world.removedNames() == ["atlas-archive"])
        #expect(world.notifier.posted.count == 1)
        #expect(!world.autoMode.isRunning)
    }

    @Test func nothingRunsWhileItIsOff() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: nil)
        defer { world.remove() }
        #expect(await world.autoMode.runNow() == nil)
        #expect(world.autoMode.error == "Auto mode is off.")
        await world.autoMode.checkSchedule()
        #expect(try world.saved().lastAutoRun == nil)
        #expect(world.notifier.posted.isEmpty && world.app.scanCount == 0)
        #expect(!world.autoMode.canRunNow)
    }
}
