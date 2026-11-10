import Foundation

/// How long the tools Bonsai finds through `CleanEnvironment` get before they are stopped. The app and the CLI use
/// these defaults; tests give the code under test minutes instead, so a crowded test machine can't turn a slow
/// answer into a wrong one.
public struct ToolTimeouts: Sendable, Equatable {
    /// Every git command of a scan, an assessment or a cleanup, except `--version`.
    public var git: Duration
    /// `git --version`, the scan's first call.
    public var gitVersion: Duration
    /// `lsof -d cwd`, once per scan or check.
    public var lsof: Duration

    public init(git: Duration = .seconds(60), gitVersion: Duration = .seconds(10), lsof: Duration = .seconds(30)) {
        self.git = git
        self.gitVersion = gitVersion
        self.lsof = lsof
    }
}
