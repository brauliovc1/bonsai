/// "How to get them back" for a project's light-clean folders (PLAN §4.5): one line per tool whose file is at
/// the checkout root or next to a folder that will be deleted, and only when a folder that tool brings back is
/// deleted at or below that place (a root `Package.swift` says nothing about a deleted `frontend/node_modules`).
/// A folder no rule knows gets no line. Pure: the caller reads the folders.
public enum RebuildHint {
    /// One tool: the file (or folder) that shows it is used, and the folder names it brings back.
    struct Rule: Sendable {
        var marks: @Sendable (String) -> Bool
        var bringsBack: Set<String>
        var line: String
    }

    static let rules: [Rule] = [
        Rule(marks: { $0 == "package-lock.json" }, bringsBack: ["node_modules"], line: "npm install"),
        Rule(marks: { $0 == "pnpm-lock.yaml" }, bringsBack: ["node_modules"], line: "pnpm install"),
        Rule(marks: { $0 == "yarn.lock" }, bringsBack: ["node_modules"], line: "yarn"),
        Rule(marks: { $0.hasPrefix("next.config.") }, bringsBack: [".next"], line: ".next comes back with next build or next dev"),
        Rule(marks: { $0 == "pubspec.yaml" }, bringsBack: [".dart_tool"], line: "flutter pub get"),
        Rule(marks: { $0 == "Podfile" }, bringsBack: ["Pods"], line: "pod install"),
        Rule(marks: { $0 == "Package.swift" }, bringsBack: [".build"], line: "swift build"),
        Rule(marks: { $0 == ".venv" || $0 == "venv" }, bringsBack: [".venv", "venv"], line: "recreate the virtualenv"),
    ]

    /// The lines for one project, the root's first, then by folder; a folder other than the root is named
    /// ("npm install (in frontend)").
    ///
    /// - Parameters:
    ///   - candidates: relative paths of the folders that will be deleted (`node_modules`, `ios/Pods`).
    ///   - entries: the names in the checkout root (key `""`) and in each candidate's parent folder (key: its
    ///     relative path), files and folders alike.
    public static func lines(candidates: [String], entries: [String: [String]]) -> [String] {
        var lines: [String] = []
        for folder in entries.keys.sorted() {
            let present = entries[folder] ?? []
            let below = candidates.filter { folder.isEmpty || $0.hasPrefix(folder + "/") }
            let names = Set(below.map { $0.split(separator: "/").last.map(String.init) ?? $0 })
            for rule in rules where !rule.bringsBack.isDisjoint(with: names) && present.contains(where: rule.marks) {
                let line = folder.isEmpty ? rule.line : "\(rule.line) (in \(folder))"
                if !lines.contains(line) { lines.append(line) }
            }
        }
        return lines
    }

    /// The folders `lines(candidates:entries:)` looks in: the root and each candidate's parent.
    public static func folders(for candidates: [String]) -> [String] {
        var folders = [""]
        for candidate in candidates {
            let parent = candidate.split(separator: "/").dropLast().joined(separator: "/")
            if !folders.contains(parent) { folders.append(parent) }
        }
        return folders
    }
}
