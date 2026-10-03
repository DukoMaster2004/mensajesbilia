import SwiftUI
import SwiftData

struct FreeNoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title: String
    @State private var text: String
    @State private var selectedSermon: ZoeSermonSummary?
    @State private var paragraphNumber: String
    @State private var catalog: [ZoeSermonSummary] = []
    @State private var showingSermonPicker = false
    @State private var isLoadingCatalog = false
    @State private var errorMessage: String?

    let note: FreeNoteRecord?
    private let service = TabernaculoZoeSearchService()

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(note: FreeNoteRecord?) {
        self.note = note
        _title = State(initialValue: note?.title ?? "")
        _text = State(initialValue: note?.text ?? "")
        _paragraphNumber = State(initialValue: note?.referenceParagraphNumber.map(String.init) ?? "")

        if let note,
           let messageID = note.referenceMessageID,
           let referenceTitle = note.referenceTitle,
           let referenceCode = note.referenceCode {
            _selectedSermon = State(initialValue: ZoeSermonSummary(
                messageID: messageID,
                title: referenceTitle,
                code: referenceCode,
                location: "",
                origin: "Tabernáculo Zoe",
                audioURL: nil
            ))
        } else {
            _selectedSermon = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                FreeNoteFieldsSection(title: $title, text: $text)
                FreeNoteReferenceSection(
                    sermon: selectedSermon,
                    paragraphNumber: $paragraphNumber,
                    isLoading: isLoadingCatalog,
                    errorMessage: errorMessage,
                    onChoose: { Task { await loadCatalogAndShowPicker() } },
                    onClear: clearReference
                )
            }
            .navigationTitle(note == nil ? "Nueva nota" : "Editar nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingSermonPicker) {
                SermonReferencePickerView(catalog: catalog) { selectedSermon = $0 }
            }
        }
    }

    @MainActor
    private func loadCatalogAndShowPicker() async {
        isLoadingCatalog = true
        errorMessage = nil
        do {
            catalog = try await service.loadCatalog()
            showingSermonPicker = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingCatalog = false
    }

    private func save() {
        let record = note ?? FreeNoteRecord()
        record.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        record.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        record.referenceMessageID = selectedSermon?.messageID
        record.referenceTitle = selectedSermon?.title
        record.referenceCode = selectedSermon?.code
        record.referenceParagraphNumber = Int(paragraphNumber)
        record.updatedAt = .now
        if note == nil {
            modelContext.insert(record)
        }
        try? modelContext.save()
        dismiss()
    }

    private func clearReference() {
        selectedSermon = nil
        paragraphNumber = ""
    }
}
