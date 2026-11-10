import CleanCore
import Foundation

/// A fresh folder under `FileManager.default.temporaryDirectory`, removed by `remove()` or on deinit.
///
/// Keep it alive for the whole test (`defer { directory.remove() }`): ARC may release an object after
/// its last use, before the end of the scope.
public final class TemporaryDirectory: Sendable {
    public let url: URL
    /// False for a folder adopted with `init(keeping:)`: it outlives this object.
    public let removesOnDeinit: Bool

    public init(prefix: String = "bonsai-test") throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        removesOnDeinit = true
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Adopts `url` (created if missing), which must be inside the system temporary directory. It is not
    /// removed on deinit: `fixture-world` leaves its demo world behind on purpose.
    public init(keeping url: URL) throws {
        guard Self.isDisposable(url) else {
            throw GitFixture.FixtureError(
                description: "\(url.path) is not inside \(FileManager.default.temporaryDirectory.path)"
            )
        }
        self.url = url.standardized
        removesOnDeinit = false
        try FileManager.default.createDirectory(at: self.url, withIntermediateDirectories: true)
    }

    deinit {
        if removesOnDeinit { remove() }
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
