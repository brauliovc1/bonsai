/// A folder light clean found by name and left alone.
public struct LightCleanSkip: Sendable, Hashable, Encodable {
    public let relativePath: String
    public let name: String
    public let reason: LightCleanSkipReason

    public init(relativePath: String, name: String, reason: LightCleanSkipReason) {
        self.relativePath = relativePath
        self.name = name
        self.reason = reason
    }
}
