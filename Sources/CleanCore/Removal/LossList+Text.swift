/// The loss list in words: what differs from a confirmed one, the one-line summary and the log's notes.
extension LossList {
    /// Entries kept in the log's notes; the rest are counted ("and N more").
    public static let logEntryCap = 200

    /// What differs from `confirmed`, one sentence per category; empty when every entry is the same (its
    /// text, detail, status letters or sha, and the path's stamp).
    public func changes(since confirmed: LossList) -> [String] {
        var changes: [String] = []
        for category in Category.allCases {
            let now = entries(category)
            let then = confirmed.entries(category)
            guard now != then else { continue }
            if then.isEmpty {
                changes.append("New: \(category.title.lowercased()) (\(Self.list(now.map(\.text)))).")
                continue
            }
            if now.isEmpty {
                changes.append("No longer any \(category.title.lowercased()).")
                continue
            }
            let before = Dictionary(then.map { ($0.text, $0) }, uniquingKeysWith: { first, _ in first })
            let after = Dictionary(now.map { ($0.text, $0) }, uniquingKeysWith: { first, _ in first })
            let added = now.map(\.text).filter { before[$0] == nil }
            let gone = then.map(\.text).filter { after[$0] == nil }
            let changed = now.map(\.text).filter { before[$0] != nil && before[$0] != after[$0] }
            var parts: [String] = []
            if !added.isEmpty { parts.append("new: " + Self.list(added)) }
            if !changed.isEmpty { parts.append("changed: " + Self.list(changed)) }
            if !gone.isEmpty { parts.append("gone: " + Self.list(gone)) }
            if parts.isEmpty { parts.append("listed in another order") }
            changes.append("\(category.title): \(parts.joined(separator: "; ")).")
        }
        return changes
    }

    /// "Lost: 3 uncommitted files, 1 repo with local work." (or "Nothing listed was lost.").
    public var summary: String {
        let lost = lostSections.map { $0.category.counted($0.entries.count) }
        return lost.isEmpty ? "Nothing listed was lost." : "Lost: " + lost.joined(separator: ", ") + "."
    }

    /// For `RemovalLogEntry.notes`: the summary, then each category with its count and entries, at most
    /// `logEntryCap` entries in all, then "and N more".
    public var logNotes: [String] {
        var notes = [summary]
        var written = 0
        for section in sections {
            notes.append("\(section.category.title) (\(section.entries.count)):")
            for entry in section.entries {
                guard written < Self.logEntryCap else { break }
                notes.append("  " + entry.text + (entry.detail.map { " (\($0))" } ?? ""))
                written += 1
            }
        }
        if entryCount > written { notes.append("and \(entryCount - written) more") }
        return notes
    }

    /// Up to five items, then "and N more".
    private static func list(_ items: [String]) -> String {
        items.prefix(5).joined(separator: ", ") + (items.count > 5 ? " and \(items.count - 5) more" : "")
    }
}
