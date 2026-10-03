import SwiftUI
import SwiftData

/// Panel de preguntas con respuestas fundamentadas (grounding).
///
/// Flujo: el usuario pregunta → GeminiService.ask devuelve SOLO citas textuales
/// con su número de párrafo → la app recupera esos ParagraphRecord reales desde
/// SwiftData y muestra el texto original guardado, no lo que el modelo recuerda.
struct SermonQnAView: View {
    let sermon: SermonRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager

    // GeminiConfig.apiKey vive en AIChatView.swift. Si todavía no lo agregaste
    // ahí, define GeminiConfig con tu API key real antes de compilar esto.
    private let gemini = GeminiService(apiKey: GeminiConfig.apiKey)

    @State private var pregunta = ""
    @State private var isLoading = false
    @State private var respuesta: String?
    @State private var citas: [ParagraphRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    encabezado

                    // Campo de pregunta
                    VStack(spacing: 10) {
                        TextField(localization.getString("sermonQAPlaceholder"), text: $pregunta, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isLoading)

                        Button(action: preguntar) {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(isLoading ? localization.getString("sermonQAThinking")
                                               : localization.getString("sermonQAAsk"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(preguntaVacia || isLoading ? Color.gray : Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(preguntaVacia || isLoading)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Respuesta
                    if let respuesta {
                        Text(respuesta)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Citas textuales reales desde SwiftData
                    if !citas.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(localization.getString("sermonQAQuotes"))
                                .font(.headline)

                            ForEach(citas) { parrafo in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(localization.getString("sermonQAParagraph")) \(parrafo.number)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.blue)
                                    Text("\u{201C}\(parrafo.text)\u{201D}")
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.blue.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    } else if respuesta == nil && !isLoading && errorMessage == nil {
                        Text(localization.getString("sermonQAEmpty"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                }
                .padding()
            }
            .navigationTitle(localization.getString("sermonQATitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.getString("close")) { dismiss() }
                }
            }
        }
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sermon.code)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(sermon.title)
                .font(.headline)
        }
    }

    private var preguntaVacia: Bool {
        pregunta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func preguntar() {
        let texto = pregunta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty, !isLoading else { return }

        isLoading = true
        errorMessage = nil
        respuesta = nil
        citas = []

        // Contexto numerado con los párrafos reales guardados en SwiftData.
        let contexto = DemoLibraryService.shared.groundingContext(context: modelContext, sermon: sermon)

        Task {
            do {
                let resultado = try await gemini.ask(prompt: texto, context: contexto)
                self.respuesta = resultado.respuesta

                if !resultado.noEncontrado {
                    let numeros = resultado.citas.map { $0.parrafo }
                    let reales = DemoLibraryService.shared.paragraphs(
                        context: modelContext,
                        sermonID: sermon.id,
                        numbers: numeros
                    )
                    // Mostrar el texto real de la base de datos, en el orden que dio Gemini.
                    let porNumero = Dictionary(reales.map { ($0.number, $0) },
                                               uniquingKeysWith: { primero, _ in primero })
                    self.citas = numeros.compactMap { porNumero[$0] }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    SermonQnAView(sermon: SermonRecord(
        code: "47-0412",
        title: "Fe Es La Sustancia",
        location: "Oakland CA",
        language: "Español",
        body: "Párrafo de ejemplo.\n\nSegundo párrafo de ejemplo."
    ))
    .environmentObject(LocalizationManager.shared)
    .modelContainer(for: [SermonRecord.self, ParagraphRecord.self], inMemory: true)
}
