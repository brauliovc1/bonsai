import ArgumentParser
import CleanCore
import Foundation

/// What every command starts from: the live environment, the saved settings and git.
struct CommandContext {
    let environment: CleanEnvironment
    let settings: Settings

    /// Loads the settings; a settings file that exists but can't be read stops the command.
    static func load() throws -> CommandContext {
        let environment = CleanEnvironment.live()
        do {
            let settings = try SettingsStore(environment: environment).load()
            return CommandContext(environment: environment, settings: settings)
        } catch {
            StandardError.write("error: \(error)")
            throw ExitCode.failure
        }
    }

    /// `cleanup.lock` for the whole command when it changes anything (`--yes`), so it never runs together
    /// with the app's cleanups, auto mode or another clean-claude. Refused (exit 1) while someone holds it.
    /// Keep the result alive until the command ends; nil without `--yes`.
    static func holdCleanupLock(if yes: Bool, environment: CleanEnvironment) throws -> FileLock? {
        guard yes else { return nil }
        let lock: FileLock?
        do {
            lock = try CleanupLock.tryAcquire(environment: environment)
        } catch {
            StandardError.write("error: \(error)")
            throw ExitCode.failure
        }
        guard let lock else {
            StandardError.write("error: \(CleanupLock.busyMessage); nothing was changed. Try again when it is done.")
            throw ExitCode.failure
        }
        return lock
    }

    /// git, or a clear error when it is missing.
    func requireGit() throws -> Git {
        guard let git = WorktreeAssessor.git(for: environment) else {
            StandardError.write("error: git not found (install the Xcode Command Line Tools or Homebrew git)")
            throw ExitCode.failure
        }
        return git
    }

    /// Scans, prints every issue as a warning, and exits 1 when no root is an existing folder.
    func scan(_ options: RootOptions, includeSizes: Bool, includeDependencies: Bool = false) async throws -> ScanResult {
        let explicit = options.roots.map { CleanEnvironment.expand($0, home: environment.homeDirectory) }
        let result = await Scanner(environment: environment, settings: settings)
            .scan(roots: explicit, includeSizes: includeSizes, includeDependencies: includeDependencies)
        for issue in result.issues {
            StandardError.write("warning: \(issue)")
        }
        guard result.hasUsableRoot else { throw ExitCode.failure }
        return result
    }

    func assessor(git: Git) -> WorktreeAssessor {
        WorktreeAssessor(git: git, settings: settings, environment: environment)
    }

    /// `du` estimates for a few folders (missing `du` = no estimates).
    func sizes(of worktrees: [Worktree]) async -> [String: Int64] {
        guard let du = environment.tools.du, !worktrees.isEmpty else { return [:] }
        return await DirectorySizer(du: du).sizes(of: worktrees.map(\.url)).sizes
    }

    func paths(for scan: ScanResult) -> PathDisplay {
        PathDisplay(roots: scan.roots.map { URL(fileURLWithPath: $0, isDirectory: true) }, home: environment.homeDirectory)
    }

    /// A path argument made absolute against the current folder, `~` expanded.
    func absoluteURL(_ argument: String) -> URL {
        if argument.hasPrefix("/") || argument.hasPrefix("~") {
            return CleanEnvironment.expand(argument, home: environment.homeDirectory)
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return current.appending(path: argument).standardized
    }
}
