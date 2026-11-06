import ArgumentParser
import CleanCore
import Foundation

struct ClaudeUsageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-usage",
        abstract: "Show how much disk space Claude's transcripts, versions and desktop app data take. Read-only."
    )

    @Flag(help: "Print the report as JSON.")
    var json = false

    func run() async throws {
        let environment = CleanEnvironment.live()
        // Only repos, worktrees and roots are needed to name transcript folders, not their sizes.
        let scan = await Scanner(environment: environment).scan(includeSizes: false)
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
