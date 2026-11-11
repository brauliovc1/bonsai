import Foundation

public struct QuickCleanItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let path: String?
    public let paths: [String]
    public let estimatedBytes: Int64?

    public init(id: String, title: String, detail: String, path: String? = nil,
                paths: [String] = [], estimatedBytes: Int64? = nil) {
        self.id = id; self.title = title; self.detail = detail
        self.paths = paths.isEmpty ? path.map { [$0] } ?? [] : paths
        self.path = path ?? (self.paths.count == 1 ? self.paths.first : nil)
        self.estimatedBytes = estimatedBytes
    }
}

public struct QuickCleanGroup: Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case worktrees, projects, toolCaches, derivedData, docker, simulators, downloads }
    public let id: Kind
    public let title: String
    public let detail: String
    public let items: [QuickCleanItem]
    public var estimatedBytes: Int64 { items.compactMap(\.estimatedBytes).reduce(0, +) }
    public var unknownSizeCount: Int { items.count { $0.estimatedBytes == nil } }

    public init(id: Kind, title: String, detail: String, items: [QuickCleanItem]) {
        self.id = id; self.title = title; self.detail = detail; self.items = items
    }
}

/// A display value, never an executable cleanup plan. Downloads do not count as freed space.
public struct QuickCleanPreview: Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let groups: [QuickCleanGroup]
    public let warnings: [String]
    public var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }
    public var estimatedBytes: Int64 { groups.filter { $0.id != .downloads }.reduce(0) { $0 + $1.estimatedBytes } }
    public var unknownSizeCount: Int { groups.filter { $0.id != .downloads }.reduce(0) { $0 + $1.unknownSizeCount } }
    public var moveBytes: Int64 { groups.filter { $0.id == .downloads }.reduce(0) { $0 + $1.estimatedBytes } }
    public var unknownMoveSizeCount: Int { groups.filter { $0.id == .downloads }.reduce(0) { $0 + $1.unknownSizeCount } }

    public init(id: UUID = UUID(), createdAt: Date, groups: [QuickCleanGroup], warnings: [String] = []) {
        self.id = id; self.createdAt = createdAt; self.groups = groups; self.warnings = warnings
    }
}
