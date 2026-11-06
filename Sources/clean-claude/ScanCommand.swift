import ArgumentParser
import CleanCore
import Foundation

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "List every git worktree under the scan roots with its repo, branch, kind and size."
    )

    @Option(
        name: .customLong("root"),
        help: ArgumentHelp(
            "A folder to scan (repeatable). Default: $CLEAN_CLAUDE_SCAN_ROOTS, else ~/Documents/GitHub.",
            valueName: "path"
        )
    )
    var roots: [String] = []

    @Flag(help: "Print the full scan result as JSON.")
    var json = false

    @Flag(name: .customLong("no-sizes"), help: "Skip measuring folder sizes (much faster).")
    var noSizes = false

    func run() async throws {
        let environment = CleanEnvironment.live()
        let explicitRoots = roots.map { CleanEnvironment.expand($0, home: environment.homeDirectory) }
        let result = await Scanner(environment: environment).scan(roots: explicitRoots, includeSizes: !noSizes)

        for issue in result.issues {
            StandardError.write("warning: \(issue)")
        }
        if result.roots.isEmpty {
            throw ExitCode.failure
        }

        if json {
            let data = try CleanJSON.encoder().encode(result)
            print(String(decoding: data, as: UTF8.self))
        } else {
            let table = ScanTable(result: result, homeDirectory: environment.homeDirectory, showSizes: !noSizes)
            print(table.render())
        }
    }
}
