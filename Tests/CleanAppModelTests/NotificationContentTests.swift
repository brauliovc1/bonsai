@testable import CleanAppModel
import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("Notifications, menu bar label, launch at login")
@MainActor
struct NotificationContentTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let gib: Int64 = 1024 * 1024 * 1024

    // MARK: - Auto-run notification

    @Test func reportOnly() throws {
        var summary = AutoRunSummary(date: date, reportOnly: true, plannedCount: 3, estimatedBytes: 3 * gib / 2)
        var content = try #require(NotificationContent.autoRun(summary))
        #expect(content.body == "Auto clean (report only): would remove 3 worktrees, about 1.5 GB. Nothing was deleted.")
        #expect(content.title == "Bonsai" && content.opens == .overview && content.identifier == "auto-run")

        summary.plannedCount = 1
        summary.notifiedCount = 2
        content = try #require(NotificationContent.autoRun(summary))
        #expect(content.body == "Auto clean (report only): would remove 1 worktree, about 1.5 GB. "
            + "2 idle worktrees have local work. Nothing was deleted.")

        summary.plannedCount = 0
        summary.notifiedCount = 1
        content = try #require(NotificationContent.autoRun(summary))
        #expect(content.body == "Auto clean (report only): nothing to remove. 1 idle worktree has local work. Nothing was deleted.")
    }

    @Test func normalRun() throws {
        var summary = AutoRunSummary(date: date, reportOnly: false, removedCount: 2, freedBytes: 512 * 1024 * 1024)
        var content = try #require(NotificationContent.autoRun(summary))
        #expect(content.body == "Removed 2 worktrees, freed 512.0 MB.")
        #expect(content.opens == .recentlyRemoved)

        summary.notifiedCount = 1
        #expect(NotificationContent.autoRun(summary)?.body == "Removed 2 worktrees, freed 512.0 MB. 1 idle worktree has local work.")
        summary.notifiedCount = 4
        #expect(NotificationContent.autoRun(summary)?.body == "Removed 2 worktrees, freed 512.0 MB. 4 idle worktrees have local work.")

        summary = AutoRunSummary(date: date, reportOnly: false, removedCount: 1, freedBytes: gib,
                                 failures: ["/a: git refused"], refused: ["/b: changed", "/c: changed"])
        content = try #require(NotificationContent.autoRun(summary))
        #expect(content.body == "Removed 1 worktree, freed 1.0 GB. 2 worktrees were left alone after a last check. "
            + "1 worktree could not be removed.")

        summary = AutoRunSummary(date: date, reportOnly: false, refused: ["/b: changed"])
        #expect(NotificationContent.autoRun(summary)?.body == "Auto clean removed nothing. 1 worktree was left alone after a last check.")
    }

    @Test func nothingToRemoveAndNothingToReportPostsNothing() {
        #expect(NotificationContent.autoRun(AutoRunSummary(date: date, reportOnly: true)) == nil)
        #expect(NotificationContent.autoRun(AutoRunSummary(date: date, reportOnly: false)) == nil)
    }

    // MARK: - Menu bar label and low space

    @Test func freeSpaceLabels() {
        #expect(FreeSpaceText.label(31 * gib) == "31 GB")
        #expect(FreeSpaceText.label(31 * gib + gib / 2 + 1) == "32 GB")
        #expect(FreeSpaceText.label(9 * gib + 4 * gib / 10) == "9.4 GB")
        #expect(FreeSpaceText.label(gib * 996 / 100) == "10 GB")
        #expect(FreeSpaceText.label(gib / 4) == "0.2 GB")
        #expect(FreeSpaceText.label(nil) == "–")
        #expect(FreeSpaceText.isLow(9 * gib, warningGB: 10))
        #expect(!FreeSpaceText.isLow(10 * gib, warningGB: 10))
        #expect(!FreeSpaceText.isLow(nil, warningGB: 10))
    }

    /// A menu bar model whose disk reads `free` bytes, in a fixture with settings in its home.
    private func menuBar(free: Int64, clock: TestClock) throws -> (GitFixture, MenuBarModel, RecordingNotifier) {
        let fixture = try GitFixture()
        var environment = fixture.environment()
        environment.now = { clock.now }
        try SettingsStore(environment: environment).save(Settings(idleThresholdDays: 60, lowSpaceWarningGB: 10))
        let app = AppModel(environment: environment, git: fixture.git)
        app.reloadSettings()
        app.disk.read = { _ in DiskSpaceModel.Reading(free: free, total: 500 * 1024 * 1024 * 1024, name: "Macintosh HD") }
        let notifier = RecordingNotifier()
        return (fixture, MenuBarModel(app: app, notifier: notifier), notifier)
    }

    @Test func theLabelShowsHowFullTheDiskIsAndWarnsBelowTheSetting() async throws {
        let clock = TestClock(date)
        let (fixture, model, notifier) = try menuBar(free: 300 * gib, clock: clock)
        defer { fixture.remove() }
        func show(free: Int64?, total: Int64? = 500 * 1024 * 1024 * 1024) async {
            model.app.disk.read = { _ in DiskSpaceModel.Reading(free: free, total: total, name: "Macintosh HD") }
            await model.refresh()
        }

        await model.refresh()
        #expect(model.fillFraction == 0.4)
        #expect(model.level == .normal && !model.isLow)
        #expect(model.accessibilityText == "Bonsai: 300 GB free of 500 GB")
        #expect(model.helpText == model.accessibilityText)
        #expect(notifier.posted.isEmpty)

        await show(free: 100 * gib)
        #expect(model.fillFraction == 0.8)
        #expect(model.level == .normal)

        await show(free: 8 * gib + gib / 5)
        #expect(model.level == .low && model.isLow)
        #expect(abs(model.fillFraction - (1 - 8.2 / 500)) < 0.0001)
        #expect(model.accessibilityText == "Bonsai: 8.2 GB free of 500 GB")
        #expect(model.helpText == "Bonsai: 8.2 GB free of 500 GB, below your 10 GB warning")

        await show(free: 5 * gib)
        #expect(model.level == .low, "half the warning exactly is not below it")
        await show(free: 5 * gib - 1)
        #expect(model.level == .veryLow)
        await show(free: 4 * gib, total: nil)
        #expect(model.level == .veryLow, "low space shows without the disk's size")
        #expect(model.fillFraction == 0)

        await show(free: nil, total: nil)
        #expect(model.level == .unknown)
        #expect(model.accessibilityText == "Bonsai: free space unknown")
        await show(free: 50 * gib, total: nil)
        #expect(model.level == .unknown, "plenty of space but nothing to fill the bar with")
    }

    @Test func theMenuWindowLineHasTheExactNumbers() {
        #expect(FreeSpaceText.summary(free: 23 * gib, total: 460 * gib) == "23.0 GB free of 460 GB (95% used)")
        #expect(FreeSpaceText.summary(free: 23 * gib, total: nil) == "23.0 GB free")
        #expect(FreeSpaceText.summary(free: nil, total: 460 * gib) == "Free space unknown")
        #expect(FreeSpaceText.isVeryLow(4 * gib, warningGB: 10) && !FreeSpaceText.isVeryLow(6 * gib, warningGB: 10))
    }

    @Test func theLowSpaceNotificationFiresAtMostOncePerDay() async throws {
        let clock = TestClock(date)
        let (fixture, model, notifier) = try menuBar(free: 3 * gib, clock: clock)
        defer { fixture.remove() }
        let store = SettingsStore(environment: model.app.environment)

        await model.refresh()
        #expect(notifier.posted.map(\.identifier) == ["low-space"])
        #expect(notifier.posted.first?.body == "Low disk space: 3.0 GB free on Macintosh HD, below your 10 GB warning. "
            + "Open Bonsai to see what can be removed.")
        #expect(notifier.posted.first?.opens == .overview)
        #expect(try store.load().lowSpaceNotifiedAt == date)
        #expect(try store.load().idleThresholdDays == 60, "other keys are kept")

        clock.set(date.addingTimeInterval(23 * 3_600 + 59 * 60))
        await model.refresh()
        await model.checkLowSpace()
        #expect(notifier.posted.count == 1, "not twice within a day")

        clock.set(date.addingTimeInterval(86_400))
        await model.refresh()
        #expect(notifier.posted.count == 2, "again a day later")
        #expect(try store.load().lowSpaceNotifiedAt == clock.now)
    }

    @Test func anUnreadableSettingsFileMeansNoLowSpaceNotification() async throws {
        let clock = TestClock(date)
        let (fixture, model, notifier) = try menuBar(free: 3 * gib, clock: clock)
        defer { fixture.remove() }
        let file = SettingsStore(environment: model.app.environment).fileURL
        try Data("{ not json".utf8).write(to: file)
        await model.refresh()
        #expect(notifier.posted.isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ not json", "never overwritten")
    }

    // MARK: - Launch at login

    @Test func launchAtLoginRegistersAndShowsApprovalAndErrors() {
        let service = FakeLoginItems()
        let model = LaunchAtLoginModel(service: service)
        #expect(!model.isOn && model.statusText.hasPrefix("Doesn't open at login"))

        model.setEnabled(true)
        #expect(service.registered == 1 && model.isOn && !model.needsApproval && model.error == nil)

        service.state = .requiresApproval
        model.refresh()
        #expect(model.isOn && model.needsApproval)
        model.openSystemSettings()
        #expect(service.openedSettings == 1)

        model.setEnabled(false)
        #expect(service.unregistered == 1 && !model.isOn)

        service.failure = "Operation not permitted"
        model.setEnabled(true)
        #expect(model.error == "Couldn't turn on launch at login: Operation not permitted")
        #expect(!model.isOn)

        let unavailable = LaunchAtLoginModel(service: UnavailableLoginItems())
        unavailable.setEnabled(true)
        #expect(unavailable.error == "Couldn't turn on launch at login: login items need the app bundle")
        #expect(unavailable.statusText.contains("/Applications"))
    }
}

@MainActor
private final class FakeLoginItems: LoginItemService {
    var state: LoginItemStatus = .notRegistered
    var registered = 0
    var unregistered = 0
    var openedSettings = 0
    var failure: String?

    struct Failure: LocalizedError {
        var errorDescription: String?
    }

    var status: LoginItemStatus { state }

    func register() throws {
        if let failure { throw Failure(errorDescription: failure) }
        registered += 1
        state = .enabled
    }

    func unregister() throws {
        unregistered += 1
        state = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openedSettings += 1
    }
}
