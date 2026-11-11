import Foundation

/// Only tracking names/refspecs cross the isolated Git boundary. URLs, includes and command keys do not.
enum BranchTrackingConfig {
    struct Entry: Equatable { let section: String; let subsection: String?; let key: String; let value: String }

    static func sanitized(common: URL, worktree: URL) -> String {
        entries(common: common, worktree: worktree).compactMap { entry in
            guard let subsection = entry.subsection,
                  (entry.section == "branch" && ["remote", "merge"].contains(entry.key))
                    || (entry.section == "remote" && entry.key == "fetch") else { return nil }
            return "[\(entry.section) \"\(escaped(subsection))\"]\n\(entry.key) = \"\(escaped(entry.value))\"\n"
        }.joined()
    }

    static func hasIncludes(common: URL, worktree: URL) -> Bool {
        entries(common: common, worktree: worktree).contains { ($0.section == "include" || $0.section == "includeif") && $0.key == "path" }
    }

    private static func entries(common: URL, worktree: URL) -> [Entry] {
        let base = parse((try? String(contentsOf: common.appending(path: "config"), encoding: .utf8)) ?? "")
        let enabled = base.last { $0.section == "extensions" && $0.key == "worktreeconfig" }?.value.lowercased()
        guard ["true", "yes", "on", "1"].contains(enabled ?? "") else { return base }
        return base + parse((try? String(contentsOf: worktree.appending(path: "config.worktree"), encoding: .utf8)) ?? "")
    }

    static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        var section: (String, String?)?
        var carried = ""
        var lines: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = withoutComment(String(raw))
            carried += line
            if line.reversed().prefix(while: { $0 == "\\" }).count % 2 == 1 {
                carried.removeLast()
            } else { lines.append(carried); carried = "" }
        }
        if !carried.isEmpty { lines.append(carried) }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = header(line); continue }
            guard let section else { continue }
            let key = String(line.prefix { $0.isLetter || $0.isNumber || $0 == "-" }).lowercased()
            guard !key.isEmpty else { continue }
            var rest = String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("=") { rest.removeFirst() }
            guard let value = decoded(rest.trimmingCharacters(in: .whitespaces)) else { continue }
            entries.append(Entry(section: section.0, subsection: section.1, key: key, value: value))
        }
        return entries
    }

    private static func header(_ line: String) -> (String, String?)? {
        var quoted = false, escaped = false
        var end: String.Index?
        for index in line.indices.dropFirst() {
            let character = line[index]
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "\"" { quoted.toggle() }
            if character == "]" && !quoted { end = index; break }
        }
        guard let end else { return nil }
        let content = String(line[line.index(after: line.startIndex)..<end]).trimmingCharacters(in: .whitespaces)
        let group = String(content.prefix { $0.isLetter || $0.isNumber || $0 == "-" }).lowercased()
        guard !group.isEmpty else { return nil }
        let suffix = String(content.dropFirst(group.count)).trimmingCharacters(in: .whitespaces)
        if suffix.isEmpty { return (group, nil) }
        if suffix.hasPrefix(".") { return (group, String(suffix.dropFirst()).lowercased()) }
        guard suffix.hasPrefix("\""), suffix.hasSuffix("\""), let name = decoded(suffix) else { return nil }
        return (group, name)
    }

    private static func withoutComment(_ line: String) -> String {
        var result = "", quoted = false, escaped = false
        for character in line {
            if escaped { result.append(character); escaped = false; continue }
            if character == "\\" { result.append(character); escaped = true; continue }
            if character == "\"" { quoted.toggle() }
            if !quoted && (character == "#" || character == ";") { break }
            result.append(character)
        }
        return result
    }

    private static func decoded(_ text: String) -> String? {
        var result = "", quoted = false, escaped = false
        for character in text {
            if escaped {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "b": result.append("\u{8}")
                case "\\", "\"": result.append(character)
                default: return nil
                }
                escaped = false; continue
            }
            if character == "\\" { escaped = true }
            else if character == "\"" { quoted.toggle() }
            else { result.append(character) }
        }
        return quoted || escaped ? nil : result
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\u{8}", with: "\\b")
    }
}
