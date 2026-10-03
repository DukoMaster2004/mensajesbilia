import Foundation
import SwiftData

@MainActor
final class DemoLibraryService {
    static let shared = DemoLibraryService()

    /// - Parameter onComplete: se llama cuando termina el seed (haya insertado
    ///   datos o no). Útil para ocultar una pantalla de carga (SeedingView).
    ///   Es opcional para no romper llamados existentes sin este parámetro.
    func seedIfNeeded(context: ModelContext, onComplete: (() -> Void)? = nil) {
        let fetch: FetchDescriptor<SermonRecord> = FetchDescriptor<SermonRecord>()
        if let existing = try? context.fetch(fetch), existing.isEmpty {
            let catalog = BroSermonCatalogLoader.shared.loadCatalog()

            for sermon in catalog {
                let sermonRecord = SermonRecord(
                    code: sermon.id,
                    title: sermon.title,
                    date: parseDate(from: sermon.meta?.date ?? sermon.date ?? ""),
                    location: sermon.meta?.location ?? sermon.location ?? "Desconocida",
                    language: "Inglés",
                    durationMinutes: estimateDuration(from: sermon.paragraphs.count),
                    audioURL: nil,
                    source: "bro-william-branham-sermon-library",
                    body: sermon.paragraphs.map { $0.text }.joined(separator: "\n\n"),
                    isFeatured: false
                )

                context.insert(sermonRecord)

                for paragraph in sermon.paragraphs {
                    context.insert(ParagraphRecord(
                        sermonID: sermonRecord.id,
                        number: paragraph.number,
                        text: paragraph.text
                    ))
                }
            }
        }

        seedBundledSpanishCatalogIfNeeded(context: context)
        try? context.save()
        onComplete?()
    }

    private func seedBundledSpanishCatalogIfNeeded(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "bro_branham_sermons_es", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              !BroSermonCatalogLoader.isGitLFSPointer(data),
              let envelope = try? JSONDecoder().decode(BroSermonCatalogEnvelope.self, from: data) else {
            return
        }

        let spanishFetch = FetchDescriptor<SermonRecord>(
            predicate: #Predicate { $0.language == "Español" }
        )
        let existingSpanishCount = (try? context.fetchCount(spanishFetch)) ?? 0
        guard existingSpanishCount < envelope.sermons.count else { return }

        for batchStart in stride(from: 0, to: envelope.sermons.count, by: 50) {
            let batchEnd = min(batchStart + 50, envelope.sermons.count)
            let batch = Array(envelope.sermons[batchStart..<batchEnd])
            DemoLibraryService.shared.upsert(catalog: batch, context: context)
        }
    }

    /// Inserta o actualiza sermones en SwiftData a partir de un catálogo
    /// (por ejemplo, el resultado de importar traducciones en español).
    /// A diferencia de seedIfNeeded, esto SIEMPRE aplica los cambios,
    /// sin importar si la base de datos ya tenía datos — por eso es el
    /// método correcto para agregar/actualizar contenido después del
    /// primer arranque de la app.
    ///
    /// - Returns: (insertados, actualizados)
    @discardableResult
    func upsert(catalog: [BroSermonCatalogEntry], context: ModelContext) -> (inserted: Int, updated: Int) {
        var insertados = 0
        var actualizados = 0

        for sermon in catalog {
            let code = sermon.id
            let fetch = FetchDescriptor<SermonRecord>(
                predicate: #Predicate { $0.code == code }
            )
            let existentes = (try? context.fetch(fetch)) ?? []

            let nuevoBody = sermon.paragraphs.map { $0.text }.joined(separator: "\n\n")
            let nuevaFecha = parseDate(from: sermon.meta?.date ?? sermon.date ?? "")
            let nuevaUbicacion = sermon.meta?.location ?? sermon.location ?? "Desconocida"
            let nuevaDuracion = estimateDuration(from: sermon.paragraphs.count)

            if let existente = existentes.first {
                // Actualiza el registro existente en vez de duplicarlo
                existente.title = sermon.title
                existente.date = nuevaFecha
                existente.location = nuevaUbicacion
                existente.language = "Español"
                existente.durationMinutes = nuevaDuracion
                existente.body = nuevoBody
                existente.updatedAt = .now

                // Reemplaza los párrafos asociados
                let sermonID = existente.id
                let paragraphFetch = FetchDescriptor<ParagraphRecord>(
                    predicate: #Predicate { $0.sermonID == sermonID }
                )
                if let paragrafosViejos = try? context.fetch(paragraphFetch) {
                    for p in paragrafosViejos { context.delete(p) }
                }
                for paragraph in sermon.paragraphs {
                    context.insert(ParagraphRecord(
                        sermonID: sermonID,
                        number: paragraph.number,
                        text: paragraph.text
                    ))
                }
                actualizados += 1
            } else {
                // Sermón nuevo, no existía por code
                let sermonRecord = SermonRecord(
                    code: code,
                    title: sermon.title,
                    date: nuevaFecha,
                    location: nuevaUbicacion,
                    language: "Español",
                    durationMinutes: nuevaDuracion,
                    audioURL: nil,
                    source: "importado-es",
                    body: nuevoBody,
                    isFeatured: false
                )
                context.insert(sermonRecord)

                for paragraph in sermon.paragraphs {
                    context.insert(ParagraphRecord(
                        sermonID: sermonRecord.id,
                        number: paragraph.number,
                        text: paragraph.text
                    ))
                }
                insertados += 1
            }
        }

        try? context.save()
        return (insertados, actualizados)
    }

