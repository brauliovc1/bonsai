import Foundation

/// One entry of `xcrun simctl runtime list -j`. Every field but `identifier` is optional: the output
/// differs between Xcode versions and a runtime that is still downloading has no size.
public struct SimulatorRuntime: Sendable, Codable, Hashable, Identifiable {
    /// The key of the entry in simctl's dictionary (a UUID).
    public var identifier: String
    /// `com.apple.CoreSimulator.SimRuntime.iOS-17-5`.
    public var runtimeIdentifier: String?
    public var version: String?
    public var build: String?
    /// `Disk Image`, `Patchable Cryptex Disk Image`, `Bundle`, ...
    public var kind: String?
    /// simctl's `deletable`: whether `simctl runtime delete` would accept it.
    public var deletable: Bool?
    public var lastUsedAt: Date?
    public var sizeBytes: Int64?

    public init(
        identifier: String,
        runtimeIdentifier: String? = nil,
        version: String? = nil,
        build: String? = nil,
        kind: String? = nil,
        deletable: Bool? = nil,
        lastUsedAt: Date? = nil,
        sizeBytes: Int64? = nil
    ) {
        self.identifier = identifier
        self.runtimeIdentifier = runtimeIdentifier
        self.version = version
        self.build = build
        self.kind = kind
        self.deletable = deletable
        self.lastUsedAt = lastUsedAt
        self.sizeBytes = sizeBytes
    }

    public var id: String { identifier }

    /// `iOS 17.5 (21F79)`, with whatever parts are known.
    public var displayName: String {
        var name: String
        if let runtimeIdentifier {
            name = Self.displayName(forRuntimeIdentifier: runtimeIdentifier)
        } else {
            name = "Runtime " + (version ?? identifier)
        }
        if let build { name += " (\(build))" }
        return name
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-17-5` -> `iOS 17.5`; anything else comes back unchanged.
    public static func displayName(forRuntimeIdentifier identifier: String) -> String {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        guard identifier.hasPrefix(prefix) else { return identifier }
        let parts = identifier.dropFirst(prefix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard let platform = parts.first, !platform.isEmpty else { return identifier }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? String(platform) : "\(platform) \(version)"
    }
}
