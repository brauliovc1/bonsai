/// Column layout for plain-text tables.
enum TextTable {
    /// Pads every column but the last; `rightAligned` columns are padded on the left.
    static func lines(_ rows: [[String]], rightAligned: Set<Int> = []) -> [String] {
        let columnCount = rows.map(\.count).max() ?? 0
        let widths = (0..<columnCount).map { column in
            rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
        }
        return rows.map { row in
            row.enumerated().map { column, cell in
                if column == row.count - 1 { return cell }
                let padding = String(repeating: " ", count: widths[column] - cell.count)
                return rightAligned.contains(column) ? padding + cell : cell + padding
            }.joined(separator: "  ")
        }
    }
}
