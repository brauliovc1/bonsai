import CleanCore
import Foundation
import Testing

@Suite("AutoSchedule")
struct AutoScheduleTests {
    private let enabledAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func settings(enabled: Bool = true, lastRun: Date? = nil, reportOnlyDays: Int = 7) -> Settings {
        Settings(
            autoEnabled: enabled,
            autoEnabledAt: enabledAt,
            reportOnlyDays: reportOnlyDays,
            lastAutoRun: lastRun.map { AutoRunSummary(date: $0, reportOnly: true) }
        )
    }

    @Test func runsOncePerDay() {
        let last = enabledAt.addingTimeInterval(3_600)
        let settings = settings(lastRun: last)
        #expect(!AutoSchedule.shouldRun(now: last.addingTimeInterval(23 * 3_600 + 59 * 60), settings: settings), "23 h 59 m")
        #expect(!AutoSchedule.shouldRun(now: last.addingTimeInterval(86_399), settings: settings))
        #expect(AutoSchedule.shouldRun(now: last.addingTimeInterval(86_400), settings: settings), "24 h")
        #expect(AutoSchedule.shouldRun(now: last.addingTimeInterval(3 * 86_400), settings: settings))
    }

    @Test func runsWhenItNeverRanAndNeverWhenOff() {
        #expect(AutoSchedule.shouldRun(now: enabledAt, settings: settings()))
        #expect(!AutoSchedule.shouldRun(now: enabledAt, settings: settings(enabled: false)))
        #expect(!AutoSchedule.shouldRun(now: enabledAt.addingTimeInterval(10 * 86_400),
                                        settings: settings(enabled: false, lastRun: enabledAt)))
    }

    @Test func aLastRunInTheFutureCountsAsOld() {
        let settings = settings(lastRun: enabledAt.addingTimeInterval(30 * 86_400))
        #expect(AutoSchedule.shouldRun(now: enabledAt.addingTimeInterval(86_400), settings: settings))
        #expect(AutoSchedule.nextRun(now: enabledAt, settings: settings) == enabledAt)
    }

    @Test func theReportOnlyWindowEndsExactlyAfterItsDays() throws {
        let settings = settings()
        let end = try #require(AutoSchedule.reportOnlyEndsAt(settings))
        #expect(end == enabledAt.addingTimeInterval(7 * 86_400))
        #expect(AutoSchedule.isReportOnly(now: enabledAt, settings: settings))
        #expect(AutoSchedule.isReportOnly(now: end.addingTimeInterval(-1), settings: settings), "the last second")
        #expect(!AutoSchedule.isReportOnly(now: end, settings: settings), "the first second after")
        #expect(!AutoSchedule.isReportOnly(now: end.addingTimeInterval(1), settings: settings))
    }

    @Test func withoutAStartDateItOnlyReports() {
        let settings = Settings(autoEnabled: true)
        #expect(AutoSchedule.reportOnlyEndsAt(settings) == nil)
        #expect(AutoSchedule.isReportOnly(now: Date.distantFuture, settings: settings))
    }

    @Test func zeroReportOnlyDaysRemovesFromTheStart() {
        let settings = settings(reportOnlyDays: 0)
        #expect(!AutoSchedule.isReportOnly(now: enabledAt, settings: settings))
        #expect(AutoSchedule.isReportOnly(now: enabledAt.addingTimeInterval(-1), settings: settings))
    }

    @Test func theNextRunIsADayAfterTheLast() {
        let last = enabledAt.addingTimeInterval(3_600)
        let settings = settings(lastRun: last)
        #expect(AutoSchedule.nextRun(now: last.addingTimeInterval(60), settings: settings) == last.addingTimeInterval(86_400))
        let late = last.addingTimeInterval(2 * 86_400)
        #expect(AutoSchedule.nextRun(now: late, settings: settings) == late, "overdue: now")
        #expect(AutoSchedule.nextRun(now: last, settings: self.settings(enabled: false, lastRun: last)) == nil)
    }

    @Test func theSummaryAndTheNoticeDateRoundTripAndOldFilesStillDecode() throws {
        var settings = settings(lastRun: enabledAt)
        settings.lastAutoRun?.refused = ["/x: changed since the plan"]
        settings.lastAutoRun?.plannedCount = 3
        settings.lastAutoRun?.estimatedBytes = 42
        settings.lowSpaceNotifiedAt = enabledAt
        let data = try CleanJSON.encoder().encode(settings)
        #expect(try CleanJSON.decoder().decode(Settings.self, from: data) == settings)

        let old = Data(#"{"lastAutoRun":{"date":"2026-01-01T00:00:00Z","reportOnly":false,"removedCount":2}}"#.utf8)
        let decoded = try CleanJSON.decoder().decode(Settings.self, from: old)
        #expect(decoded.lastAutoRun?.removedCount == 2)
        #expect(decoded.lastAutoRun?.refused == [] && decoded.lastAutoRun?.plannedCount == 0)
        #expect(decoded.lowSpaceNotifiedAt == nil)
    }
}
