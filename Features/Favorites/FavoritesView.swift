import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteRecord.createdAt, order: .reverse) private var favorites: [FavoriteRecord]
    @EnvironmentObject private var localization: LocalizationManager
    
    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        
                        Text(localization.getString("favoritesEmpty"))
                            .font(.headline)
                        
                        Text(localization.getString("favoritesEmptyHint"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    List {
                        ForEach(favorites) { favorite in
                            // Mostrar favoritos de sermones
                            if let sermonID = favorite.sermonID {
                                SermonFavoriteRow(sermonID: sermonID, modelContext: modelContext)
                            }
                            // Mostrar favoritos de párrafos
                            else if let paragraphID = favorite.paragraphID {
                                ParagraphFavoriteRow(paragraphID: paragraphID, modelContext: modelContext)
                            }
                        }
                        .onDelete(perform: deleteFavorite)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            EditButton()
                        }
                    }
                }
            }
            .navigationTitle(localization.getString("tabFavorites"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func deleteFavorite(offsets: IndexSet) {
        for index in offsets {
            let favorite = favorites[index]
            modelContext.delete(favorite)
        }
    }
}

// MARK: - Componentes Auxiliares

struct SermonFavoriteRow: View {
    let sermonID: UUID
    let modelContext: ModelContext
    @Query private var sermons: [SermonRecord]
    
    var sermon: SermonRecord? {
        sermons.first { $0.id == sermonID }
    }
    
    var body: some View {
        if let sermon = sermon {
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
}

struct ParagraphFavoriteRow: View {
    let paragraphID: UUID
    let modelContext: ModelContext
    @Query private var paragraphs: [ParagraphRecord]
    @Query private var sermons: [SermonRecord]
    @EnvironmentObject private var localization: LocalizationManager
    
    var paragraph: ParagraphRecord? {
        paragraphs.first { $0.id == paragraphID }
    }
    
    var sermon: SermonRecord? {
        guard let paragraph = paragraph else { return nil }
        return sermons.first { $0.id == paragraph.sermonID }
    }
    
    var body: some View {
        if let paragraph = paragraph, let sermon = sermon {
            NavigationLink(destination: SermonDetailView(sermon: sermon)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(sermon.code) - \(localization.getString("favoritesParagraph")) \(paragraph.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(paragraph.text)
                        .font(.subheadline)
                        .lineLimit(2)
                    Text(sermon.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    FavoritesView()
        .environmentObject(LocalizationManager.shared)
}
