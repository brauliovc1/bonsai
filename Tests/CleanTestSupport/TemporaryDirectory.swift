import CleanCore
import Foundation

/// A fresh folder under `FileManager.default.temporaryDirectory`, removed by `remove()` or on deinit.
///
/// Keep it alive for the whole test (`defer { directory.remove() }`): ARC may release an object after
/// its last use, before the end of the scope.
public final class TemporaryDirectory: Sendable {
    public let url: URL

    public init(prefix: String = "clean-claude-test") throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        remove()
    }

    /// Deletes the folder. Refuses anything that is not inside the system temporary directory.
    public func remove() {
        guard Self.isDisposable(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// True for paths strictly inside `FileManager.default.temporaryDirectory`: the only place test
    /// helpers may delete anything.
    public static func isDisposable(_ url: URL) -> Bool {
        CanonicalPath.isInside(url, directory: FileManager.default.temporaryDirectory)
    }
}
