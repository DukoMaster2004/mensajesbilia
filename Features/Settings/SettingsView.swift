import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var appState: AppState

    @Query private var sermons: [SermonRecord]
    @Query private var favorites: [FavoriteRecord]
    @Query private var notes: [NoteRecord]

    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var exportMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Apariencia
                Section(header: Text(localization.getString("settingsAppearance"))
                    .font(.headline)) {
                        Picker("Apariencia", selection: $localization.isDarkMode) {
                            Label("Claro", systemImage: "sun.max.fill")
                                .tag(false)
                            Label("Oscuro", systemImage: "moon.fill")
                                .tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                // MARK: - Idioma
                Section(header: Text(localization.getString("settingsLanguage"))
                    .font(.headline)) {

                        Picker(localization.getString("settingsLanguage"),
                               selection: $localization.currentLanguage) {
                            Text(localization.getString("settingsSpanish"))
                                .tag("es")

                            Text(localization.getString("settingsEnglish"))
                                .tag("en")
                        }
                               .pickerStyle(.segmented)
                    }

                // MARK: - Tamaño de Texto
                Section(header: Text(localization.getString("settingsTextSize"))
                    .font(.headline)) {

                        HStack {
                            Text("A")
                                .font(.caption)
                            Slider(value: $appState.readingFontSize, in: 12...24, step: 1)
                                .frame(maxWidth: .infinity)
                            Text("A")
                                .font(.title3.bold())
                        }

                        Text(String(format: "%.0f pt", appState.readingFontSize))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                // MARK: - Datos (Importar / Exportar)
                Section(header: Text(localization.getString("settingsData"))
                    .font(.headline)) {

                        NavigationLink {
                            AuthorizedImportView()
                        } label: {
                            Label(localization.getString("tabImport"), systemImage: "arrow.down.doc.fill")
                        }

                        Button(action: exportLibrary) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localization.getString("settingsExport"))
                                        .font(.subheadline)
                                    Text(localization.getString("settingsExportSubtitle"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(sermons.isEmpty)

                        if let exportMessage {
                            Text(exportMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                Section {
                    NavigationLink {
                        AboutAppView()
                    } label: {
                        Label("Sobre esta aplicación", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle(localization.getString("settingsTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(localization.isDarkMode ? .dark : .light)
            .sheet(isPresented: $showShare) {
                if let exportURL {
                    ActivityView(items: [exportURL])
                }
            }
        }
    }

    // MARK: - Exportar biblioteca

    private func exportLibrary() {
        guard !sermons.isEmpty else {
            exportMessage = localization.getString("settingsExportEmpty")
            return
        }

        let favoriteSermonIDs = Set(favorites.filter { $0.type == "sermon" }.compactMap { $0.sermonID })
        var notesBySermon: [UUID: [String]] = [:]
        for n in notes {
            if let sid = n.sermonID {
                notesBySermon[sid, default: []].append(n.text)
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let payload: [String: Any] = [
            "app": "mensajedeVGR",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "sermonCount": sermons.count,
            "sermons": sermons.map { s in
                [
                    "code": s.code,
                    "title": s.title,
                    "location": s.location,
                    "language": s.language,
                    "durationMinutes": s.durationMinutes,
                    "date": s.date.map { dateFormatter.string(from: $0) } ?? "",
                    "audioURL": s.audioURL ?? "",
                    "isFavorite": favoriteSermonIDs.contains(s.id),
                    "notes": notesBySermon[s.id] ?? []
                ] as [String: Any]
            }
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let fileName = "mensajedeVGR-biblioteca-\(dateFormatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportMessage = "✅ \(sermons.count) " + localization.getString("settingsExport").lowercased()
            showShare = true
        } catch {
            exportMessage = "❌ \(error.localizedDescription)"
        }
    }
}

// MARK: - Hoja de compartir

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
        .environmentObject(LocalizationManager.shared)
        .environmentObject(AppState())
        .modelContainer(for: [SermonRecord.self, FavoriteRecord.self, NoteRecord.self], inMemory: true)
}
