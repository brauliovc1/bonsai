/// Plain-text columns: every column but the last is padded to its widest cell.
enum AlignedColumns {
    /// `rightAligned` lists the columns (0-based) whose cells are padded on the left, e.g. sizes.
    static func lines(_ rows: [[String]], rightAligned: Set<Int> = []) -> [String] {
        guard let columnCount = rows.map(\.count).max() else { return [] }
        let widths = (0..<columnCount).map { column in
            rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
        }
        return rows.map { row in
            (0..<columnCount).map { column -> String in
                let cell = column < row.count ? row[column] : ""
                if column == columnCount - 1 { return cell }
                let padding = String(repeating: " ", count: widths[column] - cell.count)
                return rightAligned.contains(column) ? padding + cell : cell + padding
            }.joined(separator: "  ")
        }
    }
}
