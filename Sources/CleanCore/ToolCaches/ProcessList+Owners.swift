import Foundation

extension ProcessList {
    /// The names of `owners` running now, in their order, then every other process whose command line names
    /// one of `paths` (a browser Playwright installed, a mongod from the test-binary cache, a cursor-agent
    /// version): a program running from a cache is using it. nil when the list couldn't be read.
    ///
    /// This process and any clean-claude (also under `sudo` or `env`) never count: their own command line names
    /// the entries (`caches clean cursor-agent-versions`). Nor does `du` for `paths`: it only reads, and the
    /// scanner runs it.
    public func runningOwners(_ owners: [ToolOwner], mentioning paths: [String]) -> [String]? {
        guard failure == nil else { return nil }
        let facts = otherFacts
        var names: [String] = []
        for owner in owners where !names.contains(owner.name) {
            if owner.rules.contains(where: { matches($0, facts) }) { names.append(owner.name) }
        }
        let needles = paths.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !needles.isEmpty else { return names }
        for fact in facts where !fact.names.contains("du") {
            guard needles.contains(where: fact.line.contains) else { continue }
            let name = fact.process.displayName
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// The Cursor app runs (by ps, or NSWorkspace in the app). Without a process list, only NSWorkspace counts.
    public var isCursorRunning: Bool {
        failure == nil ? matches(.cursorApp, otherFacts) : cursorAppRunning
    }

    /// Every process but this one and clean-claude's own.
    private var otherFacts: [Facts] {
        let ownPID = getpid()
        return processes.map(Facts.init).filter { $0.process.pid != ownPID && !$0.names.contains("clean-claude") }
    }

    /// What the rules look at in one process, worked out once per check.
    struct Facts {
        let process: Process
        let names: Set<String>
        /// The command line in lower case.
        let line: String
        /// The file names of the command-line words, in lower case.
        let wordNames: Set<String>

        init(_ process: Process) {
            self.process = process
            names = process.commandNames
            line = process.arguments.lowercased()
            wordNames = Set(process.words.map { Process.fileName(of: $0).lowercased() })
        }
    }

    /// True when some process satisfies `rule`.
    func matches(_ rule: ToolOwner.Rule, _ facts: [Facts]) -> Bool {
        switch rule {
        case .command(let wanted):
            let lowered = Set(wanted.map { $0.lowercased() })
            return facts.contains { !$0.names.isDisjoint(with: lowered) }
        case .argumentName(let wanted):
            let lowered = Set(wanted.map { $0.lowercased() })
            return facts.contains { !$0.wordNames.isDisjoint(with: lowered) }
        case .argumentContains(let text):
            let needle = text.lowercased()
            return facts.contains { $0.line.contains(needle) }
        case .cursorApp:
            return cursorAppRunning || facts.contains { fact in
                fact.line.contains("/cursor.app/contents/") || fact.process.command.lowercased().contains("/cursor.app/contents/")
            }
        }
    }
}

extension ProcessList.Process {
    /// Programs that run another one named by their first plain argument: interpreters and wrappers.
    static let launchers: Set<String> = [
        "node", "nodejs", "bun", "deno", "python", "pythonw", "ruby", "perl", "bash", "sh", "zsh", "dash", "ksh",
        "fish", "env", "arch", "sudo", "nice", "nohup", "time", "caffeinate", "xcrun",
    ]

    /// The command line split on spaces.
    var words: [Substring] {
        arguments.split(separator: " ", omittingEmptySubsequences: true)
    }

    /// The names this process runs as, in lower case with version-less variants: the file name of `comm` when
    /// ps didn't cut it, of the first command-line word, and, after an interpreter or wrapper, of the next plain
    /// words (`node /opt/homebrew/bin/npm install` is npm, `python3 -m pip` is pip, `sudo brew` is brew).
    var commandNames: Set<String> {
        var names = Set<String>()
        var launcher = false
        if !command.isEmpty, command.count < ProcessList.commandWidth {
            // A title a program set itself ("npm install") names it by its first word.
            let name = command.hasPrefix("/") ? Substring(command) : command.split(separator: " ").first ?? ""
            let variants = Self.variants(of: Self.fileName(of: name))
            names.formUnion(variants)
            launcher = !Self.launchers.isDisjoint(with: variants)
        }
        let words = words
        guard let first = words.first else { return names }
        let firstVariants = Self.variants(of: Self.fileName(of: first))
        names.formUnion(firstVariants)
        launcher = launcher || !Self.launchers.isDisjoint(with: firstVariants)
        var budget = launcher ? 2 : 0
        var index = 1
        while budget > 0, index < words.count {
            let word = words[index]
            index += 1
            if word.hasPrefix("-") || Self.isAssignment(word) { continue }
            let variants = Self.variants(of: Self.fileName(of: word))
            names.formUnion(variants)
            budget = Self.launchers.isDisjoint(with: variants) ? budget - 1 : 2
        }
        return names
    }

    /// What "Quit … to clean this" calls a process found by its command line: its first word's file name.
    var displayName: String {
        let name = words.first.map { Self.fileName(of: $0) } ?? command
        return name.isEmpty ? "process \(pid)" : name
    }

    /// The last non-empty path component.
    static func fileName<S: StringProtocol>(of word: S) -> String {
        let parts = word.split(separator: "/", omittingEmptySubsequences: true)
        return parts.last.map { String($0) } ?? String(word)
    }

    /// `name` in lower case, plus the same without a leading "-" (a login shell) and without version suffixes:
    /// `pip3.12` -> `pip3.12`, `pip3`, `pip`.
    static func variants(of name: String) -> [String] {
        var current = name.lowercased()
        if current.hasPrefix("-") { current.removeFirst() }
        guard !current.isEmpty else { return [] }
        var result = [current]
        while let dot = current.lastIndex(of: "."), dot != current.startIndex {
            let suffix = current[current.index(after: dot)...]
            guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && $0.isNumber }) else { break }
            current = String(current[..<dot])
            result.append(current)
        }
        let withoutDigits = String(current.reversed().drop { $0.isASCII && $0.isNumber }.reversed())
        if !withoutDigits.isEmpty, withoutDigits != current { result.append(withoutDigits) }
        return result
    }

    /// `NAME=value`, as `env` takes before the command.
    static func isAssignment(_ word: Substring) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}
