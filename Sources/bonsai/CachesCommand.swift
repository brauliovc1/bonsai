import ArgumentParser
import CleanCore
import Foundation

struct CachesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "caches",
        abstract: "List package-manager caches and Cursor's data with their sizes; clean the ones you name.",
        discussion: "Only the folders in the built-in catalog are ever touched, only while the tool that owns them is "
            + "not running, and never through a symbolic link. Cursor's state.vscdb (your chats), snapshots, "
            + "workspaceStorage and ~/.cursor are shown, never cleaned.",
        subcommands: [CachesListCommand.self, CachesCleanCommand.self],
        defaultSubcommand: CachesListCommand.self
    )
}

/// The options every `caches` subcommand shares.
struct CachesOptions: ParsableArguments {
    @Option(name: .customLong("home"), help: ArgumentHelp("For tests: a fake home folder inside the temp folder.", visibility: .private))
    var home: String?

    func validate() throws {
        guard let home else { return }
        let url = URL(fileURLWithPath: home).standardized
        guard CanonicalPath.isInside(url, directory: FileManager.default.temporaryDirectory) else {
            throw ValidationError("--home is for tests and must be inside \(FileManager.default.temporaryDirectory.path)")
        }
    }

    /// The live environment, or one whose home is the test folder (settings still follow
    /// `BONSAI_SETTINGS_DIR`).
    func environment() throws -> CleanEnvironment {
        guard let home else { return try CommandContext.load().environment }
        let environment = CleanEnvironment.make(
            homeDirectory: URL(fileURLWithPath: home, isDirectory: true),
            variables: ProcessInfo.processInfo.environment,
            tools: .resolve()
        )
        do {
            _ = try SettingsStore(environment: environment).load()
        } catch {
            StandardError.write("error: \(error)")
            throw ExitCode.failure
        }
        return environment
    }

    /// Scans and prints the scan's warnings.
    func scan(_ environment: CleanEnvironment) async -> ToolCacheReport {
        let report = await ToolCacheScanner(environment: environment).scan()
        for warning in report.warnings {
            StandardError.write("warning: \(warning)")
        }
        return report
    }
}

struct CachesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Every catalog entry on this Mac with its size and whether it can be cleaned now. Read-only."
    )

    @OptionGroup var options: CachesOptions

    @Flag(help: "Print the report as JSON.")
    var json = false

    func run() async throws {
        let environment = try options.environment()
        let report = await options.scan(environment)
        if json {
            print(String(decoding: try CleanJSON.encoder().encode(report), as: UTF8.self))
        } else {
            print(CachesText(report: report, home: environment.homeDirectory).render())
        }
    }
}

struct CachesCleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Clean the named entries. Without --yes it only prints what would be cleaned.",
        discussion: "Entry ids: " + ToolCacheCatalog.cleanableIDs.joined(separator: ", ") + ". Each entry is checked "
            + "again right before it is cleaned (its tool must not be running, no symbolic link on the way), its "
            + "folder is kept, and each cleaned entry is logged."
    )

    @OptionGroup var options: CachesOptions

    @Argument(help: ArgumentHelp("The entries to clean.", valueName: "entry-id"))
    var ids: [String]

    @Flag(help: "Really clean them.")
    var yes = false

    func validate() throws {
        guard !ids.isEmpty else { throw ValidationError("Name at least one entry: " + ToolCacheCatalog.cleanableIDs.joined(separator: ", ")) }
        for id in ids {
            guard let entry = ToolCacheCatalog.entry(id: id) else {
                throw ValidationError("\(id) is not an entry. Entries: " + ToolCacheCatalog.cleanableIDs.joined(separator: ", "))
            }
            guard entry.isCleanable else { throw ValidationError("\(id) is shown only; it is never cleaned.") }
        }
    }

    func run() async throws {
        let environment = try options.environment()
        let lock = try CommandContext.holdCleanupLock(if: yes, environment: environment)
        defer { lock?.release() }
        let report = await options.scan(environment)
        let text = CachesText(report: report, home: environment.homeDirectory)
        var chosen: [ToolCacheFinding] = []
        var leftAlone = false
        var seen = Set<String>()
        for id in ids where seen.insert(id).inserted {
            guard let finding = report.finding(id: id) else {
                print("\(id): not on this Mac (nothing at " + (ToolCacheCatalog.entry(id: id)?.paths.map { "~/" + $0 }.joined(separator: ", ") ?? "?") + ")")
                continue
            }
            print(text.plan(finding))
            if finding.isReady { chosen.append(finding) } else { leftAlone = true }
        }
        guard yes else {
            print("")
            print(chosen.isEmpty ? "Nothing to clean." : "Would clean \(chosen.count) \(chosen.count == 1 ? "entry" : "entries"), "
                + "about \(ByteFormatting.string(chosen.compactMap(\.bytes).reduce(0, +))) (estimate).")
            print("Nothing was changed. Add --yes to clean them.")
            return
        }
        guard !chosen.isEmpty else {
            print("Nothing was cleaned.")
            throw ExitCode.failure
        }
        let result = await ToolCacheCleaner(environment: environment).clean(chosen)
        print("")
        print(CachesText.result(result, home: environment.homeDirectory))
        for warning in result.warnings {
            StandardError.write("warning: \(warning)")
        }
        if leftAlone || !result.refused.isEmpty || result.failedCount > 0 || !result.logged { throw ExitCode.failure }
    }
}
