import Foundation

struct BroSermonCatalogEnvelope: Codable {
    let sermons: [BroSermonCatalogEntry]
}

struct BroSermonCatalogEntry: Codable {
    let id: String
    let title: String
    let meta: BroSermonMeta?
    let paragraphs: [BroSermonParagraph]
    let date: String?
    let location: String?
}

struct BroSermonMeta: Codable {
    let date: String?
    let location: String?
    let building: String?
}

struct BroSermonParagraph: Codable {
    let number: Int
    let text: String
}

@MainActor
final class BroSermonCatalogLoader {
    static let shared = BroSermonCatalogLoader()

    private let bundleFileName = "bro_branham_sermons"

    static func isGitLFSPointer(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(200), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return prefix.lowercased().hasPrefix("version https://git-lfs.github.com/spec/v1")
    }

    func loadCatalog() -> [BroSermonCatalogEntry] {
        if let cached = loadCachedCatalog() {
            return cached
        }

        if let bundled = loadBundledCatalog() {
            cacheCatalog(bundled)
            return bundled
        }

        return loadFallbackCatalog()
    }

    func fetchCatalog() async -> [BroSermonCatalogEntry] {
        if let cached = loadCachedCatalog() {
            return cached
        }

        if let bundled = loadBundledCatalog() {
            cacheCatalog(bundled)
            return bundled
        }

        return loadFallbackCatalog()
    }

    private func parse(_ data: Data) -> [BroSermonCatalogEntry] {
        do {
            let envelope = try JSONDecoder().decode(BroSermonCatalogEnvelope.self, from: data)
            return envelope.sermons
        } catch {
            return loadFallbackCatalog()
        }
    }

    private func loadBundledCatalog() -> [BroSermonCatalogEntry]? {
        guard let url = Bundle.main.url(forResource: bundleFileName, withExtension: "json") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else { return nil }

        if Self.isGitLFSPointer(data) {
            print("⚠️ bro_branham_sermons.json es un puntero de Git LFS sin resolver, corre git lfs pull")
            return nil
        }

        return parse(data)
    }

    private func loadFallbackCatalog() -> [BroSermonCatalogEntry] {
        let fallbackJSON = """
        {
          "sermons": [
            {
              "id": "58-0928E",
              "title": "The Serpent's Seed",
              "meta": {
                "date": "September 28th, 1958",
                "location": "Jeffersonville, Indiana"
              },
              "paragraphs": [
                { "number": 1, "text": "La serpiente, la semilla, la mujer y el hombre son temas estudiados en este mensaje." },
                { "number": 2, "text": "La enseñanza central enfatiza la caída y el origen del problema espiritual en la humanidad." },
                { "number": 3, "text": "En las Escrituras encontramos que la relación del hombre y la mujer no se entiende apartada de la revelación de Dios." }
              ]
            },
            {
              "id": "61-1015M",
              "title": "Questions and Answers",
              "meta": {
                "date": "Morning of October 15th, 1961",
                "location": "Jeffersonville, IN"
              },
              "paragraphs": [
                { "number": 1, "text": "Aquí se responden preguntas sobre la mujer, el hombre, la serpiente y la revelación de la Palabra." },
                { "number": 2, "text": "La respuesta del mensaje insiste en la necesidad de mirar la verdad en el contexto de la Escritura." },
                { "number": 3, "text": "El propósito del sermón es clarificar pendientes doctrinales y fortalecer la obediencia espiritual." }
              ]
            }
          ]
        }
        """

        guard let data = fallbackJSON.data(using: .utf8) else { return [] }
        return parse(data)
    }

    // Antes era "private func" — ahora es "func" (sin private) para que
    // la extensión BroSermonCatalogLoader+Import.swift pueda usarla.
    func cacheCatalog(_ sermons: [BroSermonCatalogEntry]) {
        let folderURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let fileURL = folderURL.appendingPathComponent("bro_branham_sermons_cache.json")

        let payload = BroSermonCatalogEnvelope(sermons: sermons)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL)
    }

    private func loadCachedCatalog() -> [BroSermonCatalogEntry]? {
        let folderURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let fileURL = folderURL.appendingPathComponent("bro_branham_sermons_cache.json")

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let envelope = try? JSONDecoder().decode(BroSermonCatalogEnvelope.self, from: data)
        return envelope?.sermons
    }
}
