import CleanCore
import Foundation

/// A fake home folder in the temporary directory, with helpers to fill it with files of known size.
/// Keep it alive for the whole test (`defer { home.remove() }`).
public final class FakeHome: Sendable {
    private let directory: TemporaryDirectory

    public init() throws {
        directory = try TemporaryDirectory(prefix: "clean-claude-home")
    }

    public var url: URL { directory.url }

    public func remove() {
        directory.remove()
    }

    /// An environment whose home, Claude folders and settings all live inside this fake home. `du` is the
    /// real one (it only reads the fake folders); docker and xcrun are whatever the test passes, usually
    /// paths that do not exist.
    public func environment(
        docker: URL? = nil,
        xcrun: URL? = nil,
        developerToolsInstalled: Bool = false,
        du: URL? = URL(fileURLWithPath: "/usr/bin/du")
    ) -> CleanEnvironment {
        CleanEnvironment.make(
            homeDirectory: url,
            variables: [:],
            tools: ToolPaths(
                du: du,
                xcrun: xcrun,
                docker: docker,
                developerToolsInstalled: developerToolsInstalled
            )
        )
    }

    /// A folder (and its parents) at a path relative to the fake home.
    @discardableResult
    public func addFolder(_ relativePath: String) throws -> URL {
        let folder = url.appending(path: relativePath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A file of `kibibytes` KiB of zeros. Multiples of 4 KiB are what `du` reports back exactly on APFS.
    @discardableResult
    public func addFile(_ relativePath: String, kibibytes: Int) throws -> URL {
        let file = url.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: kibibytes * 1024).write(to: file)
        return file
    }
}
