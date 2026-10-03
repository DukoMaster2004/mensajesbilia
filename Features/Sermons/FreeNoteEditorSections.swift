import SwiftUI

struct FreeNoteFieldsSection: View {
    @Binding var title: String
    @Binding var text: String

    var body: some View {
        Section("Nota") {
            TextField("Título", text: $title)
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .accessibilityLabel("Texto de la nota")
        }
    }
}

struct FreeNoteReferenceSection: View {
    let sermon: ZoeSermonSummary?
    @Binding var paragraphNumber: String
    let isLoading: Bool
    let errorMessage: String?
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        Section("Referencia opcional") {
            if let sermon {
                Text(sermon.title).font(.headline)
                Text(sermon.code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Número de párrafo", text: $paragraphNumber)
                    .keyboardType(.numberPad)
                Button("Quitar referencia", role: .destructive, action: onClear)
            }

            Button(action: onChoose) {
                Label(sermon == nil ? "Vincular a un sermón" : "Cambiar sermón", systemImage: "books.vertical")
            }
            .disabled(isLoading)

            if isLoading { ProgressView("Cargando mensajes…") }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}