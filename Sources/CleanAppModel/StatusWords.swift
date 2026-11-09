/// A status as the app words it (PLAN §8.4): plain words in sentence case, the color they mean, and an SF
/// Symbol for the chip.
public struct StatusWords: Hashable, Sendable {
    public let text: String
    public let tone: StatusTone
    /// Shown next to a chip as a quiet note ("2 stashes kept", "Claude session"), never as the chip itself.
    public let isNote: Bool
    public let symbol: String?

    public init(_ text: String, _ tone: StatusTone, symbol: String? = nil, isNote: Bool = false) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
        self.isNote = isNote
    }
}
