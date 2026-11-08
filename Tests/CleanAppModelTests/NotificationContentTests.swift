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
        #expect(content.body == "Auto mode (report only): would remove 3 worktrees, about 1.5 GB. Nothing was deleted.")
        #expect(content.title == "Bonsai" && content.opens == .overview && content.identifier == "auto-run")

        summary.plannedCount = 1
        summary.notifiedCount = 2
        content = try #require(NotificationContent.autoRun(summary))
        #expect(content.body == "Auto mode (report only): would remove 1 worktree, about 1.5 GB. "
            + "2 idle worktrees have local work. Nothing was deleted.")

        summary.plannedCount = 0
        summary.notifiedCount = 1
        content = try #require(NotificationContent.autoRun(summary))
        #expect(content.body == "Auto mode (report only): nothing to remove. 1 idle worktree has local work. Nothing was deleted.")
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
        #expect(NotificationContent.autoRun(summary)?.body == "Auto mode removed nothing. 1 worktree was left alone after a last check.")
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

    @Test func theLabelWarnsBelowTheLowSpaceSetting() async throws {
        let clock = TestClock(date)
        let (fixture, model, notifier) = try menuBar(free: 50 * gib, clock: clock)
        defer { fixture.remove() }
        await model.refresh()
        #expect(model.freeSpaceText == "50 GB")
        #expect(model.symbolName == "internaldrive" && !model.isLow)
        #expect(notifier.posted.isEmpty)
        #expect(model.helpText == "50 GB free on Macintosh HD")

        model.app.disk.read = { _ in DiskSpaceModel.Reading(free: 8 * self.gib + self.gib / 5, total: nil, name: nil) }
        await model.refresh()
        #expect(model.freeSpaceText == "8.2 GB")
        #expect(model.symbolName == "exclamationmark.triangle" && model.isLow)
        #expect(model.helpText == "8.2 GB free (below your 10 GB warning)")
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
