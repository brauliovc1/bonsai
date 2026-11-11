import Foundation

/// A fresh, read-only mount check. Failure is distinct from an empty list.
public struct AttachedImages: Sendable {
    public var paths: @Sendable () async throws -> Set<String>

    public init(_ paths: @escaping @Sendable () async throws -> Set<String>) { self.paths = paths }

    public static func live(runner: CommandRunner = .live) -> Self {
        Self {
            let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"), ["info", "-plist"], timeout: .seconds(60))
            guard result.succeeded else { throw DownloadsError("Could not check attached disk images.") }
            return try parse(result.stdout)
        }
    }

    public static func parse(_ data: Data) throws -> Set<String> {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]]
        else { throw DownloadsError("Could not read attached disk images.") }
        return Set(images.compactMap { $0["image-path"] as? String }.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        })
    }
}

public struct DownloadsError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
