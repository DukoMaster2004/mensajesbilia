import SwiftUI
import SwiftData

private struct SermonNoteEntry: Identifiable {
    let note: NoteRecord
    let sermon: SermonRecord
    let paragraph: ParagraphRecord?
    let summary: ZoeSermonSummary
    var id: UUID { note.id }
}

struct NotesWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FreeNoteRecord.updatedAt, order: .reverse) private var freeNotes: [FreeNoteRecord]
    @Query(sort: \NoteRecord.updatedAt, order: .reverse) private var sermonNotes: [NoteRecord]
    @Query private var sermons: [SermonRecord]
    @Query private var paragraphs: [ParagraphRecord]
    @State private var searchText = ""
    @State private var showsSermonNotes = false
    @State private var showingEditor = false
    @State private var editingNote: FreeNoteRecord?

    private var filteredFreeNotes: [FreeNoteRecord] {
        freeNotes.filter { note in
            matchesSearch([
                note.title, note.text, note.referenceTitle ?? "", note.referenceCode ?? "",
                note.referenceParagraphNumber.map(String.init) ?? ""
            ])
        }
    }

    private var filteredSermonNotes: [SermonNoteEntry] {
        sermonNotes.compactMap { note in
            guard let sermonID = note.sermonID,
                  let sermon = sermons.first(where: { $0.id == sermonID }),
                  let summary = summary(for: sermon) else { return nil }
            let paragraph = note.paragraphID.flatMap { id in paragraphs.first(where: { $0.id == id }) }
            guard matchesSearch([
                sermon.title, sermon.code, paragraph.map { String($0.number) } ?? "Mensaje", note.text
            ]) else { return nil }
            return SermonNoteEntry(note: note, sermon: sermon, paragraph: paragraph, summary: summary)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tipo de notas", selection: $showsSermonNotes) {
                    Text("Libres").tag(false)
                    Text("De sermones").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                if showsSermonNotes { sermonNotesList } else { freeNotesList }
            }
            .navigationTitle("Mis notas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                if !showsSermonNotes {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editingNote = nil
                            showingEditor = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Crear nota libre")
                    }
                }
            }
            .searchable(
                text: $searchText,
                prompt: showsSermonNotes ? "Título, código o párrafo" : "Buscar notas o referencias"
            )
            .sheet(isPresented: $showingEditor) {
                FreeNoteEditorView(note: editingNote)
                    .id(editingNote?.id)
            }
        }
    }

    @ViewBuilder
    private var freeNotesList: some View {
        if filteredFreeNotes.isEmpty {
            ContentUnavailableView {
                Label(searchText.isEmpty ? "Escribe tu primera nota" : "No hay coincidencias", systemImage: "note.text")
            } description: {
                Text(searchText.isEmpty
                    ? "Tus notas pueden ser independientes o vincularse a un sermón y párrafo."
                    : "Busca por palabras de la nota, el título o el párrafo.")
            } actions: {
                if searchText.isEmpty {
                    Button("Crear nota") {
                        editingNote = nil
                        showingEditor = true
                    }
                }
            }
        } else {
            List {
                ForEach(filteredFreeNotes) { note in
                    HStack(spacing: 12) {
                        Button {
                            editingNote = note
                            showingEditor = true
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.title.isEmpty ? "Nota sin título" : note.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let reference = referenceText(for: note) {
                                    Label(reference, systemImage: "bookmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(note.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                Text(note.updatedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        if let summary = referenceSummary(for: note) {
                            NavigationLink {
                                ZoeSermonDetailView(sermon: summary)
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel("Abrir sermón vinculado")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteFreeNotes)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var sermonNotesList: some View {
        if filteredSermonNotes.isEmpty {
            emptyState("Aún no hay notas de sermones", detail: "Las notas de párrafos y mensajes aparecerán aquí.")
        } else {
            List(filteredSermonNotes) { entry in
                NavigationLink {
                    ZoeSermonDetailView(sermon: entry.summary)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(entry.sermon.title) · \(entry.sermon.code)")
                            .font(.headline)
                        Text(entry.paragraph.map { "Párrafo \($0.number)" } ?? "Nota del mensaje")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.note.text)
                            .font(.subheadline)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
        }
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        ContentUnavailableView(
            searchText.isEmpty ? title : "No hay coincidencias",
            systemImage: "text.book.closed",
            description: Text(detail)
        )
    }

    private func matchesSearch(_ values: [String]) -> Bool {
        let terms = searchTerms(searchText)
        let searchableText = values
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return terms.allSatisfy { searchableText.contains($0) }
    }

    private func searchTerms(_ value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private func referenceText(for note: FreeNoteRecord) -> String? {
        guard let title = note.referenceTitle, !title.isEmpty else { return nil }
        let code = note.referenceCode.map { " · \($0)" } ?? ""
        let paragraph = note.referenceParagraphNumber.map { " · Párrafo \($0)" } ?? ""
        return title + code + paragraph
    }

    private func referenceSummary(for note: FreeNoteRecord) -> ZoeSermonSummary? {
        guard let messageID = note.referenceMessageID,
              let title = note.referenceTitle,
              let code = note.referenceCode else { return nil }
        return ZoeSermonSummary(
            messageID: messageID,
            title: title,
            code: code,
            location: "",
            origin: "Tabernáculo Zoe",
            audioURL: nil
        )
    }

    private func deleteFreeNotes(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(filteredFreeNotes[index]) }
        try? modelContext.save()
    }

    private func summary(for sermon: SermonRecord) -> ZoeSermonSummary? {
        let prefix = "tabernaculozoe:"
        guard sermon.source.hasPrefix(prefix) else { return nil }
        let messageID = String(sermon.source.dropFirst(prefix.count))
        guard !messageID.isEmpty else { return nil }
        return ZoeSermonSummary(
            messageID: messageID,
            title: sermon.title,
            code: sermon.code,
            location: sermon.location,
            origin: "Tabernáculo Zoe",
            audioURL: sermon.audioURL
        )
    }
}