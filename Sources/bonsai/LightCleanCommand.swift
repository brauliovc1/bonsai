import ArgumentParser
import CleanCore
import Foundation

struct LightCleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "light-clean",
        abstract: "Delete a worktree's dependency and build-output folders (node_modules, dist, .build, ...) that "
            + "git ignores and tracks nothing in.",
        discussion: "Without --yes this is a dry run: it lists the folders it would delete with their sizes, and the "
            + "folders it skips with the reason. Works on main checkouts too. Every folder is checked again right "
            + "before it is deleted, nothing is deleted while a process has its working folder in the worktree, and "
            + "the cleanup is logged. Deleted folders can't be restored; reinstall or rebuild to get them back."
    )

    @OptionGroup var rootOptions: RootOptions

    @Argument(help: ArgumentHelp("The worktree or main checkout to clean.", valueName: "path"))
    var path: String

    @Flag(help: "Delete for real. Without it nothing is changed.")
    var yes = false

    func run() async throws {
        let context = try CommandContext.load()
        let lock = try CommandContext.holdCleanupLock(if: yes, environment: context.environment)
        defer { lock?.release() }
        let git = try context.requireGit()
        let scan = try await context.scan(rootOptions, includeSizes: false)
        let url = context.absoluteURL(path)
        guard let worktree = scan.worktrees.first(where: { CanonicalPath.same($0.url, url) }) else {
            StandardError.write("error: \(url.path) is not a worktree of a repo under the scan roots (see --root)")
            throw ExitCode.failure
        }
        let name = context.paths(for: scan).string(worktree.url)
        if let blocker = await SafetyCheck(git: git).identityBlocker(of: worktree) {
            StandardError.write("error: \(name): \(blocker.sentence)")
            throw ExitCode.failure
        }

        let findings = await LightCleanFinder(git: git, du: context.environment.tools.du)
            .candidates(in: worktree, knownWorktrees: scan.worktrees)
        if let problem = findings.problem {
            StandardError.write("error: \(name): \(problem)")
            throw ExitCode.failure
        }
        print(LightCleanText.findings(findings, name: name))
        guard !findings.candidates.isEmpty else { return }

        guard yes else {
            let index = await ProcessCwdIndex.capture(lsof: context.environment.tools.lsof)
            if let reason = LightCleaner.inUseReason(index, worktree: worktree.url) {
                print("warning: \(reason.sentence) --yes would delete nothing while that is so.")
            }
            print("Dry run: nothing was deleted. Add --yes to delete these folders.")
            return
        }

        let cleaner = LightCleaner(git: git, environment: context.environment)
        let result: LightCleanResult
        do {
            result = try await cleaner.clean(
                worktree,
                candidates: findings.candidates,
                knownWorktrees: scan.worktrees,
                expectation: LightCleanExpectation(worktree: worktree)
            )
        } catch {
            StandardError.write("error: \(name): \(error)")
            throw ExitCode.failure
        }
        print("")
        print(LightCleanText.result(result, name: name))
        for warning in result.warnings {
            StandardError.write("warning: \(warning)")
        }
        if !result.failed.isEmpty || !result.logged { throw ExitCode.failure }
    }
}
