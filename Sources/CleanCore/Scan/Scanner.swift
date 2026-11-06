import Foundation

/// Roots -> repos -> worktrees -> sizes. Read-only: a scan never changes anything on disk.
public struct Scanner: Sendable {
    public var environment: CleanEnvironment

    public init(environment: CleanEnvironment) {
        self.environment = environment
    }

    /// Scan roots: explicit roots, else `$CLEAN_CLAUDE_SCAN_ROOTS`, else `~/Documents/GitHub` if it exists.
    public static func resolveRoots(explicit: [URL], environment: CleanEnvironment) -> [URL] {
        if !explicit.isEmpty { return explicit }
        if let override = environment.scanRootsOverride, !override.isEmpty { return override }
        let defaultRoot = environment.homeDirectory.appending(path: "Documents/GitHub", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: defaultRoot.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return [defaultRoot]
        }
        return []
    }

    public func scan(
        roots explicitRoots: [URL] = [],
        includeSizes: Bool = true,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async -> ScanResult {
        let startedAt = environment.now()
        let clock = ContinuousClock()
        let start = clock.now
        var issues: [ScanIssue] = []

        let roots = Self.resolveRoots(explicit: explicitRoots, environment: environment).map(\.standardized)
        if roots.isEmpty {
            issues.append(ScanIssue(kind: .noRoots, message: "no scan roots: pass --root or create ~/Documents/GitHub"))
        }

        progress(.discoveringRepos(roots: roots.count))
        let discovery = RepoDiscovery().discover(roots: roots)
        issues += discovery.issues

        var worktrees: [Worktree] = []
        if let git = await usableGit(issues: &issues) {
            let scanner = WorktreeScanner(git: git, cursorWorktreesDirectory: environment.cursorWorktreesDirectory)
            let listing = await scanner.scan(repos: discovery.repos) { completed, total in
                progress(.listingWorktrees(completed: completed, total: total))
            }
            worktrees = listing.worktrees
            issues += listing.issues
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

        progress(.finished)
        return ScanResult(
            roots: roots.map(\.path),
            repos: discovery.repos.map(\.path),
            worktrees: worktrees,
            sizes: sizes,
            issues: issues,
            startedAt: startedAt,
            duration: start.duration(to: clock.now) / .seconds(1)
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
        let git = Git(executable: executable)
        let version: GitVersion?
        do {
            version = try await git.version()
        } catch {
            issues.append(ScanIssue(kind: .gitMissing, path: executable.path, message: "\(error)"))
            return nil
        }
        guard let version, version.isSupported else {
            let found = version.map { "git \($0)" } ?? "an unknown git version"
            issues.append(ScanIssue(
                kind: .gitUnsupported,
                path: executable.path,
                message: "\(found) is not supported; clean-claude needs git \(GitVersion.minimumSupported) or newer"
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
