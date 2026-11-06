/// How Claude Code names a folder's transcript directory under `<claude config>/projects/` (PLAN §4.3,
/// signal 4): the absolute path with every UTF-16 code unit outside `[A-Za-z0-9]` replaced by `-`. Claude
/// Code uses a JavaScript regex without the `u` flag, so an emoji (two code units) becomes `--`.
///
/// P3's `ClaudeProjectFolderName` encodes the same thing for its usage scanner; P4 merges the two.
public enum TranscriptFolderEncoding {
    public static func encode(_ path: String) -> String {
        String(path.utf16.map { unit -> Character in
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: Character(Unicode.Scalar(UInt8(unit)))
            default: "-"
            }
        })
    }
}
