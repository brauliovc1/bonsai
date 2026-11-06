import Foundation

/// The main repos found under the scan roots, plus the folders that could not be read.
public struct DiscoveryResult: Sendable {
    /// Main repo folders (with a `.git` directory), sorted by path.
    public var repos: [URL]
    public var issues: [ScanIssue]

    public init(repos: [URL], issues: [ScanIssue]) {
        self.repos = repos
        self.issues = issues
    }
}
