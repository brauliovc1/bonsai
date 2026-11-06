import ArgumentParser
import CleanCore
import Foundation

struct RemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove worktrees the safe way (git worktree remove, never --force; branches are kept).",
        discussion: "Without --yes this is a dry run: it prints each verdict with all its reasons and what would "
            + "happen. Every removal is checked again right before it runs, and logged."
    )

    @OptionGroup var rootOptions: RootOptions

    @Argument(help: ArgumentHelp("Worktree folders to remove.", valueName: "path"))
    var paths: [String]

    @Flag(help: "Remove for real. Without it nothing is changed.")
    var yes = false

    func run() async throws {
        let context = try CommandContext.load()
        let git = try context.requireGit()
        let scan = try await context.scan(rootOptions, includeSizes: false)
        let display = context.paths(for: scan)

        var targets: [Worktree] = []
        var failed = false
        for argument in paths {
            let url = context.absoluteURL(argument)
            guard let worktree = scan.worktrees.first(where: { CanonicalPath.same($0.url, url) }) else {
                StandardError.write("error: \(url.path) is not a worktree of a repo under the scan roots (see --root)")
                failed = true
                continue
            }
            if !targets.contains(worktree) { targets.append(worktree) }
        }

        let sizes = await context.sizes(of: targets.filter { !$0.isMain })
        let assessments = await context.assessor(git: git)
            .assess(targets, knownWorktrees: scan.worktrees, sizes: sizes)

        if yes {
            let remover = Remover(git: git, settings: context.settings, environment: context.environment)
            for assessment in assessments {
                if !(await removeOne(assessment, remover: remover, known: scan.worktrees, display: display)) { failed = true }
            }
        } else {
            for assessment in assessments {
                print(VerdictText.describe(assessment, display: display))
                print("")
            }
            let removable = assessments.filter(\.safety.manualAllowed).count
            print("Dry run: nothing was removed. \(removable) of \(assessments.count) can be removed; add --yes to remove them.")
        }
        if failed { throw ExitCode.failure }
    }

    /// Removes one worktree through `Remover` in manual mode; prints what happened.
    private func removeOne(
        _ assessment: WorktreeAssessment,
        remover: Remover,
        known: [Worktree],
        display: PathDisplay
    ) async -> Bool {
        let worktree = assessment.worktree
        let name = display.string(worktree.url)
        if worktree.kind == .claude {
            print("warning: \(SafetyReason.claudeSessionWarning)")
        }
        do {
            let result = try await remover.remove(
                worktree,
                mode: .manual,
                estimatedBytes: assessment.estimatedBytes,
                knownWorktrees: known
            )
            let freed = result.freedBytes.map(ByteFormatting.string) ?? "unknown"
            let estimate = result.entry.estimatedBytes.map { " (estimate \(ByteFormatting.string($0)))" } ?? ""
            let kept = worktree.branch.map { "branch \($0) kept" } ?? "commit \(worktree.head?.prefix(12) ?? "?") kept"
            print("removed \(name): freed \(freed)\(estimate); \(kept); log id \(result.entry.id.uuidString)")
            for note in result.safety.notes where note != .claudeSession {
                print("  note: \(note.sentence)")
            }
            for warning in result.warnings {
                StandardError.write("warning: \(warning)")
            }
            return result.logged
        } catch {
            StandardError.write("error: \(name): \(error)")
            return false
        }
    }
}
