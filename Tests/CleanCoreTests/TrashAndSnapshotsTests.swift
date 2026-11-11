@testable import CleanCore
import CleanTestSupport
import Darwin
import Foundation
import Testing

@Suite("Trash and local snapshots")
struct TrashAndSnapshotsTests {
    @Test func missingAndEmptyTrashAreReadableAndDoNotRunDU() async throws {
        let home = try TemporaryDirectory(prefix: "bonsai-trash-info")
        defer { home.remove() }
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }
        #expect(await TrashInfo.read(home: home.url, runner: runner.runner) == TrashInfo(bytes: 0, count: 0))
        try FileManager.default.createDirectory(at: home.url.appending(path: ".Trash"), withIntermediateDirectories: true)
        #expect(await TrashInfo.read(home: home.url, runner: runner.runner) == TrashInfo(bytes: 0, count: 0))
        #expect(runner.calls.isEmpty)
    }

    @Test func readableTrashCountsTopLevelItemsAndUsesAllocatedBytes() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        try Data("one".utf8).write(to: world.trash.appending(path: "one.zip"))
        let folder = world.trash.appending(path: "folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: folder.appending(path: "nested.pkg"))
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: "12\tignored-path\n") }
        let result = await TrashInfo.read(home: world.home, runner: runner.runner)
        #expect(result.readable && result.count == 2 && result.bytes == Int64(12 * 1024))
        let call = try #require(runner.calls.first)
        #expect(runner.calls.count == 1 && call.executable.path == "/usr/bin/du")
        #expect(call.arguments == ["-skx", world.trash.resolvingSymlinksInPath().path])
        #expect(call.timeout == .seconds(300))
    }

    @Test(arguments: [false, true])
    func nonDirectoryTrashIsUnreadableWithoutRunningDU(symlink: Bool) async throws {
        let home = try TemporaryDirectory(prefix: "bonsai-trash-info")
        defer { home.remove() }
        let trash = home.url.appending(path: ".Trash")
        if symlink { try FileManager.default.createSymbolicLink(at: trash, withDestinationURL: home.url) }
        else { try Data("file".utf8).write(to: trash) }
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }
        let result = await TrashInfo.read(home: home.url, runner: runner.runner)
        #expect(!result.readable && result.bytes == nil && result.count == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test func deniedItemListingIsUnreadableWithoutRunningDU() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }
        let result = await TrashInfo.read(home: world.home, runner: runner.runner, itemCount: { _ in
            throw CocoaError(.fileReadNoPermission)
        })
        #expect(!result.readable && result.bytes == nil && result.count == nil)
        #expect(runner.calls.isEmpty)
        #expect(TrashInfo.unreadableMessage == "Bonsai can't see inside the Trash without Full Disk Access")
    }

    @Test func inaccessibleParentIsUnreadableRatherThanAnEmptyTrash() async throws {
        let temporary = try TemporaryDirectory(prefix: "bonsai-trash-denied-parent")
        defer { temporary.remove() }
        let home = temporary.url.appending(path: "home")
        let trash = home.appending(path: ".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("protected".utf8).write(to: trash.appending(path: "keep.zip"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path) }
        var info = stat()
        let status = lstat(trash.path, &info)
        #expect(status == -1 && errno == EACCES, "the fixture must deny lstat, rather than remove .Trash")
        let runner = ScriptedCommandRunner { _ in throw ScriptedCommandRunner.StartFailure() }
        let result = await TrashInfo.read(home: home, runner: runner.runner)
        #expect(!result.readable && result.bytes == nil && result.count == nil)
        #expect(runner.calls.isEmpty)
    }

    @Test(arguments: TrashSnapshotCommandFailure.allCases)
    func trashMeasurementFailuresAreUnreadable(failure: TrashSnapshotCommandFailure) async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        try Data("fixture".utf8).write(to: world.trash.appending(path: "file.zip"))
        let runner = ScriptedCommandRunner { _ in try failure.result() }
        let result = await TrashInfo.read(home: world.home, runner: runner.runner)
        #expect(!result.readable && result.bytes == nil && result.count == nil)
        #expect(runner.calls.count == 1)
    }

    @Test func unconfirmedEmptyCannotCallFinderMeasureOrLog() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        let fake = TrashFlowProbe(capacities: [100, 150])
        let flow = EmptyTrashFlow(emptier: fake, log: world.log, home: world.home, freeSpace: fake.freeSpace)
        #expect(try await flow.run(confirmed: false) == nil)
        #expect(fake.trace.isEmpty)
        #expect(try world.log.entries().isEmpty)
    }

    @Test func confirmedEmptyMeasuresAroundFakeFinderThenLogsOnce() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        let fake = TrashFlowProbe(capacities: [100, 175])
        let now = world.now
        let flow = EmptyTrashFlow(emptier: fake, log: world.log, home: world.home, freeSpace: fake.freeSpace, now: { now })
        let result = try #require(try await flow.run(confirmed: true))
        #expect(fake.trace == ["capacity", "empty", "capacity"])
        #expect(result.entry.action == .trashEmptied && result.entry.mode == .manual)
        #expect(result.entry.path == world.trash.path && result.entry.repoPath == world.home.path)
        #expect(result.entry.date == now && result.entry.freedBytes == Int64(75))
        #expect(result.warnings.isEmpty)
        #expect(try world.log.entries() == [result.entry])
    }

    @Test func emptyMeasurementsClampDecreasesAndKeepMissingValuesUnknown() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        let scenarios: [(Int64?, Int64?, Int64?)] = [(100, 90, 0), (nil, 150, nil), (100, nil, nil), (nil, nil, nil)]
        for (before, after, expected) in scenarios {
            let fake = TrashFlowProbe(capacities: [before, after])
            let flow = EmptyTrashFlow(emptier: fake, log: world.log, home: world.home, freeSpace: fake.freeSpace)
            #expect(try await flow.run(confirmed: true)?.entry.freedBytes == expected)
        }
        #expect(try world.log.entries().count == scenarios.count)
    }

    @Test func deniedAndFailedFinderCallsPropagateWithoutSuccessLogs() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        for failure in [TrashEmptyError.automationDenied, .failed("Finder unavailable")] {
            let fake = TrashFlowProbe(capacities: [100, 175], failure: failure)
            let flow = EmptyTrashFlow(emptier: fake, log: world.log, home: world.home, freeSpace: fake.freeSpace)
            do { _ = try await flow.run(confirmed: true); Issue.record("a failed Finder call must throw") }
            catch { #expect(error.localizedDescription == failure.localizedDescription) }
            #expect(fake.trace == ["capacity", "empty"])
        }
        #expect(try world.log.entries().isEmpty)
        #expect(TrashEmptyError.automationDenied.localizedDescription == "Allow Bonsai to control Finder in System Settings › Privacy & Security › Automation")
    }

    @Test func successfulEmptyWithUnwritableLogReturnsAWarningAndMeasuredResult() async throws {
        let world = try DownloadsWorld()
        defer { world.directory.remove() }
        let blocked = world.home.appending(path: "settings-file")
        try Data("file".utf8).write(to: blocked)
        let fake = TrashFlowProbe(capacities: [100, 150])
        let flow = EmptyTrashFlow(emptier: fake, log: RemovalLog(directory: blocked), home: world.home, freeSpace: fake.freeSpace)
        let result = try #require(try await flow.run(confirmed: true))
        #expect(fake.trace == ["capacity", "empty", "capacity"])
        #expect(result.entry.freedBytes == Int64(50) && result.entry.action == .trashEmptied)
        #expect(result.warnings.count == 1 && result.warnings[0].contains("history could not be written"))
    }

    @Test func snapshotsParseDatesStrictlyAndSortNewestFirst() throws {
        let text = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-09-081530.local
          com.apple.TimeMachine.2026-11-10-093000.local
        com.apple.TimeMachine.2026-02-30-093000.local
        com.apple.TimeMachine.2026-11-10-253000.local
        com.apple.TimeMachine.not-a-date.local
        com.apple.TimeMachine.2026-11-10-093000.backup
        unrelated.2026-11-10-093000.local
        """
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let result = LocalSnapshots.parse(text, timeZone: utc)
        #expect(result.map(\.id) == ["com.apple.TimeMachine.2026-11-10-093000.local", "com.apple.TimeMachine.2026-11-09-081530.local"])
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-11-10T09:30:00Z"))
        #expect(result.first?.date == expected)
        #expect(LocalSnapshots.parse("Snapshots for disk /:\n", timeZone: utc).isEmpty)
        #expect(LocalSnapshots.parse("", timeZone: utc).isEmpty)
        let east = try #require(TimeZone(secondsFromGMT: 7200))
        #expect(LocalSnapshots.parse(text, timeZone: east).first?.date == expected.addingTimeInterval(-7200))
    }

    @Test func purgeableSpaceIsOnlyThePositiveKnownDifference() {
        #expect(LocalSnapshots.purgeable(important: 500, available: 125) == Int64(375))
        #expect(LocalSnapshots.purgeable(important: 125, available: 500) == Int64(0))
        #expect(LocalSnapshots.purgeable(important: 125, available: 125) == Int64(0))
        #expect(LocalSnapshots.purgeable(important: nil, available: 125) == nil)
        #expect(LocalSnapshots.purgeable(important: 125, available: nil) == nil)
    }

    @Test func snapshotReadUsesOnlyTheReadOnlyCommand() async throws {
        let home = try TemporaryDirectory(prefix: "bonsai-snapshots")
        defer { home.remove() }
        let runner = ScriptedCommandRunner { _ in ScriptedCommandRunner.result(stdout: "Snapshots for disk /:\ncom.apple.TimeMachine.2026-11-10-093000.local\n") }
        let result = await LocalSnapshots.read(home: home.url, runner: runner.runner)
        #expect(result.snapshots.count == 1 && result.warnings.isEmpty)
        let call = try #require(runner.calls.first)
        #expect(runner.calls.count == 1 && call.executable.path == "/usr/bin/tmutil")
        #expect(call.arguments == ["listlocalsnapshots", "/"] && call.timeout == .seconds(60))
    }

    @Test(arguments: [TrashSnapshotCommandFailure.exitFailure, .timedOut, .startFailure])
    func snapshotRunnerFailuresReturnAWarning(failure: TrashSnapshotCommandFailure) async throws {
        let home = try TemporaryDirectory(prefix: "bonsai-snapshots")
        defer { home.remove() }
        let runner = ScriptedCommandRunner { _ in try failure.result() }
        let result = await LocalSnapshots.read(home: home.url, runner: runner.runner)
        #expect(result.snapshots.isEmpty && result.warnings.count == 1)
        #expect(result.warnings[0].contains("Could not read local snapshots"))
        #expect(runner.calls.count == 1)
    }
}

enum TrashSnapshotCommandFailure: CaseIterable, Sendable {
    case exitFailure, timedOut, malformedOutput, startFailure
    func result() throws -> ProcessResult {
        switch self {
        case .exitFailure: ScriptedCommandRunner.result(exitCode: 1, stderr: "not allowed")
        case .timedOut: ScriptedCommandRunner.result(timedOut: true)
        case .malformedOutput: ScriptedCommandRunner.result(stdout: "not a size")
        case .startFailure: throw ScriptedCommandRunner.StartFailure()
        }
    }
}

private final class TrashFlowProbe: TrashEmptier, @unchecked Sendable {
    private let lock = NSLock()
    private var capacities: [Int64?]
    private var recorded: [String] = []
    private let failure: TrashEmptyError?
    init(capacities: [Int64?], failure: TrashEmptyError? = nil) { self.capacities = capacities; self.failure = failure }
    var trace: [String] { lock.withLock { recorded } }
    var freeSpace: FreeSpaceProbe { FreeSpaceProbe { [self] in lock.withLock { recorded.append("capacity"); return capacities.isEmpty ? nil : capacities.removeFirst() } } }
    func empty() async throws {
        lock.withLock { recorded.append("empty") }
        if let failure { throw failure }
    }
}
