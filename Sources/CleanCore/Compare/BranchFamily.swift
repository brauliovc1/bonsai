import Foundation

public struct BranchFamily: Sendable {
    public struct Chain: Sendable, Codable, Hashable {
        /// Starts with the selected branch, followed by its parents.
        public let branches: [String]
        /// The closing edge is reported rather than followed forever.
        public let cycleAt: String?
    }
    public let origins: [String: BranchOrigin]
    public init(origins: [String: BranchOrigin]) { self.origins = origins }

    public func children(of branch: String) -> [String] {
        origins.filter { $0.value.parent == branch }.map(\.key).sorted()
    }

    public func chain(from branch: String, through base: String) -> Chain {
        var branches: [String] = []
        var seen: Set<String> = []
        var next: String? = branch
        while let current = next {
            guard seen.insert(current).inserted else { return Chain(branches: branches, cycleAt: current) }
            branches.append(current)
            if current == base { break }
            next = origins[current]?.parent
        }
        return Chain(branches: branches, cycleAt: nil)
    }
}
