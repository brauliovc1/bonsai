import ArgumentParser
import CleanCore
import Foundation

struct BranchesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "branches", abstract: "Read branch distances, origins and history without changing the repo.",
        subcommands: [BranchListCommand.self, BranchShowCommand.self], defaultSubcommand: BranchListCommand.self)
}

struct BranchOptions: ParsableArguments {
    @Option(help: "A Git checkout (defaults to the current folder).") var repo: String?
    @Option(help: "The base ref (defaults to origin/HEAD, main or master).") var base: String?
    @Flag(help: "Print structured JSON.") var json = false

    func reader() async throws -> (GitReadOnly, RefCatalog, String) {
        let environment = Launch.environment
        guard let executable = environment.tools.git else { throw ValidationError("Git was not found. Install the Xcode Command Line Tools or Homebrew Git.") }
        let folder = CleanEnvironment.expand(repo ?? FileManager.default.currentDirectoryPath, home: environment.homeDirectory)
        let git = try GitReadOnly(repository: folder, executable: executable, timeout: environment.timeouts.git)
        let catalog = try await RefCatalog.load(using: git)
        return (git, catalog, base ?? catalog.defaultBase ?? "HEAD")
    }
}

struct BranchListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "Show each branch's distance and likely origin.")
    @OptionGroup var options: BranchOptions
    @Flag(name: .customLong("remotes"), help: "Include remote branches.") var includesRemotes = false

    func run() async throws {
        let (git, catalog, base) = try await options.reader()
        let map = try await BranchMap().load(base: base, catalog: catalog, includeRemotes: includesRemotes, using: git)
        let reader = BranchLineageReader(git: git, catalog: catalog)
        let family = try await reader.family(base: base, includeRemotes: includesRemotes)
        let rows = map.entries.map { BranchListRow(entry: $0, origin: family.origins[$0.ref]) }
        if options.json { try BranchCLI.json(BranchListReport(base: map.base, baseSHA: map.baseSHA, branches: rows)) }
        else {
            BranchCLI.line(map.summary)
            for entry in map.entries {
                let counts = entry.metrics.problem ?? "\(entry.metrics.behind ?? 0) behind · \(entry.metrics.ahead ?? 0) ahead"
                let merged = entry.metrics.isMerged ? " · Merged" : ""
                BranchCLI.line("\(entry.name) · \(counts)\(merged)")
                if let origin = family.origins[entry.ref] { BranchCLI.line("  " + BranchCLI.origin(origin)) }
            }
        }
    }
}

struct BranchShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show a branch's origin, fork, merges, family and upstream.")
    @Argument(help: "The branch whose history to inspect.") var branch: String
    @OptionGroup var options: BranchOptions

    func run() async throws {
        let (git, catalog, base) = try await options.reader()
        let history = try await BranchLineageReader(git: git, catalog: catalog).load(branch: branch, base: base)
        if options.json { try BranchCLI.json(history); return }
        BranchCLI.line(BranchCLI.name(history.branch))
        BranchCLI.line(BranchCLI.origin(history.origin))
        if let fork = history.forkPoint { BranchCLI.line("Fork point: \(fork.shortSHA) · \(fork.subject) · \(fork.date.formatted(.iso8601)) (\(history.forkSource.rawValue))") }
        switch history.merged.state {
        case .mergeCommit:
            if let commit = history.merged.commit { BranchCLI.line("Into \(base) on \(commit.date.formatted(.iso8601)) by \(commit.shortSHA) '\(commit.subject)'") }
        case .changesInBase: BranchCLI.line("Its changes are already in \(base) (squashed or rebased); date unknown.")
        case .notMerged: BranchCLI.line("Not merged into \(base).")
        case .unavailable: BranchCLI.line("Can't check the merge: \(history.merged.detail ?? "Git could not read this history.")")
        }
        BranchCLI.line("Parent chain: " + history.parentChain.branches.reversed().map(BranchCLI.name).joined(separator: " → "))
        if let cycle = history.parentChain.cycleAt { BranchCLI.line("Cycle at " + BranchCLI.name(cycle)) }
        if !history.children.isEmpty { BranchCLI.line("Branches cut from it: " + history.children.map(BranchCLI.name).joined(separator: ", ")) }
        BranchCLI.line(history.upstream.summary + (history.upstream.ref.map { " · " + BranchCLI.name($0) } ?? ""))
        if let worktree = history.worktree { BranchCLI.line("Worktree: " + worktree) }
        for problem in history.problems { BranchCLI.line(problem) }
    }
}

private struct BranchListReport: Encodable { let base: String; let baseSHA: String; let branches: [BranchListRow] }
private struct BranchListRow: Encodable {
    let ref: String; let name: String; let sha: String; let kind: BranchMapEntry.Kind; let worktree: String?
    let metrics: BranchMapMetrics; let merged: Bool; let origin: BranchOrigin
    init(entry: BranchMapEntry, origin: BranchOrigin?) {
        ref = entry.ref; name = entry.name; sha = entry.sha; kind = entry.kind; worktree = entry.worktree
        metrics = entry.metrics; merged = entry.metrics.isMerged
        self.origin = origin ?? BranchOrigin(parent: nil, source: .unknown, reason: "No local creation record names this ref.")
    }
}

private enum BranchCLI {
    static func name(_ ref: String) -> String {
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] where ref.hasPrefix(prefix) { return String(ref.dropFirst(prefix.count)) }
        return ref
    }
    static func line(_ text: String) { print(DiffText.decode(Data(text.utf8))) }
    static func origin(_ origin: BranchOrigin) -> String {
        let parent = origin.parent.map(name) ?? "Unknown"
        let fact = origin.source == .reflog ? "Cut from \(parent)" : origin.source == .sharedHistory ? "Probably cut from \(parent)" : "Cut from: unknown"
        return fact + (origin.date.map { " on " + $0.formatted(.iso8601) } ?? "") + " · \(origin.source.rawValue) · \(origin.reason)"
    }
    static func json<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}
