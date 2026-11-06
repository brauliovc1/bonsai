import ArgumentParser
import CleanCore
import Foundation

struct SettingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Show the settings shared by the app and the CLI (read-only)."
    )

    @Flag(help: "Print the settings as JSON.")
    var json = false

    func run() async throws {
        let context = try CommandContext.load()
        let settings = context.settings
        if json {
            print(String(decoding: try CleanJSON.encoder().encode(settings), as: UTF8.self))
            return
        }

        let store = SettingsStore(environment: context.environment)
        let exists = FileManager.default.fileExists(atPath: store.fileURL.path)
        let roots = Scanner.resolveRoots(explicit: [], environment: context.environment, settings: settings)
        let now = context.environment.now()

        var rows: [[String]] = []
        rows.append(["file", store.fileURL.path + (exists ? "" : " (not created yet: defaults)")])
        rows.append(["scanRoots", settings.scanRoots.isEmpty ? "(default)" : settings.scanRoots.joined(separator: ", ")])
        rows.append(["  in effect", roots.isEmpty ? "(none)" : roots.map(\.path).joined(separator: ", ")])
        for refusal in settings.refusedScanRoots(home: context.environment.homeDirectory) {
            rows.append(["  skipped", "\(refusal.path): \(refusal.reason)"])
        }
        rows.append(["idleThresholdDays", "\(settings.idleThresholdDays)"])
        rows.append(["lowSpaceWarningGB", "\(settings.lowSpaceWarningGB)"])
        rows.append(["autoEnabled", "\(settings.autoEnabled)"])
        rows.append(["autoEnabledAt", settings.autoEnabledAt.map(DateText.short) ?? "-"])
        rows.append(["reportOnlyDays", "\(settings.reportOnlyDays)"])
        rows.append(["  report-only now", "\(settings.isReportOnly(now: now))"])
        rows.append(["includeClaudeInAuto", "\(settings.includeClaudeInAuto)"])
        if let run = settings.lastAutoRun {
            let mode = run.reportOnly ? "report-only" : "removed \(run.removedCount)"
            rows.append(["lastAutoRun", "\(DateText.short(run.date)): \(mode), freed "
                + "\(ByteFormatting.string(run.freedBytes)), notified \(run.notifiedCount), "
                + "\(run.failures.count) failures"])
        } else {
            rows.append(["lastAutoRun", "-"])
        }
        print(TextTable.lines(rows).joined(separator: "\n"))
    }
}
