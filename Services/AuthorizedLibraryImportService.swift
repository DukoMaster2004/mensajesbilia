import Foundation

struct AuthorizedMediaSource: Identifiable {
    let id: UUID
    let title: String
    let sourceURL: URL
    let kind: SourceKind
    let requiresAuthorization: Bool
    let notes: String

    enum SourceKind: String {
        case audio
        case pdf
        case transcript
        case metadata
    }
}

enum AuthorizedLibraryImportError: Error {
    case unsupportedSource
    case missingAuthorization
    case invalidURL
    case importNotAllowed
}

final class AuthorizedLibraryImportService {
    static let shared = AuthorizedLibraryImportService()

    private init() {}

    func validateSourceURL(_ url: URL) -> Bool {
        let allowedHosts = ["branham.org", "d2w09gj4mqt5u.cloudfront.net", "d21kl6o5a7faj0.cloudfront.net"]
        return allowedHosts.contains(url.host ?? "")
    }

    func makeAuthorizedSource(title: String, url: URL, kind: AuthorizedMediaSource.SourceKind) throws -> AuthorizedMediaSource {
        guard validateSourceURL(url) else {
            throw AuthorizedLibraryImportError.invalidURL
        }

        return AuthorizedMediaSource(
            id: UUID(),
            title: title,
            sourceURL: url,
            kind: kind,
            requiresAuthorization: true,
            notes: "Se usa solo cuando el usuario o la organización tiene derechos autorizados para importar este archivo."
        )
    }

    func describeImportPolicy() -> String {
        "No se descargan ni se copian archivos protegidos sin autorización explícita. La app acepta contenido autorizado desde archivos locales, PDFs, audios, transcripciones o metadatos legítimos del usuario."
    }
}
