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
                let preview = try await pruner.preview(repo: repo)
                guard !preview.entries.isEmpty else { continue }
                if !preview.refusals.isEmpty {
                    print("\(display.string(repo)): refused, nothing pruned (git prunes a whole repo at once)")
                    preview.refusals.forEach { print("  refused: \($0)") }
                    preview.entries.forEach { print("  \($0.note)") }
                    if yes { failed = true }
                    continue
                }
                if yes {
                    let result = try await pruner.prune(repo: repo)
                    total += result.pruned.count
                    print("\(display.string(repo)): pruned \(result.pruned.count)")
                    (result.entry?.notes ?? result.pruned).forEach { print("  \($0)") }
                    result.warnings.forEach { StandardError.write("warning: \($0)") }
                    if !result.warnings.isEmpty { failed = true }
                } else {
                    total += preview.entries.count
                    print("\(display.string(repo)): would prune \(preview.entries.count)")
                    preview.entries.forEach { print("  \($0.note)") }
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
