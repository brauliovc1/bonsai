import ArgumentParser

@main
struct BonsaiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bonsai",
        abstract: "Find git worktrees and developer caches, and remove only what is safe to remove.",
        subcommands: [
            ScanCommand.self,
            RemoveCommand.self,
            RestoreCommand.self,
            PruneCommand.self,
            AutoCommand.self,
            LogCommand.self,
            SettingsCommand.self,
            DockerCommand.self,
            SimulatorsCommand.self,
            ClaudeUsageCommand.self,
            LightCleanCommand.self,
            DerivedDataCommand.self,
            ProjectsCommand.self,
            CachesCommand.self,
        ]
    )
}
