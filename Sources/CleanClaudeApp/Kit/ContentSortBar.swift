import SwiftUI

/// The same visible ordering control on every list of sizes.
enum ContentSort: String, CaseIterable, Identifiable {
    case size, activity, name
    var id: Self { self }
    var title: String {
        switch self { case .size: "Size"; case .activity: "Last activity"; case .name: "Name" }
    }
}

struct ContentSortBar: View {
    @Binding var selection: ContentSort
    var showsActivity = false
    var body: some View {
        HStack(spacing: 8) {
            Text("Sort:").foregroundStyle(.secondary)
            Picker("Sort", selection: $selection) {
                Text("Size").tag(ContentSort.size)
                if showsActivity { Text("Last activity").tag(ContentSort.activity) }
                Text("Name").tag(ContentSort.name)
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            .help("Largest sizes first; oldest activity first; names alphabetically.")
            Spacer(minLength: 0)
        }
        .font(.callout).controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 5)
    }
}
