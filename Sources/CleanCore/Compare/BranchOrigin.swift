import Foundation

/// A reflog fact is kept distinct from an inference after that local history expires.
public struct BranchOrigin: Sendable, Codable, Hashable {
    public enum Source: String, Sendable, Codable { case reflog, sharedHistory, unknown }
    public let parent: String?
    public let source: Source
    public let date: Date?
    public let atSHA: String?
    public let reason: String

    public init(parent: String?, source: Source, date: Date? = nil, atSHA: String? = nil, reason: String) {
        self.parent = parent; self.source = source; self.date = date; self.atSHA = atSHA; self.reason = reason
    }
    public var isCertain: Bool { source == .reflog }
}
