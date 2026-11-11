import Foundation

/// The identity confirmed by the user, retained across the move to Trash.
public struct DownloadIdentity: Sendable, Codable, Hashable {
    public let resourceIdentifier: Data
    public let device: Int32
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int
    public let modifiedNanoseconds: Int

    static func read(_ url: URL) -> Self? {
        guard DirectoryEntries.kind(ofItemAt: url.path) == .other,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileResourceIdentifierKey]),
              values.isRegularFile == true, let resource = values.fileResourceIdentifier,
              let stamp = FileStamp.of(url.path)
        else { return nil }
        let identifier: Data
        if let data = resource as? Data { identifier = data }
        else if let data = try? NSKeyedArchiver.archivedData(withRootObject: resource, requiringSecureCoding: false) {
            identifier = data
        } else { return nil }
        return Self(resourceIdentifier: identifier, device: stamp.device, inode: stamp.inode, size: stamp.size,
                    modifiedSeconds: stamp.modifiedSeconds, modifiedNanoseconds: stamp.modifiedNanoseconds)
    }
}

public struct DownloadFile: Sendable, Codable, Hashable, Identifiable {
    public var id: String { path }
    public let path: String
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var bytes: Int64 { identity.size }
    public let addedAt: Date
    public let identity: DownloadIdentity
    public let skipReason: String?
    public var canMove: Bool { skipReason == nil }
}

public struct DownloadsReport: Sendable, Codable, Hashable {
    public let files: [DownloadFile]
    public let warnings: [String]
    public var eligible: [DownloadFile] { files.filter(\.canMove) }
    public var bytes: Int64 { eligible.reduce(0) { $0 + $1.bytes } }
}
