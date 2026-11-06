import ArgumentParser
import CleanCore
import Foundation

struct ClaudeUsageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-usage",
        abstract: "Show how much disk space Claude's transcripts, versions and desktop app data take. Read-only."
    )

    @Option(
        name: .customLong("root"),
        help: ArgumentHelp(
            "A folder to scan for the repos whose transcript folders get named (repeatable). "
                + "Default: $CLEAN_CLAUDE_SCAN_ROOTS, else ~/Documents/GitHub.",
            valueName: "path"
        )
    )
    var roots: [String] = []

    @Flag(help: "Print the report as JSON.")
    var json = false

    func run() async throws {
        let environment = CleanEnvironment.live()
        let explicitRoots = roots.map { CleanEnvironment.expand($0, home: environment.homeDirectory) }
        // Only repos, worktrees and roots are needed to name transcript folders, not their sizes.
        let scan = await Scanner(environment: environment).scan(roots: explicitRoots, includeSizes: false)
        let report = await ClaudeUsageScanner(environment: environment).scan(using: scan)

        for issue in scan.issues {
            StandardError.write("warning: \(issue)")
        }
        for warning in report.warnings {
            StandardError.write("warning: \(warning)")
        }

        if json {
            let data = try CleanJSON.encoder().encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(ClaudeUsageText(report: report, homeDirectory: environment.homeDirectory).render())
        }
    }
}
