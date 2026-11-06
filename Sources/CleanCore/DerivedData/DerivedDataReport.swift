/// Everything `DerivedDataScanner` found.
public struct DerivedDataReport: Sendable, Hashable, Encodable {
    /// The DerivedData root that was listed.
    public var root: String
    /// False when the root does not exist (Xcode never built anything, or a custom location is gone).
    public var rootExists: Bool
    /// Why the root was not listed (it is `/`, the home folder, a folder above it, or not a folder): an
    /// error to show. nil normally.
    public var refusal: String?
    /// Every folder in the root (symlinks and files are left out), sorted by name.
    public var entries: [DerivedDataEntry]
    public var warnings: [String]

    public init(
        root: String,
        rootExists: Bool,
        refusal: String? = nil,
        entries: [DerivedDataEntry] = [],
        warnings: [String] = []
    ) {
        self.root = root
        self.rootExists = rootExists
        self.refusal = refusal
        self.entries = entries
        self.warnings = warnings
    }

    /// What `DerivedDataCleaner.delete` may be given.
    public var orphans: [OrphanedDerivedData] {
        entries.compactMap(\.orphan)
    }

    public var totalBytes: Int64 {
        entries.compactMap(\.bytes).reduce(0, +)
    }

    public func entries(in state: DerivedDataState) -> [DerivedDataEntry] {
        entries.filter { $0.state == state }
    }

    public func bytes(in state: DerivedDataState) -> Int64 {
        entries(in: state).compactMap(\.bytes).reduce(0, +)
    }
}
