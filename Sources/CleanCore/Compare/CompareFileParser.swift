import Foundation

/// Parses Git's NUL-delimited raw + numstat stream without splitting paths at tabs or newlines.
public enum CompareFileParser {
    public static func parse(_ data: Data) -> [CompareFile] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var files: [CompareFile] = []
        var index = 0
        while index < fields.count {
            let field = fields[index]
            index += 1
            if field.hasPrefix(":") {
                let parts = field.dropFirst().split(separator: " ")
                guard parts.count >= 5, index < fields.count else { continue }
                let code = String(parts[4])
                let first = fields[index]; index += 1
                let paired = code.hasPrefix("R") || code.hasPrefix("C")
                let path: String
                if paired, index < fields.count { path = fields[index]; index += 1 } else { path = first }
                let status: CompareFile.Status
                switch code.first {
                case "A": status = .added
                case "D": status = .deleted
                case "R": status = .renamed
                case "C": status = .copied
                case "T": status = .typeChanged
                case "U": status = .unmerged
                default: status = .modified
                }
                files.append(CompareFile(path: path, oldPath: paired ? first : nil, status: status,
                    additions: 0, deletions: 0, isBinary: false, similarity: Int(code.dropFirst()),
                    oldMode: String(parts[0]), newMode: String(parts[1])))
            } else {
                let pieces = field.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard pieces.count == 3 else { continue }
                var path = String(pieces[2])
                if path.isEmpty, index + 1 < fields.count { index += 1; path = fields[index]; index += 1 }
                if let position = files.firstIndex(where: { $0.path == path }) {
                    files[position].additions = Int(pieces[0]) ?? 0
                    files[position].deletions = Int(pieces[1]) ?? 0
                    files[position].isBinary = pieces[0] == "-" || pieces[1] == "-"
                }
            }
        }
        return files
    }
}
