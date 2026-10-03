import Foundation

// MARK: - Importación de sermones adicionales (ej. traducciones al español)

extension BroSermonCatalogLoader {
    
    enum ImportError: LocalizedError {
        case invalidJSON(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidJSON(let detalle):
                return "El archivo JSON no tiene el formato esperado: \(detalle)"
            }
        }
    }
    
    /// Importa sermones desde un archivo JSON externo (con el mismo formato
    /// que `bro_branham_sermons.json`) y los combina con el catálogo actual.
    /// Los sermones nuevos se agregan a la caché, así que `loadCatalog()`
    /// los incluirá automáticamente a partir de ahora.
    ///
    /// - Returns: cuántos sermones nuevos se agregaron (los que ya existían
    ///   por "id" se omiten para no duplicar).
    @discardableResult
    func importAndMerge(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        
        if Self.isGitLFSPointer(data) {
            throw ImportError.invalidJSON("El archivo es un puntero de Git LFS sin resolver.")
        }
        
        let envelope: BroSermonCatalogEnvelope
        do {
            envelope = try JSONDecoder().decode(BroSermonCatalogEnvelope.self, from: data)
        } catch {
            throw ImportError.invalidJSON(error.localizedDescription)
        }
        
        let catalogoActual = loadCatalog()
        var idsExistentes = Set(catalogoActual.map { $0.id })
        
        var nuevos: [BroSermonCatalogEntry] = []
        for sermon in envelope.sermons {
            guard !idsExistentes.contains(sermon.id) else { continue }
            nuevos.append(sermon)
            idsExistentes.insert(sermon.id)
        }
        
        guard !nuevos.isEmpty else { return 0 }
        
        let catalogoCombinado = catalogoActual + nuevos
        cacheCatalog(catalogoCombinado)
        
        return nuevos.count
    }
}
