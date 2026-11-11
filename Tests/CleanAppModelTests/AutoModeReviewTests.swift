@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

/// The P8 review's items, each with the safe expectation: two instances, the last check before git,
/// quitting mid-removal, on without a start date, the wording of a stopped run, the low-space date.
@Suite("Auto clean review fixes")
@MainActor
struct AutoModeReviewTests {
    /// 1. Two app instances on one settings folder run at once: `cleanup.lock` lets one remove, once; the
    /// other skips, and a manual removal in it is refused while the first runs. Either instance may win the
    /// lock: each has the manual removal of the other ready, run by whichever plans first.
    @Test func twoInstancesOnOneSettingsFolderRemoveOnce() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8)
        defer { world.remove() }
        let other = ScreenModels(
            app: AppModel(environment: world.environment, git: world.demo.fixture.git),
            runner: FakeToolchain().runner,
            notifier: RecordingNotifier()
        )
        let review = try world.url("atlas-review")
        let instances = [world.models, other]
        var confirmations: [RemovalConfirmation] = []
        for instance in instances {
            await instance.app.refresh()
            confirmations.append(await instance.worktrees.prepareRemoval(instance.worktrees.ids([review])))
        }
        let manual = Box<[RemovalOutcome]>([])
        let hooksRun = Box(0)
        for (index, instance) in instances.enumerated() {
            // Runs in the instance that holds the lock; the manual removal goes to the one that doesn't.
            let loser = instances[1 - index], confirmation = confirmations[1 - index]
            instance.autoMode.afterPlanning = {
                hooksRun.value += 1
                manual.value = await loser.worktrees.confirmRemoval(confirmation)
            }
        }

        async let first = world.autoMode.runNow()
        async let second = other.autoMode.runNow()
        let results = await [first, second]

        #expect(results.compactMap { $0 }.count == 1, "one instance ran")
        #expect(hooksRun.value == 1, "only the instance that ran planned")
        #expect(try world.removedNames() == ["atlas-archive"], "removed once, one log entry")
        let errors = [world.autoMode.error, other.autoMode.error].compactMap { $0 }
        #expect(errors == ["Auto clean waited: \(CleanupLock.busyMessage). The next check tries again."])
        #expect(manual.value.map(\.error) == [CleanupLock.busyMessage])
        #expect(try world.exists("atlas-review"))

        let skipped = try #require(results.firstIndex { $0 == nil }.map { instances[$0] })
        await skipped.autoMode.checkSchedule()
        #expect(try world.removedNames() == ["atlas-archive"], "a day hasn't passed: the other skips")
    }

    /// 1. The CLI's `--yes` commands are refused while the app holds `cleanup.lock`.
    @Test func theCLIIsRefusedWhileTheAppCleansUp() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8)
        defer { world.remove() }
        let archive = try world.url("atlas-archive")
        let environment = [
            "BONSAI_SETTINGS_DIR": world.environment.settingsDirectory.path,
            "CLAUDE_CONFIG_DIR": world.environment.claudeConfigDirectory.path,
        ]
        let commands = [
            ["remove", archive.path, "--root", world.demo.folder.path, "--yes"],
            ["auto", "--root", world.demo.folder.path, "--yes"],
        ]
        let results = await world.app.cleaningUp { () -> [ProcessResult] in
            var results: [ProcessResult] = []
            for arguments in commands {
                if let result = try? await CLIBinary.run(arguments, environment: environment) { results.append(result) }
            }
            return results
        }
        let ran = try #require(results)
        #expect(ran.count == 2)
        for result in ran {
            #expect(!result.succeeded)
            #expect(result.stderr.contains(CleanupLock.busyMessage), "\(result.stderr)")
        }
        #expect(try world.exists("atlas-archive"))
        #expect(try world.logEntries().isEmpty)
        #expect(try world.saved().lastAutoRun == nil, "the CLI saved nothing either")
    }

    /// 2. Auto mode turned off on disk (another instance, the CLI) while the first removal's last check runs:
    /// the rules are read again right before git, so nothing is removed.
    @Test func turnedOffDuringTheLastCheckNothingIsRemoved() async throws {
        let gate = ProcessGate(stage: "lsof")
        let world = try await AutoWorld.make(enabledDaysAgo: 8, gate: gate)
        defer { world.remove() }
        var store = SettingsStore(environment: world.environment)
        store.lockTimeout = TestWait.limit
        world.autoMode.afterPlanning = { [store] in
            gate.arm()
            Task { @MainActor in
                #expect(await eventually { gate.isWaiting }, "the last check didn't reach lsof within \(TestWait.limit)")
                #expect(throws: Never.self, "auto clean turned off on disk") { _ = try store.update { $0.autoEnabled = false } }
                gate.open()
            }
        }

        let summary = try #require(await world.autoMode.runNow())
        #expect(summary.removedCount == 0)
        #expect(summary.stopReason == .turnedOff && summary.stoppedCount == 1)
        #expect(try world.exists("atlas-archive"))
        #expect(try world.logEntries().isEmpty)
        #expect(world.notifier.posted.isEmpty)
    }

    /// 2. "Include Claude worktrees" switched off while the Claude worktree's last check runs: it stays.
    @Test func claudeSettingOffDuringTheLastCheckTheClaudeWorktreeStays() async throws {
        let gate = ProcessGate(stage: "lsof")
        let world = try await AutoWorld.make(enabledDaysAgo: 8, includeClaude: true, gate: gate)
        defer { world.remove() }
        try world.demo.fixture.write("x\n", to: "keep.txt", in: try world.url("atlas-archive"))
        world.autoMode.afterPlanning = {
            gate.arm()
            Task { @MainActor in
                #expect(await eventually { gate.isWaiting }, "the last check didn't reach lsof within \(TestWait.limit)")
                #expect(world.autoMode.save("test") { $0.includeClaudeInAuto = false }, "the setting was saved")
                gate.open()
            }
        }

        let summary = try #require(await world.autoMode.runNow())
        #expect(summary.plannedCount == 1, "only tidy-otter was planned")
        #expect(summary.removedCount == 0 && summary.stopReason == .rulesChanged)
        #expect(try world.exists("tidy-otter"))
        #expect(try world.logEntries().isEmpty)
        #expect(world.notifier.posted.map(\.body) == ["Auto clean removed nothing. 1 idle worktree has local work. "
            + "The rules changed, so the run stopped."])
    }

    /// 3. Quit while `git worktree remove` runs: that removal finishes and is logged, the next one is left
    /// alone, and quitting waits for it; nothing new starts.
    @Test func quittingFinishesTheRemovalInProgressThenStops() async throws {
        let gate = ProcessGate(stage: "remove")
        let world = try await AutoWorld.make(enabledDaysAgo: 8, includeClaude: true, gate: gate)
        defer { world.remove() }
        let quit = Box(false)
        let waitedForTheRemoval = Box(false)
        world.autoMode.afterPlanning = {
            gate.arm()
            Task { @MainActor in
                #expect(await eventually { gate.isWaiting }, "git worktree remove didn't start within \(TestWait.limit)")
                Task { @MainActor in
                    await world.app.prepareToQuit()
                    quit.value = true
                }
                #expect(await eventually { world.app.isQuitting }, "quitting didn't start within \(TestWait.limit)")
                // Time for a quit that doesn't wait to finish; one that waits can't, the removal is at the gate.
                try? await Task.sleep(for: .milliseconds(300))
                waitedForTheRemoval.value = !quit.value
                gate.open()
            }
        }

        let summary = try #require(await world.autoMode.runNow())
        #expect(summary.removedCount == 1 && summary.stopReason == .quitting && summary.stoppedCount == 1)
        #expect(try world.logEntries().count == 1, "the removal in progress was logged")
        #expect(await eventually { quit.value })
        #expect(waitedForTheRemoval.value, "quitting waited for the removal")
        #expect(world.notifier.posted.isEmpty)
        #expect(await world.app.cleaningUp { true } == nil)
        #expect(world.app.busyReason == "the app is quitting")
    }

    /// 3. The same for a manual batch: the removal in progress finishes, the rest are not removed.
    @Test func quittingStopsAManualBatchAfterTheCurrentRemoval() async throws {
        let gate = ProcessGate(stage: "remove")
        let world = try await AutoWorld.make(enabledDaysAgo: nil, gate: gate)
        defer { world.remove() }
        await world.app.refresh()
        let worktrees = world.models.worktrees
        let confirmation = await worktrees.prepareRemoval(worktrees.ids([try world.url("atlas-review"), try world.url("atlas-archive")]))
        #expect(confirmation.allowed.count == 2)
        gate.arm()
        Task { @MainActor in
            #expect(await eventually { gate.isWaiting }, "git worktree remove didn't start within \(TestWait.limit)")
            Task { @MainActor in await world.app.prepareToQuit() }
            #expect(await eventually { world.app.isQuitting }, "quitting didn't start within \(TestWait.limit)")
            gate.open()
        }

        let outcomes = await worktrees.confirmRemoval(confirmation)
        #expect(outcomes.filter(\.removed).count == 1)
        #expect(outcomes.compactMap(\.error) == ["not removed: the app is quitting"])
        #expect(try world.logEntries().count == 1)
    }

    /// 5. On with no start date: the report-only week starts now, permission is asked, the text is normal.
    @Test func onWithoutAStartDateStartsTheReportOnlyWeekNow() async throws {
        let world = try await AutoWorld.make(enabledDaysAgo: 8, startDateMissing: true)
        defer { world.remove() }
        let start = world.clock.now
        #expect(try world.saved().autoEnabledAt == start)
        let end = start.addingTimeInterval(7 * 86_400).formatted(date: .abbreviated, time: .shortened)
        #expect(world.autoMode.statusText == "Auto clean: report-only until \(end)")
        #expect(await eventually { world.notifier.authorizationRequests == 1 })
        #expect(try #require(await world.autoMode.runNow()).reportOnly)

        world.clock.advance(by: 8 * 86_400)
        #expect(try #require(await world.autoMode.runNow()).reportOnly == false, "the week ends like any other")
    }

    /// 8. No notification shown, nothing written: a fresh install gets no settings.json for a notice nobody saw.
    @Test func theLowSpaceDateIsSavedOnlyWhenANotificationWasShown() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let app = AppModel(environment: fixture.environment(), git: fixture.git)
        app.disk.read = { _ in DiskSpaceModel.Reading(free: 3 * 1024 * 1024 * 1024, total: nil, name: nil) }
        let notifier = RecordingNotifier()
        notifier.allowed = false
        let model = MenuBarModel(app: app, notifier: notifier)
        let file = SettingsStore(environment: app.environment).fileURL

        await model.refresh()
        #expect(model.isLow && notifier.posted.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path), "nothing shown, nothing written")

        notifier.allowed = true
        await model.refresh()
        #expect(notifier.posted.count == 1)
        #expect(try SettingsStore(environment: app.environment).load().lowSpaceNotifiedAt != nil)
    }
}

/// A value the test and its tasks share on the main actor.
@MainActor
final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
