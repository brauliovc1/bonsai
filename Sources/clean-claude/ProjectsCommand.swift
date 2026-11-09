import ArgumentParser
import CleanCore
import Foundation

struct ProjectsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "projects",
        abstract: "List every checkout's dependency and build-output folders (node_modules, .next, build, ...) with "
            + "how long each project has been idle. Read-only.",
        discussion: "Lists main checkouts and sibling or other worktrees whose light-clean folders git ignores and "
            + "tracks nothing in, biggest first. By default only projects idle at least the settings' threshold "
            + "(30 days) are shown. Claude and Cursor worktrees are only counted: remove them whole with "
            + "`clean-claude remove`. Nothing is deleted or written; to clean one project, run "
            + "`clean-claude light-clean <path>` (a dry run) and add --yes."
    )

    @OptionGroup var rootOptions: RootOptions

    @Option(
        name: .customLong("idle-days"),
        help: ArgumentHelp("Show projects idle at least this many days. Default: the settings' threshold.", valueName: "N")
    )
    var idleDays: Int?

    @Flag(help: "Show every project, however recently it was used.")
    var all = false

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    func validate() throws {
        if let idleDays, idleDays < 0 { throw ValidationError("--idle-days can't be negative.") }
    }

    func run() async throws {
        let context = try CommandContext.load()
        let git = try context.requireGit()
        let scan = try await context.scan(rootOptions, includeSizes: false)
        let threshold = idleDays ?? context.settings.effectiveIdleThresholdDays
        let index = await ProcessCwdIndex.capture(lsof: context.environment.tools.lsof)
        // No size cache: this command writes nothing.
        let report = await ProjectFoldersScanner(git: git, environment: context.environment)
            .scan(scan.worktrees, knownWorktrees: scan.worktrees, cwdIndex: index)
        for problem in report.problems {
            StandardError.write("warning: \(problem)")
        }
        let shown = all ? report.projects : report.projects.filter { $0.isIdle(atLeast: threshold) }
        if json {
            print(try ProjectsJSON(report: report, shown: shown, threshold: threshold, all: all).encoded())
        } else {
            print(ProjectsText(report: report, shown: shown, threshold: threshold, all: all, paths: context.paths(for: scan)).render())
        }
    }
}
