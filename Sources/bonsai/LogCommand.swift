import ArgumentParser
import CleanCore
import Foundation

struct LogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Show every cleanup Bonsai has done (removals.jsonl), oldest first."
    )

    @Flag(help: "Print the entries as JSON.")
    var json = false

    func run() async throws {
        let context = try CommandContext.load()
        let log = RemovalLog(environment: context.environment)
        let entries: [RemovalLogEntry]
        do {
            entries = try log.entries()
        } catch {
            StandardError.write("error: cannot read \(log.fileURL.path): \(error)")
            throw ExitCode.failure
        }

        if json {
            print(String(decoding: try CleanJSON.encoder().encode(entries), as: UTF8.self))
            return
        }
        guard !entries.isEmpty else {
            print("No cleanups logged yet (\(log.fileURL.path)).")
            return
        }

        let display = PathDisplay(roots: [], home: context.environment.homeDirectory)
        var rows = [["DATE", "MODE", "ACTION", "FREED", "BRANCH", "RESTORED", "ID", "PATH"]]
        for entry in entries {
            rows.append([
                DateText.short(entry.date),
                entry.mode.rawValue,
                entry.action.rawValue,
                entry.freedBytes.map(ByteFormatting.string) ?? "-",
                entry.branch ?? entry.headSha.map { String($0.prefix(12)) } ?? "-",
                entry.restoredAt.map(DateText.short) ?? "-",
                String(entry.id.uuidString.prefix(8)).lowercased(),
                display.string(entry.path),
            ])
        }
        print(TextTable.lines(rows, rightAligned: [3]).joined(separator: "\n"))
        print("\(entries.count) entries in \(log.fileURL.path)")
    }
}
