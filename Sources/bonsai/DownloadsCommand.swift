import ArgumentParser
import CleanCore
import Foundation

struct DownloadsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "downloads", abstract: "List old installers and archives, Trash, and local Time Machine snapshots.",
        discussion: "Only regular files at the top of Downloads, added at least 30 days ago, can be moved. Attached disk images stay. The CLI never empties the Trash.")

    @Flag(help: "Print the read-only report as JSON.") var json = false
    @Flag(name: .customLong("move-to-trash"), help: "Preview moving the listed old downloads to Trash. Add --yes to move them.")
    var moveToTrash = false
    @Flag(help: "Move the listed files to Trash. They can be put back while still in Trash.") var yes = false
    @Option(help: "Inspect a different home folder (listing and dry runs only).") var home: String?

    func validate() throws {
        if yes && !moveToTrash { throw ValidationError("--yes only goes with --move-to-trash.") }
        if json && moveToTrash { throw ValidationError("--json is for listing only.") }
        if home != nil && yes { throw ValidationError("--home is for listing and dry runs only.") }
    }

    func run() async throws {
        let context = try CommandContext.load()
        let environment = context.environment
        let homeDirectory = home.map(context.absoluteURL) ?? environment.homeDirectory
        let lock = try CommandContext.holdCleanupLock(if: yes, environment: environment)
        defer { lock?.release() }
        let scanner = DownloadsScanner(home: homeDirectory, now: environment.now)
        async let downloads = scanner.scan()
        async let trash = TrashInfo.read(home: homeDirectory)
        async let snapshots = LocalSnapshots.read(home: homeDirectory)
        let report = await DownloadsListing(downloads: downloads, trash: trash, timeMachine: snapshots)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
            return
        }
        print("Old installers and archives")
        for file in report.downloads.files {
            print("\(file.name)  \(ByteFormatting.string(file.bytes))  \(file.skipReason ?? "Can move to Trash")")
        }
        if report.downloads.files.isEmpty { print("No old installers or archives.") }
        if let bytes = report.trash.bytes, let count = report.trash.count {
            print("Trash: \(count) \(count == 1 ? "item" : "items"), \(ByteFormatting.string(bytes))")
        } else { print(TrashInfo.unreadableMessage) }
        print("Time Machine: \(report.timeMachine.snapshots.count) local snapshots")
        for snapshot in report.timeMachine.snapshots { print("  \(snapshot.id)") }
        if let purgeable = report.timeMachine.purgeableBytes, purgeable > 0 {
            print("macOS can free up to \(ByteFormatting.string(purgeable)) by itself")
        }
        for warning in report.downloads.warnings + report.timeMachine.warnings { StandardError.write("warning: \(warning)") }
        guard moveToTrash else { return }
        let files = report.downloads.eligible
        guard yes else {
            print("Would move \(files.count) \(files.count == 1 ? "file" : "files") (\(ByteFormatting.string(report.downloads.bytes))) to Trash.")
            print("Nothing was changed. Add --yes to move them. Emptying the Trash is a separate action in the app.")
            return
        }
        let results = await DownloadsMover(scanner: scanner, log: RemovalLog(environment: environment)).move(files)
        for result in results {
            print("\(result.file.name): \(result.reason)")
            for warning in result.warnings { StandardError.write("warning: \(warning)") }
        }
        if results.contains(where: { $0.status != .moved || !$0.warnings.isEmpty }) { throw ExitCode.failure }
    }
}
