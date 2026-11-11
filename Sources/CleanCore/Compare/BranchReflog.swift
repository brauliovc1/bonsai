import Foundation

/// `log -g --date=raw --format=%H%x00%gD%x00%gs%x00` supplies the reflog timestamp, not the commit date.
enum BranchReflog {
    static let format = "--format=%H%x00%gD%x00%gs%x00"

    static func creation(in data: Data) -> BranchOrigin? {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var found: BranchOrigin?
        var index = 0
        while index + 2 < fields.count {
            let sha = String(decoding: fields[index], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let selector = String(decoding: fields[index + 1], as: UTF8.self)
            let message = String(decoding: fields[index + 2], as: UTF8.self)
            index += 3
            let prefix = "branch: Created from "
            guard CommitSummary.isHash(sha), message.hasPrefix(prefix),
                  let start = selector.range(of: "@{", options: .backwards), selector.hasSuffix("}") else { continue }
            let rawDate = selector[start.upperBound..<selector.index(before: selector.endIndex)]
            guard let first = rawDate.split(whereSeparator: \.isWhitespace).first, let seconds = TimeInterval(first) else { continue }
            let parent = String(message.dropFirst(prefix.count))
            guard !parent.isEmpty else { continue }
            found = BranchOrigin(parent: parent, source: .reflog, date: Date(timeIntervalSince1970: seconds), atSHA: sha,
                                 reason: "The branch's local reflog records its creation.")
        }
        return found
    }
}
