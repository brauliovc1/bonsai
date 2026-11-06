import ArgumentParser

@main
struct CleanClaudeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean-claude",
        abstract: "Find git worktrees and developer caches, and remove only what is safe to remove.",
        subcommands: [
            ScanCommand.self,
            RemoveCommand.self,
            RestoreCommand.self,
            PruneCommand.self,
            AutoCommand.self,
            LogCommand.self,
            SettingsCommand.self,
        ]
    )
}
