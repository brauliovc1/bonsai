@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// One cleanup at a time with auto mode, and when its checks run.
@Suite("Auto mode guard and schedule")
@MainActor
struct AutoModeScheduleTests {
    @Test func aManualCleanupKeepsTheRunFromStartingAndTheNextCheckTriesAgain() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8)
        defer { world.remove() }
        let gate = Gate()
        let manual = Task { await world.app.cleaningUp { await gate.wait() } }
        #expect(await eventually { world.app.isCleaningUp })

        await world.autoMode.checkSchedule()
        #expect(try world.saved().lastAutoRun == nil, "it did not start")
        #expect(world.autoMode.error == "Auto mode waited: another cleanup is still running. The next check tries again.")
        #expect(try world.exists("atlas-archive"))
        #expect(world.app.busyReason == "another cleanup is still running")

        await gate.open()
        _ = await manual.value
        await world.autoMode.checkSchedule()
        #expect(try world.saved().lastAutoRun?.removedCount == 1, "the next check ran it")
        #expect(try !world.exists("atlas-archive"))
    }

    @Test func manualCleanupsAreRefusedWhileAutoModeRuns() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8)
        defer { world.remove() }
        await world.app.refresh()
        let worktrees = world.models.worktrees
        let confirmation = await worktrees.prepareRemoval(worktrees.ids([try world.url("atlas-review")]))
        #expect(confirmation.allowed.count == 1)

        var outcomes: [RemovalOutcome] = []
        var reason = ""
        world.autoMode.afterPlanning = {
            reason = world.app.busySentence
            outcomes = await worktrees.confirmRemoval(confirmation)
        }
        await world.autoMode.runNow()

        #expect(reason == "Auto mode is running.")
        #expect(outcomes.map(\.error) == ["Auto mode is running"])
        #expect(try world.exists("atlas-review"), "the manual removal was refused")
        #expect(try world.removedNames() == ["atlas-archive"], "the auto run went on")
        #expect(!world.app.isAutoRunning && !world.app.isCleaningUp)
        #expect(world.app.busyReason == "another cleanup is still running")
    }

    @Test func checksRunOncePerDay() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 1)
        defer { world.remove() }
        let start = world.clock.now

        await world.autoMode.checkSchedule()
        #expect(try world.saved().lastAutoRun?.date == start, "never ran: runs")
        #expect(world.autoMode.nextRun == start.addingTimeInterval(86_400))
        #expect(world.autoMode.nextRunText.hasPrefix("Next run: after "))

        world.clock.set(start.addingTimeInterval(23 * 3_600))
        await world.autoMode.checkSchedule()
        #expect(try world.saved().lastAutoRun?.date == start, "23 h (an hourly check): no run")
        world.clock.set(start.addingTimeInterval(23 * 3_600 + 59 * 60))
        await world.autoMode.checkSchedule()
        #expect(try world.saved().lastAutoRun?.date == start, "23 h 59 m: no run")

        world.clock.set(start.addingTimeInterval(86_400))
        await world.autoMode.checkSchedule()
        #expect(try world.saved().lastAutoRun?.date == world.clock.now, "24 h: runs")
        #expect(world.notifier.posted.count == 2, "one notification per run")
        #expect(AutoSchedule.checkInterval == 3_600 && AutoSchedule.checkTolerance == 600, "checked hourly")
    }

    @Test func theLaunchAndWakeChecksRunAutoMode() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 1)
        defer { world.remove() }
        let center = NotificationCenter()
        let wake = Notification.Name("test.didWake")
        let scheduler = AutoModeScheduler(model: world.autoMode)
        scheduler.wakeDelay = .milliseconds(600)
        scheduler.start(wakeCenter: center, wakeName: wake, hourly: false)
        defer { scheduler.stop() }

        #expect(await eventually { (try? world.saved().lastAutoRun) != nil }, "the launch check")
        #expect(await eventually { !world.autoMode.isRunning })
        let first = try #require(try world.saved().lastAutoRun?.date)

        center.post(name: wake, object: nil)
        try await Task.sleep(for: .milliseconds(900))
        #expect(try world.saved().lastAutoRun?.date == first, "woke within a day: no run")

        world.clock.advance(by: 86_400)
        let scans = world.app.scanCount
        center.post(name: wake, object: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!world.autoMode.isRunning && world.app.scanCount == scans, "not right at the wake: it waits a while first")
        #expect(await eventually { (try? world.saved().lastAutoRun?.date) == world.clock.now }, "woke a day later: runs")
        #expect(AutoModeScheduler.identifier == "io.github.brauliovc1.bonsai.auto")
        #expect(AutoSchedule.wakeDelay == .seconds(300))
    }

    @Test func theOverviewRowShowsOffReportOnlyAndOnWithTheRuns() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: nil)
        defer { world.remove() }
        let overview = world.models.overview
        #expect(overview.autoModeText == "Auto mode: off")
        #expect(overview.autoModeDetail == "Last run: never. Next run: none while auto mode is off.")

        await world.autoMode.enable()
        let end = world.clock.now.addingTimeInterval(7 * 86_400).formatted(date: .abbreviated, time: .shortened)
        #expect(overview.autoModeText == "Auto mode: report-only until \(end)")
        #expect(overview.autoModeDetail.hasSuffix("Next run: at the next check (daily, at launch and when the Mac wakes)."))

        await world.autoMode.runNow()
        let ran = world.clock.now.formatted(date: .abbreviated, time: .shortened)
        #expect(overview.autoModeDetail.hasPrefix("Last run: \(ran), report only: would remove 1 worktree"))

        world.clock.advance(by: 8 * 86_400)
        #expect(overview.autoModeText == "Auto mode: on")
        #expect(world.autoMode.reportOnlyText == nil)
    }
}

/// Holds a task until opened.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
