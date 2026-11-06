/// Runs async work over a list with at most `limit` items in flight.
public enum BoundedConcurrency {
    /// Transforms every item, at most `limit` at a time. Results keep the order of `items`.
    /// `onCompletion` is called once per finished item with the number finished so far.
    public static func map<Item: Sendable, Output: Sendable>(
        _ items: [Item],
        limit: Int,
        onCompletion: @Sendable (Int) -> Void = { _ in },
        _ transform: @escaping @Sendable (Item) async -> Output
    ) async -> [Output] {
        guard !items.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, Output).self) { group in
            var results = [Output?](repeating: nil, count: items.count)
            var next = 0
            func start(_ index: Int) {
                let item = items[index]
                group.addTask { (index, await transform(item)) }
            }
            while next < min(max(limit, 1), items.count) {
                start(next)
                next += 1
            }
            var completed = 0
            while let (index, output) = await group.next() {
                results[index] = output
                completed += 1
                onCompletion(completed)
                if next < items.count {
                    start(next)
                    next += 1
                }
            }
            return results.map { $0! }
        }
    }
}
