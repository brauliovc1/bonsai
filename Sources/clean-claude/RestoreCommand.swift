import ArgumentParser
import CleanCore
import Foundation

struct RestoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Put a removed worktree back from its kept branch (or commit). Dependencies are not reinstalled.",
        discussion: "Without --yes this is a dry run that checks everything and prints the git command."
    )

    @Argument(help: ArgumentHelp("The log entry id (from `clean-claude log`); a unique prefix is enough.", valueName: "id"))
    var id: String

    @Flag(help: "Restore for real. Without it nothing is changed.")
    var yes = false

    func run() async throws {
        let context = try CommandContext.load()
        let lock = try CommandContext.holdCleanupLock(if: yes, environment: context.environment)
        defer { lock?.release() }
        let git = try context.requireGit()
        let restorer = Restorer(git: git, environment: context.environment)
        let entryID = try resolve(id, in: restorer.log)
        let home = context.environment.homeDirectory
        let display = PathDisplay(roots: [], home: home)

        do {
            if yes {
                let result = try await restorer.restore(entryID: entryID)
                print("restored \(display.string(result.path)) at \(result.ref)")
                print(result.note)
                for warning in result.warnings {
                    StandardError.write("warning: \(warning)")
                }
            } else {
                let plan = try await restorer.plan(entryID: entryID)
                let arguments = plan.arguments.map(VerdictText.quoted).joined(separator: " ")
                print("would run: git -C \(VerdictText.quoted(plan.entry.repoPath)) \(arguments)")
                if plan.entry.action == .worktreeRemoveAnyway { print(Restorer.lostFilesNote) }
                print(Restorer.dependenciesNote)
                print("Dry run: nothing was changed. Add --yes to restore.")
            }
        } catch {
            StandardError.write("error: \(error)")
            throw ExitCode.failure
        }
    }

    /// A full UUID or a unique, case-insensitive prefix of one.
    private func resolve(_ text: String, in log: RemovalLog) throws -> UUID {
        if let uuid = UUID(uuidString: text) { return uuid }
        let entries: [RemovalLogEntry]
        do {
            entries = try log.entries()
        } catch {
            StandardError.write("error: cannot read \(log.fileURL.path): \(error)")
            throw ExitCode.failure
        }
        let prefix = text.lowercased()
        let matches = Set(entries.map(\.id).filter { $0.uuidString.lowercased().hasPrefix(prefix) })
        guard !prefix.isEmpty, matches.count == 1, let match = matches.first else {
            let problem = matches.isEmpty ? "no log entry starts with" : "more than one log entry starts with"
            StandardError.write("error: \(problem) \(text)")
            throw ExitCode.failure
        }
        return match
    }
}
