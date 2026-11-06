import Foundation

/// The fixed absolute locations each external tool is looked up in, in order (PLAN §3 "Running tools").
///
/// A GUI app launched from Finder gets a minimal `PATH`, so tools are never looked up through `PATH`.
public struct ToolCandidates: Sendable, Equatable {
    public var git: [URL]
    public var du: [URL]
    public var lsof: [URL]
    public var xcrun: [URL]
    public var defaults: [URL]
    public var docker: [URL]
    /// Shims that pop the Command Line Tools installer when the developer tools are missing. They are
    /// only used when `xcode-select -p` succeeds.
    public var requiringDeveloperTools: Set<URL>

    public init(
        git: [URL],
        du: [URL],
        lsof: [URL],
        xcrun: [URL],
        defaults: [URL],
        docker: [URL],
        requiringDeveloperTools: Set<URL>
    ) {
        self.git = git
        self.du = du
        self.lsof = lsof
        self.xcrun = xcrun
        self.defaults = defaults
        self.docker = docker
        self.requiringDeveloperTools = requiringDeveloperTools
    }

    public static let standard = ToolCandidates(
        git: paths("/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"),
        du: paths("/usr/bin/du"),
        lsof: paths("/usr/sbin/lsof"),
        xcrun: paths("/usr/bin/xcrun"),
        defaults: paths("/usr/bin/defaults"),
        docker: paths(
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ),
        requiringDeveloperTools: Set(paths("/usr/bin/git", "/usr/bin/xcrun"))
    )

    private static func paths(_ paths: String...) -> [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }
}
