import ArgumentParser
import CleanCore
import Foundation

struct DerivedDataCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "derived-data",
        abstract: "List Xcode's DerivedData folders with their state and size; with --delete-orphans --yes, delete "
            + "the ones whose project no longer exists.",
        discussion: "A folder is orphaned only when its info.plist names a project path that does not exist (and is "
            + "not one of Xcode's temporary workspaces under /var/folders). Live projects' folders and folders "
            + "without an info.plist are never deleted. Each folder is checked again right before it is deleted, "
            + "and the cleanup is logged."
    )

    @Flag(
        name: .customLong("delete-orphans"),
        help: "Prepare deleting the orphaned folders. Without --yes it only prints what would be deleted."
    )
    var deleteOrphans = false

    @Flag(help: "Really delete what --delete-orphans describes.")
    var yes = false

    @Option(help: ArgumentHelp("List this DerivedData folder instead of Xcode's (listing only).", valueName: "path"))
    var location: String?

    func validate() throws {
        if yes && !deleteOrphans {
            throw ValidationError("--yes only goes with --delete-orphans.")
        }
        if location != nil && deleteOrphans {
            throw ValidationError("--location is for listing only; --delete-orphans always uses Xcode's DerivedData location.")
        }
    }

    func run() async throws {
        let context = try CommandContext.load()
        let lock = try CommandContext.holdCleanupLock(if: yes, environment: context.environment)
        defer { lock?.release() }
        let environment = context.environment
        let report: DerivedDataReport
        if let location {
            report = await DerivedDataScanner(
                root: context.absoluteURL(location),
                du: environment.tools.du,
                homeDirectory: environment.homeDirectory
            ).scan()
        } else {
            report = await DerivedDataScanner.scan(environment: environment)
        }
        for warning in report.warnings {
            StandardError.write("warning: \(warning)")
        }
        if let refusal = report.refusal {
            StandardError.write("error: \(refusal)")
            throw ExitCode.failure
        }
        print(DerivedDataText(report: report, home: environment.homeDirectory).render())
        guard deleteOrphans else { return }

        print("")
        let orphans = report.orphans
        guard !orphans.isEmpty else {
            print("No orphaned folders: nothing to delete.")
            return
        }
        let bytes = orphans.compactMap(\.bytes).reduce(0, +)
        guard yes else {
            print("Would delete \(orphans.count) orphaned \(orphans.count == 1 ? "folder" : "folders"), "
                + "about \(ByteFormatting.string(bytes)) (estimate).")
            print("Nothing was changed. Add --yes to delete them.")
            return
        }

        let deletion = await DerivedDataCleaner(environment: environment).delete(orphans)
        print(DerivedDataText.deletion(deletion))
        for warning in deletion.warnings {
            StandardError.write("warning: \(warning)")
        }
        if !deletion.failed.isEmpty || !deletion.logged { throw ExitCode.failure }
    }
}
