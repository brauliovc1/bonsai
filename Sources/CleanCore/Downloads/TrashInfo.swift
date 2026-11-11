import Foundation

public struct TrashInfo: Sendable, Codable, Hashable {
    public static let unreadableMessage = "Bonsai can't see inside the Trash without Full Disk Access"
    public let bytes: Int64?
    public let count: Int?
    public var readable: Bool { bytes != nil && count != nil }

    public init(bytes: Int64?, count: Int?) { self.bytes = bytes; self.count = count }

    public static func read(home: URL, runner: CommandRunner = .live,
                            itemCount: @Sendable (URL) throws -> Int = { url in
                                try FileManager.default.contentsOfDirectory(atPath: url.path).count
                            }) async -> Self {
        let directory = home.resolvingSymlinksInPath().appending(path: ".Trash")
        guard let kind = DirectoryEntries.kind(ofItemAt: directory.path) else {
            return errno == ENOENT ? Self(bytes: 0, count: 0) : Self(bytes: nil, count: nil)
        }
        guard kind == .directory else { return Self(bytes: nil, count: nil) }
        do {
            let count = try itemCount(directory)
            if count == 0 { return Self(bytes: 0, count: 0) }
            let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/du"), ["-skx", directory.path], timeout: .seconds(300))
            guard result.succeeded, let kilobytes = DirectorySizer.parseKilobytes(result.stdout) else {
                return Self(bytes: nil, count: nil)
            }
            return Self(bytes: kilobytes * 1024, count: count)
        } catch { return Self(bytes: nil, count: nil) }
    }
}
