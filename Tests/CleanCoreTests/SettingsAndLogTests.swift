@testable import CleanCore
import CleanTestSupport
import Foundation
import Testing

@Suite("SettingsStore and RemovalLog")
struct SettingsAndLogTests {
    @Test func missingFileGivesDefaults() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let settings = try SettingsStore(directory: folder.url).load()
        #expect(settings == Settings())
        #expect(settings.idleThresholdDays == 30 && settings.lowSpaceWarningGB == 10 && settings.reportOnlyDays == 7)
        #expect(!settings.autoEnabled && !settings.includeClaudeInAuto)
        #expect(settings.scanRoots.isEmpty && settings.autoEnabledAt == nil && settings.lastAutoRun == nil)
    }

    @Test func partialFileAndUnknownKeys() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = SettingsStore(directory: folder.url)
        try Data(#"{"idleThresholdDays": 14, "futureKey": {"a": 1}, "lastAutoRun": {"removedCount": 2}}"#.utf8)
            .write(to: store.fileURL)
        let settings = try store.load()
        #expect(settings.idleThresholdDays == 14)
        #expect(settings.reportOnlyDays == 7 && !settings.autoEnabled)
        #expect(settings.lastAutoRun?.removedCount == 2)
        #expect(settings.lastAutoRun?.reportOnly == true)
    }

    @Test func roundTripIsPrettySortedISO8601() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = SettingsStore(directory: folder.url.appending(path: "nested/settings"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = Settings(
            scanRoots: ["~/code", "/work"],
            idleThresholdDays: 21,
            lowSpaceWarningGB: 20,
            autoEnabled: true,
            autoEnabledAt: date,
            reportOnlyDays: 3,
            includeClaudeInAuto: true,
            lastAutoRun: AutoRunSummary(date: date, reportOnly: false, removedCount: 4, freedBytes: 9_000,
                                        notifiedCount: 2, failures: ["x: refused"])
        )
        try store.save(settings)
        #expect(try store.load() == settings)

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"autoEnabledAt\" : \"2027-01-15T08:00:00Z\""))
        let keys = ["autoEnabled\"", "autoEnabledAt", "idleThresholdDays", "includeClaudeInAuto", "lastAutoRun",
                    "lowSpaceWarningGB", "reportOnlyDays", "scanRoots"]
        let offsets = keys.map { text.range(of: "\"\($0)")!.lowerBound }
        #expect(offsets == offsets.sorted())
    }

    @Test func brokenFileThrowsInsteadOfFallingBackToDefaults() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = SettingsStore(directory: folder.url)
        try Data("{not json".utf8).write(to: store.fileURL)
        #expect(throws: SettingsStore.LoadError.self) { try store.load() }
    }

    @Test func scannerUsesSettingsRootsAfterOverrides() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        var environment = fixture.environment()
        let settings = Settings(scanRoots: ["~/code"])
        #expect(Scanner.resolveRoots(explicit: [], environment: environment, settings: settings).map(\.path)
            == [fixture.home.appending(path: "code").path])
        environment.scanRootsOverride = [URL(fileURLWithPath: "/override")]
        #expect(Scanner.resolveRoots(explicit: [], environment: environment, settings: settings).map(\.path) == ["/override"])
    }

    @Test func missingRootsAreNotUsable() async throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        let scanner = Scanner(environment: fixture.environment())
        let missing = await scanner.scan(roots: [fixture.url.appending(path: "missing")], includeSizes: false)
        #expect(!missing.hasUsableRoot)
        let mixed = await scanner.scan(roots: [fixture.url.appending(path: "missing"), fixture.scanRoot], includeSizes: false)
        #expect(mixed.hasUsableRoot)
    }

    private func entry(_ path: String) -> RemovalLogEntry {
        RemovalLogEntry(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            mode: .manual,
            action: .worktreeRemove,
            repoPath: "/r",
            path: path,
            branch: "b",
            headSha: "abc",
            kind: .sibling,
            estimatedBytes: 10,
            freedBytes: 5,
            notes: ["n"]
        )
    }

    @Test func corruptLastLineIsSkippedAndTheNextAppendStartsClean() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = RemovalLog(directory: folder.url)
        #expect(try log.entries().isEmpty)
        let first = entry("/a")
        let second = entry("/b")
        try log.append(first)
        try log.append(second)
        let handle = try FileHandle(forWritingTo: log.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"id":"half-writ"#.utf8))
        try handle.close()

        #expect(try log.entries() == [first, second])
        let third = entry("/c")
        try log.append(third)
        #expect(try log.entries() == [first, second, third])
        let lines = try String(contentsOf: log.fileURL, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 4)
    }

    @Test func markingRestoredPersistsAndKeepsOtherLines() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = RemovalLog(directory: folder.url)
        let first = entry("/a")
        let second = entry("/b")
        try log.append(first)
        let handle = try FileHandle(forWritingTo: log.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("garbage line\n".utf8))
        try handle.close()
        try log.append(second)

        let restoredAt = Date(timeIntervalSince1970: 1_800_100_000)
        try log.markRestored(id: second.id, at: restoredAt)
        let reread = RemovalLog(directory: folder.url)
        #expect(try reread.entry(id: second.id)?.restoredAt == restoredAt)
        #expect(try reread.entry(id: first.id)?.restoredAt == nil)
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(text.contains("\ngarbage line\n"))
        #expect(text.split(separator: "\n").count == 3)
        #expect(throws: RemovalLog.LogError.self) { try log.markRestored(id: UUID(), at: restoredAt) }
    }
}
