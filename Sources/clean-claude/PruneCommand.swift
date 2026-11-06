import ArgumentParser
import CleanCore
import Foundation

struct PruneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Clear git's records of worktrees whose folders are gone (git worktree prune).",
        discussion: "Without --yes this is a dry run (git worktree prune --dry-run --verbose)."
    )

    @OptionGroup var rootOptions: RootOptions

    @Flag(help: "Prune for real. Without it nothing is changed.")
    var yes = false

    func run() async throws {
        let context = try CommandContext.load()
        let git = try context.requireGit()
        let scan = try await context.scan(rootOptions, includeSizes: false)
        let display = context.paths(for: scan)
        let pruner = Pruner(git: git, environment: context.environment)

        var failed = false
        var total = 0
        for repoPath in scan.repos {
            let repo = URL(fileURLWithPath: repoPath, isDirectory: true)
            do {
                let lines = try await pruner.preview(repo: repo)
                guard !lines.isEmpty else { continue }
                if yes {
                    let result = try await pruner.prune(repo: repo)
                    total += result.pruned.count
                    print("\(display.string(repo)): pruned \(result.pruned.count)")
                    result.pruned.forEach { print("  \($0)") }
                    result.warnings.forEach { StandardError.write("warning: \($0)") }
                    if !result.warnings.isEmpty { failed = true }
                } else {
                    total += lines.count
                    print("\(display.string(repo)): would prune \(lines.count)")
                    lines.forEach { print("  \($0)") }
                }
            } catch {
                StandardError.write("error: \(display.string(repo)): \(error)")
                failed = true
            }
        }

        if yes {
            print("Pruned \(total) worktree records in \(scan.repos.count) repos.")
        } else {
            print("Dry run: nothing was changed. \(total) worktree records would be pruned; add --yes to prune them.")
        }
        if failed { throw ExitCode.failure }
    }
}
