/// A command as one line of text, for showing the user what would run. Display only: commands are never
/// started through a shell.
public enum CommandLineDisplay {
    public static func string(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(quoted).joined(separator: " ")
    }

    private static func quoted(_ word: String) -> String {
        let plain = !word.isEmpty && word.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || "/._-+=:,@%".contains(character))
        }
        if plain { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
