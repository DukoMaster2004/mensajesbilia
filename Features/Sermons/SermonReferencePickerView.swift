import SwiftUI

struct SermonReferencePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    let catalog: [ZoeSermonSummary]
    let onSelect: (ZoeSermonSummary) -> Void

    private var filteredCatalog: [ZoeSermonSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalog }
        return catalog.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.code.localizedCaseInsensitiveContains(query)
                || $0.location.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCatalog) { sermon in
                Button {
                    onSelect(sermon)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sermon.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(sermon.code) · \(sermon.location)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Título, código o lugar")
            .navigationTitle("Vincular nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}