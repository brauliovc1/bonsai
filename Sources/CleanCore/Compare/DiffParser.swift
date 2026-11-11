import Foundation

public struct DiffDocument: Sendable, Equatable {
    public var hunks: [DiffHunk] = []
    public var isBinary = false
    public var oldBytes: Int?
    public var newBytes: Int?
    public init() {}
}

public struct DiffHunk: Sendable, Equatable, Identifiable {
    public let id: Int
    public let header: String
    public let function: String
    public let oldStart: Int
    public let newStart: Int
    public var lines: [DiffLine]
}

public struct DiffLine: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable { case context, added, removed, noNewline }
    public let id: Int
    public let kind: Kind
    public let oldNumber: Int?
    public let newNumber: Int?
    public let text: String
    /// UTF-16 offsets, also usable by AppKit's text system.
    public var changedWords: [Range<Int>] = []
}

public enum DiffParser {
    public static func parse(_ data: Data) -> DiffDocument {
        // Strip CR only as part of CRLF. Any other control byte remains visibly escaped.
        let text = DiffText.decode(Data(data).replacingCRLF())
        let pattern = /^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@(.*)$/
        var result = DiffDocument()
        var old = 0; var new = 0; var identity = 0; var active = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let match = line.wholeMatch(of: pattern) {
                active = true
                old = Int(match.1) ?? 0; new = Int(match.3) ?? 0
                result.hunks.append(DiffHunk(id: identity, header: line,
                    function: String(match.5).trimmingCharacters(in: .whitespaces), oldStart: old, newStart: new, lines: []))
                identity += 1
                continue
            }
            if line.hasPrefix("diff --git ") { active = false }
            if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") { result.isBinary = true }
            guard active, !result.hunks.isEmpty, let first = line.first else { continue }
            let kind: DiffLine.Kind
            let oldNumber: Int?; let newNumber: Int?
            switch first {
            case " ": kind = .context; oldNumber = old; newNumber = new; old += 1; new += 1
            case "-": kind = .removed; oldNumber = old; newNumber = nil; old += 1
            case "+": kind = .added; oldNumber = nil; newNumber = new; new += 1
            case "\\": kind = .noNewline; oldNumber = nil; newNumber = nil
            default: continue
            }
            result.hunks[result.hunks.count - 1].lines.append(DiffLine(id: identity, kind: kind,
                oldNumber: oldNumber, newNumber: newNumber, text: first == "\\" ? line : String(line.dropFirst())))
            identity += 1
        }
        for h in result.hunks.indices { highlightPairs(&result.hunks[h].lines) }
        return result
    }

    private static func highlightPairs(_ lines: inout [DiffLine]) {
        var i = 0
        while i < lines.count {
            guard lines[i].kind == .removed else { i += 1; continue }
            let removedStart = i
            while i < lines.count && lines[i].kind == .removed { i += 1 }
            let addedStart = i
            while i < lines.count && lines[i].kind == .added { i += 1 }
            for pair in 0..<min(addedStart - removedStart, i - addedStart) {
                let oldIndex = removedStart + pair; let newIndex = addedStart + pair
                let words = WordDiff.ranges(old: lines[oldIndex].text, new: lines[newIndex].text)
                lines[oldIndex].changedWords = words.old
                lines[newIndex].changedWords = words.new
            }
        }
    }
}

private extension Data {
    func replacingCRLF() -> Data {
        let bytes = Array(self)
        return Data(bytes.enumerated().compactMap { i, byte in
            byte == 13 && i + 1 < bytes.count && bytes[i + 1] == 10 ? nil : byte
        })
    }
}
