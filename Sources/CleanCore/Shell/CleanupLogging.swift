import Foundation

/// The log entry a cleanup command writes once it has run (PLAN §3: every cleanup goes to
/// `removals.jsonl`). Part of `CleanupCommandResult.measuredRun`, so a command can't run without it.
struct CleanupLogging: Sendable {
    var log: RemovalLog
    var action: RemovalAction
    var estimatedBytes: Int64?
    var now: @Sendable () -> Date

    /// Appends one manual entry for a command that ran (succeeded or not). `notes` = the command line,
    /// then how it ended when it did not succeed, then the size the tool reported itself.
    func record(_ result: inout CleanupCommandResult, executable: URL, arguments: [String]) {
        var notes = [CommandLineDisplay.string(executable: executable.path, arguments: arguments)]
        if result.timedOut {
            notes.append("timed out")
        } else if result.exitCode != 0 {
            notes.append("exit \(result.exitCode)")
        }
        if let reported = result.reportedBytes {
            notes.append("the tool reported \(ByteFormatting.string(reported)) reclaimed")
        }
        let entry = RemovalLogEntry(
            date: now(),
            mode: .manual,
            action: action,
            repoPath: executable.path,
            path: executable.path,
            estimatedBytes: estimatedBytes,
            freedBytes: result.freedBytes,
            notes: notes
        )
        result.logEntry = entry
        do {
            try log.append(entry)
        } catch {
            result.logError = "the cleanup was not logged: \(error)"
        }
    }
}
