/// One card of the Overview: a category with something to free, how much, what it is in one line, and the button
/// that opens its screen already filtered to what the card counted.
public struct OverviewCard: Identifiable, Hashable, Sendable {
    public let category: OverviewCategory
    public let bytes: Int64
    /// One line: what the size is made of.
    public let detail: String

    public init(category: OverviewCategory, bytes: Int64, detail: String) {
        self.category = category
        self.bytes = bytes
        self.detail = detail
    }

    public var id: OverviewCategory { category }
    public var title: String { category.title }
    public var sizeText: String { DisplayText.bytes(bytes) }
    public var buttonTitle: String { "Review and clean" }
}
