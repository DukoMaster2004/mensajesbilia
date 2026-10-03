import SwiftUI
import SwiftData

private enum SermonLibraryFilter: String, CaseIterable {
    case all
    case audio
    case favorites

    var title: String {
        switch self {
        case .all: "Todos"
        case .audio: "Audio directo"
        case .favorites: "Favoritos"
        }
    }
}

struct SermonLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var favorites: [FavoriteRecord]
    @Query private var storedSermons: [SermonRecord]
    @State private var catalog: [ZoeSermonSummary] = []
    @State private var searchText = ""
    @State private var filter = SermonLibraryFilter.all
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSavedNotes = false

    private let service = TabernaculoZoeSearchService()

    private var filteredSermons: [ZoeSermonSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.filter { sermon in
            let matchesSearch = query.isEmpty || sermon.title.localizedCaseInsensitiveContains(query)
                || sermon.code.localizedCaseInsensitiveContains(query)
                || sermon.location.localizedCaseInsensitiveContains(query)
                || sermon.origin.localizedCaseInsensitiveContains(query)
            let hasAudio = sermon.audioURL != nil || BranhamAudioCatalog.shared.entry(for: sermon.code) != nil
            let sermonID = storedSermons.first(where: { $0.code == sermon.code })?.id
            let isFavorite = sermonID.map { id in
                favorites.contains { $0.sermonID == id && ($0.type == "sermon" || $0.type == "paragraph") }
            } ?? false
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .audio: matchesFilter = hasAudio
            case .favorites: matchesFilter = isFavorite
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && catalog.isEmpty {
                    ProgressView("Cargando mensajes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Text("\(catalog.count) mensajes disponibles · texto cargado al abrir")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Filtrar", selection: $filter) {
                                ForEach(SermonLibraryFilter.allCases, id: \.self) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if let errorMessage {
                            Section {
                                ContentUnavailableView {
                                    Label("No se pudo actualizar", systemImage: "wifi.exclamationmark")
                                } description: {
                                    Text(errorMessage)
                                } actions: {
                                    Button("Reintentar") {
                                        Task { await loadCatalog() }
                                    }
                                }
                            }
                        }

                        ForEach(filteredSermons) { sermon in
                            NavigationLink {
                                ZoeSermonDetailView(sermon: sermon)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sermon.title)
                                        .font(.headline)
                                    HStack(spacing: 6) {
                                        Text(sermon.code)
                                        if !sermon.location.isEmpty {
                                            Text("·")
                                            Text(sermon.location)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    if !sermon.origin.isEmpty {
                                        Text(sermon.origin)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    .overlay {
                        if !isLoading && filteredSermons.isEmpty && errorMessage == nil {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    .refreshable { await loadCatalog() }
                }
            }
            .searchable(text: $searchText, prompt: "Título, código o lugar")
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showSavedNotes = true
                        } label: {
                            Image(systemName: "note.text")
                        }
                        .accessibilityLabel("Buscar notas por título y párrafo")

                        Button {
                            Task { await loadCatalog() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                        .accessibilityLabel("Actualizar biblioteca")
                    }
                }
            }
            .sheet(isPresented: $showSavedNotes) {
                NotesWorkspaceView()
            }
            .task {
                await loadCatalog()
            }
        }
    }

    @MainActor
    private func loadCatalog() async {
        isLoading = true
        errorMessage = nil
        do {
            catalog = try await service.loadCatalog()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ZoeSermonDetailView: View {
    let sermon: ZoeSermonSummary

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var favorites: [FavoriteRecord]
    @Query private var notes: [NoteRecord]
    @Query private var highlights: [ParagraphHighlightRecord]
    @State private var paragraphs: [ZoeSermonParagraph] = []
    @State private var sermonRecord: SermonRecord?
    @State private var paragraphRecordsByNumber: [Int: ParagraphRecord] = [:]
    @State private var activeParagraphNumber: Int?
    @State private var editingParagraphNumber: Int?
    @State private var paragraphNoteDraft = ""
    @State private var sermonNoteDraft = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @StateObject private var speech = SpeechManager.shared

    private let service = TabernaculoZoeSearchService()

    private var branhamAudioPage: URL? {
        URL(string: "https://branham.org/es/messageaudio/SPN/\(sermon.code)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(sermon.title)
                        .font(.title3.bold())
                    Text("\(sermon.code) · \(sermon.location)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !sermon.origin.isEmpty {
                        Text("Transcripción: \(sermon.origin)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                audioSection

                if isLoading {
                    ProgressView("Cargando transcripción…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("No se pudo cargar el texto", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Reintentar") {
                            Task { await loadSermon() }
                        }
                    }
                } else {
                    ForEach(paragraphs) { paragraph in
                        paragraphRow(paragraph)
                    }

                    if sermonRecord != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Nota general del mensaje")
                                .font(.headline)
                            TextEditor(text: $sermonNoteDraft)
                                .frame(minHeight: 110)
                                .padding(4)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.25))
                                }
                            Button {
                                saveNote(paragraphID: nil, text: sermonNoteDraft)
                            } label: {
                                Label("Guardar nota", systemImage: "square.and.arrow.down")
                            }
                            .disabled(isLoading)
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(sermon.code)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSermon() }
        .onDisappear { speech.stop() }
    }

    @ViewBuilder
    private func paragraphRow(_ paragraph: ZoeSermonParagraph) -> some View {
        let storedParagraph = paragraphRecordsByNumber[paragraph.number]
        let isFavorite = storedParagraph.map { stored in
            favorites.contains { $0.type == "paragraph" && $0.paragraphID == stored.id }
        } ?? false
        let isHighlighted = storedParagraph.map { stored in
            highlights.contains { $0.paragraphID == stored.id }
        } ?? false
        let isCurrent = activeParagraphNumber == paragraph.number && (speech.isPlaying || speech.isPaused)

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                Text("Párrafo \(paragraph.number)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)

                Button { toggleReading(paragraph) } label: {
                    Image(systemName: isCurrent ? (speech.isPaused ? "play.fill" : "pause.fill") : "speaker.wave.2")
                }
                .accessibilityLabel(isCurrent ? (speech.isPaused ? "Continuar lectura" : "Pausar lectura") : "Leer párrafo")

                Button { toggleFavorite(storedParagraph) } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .disabled(storedParagraph == nil)
                .accessibilityLabel(isFavorite ? "Quitar de favoritos" : "Agregar a favoritos")

                Button { toggleHighlight(storedParagraph) } label: {
                    Image(systemName: "highlighter")
                        .foregroundStyle(isHighlighted ? .orange : .secondary)
                }
                .disabled(storedParagraph == nil)
                .accessibilityLabel(isHighlighted ? "Quitar resaltado" : "Resaltar párrafo")

                Button { beginParagraphNote(paragraph, storedParagraph: storedParagraph) } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(editingParagraphNumber == paragraph.number ? .blue : .secondary)
                }
                .disabled(storedParagraph == nil)
                .accessibilityLabel("Anotar párrafo")
            }

            Text(paragraph.text)
                .font(.system(size: appState.readingFontSize))
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(5)
                .background(isHighlighted ? Color.yellow.opacity(0.32) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if editingParagraphNumber == paragraph.number {
                TextEditor(text: $paragraphNoteDraft)
                    .frame(minHeight: 90)
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25))
                    }
                HStack {
                    Button("Cancelar") { editingParagraphNumber = nil }
                    Spacer()
                    Button("Guardar") {
                        saveNote(paragraphID: storedParagraph?.id, text: paragraphNoteDraft)
                        editingParagraphNumber = nil
                    }
                    .fontWeight(.semibold)
                }
            }
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var audioSection: some View {
        if let audio = BranhamAudioCatalog.shared.entry(for: sermon.code) {
            OfficialAudioPlayerView(entry: audio)
        } else if let audioString = sermon.audioURL,
                  let audioURL = URL(string: audioString) {
            Link(destination: audioURL) {
                Label("Abrir audio disponible", systemImage: "play.circle.fill")
            }
        } else if let branhamAudioPage {
            Link(destination: branhamAudioPage) {
                Label("Buscar audio en branham.org", systemImage: "headphones")
            }
        }
    }

    @MainActor
    private func loadSermon() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedParagraphs = try await service.loadSermon(messageID: sermon.messageID)
            try persistSermon(loadedParagraphs)
            paragraphs = loadedParagraphs
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func persistSermon(_ loadedParagraphs: [ZoeSermonParagraph]) throws {
        let code = sermon.code
        let sermonFetch = FetchDescriptor<SermonRecord>(predicate: #Predicate { $0.code == code })
        let existingSermon = try modelContext.fetch(sermonFetch).first
        let record = existingSermon ?? SermonRecord(
            code: sermon.code,
            title: sermon.title,
            location: sermon.location,
            language: "Español",
            durationMinutes: max(30, min(120, loadedParagraphs.count / 5)),
            audioURL: sermon.audioURL,
            source: "tabernaculozoe:\(sermon.messageID)",
            body: ""
        )
        record.title = sermon.title
        record.location = sermon.location
        record.language = "Español"
        record.audioURL = sermon.audioURL
        record.source = "tabernaculozoe:\(sermon.messageID)"
        record.body = loadedParagraphs.map(\.text).joined(separator: "\n\n")
        record.updatedAt = .now
        if existingSermon == nil {
            modelContext.insert(record)
        }

        let sermonID = record.id
        let paragraphFetch = FetchDescriptor<ParagraphRecord>(
            predicate: #Predicate { $0.sermonID == sermonID }
        )
        let existingParagraphs = try modelContext.fetch(paragraphFetch)
        var paragraphsByNumber = Dictionary(
            existingParagraphs.map { ($0.number, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for paragraph in loadedParagraphs {
            if let stored = paragraphsByNumber[paragraph.number] {
                stored.text = paragraph.text
            } else {
                let stored = ParagraphRecord(
                    sermonID: sermonID,
                    number: paragraph.number,
                    text: paragraph.text
                )
                modelContext.insert(stored)
                paragraphsByNumber[paragraph.number] = stored
            }
        }

        try modelContext.save()
        sermonRecord = record
        paragraphRecordsByNumber = paragraphsByNumber
        sermonNoteDraft = notes.first {
            $0.sermonID == record.id && $0.paragraphID == nil
        }?.text ?? ""
    }

    private func toggleReading(_ paragraph: ZoeSermonParagraph) {
        if activeParagraphNumber == paragraph.number && speech.isPlaying {
            speech.pause()
        } else if activeParagraphNumber == paragraph.number && speech.isPaused {
            speech.resume()
        } else {
            activeParagraphNumber = paragraph.number
            speech.speak(paragraphs: [paragraph.text], language: "Español")
        }
    }

    private func toggleFavorite(_ paragraph: ParagraphRecord?) {
        guard let paragraph else { return }
        if let favorite = favorites.first(where: {
            $0.type == "paragraph" && $0.paragraphID == paragraph.id
        }) {
            modelContext.delete(favorite)
        } else {
            modelContext.insert(FavoriteRecord(
                type: "paragraph",
                sermonID: paragraph.sermonID,
                paragraphID: paragraph.id
            ))
        }
        try? modelContext.save()
    }

    private func toggleHighlight(_ paragraph: ParagraphRecord?) {
        guard let paragraph else { return }
        if let highlight = highlights.first(where: { $0.paragraphID == paragraph.id }) {
            modelContext.delete(highlight)
        } else {
            modelContext.insert(ParagraphHighlightRecord(
                sermonID: paragraph.sermonID,
                paragraphID: paragraph.id
            ))
        }
        try? modelContext.save()
    }

    private func beginParagraphNote(
        _ paragraph: ZoeSermonParagraph,
        storedParagraph: ParagraphRecord?
    ) {
        if editingParagraphNumber == paragraph.number {
            editingParagraphNumber = nil
            return
        }
        editingParagraphNumber = paragraph.number
        paragraphNoteDraft = notes.first { $0.paragraphID == storedParagraph?.id }?.text ?? ""
    }

    private func saveNote(paragraphID: UUID?, text: String) {
        guard let sermonRecord else { return }
        let matchingNotes = notes.filter {
            $0.sermonID == sermonRecord.id && $0.paragraphID == paragraphID
        }
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.isEmpty {
            matchingNotes.forEach(modelContext.delete)
        } else if let existing = matchingNotes.first {
            existing.text = cleanedText
            existing.updatedAt = .now
            matchingNotes.dropFirst().forEach(modelContext.delete)
        } else {
            modelContext.insert(NoteRecord(sermonID: sermonRecord.id, paragraphID: paragraphID, text: cleanedText))
        }
        try? modelContext.save()
    }
}

