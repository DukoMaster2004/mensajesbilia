import SwiftUI
import SwiftData

struct SermonsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sermons: [SermonRecord]
    @State private var searchText = ""
    @EnvironmentObject private var localization: LocalizationManager  // ← CAMBIADO a EnvironmentObject
    
    var filteredSermons: [SermonRecord] {
        if searchText.isEmpty {
            return sermons
        } else {
            return sermons.filter { sermon in
                sermon.title.localizedCaseInsensitiveContains(searchText) ||
                sermon.code.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSermons) { sermon in
                    NavigationLink(destination: SermonDetailView(sermon: sermon)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sermon.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(sermon.title)
                                .font(.headline)
                            Text(sermon.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .searchable(text: $searchText, prompt: localization.getString("homeSearch"))
            .navigationTitle(localization.getString("tabMessages"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SermonsListView()
        .environmentObject(LocalizationManager.shared)
}
