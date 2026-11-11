import Foundation

public struct BranchUpstream: Sendable, Codable, Hashable {
    public let ref: String?
    public let ahead: Int?
    public let behind: Int?
    public let problem: String?
    public init(ref: String?, ahead: Int? = nil, behind: Int? = nil, problem: String? = nil) {
        self.ref = ref; self.ahead = ahead; self.behind = behind; self.problem = problem
    }
    public var summary: String {
        if let problem { return problem }
        guard ref != nil, let ahead else { return "No upstream" }
        let status = ahead == 0 ? "Pushed" : "\(ahead) \(ahead == 1 ? "commit" : "commits") not pushed"
        return status + ((behind ?? 0) > 0 ? " · \(behind!) behind upstream" : "")
    }
}
