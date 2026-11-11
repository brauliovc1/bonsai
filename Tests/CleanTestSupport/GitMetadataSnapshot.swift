import Foundation

/// Byte-for-byte snapshot, including refs, logs, config, index and all loose/packed objects.
public struct GitMetadataSnapshot: Equatable, Sendable {
    public let files: [String: Data]
    public init(directory: URL) throws {
        var files: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            self.files = [:]; return
        }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true || values.isSymbolicLink == true {
                files[String(file.path.dropFirst(directory.path.count + 1))] = try Data(contentsOf: file)
            }
        }
        self.files = files
    }
}
