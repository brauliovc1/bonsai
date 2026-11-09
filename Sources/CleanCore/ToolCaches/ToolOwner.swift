import Foundation

/// A program that must not be running while a tool-cache entry is cleaned (PLAN §4.6), and how to recognise
/// it in `ps` output. A running owner refuses the entry with "Quit <name> to clean this".
public struct ToolOwner: Sendable, Hashable {
    public enum Rule: Sendable, Hashable {
        /// One of the process's command names is in the set: the executable's file name, or the script an
        /// interpreter or wrapper runs (`node …/bin/npm`, `python3 -m pip`, `sudo brew`). Compared in lower
        /// case, with version suffixes dropped (`pip3.12` also counts as `pip3` and `pip`).
        case command(Set<String>)
        /// A command-line word's file name is in the set, in any process (`node …/npm-cli.js`).
        case argumentName(Set<String>)
        /// The command line contains this text, ignoring case, in any process (`GradleDaemon`, `playwright`).
        case argumentContains(String)
        /// The Cursor app: an executable inside a `Cursor.app` bundle (the app itself or one of its helpers),
        /// or, in the app, a running application with Cursor's bundle id (`ProcessList.cursorAppRunning`).
        case cursorApp
    }

    /// The name in "Quit <name> to clean this".
    public let name: String
    public let rules: [Rule]

    public init(_ name: String, _ rules: [Rule]) {
        self.name = name
        self.rules = rules
    }

    /// The Cursor app (PLAN §4.6: by executable path in `ps`, and by bundle id through NSWorkspace in the app).
    public static let cursor = ToolOwner("Cursor", [.cursorApp])

    /// The sentence a running owner refuses an entry with.
    public static func quitSentence(_ names: [String]) -> String {
        "Quit \(list(names)) to clean this"
    }

    /// "npm", "npm and npx", "a, b and c" (or "or").
    static func list(_ names: [String], conjunction: String = "and") -> String {
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " \(conjunction) " + last
    }
}
