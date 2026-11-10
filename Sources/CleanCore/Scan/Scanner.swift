import Foundation

/// Roots -> repos -> worktrees -> sizes. Read-only: a scan never changes anything on disk.
public struct Scanner: Sendable {
    public var environment: CleanEnvironment
    public var settings: Settings

    public init(environment: CleanEnvironment, settings: Settings = Settings()) {
        self.environment = environment
        self.settings = settings
    }

    /// Scan roots: explicit roots, else `$BONSAI_SCAN_ROOTS` (`EnvironmentName`), else `settings.scanRoots` (only the ones
    /// `ScanRootRule` accepts, canonical), else `~/Documents/GitHub` if it exists.
    public static func resolveRoots(
        explicit: [URL],
        environment: CleanEnvironment,
        settings: Settings = Settings()
    ) -> [URL] {
        if !explicit.isEmpty { return explicit }
        if let override = environment.scanRootsOverride, !override.isEmpty { return override }
        let saved = settings.scanRootURLs(home: environment.homeDirectory)
        if !saved.isEmpty { return saved }
        let defaultRoot = environment.homeDirectory.appending(path: "Documents/GitHub", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: defaultRoot.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return [defaultRoot]
        }
        return []
    }

    /// `includeDependencies` also finds every worktree's light-clean folders and sums their sizes
    /// (`ScanResult.dependencyBytes`); it is slow, so it is off unless asked for. `includeGitDetails` reads
    /// each worktree's last commit and each repo's remotes (`ScanResult.lastCommits`, `.remotes`): one
    /// `git log -1` per distinct HEAD and one `git remote -v` per repo, read-only.
    public func scan(
        roots explicitRoots: [URL] = [],
        includeSizes: Bool = true,
        includeDependencies: Bool = false,
        includeGitDetails: Bool = false,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async -> ScanResult {
        let startedAt = environment.now()
        let clock = ContinuousClock()
        let start = clock.now
        var issues: [ScanIssue] = []

        let roots = Self.resolveRoots(explicit: explicitRoots, environment: environment, settings: settings)
            .map(\.standardized)
        // Saved roots that are refused are skipped; say so whenever the saved list is what decides.
        if explicitRoots.isEmpty, environment.scanRootsOverride?.isEmpty ?? true {
            issues += settings.refusedScanRoots(home: environment.homeDirectory).map {
                ScanIssue(kind: .rootRefused, path: $0.path, message: "scan root skipped: \($0.reason)")
            }
        }
        if roots.isEmpty {
            issues.append(ScanIssue(kind: .noRoots, message: "no scan roots: pass --root or create ~/Documents/GitHub"))
        }

        progress(.discoveringRepos(roots: roots.count))
        let discovery = RepoDiscovery().discover(roots: roots)
        issues += discovery.issues

        var worktrees: [Worktree] = []
        let git = await usableGit(issues: &issues)
        if let git {
            let scanner = WorktreeScanner(git: git, cursorWorktreesDirectory: environment.cursorWorktreesDirectory)
            let listing = await scanner.scan(repos: discovery.repos) { completed, total in
                progress(.listingWorktrees(completed: completed, total: total))
            }
            worktrees = listing.worktrees
            issues += listing.issues
        }

        var lastCommits: [String: CommitSummary]?
        var remotes: [String: [GitRemote]]?
        if includeGitDetails, let git {
            let reader = GitInfoReader(git: git)
            lastCommits = await reader.lastCommits(of: worktrees)
            remotes = await reader.remotes(of: discovery.repos)
        }

        var sizes: [String: Int64] = [:]
        if includeSizes, !worktrees.isEmpty {
            if let du = environment.tools.du {
                let measured = await DirectorySizer(du: du).sizes(of: worktrees.map(\.url)) { completed, total in
                    progress(.measuringSizes(completed: completed, total: total))
                }
                sizes = Self.excludingNestedWorktrees(measured.sizes, worktrees: worktrees)
                issues += measured.issues
            } else {
                issues.append(ScanIssue(kind: .duMissing, message: "/usr/bin/du not found; sizes skipped"))
            }
        }

        var dependencyBytes: [String: Int64]?
        if includeDependencies, let git, !worktrees.isEmpty {
            if let du = environment.tools.du {
                dependencyBytes = await LightCleanFinder(git: git, du: du).dependencyBytes(of: worktrees)
            } else if !issues.contains(where: { $0.kind == .duMissing }) {
                issues.append(ScanIssue(kind: .duMissing, message: "/usr/bin/du not found; dependency sizes skipped"))
            }
        }

        progress(.finished)
        return ScanResult(
            roots: roots.map(\.path),
            repos: discovery.repos.map(\.path),
            worktrees: worktrees,
            sizes: sizes,
            issues: issues,
            startedAt: startedAt,
            duration: start.duration(to: clock.now) / .seconds(1),
            dependencyBytes: dependencyBytes,
            lastCommits: lastCommits,
            remotes: remotes
        )
    }

    /// Git from the environment, if it exists and is at least 2.36; otherwise records why not.
    private func usableGit(issues: inout [ScanIssue]) async -> Git? {
        guard let executable = environment.tools.git else {
            issues.append(ScanIssue(
                kind: .gitMissing,
                message: "git not found (install the Xcode Command Line Tools or Homebrew git)"
            ))
            return nil
        }
        let git = Git(executable: executable, timeout: environment.timeouts.git)
        let version: GitVersion?
        do {
            version = try await git.version(timeout: environment.timeouts.gitVersion)
        } catch {
            issues.append(ScanIssue(kind: .gitMissing, path: executable.path, message: "\(error)"))
            return nil
        }
        guard let version, version.isSupported else {
            let found = version.map { "git \($0)" } ?? "an unknown git version"
            issues.append(ScanIssue(
                kind: .gitUnsupported,
                path: executable.path,
                message: "\(found) is not supported; Bonsai needs git \(GitVersion.minimumSupported) or newer"
            ))
            return nil
        }
        return git
    }

    /// A main checkout's `du` includes linked worktrees nested inside it (`<repo>/.claude/worktrees/...`).
    /// Subtract them so each worktree's bytes are counted once.
    static func excludingNestedWorktrees(_ sizes: [String: Int64], worktrees: [Worktree]) -> [String: Int64] {
        var adjusted = sizes
        for main in worktrees where main.isMain {
            guard let mainSize = sizes[main.path] else { continue }
            let nested = worktrees.filter { worktree in
                !worktree.isMain && CanonicalPath.isInside(worktree.url, directory: main.url)
            }
            let nestedBytes = nested.compactMap { sizes[$0.path] }.reduce(0, +)
            adjusted[main.path] = max(0, mainSize - nestedBytes)
        }
        return adjusted
    }
}