    func allMessages(context: ModelContext) -> [SermonRecord] {
        let fetch: FetchDescriptor<SermonRecord> = FetchDescriptor<SermonRecord>(sortBy: [SortDescriptor(\.title)])
        return (try? context.fetch(fetch)) ?? []
    }

    func search(context: ModelContext, query: String) -> [SermonRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allMessages(context: context) }

        return allMessages(context: context).filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.code.localizedCaseInsensitiveContains(trimmed) ||
            $0.location.localizedCaseInsensitiveContains(trimmed) ||
            $0.body.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Arma el contexto numerado con los párrafos REALES de un sermón
    /// específico, para mandárselo a GeminiService como grounding.
    /// Ej: "[Párrafo 1] texto...\n\n[Párrafo 2] texto...\n\n"
    func groundingContext(context: ModelContext, sermon: SermonRecord, maxCaracteresPorParrafo: Int = 800) -> String {
        let sermonID = sermon.id
        let fetch = FetchDescriptor<ParagraphRecord>(
            predicate: #Predicate { $0.sermonID == sermonID },
            sortBy: [SortDescriptor(\.number)]
        )
        let parrafos = (try? context.fetch(fetch)) ?? []

        return parrafos.reduce(into: "") { resultado, parrafo in
            let textoRecortado = String(parrafo.text.prefix(maxCaracteresPorParrafo))
            resultado += "[Párrafo \(parrafo.number)] \(textoRecortado)\n\n"
        }
    }

    /// Recupera los párrafos reales (texto original guardado en SwiftData)
    /// de un sermón, filtrando solo por los números que citó Gemini.
    /// Nunca se usa el texto que "devuelve" el modelo como fuente de verdad.
    func paragraphs(context: ModelContext, sermonID: UUID, numbers: [Int]) -> [ParagraphRecord] {
        guard !numbers.isEmpty else { return [] }
        let numerosSet = Set(numbers)

        let fetch = FetchDescriptor<ParagraphRecord>(
            predicate: #Predicate { $0.sermonID == sermonID },
            sortBy: [SortDescriptor(\.number)]
        )
        let todos = (try? context.fetch(fetch)) ?? []
        return todos.filter { numerosSet.contains($0.number) }
    }

    private func parseDate(from value: String) -> Date {
        if value.isEmpty { return Date() }

        let patterns = [
            "MMMM d, yyyy",
            "MMMM d 'of' yyyy",
            "MMMM dth, yyyy",
            "MMMM dth, yyyy",
            "MMMM d, yyyy",
            "MMMM d, yyyy",
            "MMMM d, yyyy",
            "MMMM dth of yyyy",
            "MMMM d'nd', yyyy",
            "MMMM d'st', yyyy",
            "MMMM d'rd', yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for pattern in patterns {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) { return date }
        }

        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: value) { return date }

        return Date()
    }

    private func estimateDuration(from paragraphCount: Int) -> Int {
        let minutes = max(30, paragraphCount / 5)
        return min(120, minutes)
    }
}
