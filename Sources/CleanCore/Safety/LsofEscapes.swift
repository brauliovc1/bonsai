/// Decodes the escapes lsof uses in `-F` output for bytes it can't print (checked on this Mac, with
/// `LC_ALL=C` as `ProcessRunner` sets it): `\xNN` for bytes >= 0x80, `\\` for a backslash, `\b \f \n \r \t`,
/// and `^@`...`^_` / `^?` for other control bytes.
///
/// `^` itself is not escaped, so `^A` can be byte 0x01 or a literal `^A`. `decode` returns the reading with
/// carets kept first and, when the text has a caret sequence, the reading with them decoded second.
enum LsofEscapes {
    static func decode(_ text: String) -> [String] {
        let literal = decode(text, carets: false)
        guard text.contains("^") else { return [literal] }
        let decoded = decode(text, carets: true)
        return decoded == literal ? [literal] : [literal, decoded]
    }

    private static func decode(_ text: String, carets: Bool) -> String {
        let input = Array(text.utf8)
        var bytes: [UInt8] = []
        var index = 0
        while index < input.count {
            let byte = input[index]
            if byte == UInt8(ascii: "\\"), index + 1 < input.count {
                let next = input[index + 1]
                if next == UInt8(ascii: "x"), index + 3 < input.count,
                   let value = UInt8(String(decoding: input[(index + 2)...(index + 3)], as: UTF8.self), radix: 16) {
                    bytes.append(value)
                    index += 4
                    continue
                }
                if let control = controlEscapes[next] {
                    bytes.append(control)
                    index += 2
                    continue
                }
            }
            if carets, byte == UInt8(ascii: "^"), index + 1 < input.count {
                let next = input[index + 1]
                if next == UInt8(ascii: "?") {
                    bytes.append(0x7F)
                    index += 2
                    continue
                }
                if next >= 0x40, next <= 0x5F {
                    bytes.append(next - 0x40)
                    index += 2
                    continue
                }
            }
            bytes.append(byte)
            index += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static let controlEscapes: [UInt8: UInt8] = [
        UInt8(ascii: "\\"): UInt8(ascii: "\\"),
        UInt8(ascii: "b"): 0x08,
        UInt8(ascii: "f"): 0x0C,
        UInt8(ascii: "n"): 0x0A,
        UInt8(ascii: "r"): 0x0D,
        UInt8(ascii: "t"): 0x09,
    ]
}
