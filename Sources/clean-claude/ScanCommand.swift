import ArgumentParser
import CleanCore
import Foundation

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "List every git worktree under the scan roots with its repo, branch, kind, size, idle days "
            + "and removal status."
    )

    @OptionGroup var rootOptions: RootOptions

    @Flag(help: "Print the full scan result and every verdict as JSON.")
    var json = false

    @Flag(name: .customLong("no-sizes"), help: "Skip measuring folder sizes (much faster).")
    var noSizes = false

    @Flag(help: "Also find each worktree's light-clean folders and show their total size in a DEPS column (slow).")
    var deps = false

    @Option(help: ArgumentHelp("Only show worktrees with this status.", valueName: "auto-ready|safe|blocked"))
    var status: StatusFilter?

    enum StatusFilter: String, ExpressibleByArgument, CaseIterable {
        case autoReady = "auto-ready"
        case safe
        case blocked
    }

    func run() async throws {
        let context = try CommandContext.load()
        // The last commits and remotes go only into the JSON; the table stays as it is.
        let result = try await context.scan(
            rootOptions, includeSizes: !noSizes, includeDependencies: deps, includeGitDetails: json
        )

        var assessments: [WorktreeAssessment] = []
        if let git = WorktreeAssessor.git(for: context.environment), !result.worktrees.isEmpty {
            assessments = await context.assessor(git: git).assess(result)
        }
        let shown = assessments.filter { status == nil || $0.status.group == status?.rawValue }

        if json {
            print(try ScanJSON(scan: result, assessments: shown).encoded())
        } else {
            let table = ScanTable(
                result: result,
                assessments: shown,
                allAssessments: assessments,
                paths: context.paths(for: result),
                showSizes: !noSizes,
                showDependencies: deps
            )
            print(table.render())
        }
    }
}
