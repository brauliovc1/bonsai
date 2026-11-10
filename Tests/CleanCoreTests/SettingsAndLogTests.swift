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
            == [CanonicalPath.resolve(fixture.home.appending(path: "code"))], "saved roots are canonical")
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

    // Item 12, then wave 4: a threshold below 7 days would make a worktree used last week auto-ready.
    @Test func outOfRangeSettingsAreErrors() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = SettingsStore(directory: folder.url)
        #expect(Settings.idleThresholdRange == 7...365)
        let bad = [
            #"{"idleThresholdDays": 0}"#, #"{"idleThresholdDays": -3}"#, #"{"idleThresholdDays": 1}"#,
            #"{"idleThresholdDays": 6}"#, #"{"idleThresholdDays": 366}"#, #"{"reportOnlyDays": -1}"#,
        ]
        for text in bad {
            try Data(text.utf8).write(to: store.fileURL)
            #expect(throws: SettingsStore.LoadError.self, "\(text)") { try store.load() }
        }
        for days in [7, 365] {
            try Data(#"{"idleThresholdDays": \#(days), "reportOnlyDays": 0}"#.utf8).write(to: store.fileURL)
            #expect(try store.load().idleThresholdDays == days)
        }

        try FileManager.default.removeItem(at: store.fileURL)
        for days in [0, 1, 6, 366] {
            #expect(throws: SettingsStore.LoadError.self, "\(days)") { try store.save(Settings(idleThresholdDays: days)) }
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    /// Settings built in code are held to the lowest allowed threshold too.
    @Test func theRulesNeverApplyAThresholdBelowTheRange() {
        #expect(Settings(idleThresholdDays: 1).effectiveIdleThresholdDays == 7)
        #expect(Settings(idleThresholdDays: 45).effectiveIdleThresholdDays == 45)
        let worktree = Worktree(path: "/tmp/w", repoPath: "/tmp/r", head: "abc", branch: "b", isMain: false, kind: .sibling)
        let safety = SafetyCheck.evaluate(
            worktree: worktree, state: WorktreeState(), idle: .idle(days: 1), settings: Settings(idleThresholdDays: 1),
            cwdIndex: ProcessCwdIndex(entries: [])
        )
        #expect(!safety.autoEligible, "one day idle is not idle enough, whatever the setting says")
    }

    // Item 10: an append from another writer while markRestored rewrites the file must not be lost. The other
    // writer is a thread of its own (a busy GCD pool once kept it from ever running), it waits for the lock as long
    // as the rewrite holds it, and every wait is checked.
    @Test func appendDuringARewriteIsKept() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var patient = RemovalLog(directory: folder.url)
        patient.lockTimeout = TestWait.limit
        let log = patient
        let first = entry("/a")
        let second = entry("/b")
        try log.append(first)

        let writer = TestThreads()
        let appending = DispatchSemaphore(value: 0), appended = DispatchSemaphore(value: 0)
        let failure = Shared<String?>(nil), heldBack = Shared<Bool?>(nil)
        var rewriting = log
        rewriting.duringRewrite = {
            writer.start {
                appending.signal()
                do { try log.append(second) } catch { failure.change { $0 = "\(error)" } }
                appended.signal()
            }
            // Without the lock the append lands here and the rewrite then drops it.
            let started = appending.wait(timeout: TestWait.deadline) == .success
            let landed = appended.wait(timeout: .now() + 0.5) == .success
            if landed { appended.signal() }
            heldBack.change { $0 = started && !landed }
        }
        try rewriting.markRestored(id: first.id, at: Date(timeIntervalSince1970: 1_800_100_000))

        #expect(appended.wait(timeout: TestWait.deadline) == .success,
                "the append didn't finish within \(TestWait.limit) of the rewrite letting go")
        #expect(heldBack.value == true, "the append started during the rewrite and waited for its lock")
        #expect(failure.value == nil)
        let entries = try log.entries()
        #expect(entries.map(\.id) == [first.id, second.id])
        #expect(entries.first?.restoredAt != nil)
        #expect(FileManager.default.fileExists(atPath: log.lockURL.path))
        #expect(writer.join(timeout: TestWait.limit), "the writer didn't stop within \(TestWait.limit)")
    }
}
