/// What the Deps column knows about one worktree: the size of the folders light clean could delete in it.
public enum DependencySize: Sendable, Hashable {
    case notMeasured
    case measuring
    /// nil: nothing to clean there, or it could not be measured.
    case measured(Int64?)

    public var bytes: Int64? {
        if case .measured(let bytes) = self { return bytes }
        return nil
    }

    public var isMeasuring: Bool { self == .measuring }
}
