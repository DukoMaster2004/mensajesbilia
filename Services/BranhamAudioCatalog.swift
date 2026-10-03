import Foundation

/// Una entrada de audio oficial extraída de https://branham.org/es/messageaudio
struct BranhamAudioEntry: Codable {
    let code: String
    let lang: String      // "SPN" | "ENG"
    let title: String
    let audio: String     // URL directa del .m4a en el CDN oficial
    let stream: String    // URL de la página de stream en branham.org
    let pdf: String

    var audioURL: URL? { URL(string: audio) }
    var streamURL: URL? { URL(string: stream) }
    var pdfURL: URL? { pdf.isEmpty ? nil : URL(string: pdf) }
}

/// Catálogo de audio oficial de branham.org.
/// Carga `branham_audio_catalog.json` del bundle una sola vez y permite
/// resolver el audio oficial a partir del código de un sermón.
@MainActor
final class BranhamAudioCatalog {
    static let shared = BranhamAudioCatalog()

    private var entries: [BranhamAudioEntry] = []
    private var byExactCode: [String: BranhamAudioEntry] = [:]
    private var byBaseCode: [String: BranhamAudioEntry] = [:]
    private var didLoad = false

    private init() {}

    /// Normaliza un código: mayúsculas y sin espacios.
    private func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Código base sin la letra sufijo (ej. "58-0928E" -> "58-0928").
    private func baseCode(_ code: String) -> String {
        let n = normalize(code)
        // quita letras finales después de los dígitos
        var end = n.endIndex
        while end > n.startIndex {
            let prev = n.index(before: end)
            if n[prev].isLetter { end = prev } else { break }
        }
        return String(n[..<end])
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        guard let url = Bundle.main.url(forResource: "branham_audio_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BranhamAudioEntry].self, from: data) else {
            return
        }

        entries = decoded
        for e in decoded {
            let key = normalize(e.code)
            byExactCode[key] = e
            let base = baseCode(e.code)
            // Preferir la variante española si hay colisión de código base.
            if byBaseCode[base] == nil || e.lang == "SPN" {
                byBaseCode[base] = e
            }
        }
    }

    /// Resuelve la entrada de audio oficial para un código de sermón.
    /// Intenta coincidencia exacta y luego por código base (sin sufijo de letra).
    func entry(for code: String) -> BranhamAudioEntry? {
        loadIfNeeded()
        let key = normalize(code)
        if let exact = byExactCode[key] { return exact }
        return byBaseCode[baseCode(code)]
    }

    /// URL directa del .m4a oficial para un código, si existe.
    func audioURL(for code: String) -> URL? {
        entry(for: code)?.audioURL
    }

    /// Busca por título o código en los metadatos oficiales disponibles localmente.
    func search(query: String, limit: Int = 5) -> [BranhamAudioEntry] {
        loadIfNeeded()
        let normalizedQuery = searchKey(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))
        let queryCode = searchCode(query)
        let scoredEntries = entries.compactMap { entry -> (entry: BranhamAudioEntry, score: Int)? in
            let titleKey = searchKey(entry.title)
            let titleTokens = Set(titleKey.split(separator: " ").map(String.init))
            let normalizedCode = entry.code.lowercased().filter { $0.isLetter || $0.isNumber }
            let codeMatches = !normalizedCode.isEmpty && queryCode.contains(normalizedCode)
            let titleMatches = queryTokens.intersection(titleTokens).count
            guard codeMatches || titleMatches > 0 else { return nil }

            let score = (codeMatches ? 100 : 0)
                + (titleKey == normalizedQuery ? 50 : 0)
                + (titleKey.contains(normalizedQuery) ? 20 : 0)
                + titleMatches
            return (entry, score)
        }

        return scoredEntries
            .sorted { first, second in
                if first.score != second.score { return first.score > second.score }
                return first.entry.code < second.entry.code
            }
            .prefix(max(0, limit))
            .map(\.entry)
    }

    private func searchKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 && !["the", "and", "for", "los", "las", "del", "una", "uno"].contains($0) }
            .joined(separator: " ")
    }

    private func searchCode(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    var count: Int {
        loadIfNeeded()
        return entries.count
    }
}
