import Foundation

enum GeminiServiceError: Error, LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case requestFailed(String)
    case networkError(Error)
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API Key de Gemini no configurada. Verifica Secrets.swift"
        case .invalidResponse:
            return "La respuesta de Gemini no tiene el formato esperado"
        case .requestFailed(let details):
            return details.isEmpty
                ? "No se pudo consultar la inteligencia artificial. Inténtalo de nuevo."
                : "No se pudo consultar la inteligencia artificial: \(details)"
        case .networkError(let error):
            return "Error de red: \(error.localizedDescription)"
        case .decodingError(let details):
            return "Error al procesar la respuesta: \(details)"
        }
    }
}

/// Estructura que representa la respuesta de Gemini con citas
struct GeminiResponse {
    let respuesta: String
    let citas: [CitaExtraida]
    let noEncontrado: Bool
}

struct CitaExtraida {
    let parrafo: Int
    let texto: String
}

final class GeminiService {
    private let apiKey: String
    private let baseURL = GeminiConfig.baseURL
    private let model: String

    init(apiKey: String = GeminiConfig.apiKey, model: String = GeminiConfig.model) {
        self.apiKey = apiKey
        self.model = model
    }

    /// Realiza una pregunta a Gemini sobre un contexto específico
    /// - Parameters:
    ///   - prompt: La pregunta del usuario
    ///   - context: El contexto (párrafos numerados de sermones)
    /// - Returns: GeminiResponse con la respuesta y citas extraídas
    func ask(prompt: String, context: String) async throws -> GeminiResponse {
        guard !apiKey.isEmpty else {
            throw GeminiServiceError.invalidAPIKey
        }

        let endpoint = baseURL
            .appendingPathComponent(model)
            .appendingPathComponent(":generateContent")
        
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        Eres un asistente de consulta de un catálogo local de sermones de William Branham.
        Responde únicamente con hechos explícitos en los pasajes suministrados. No uses conocimiento general, recuerdos, inferencias doctrinales ni información externa.
        Si los pasajes no bastan para responder, di exactamente: "No encontré evidencia suficiente sobre eso en los mensajes disponibles". No completes huecos.
        No inventes citas, títulos, fechas ni números de párrafo. Cada afirmación sobre el contenido debe citarse con el identificador y párrafo que aparecen en el contexto, por ejemplo [58-0928E, párrafo 15].
        Si el usuario pregunta por información que no trata de los mensajes, explica que este chat solo responde con el catálogo disponible.
        Responde en español, de forma clara y breve. Si se solicita una cita, reproduce el texto tal como aparece en el contexto y conserva su referencia.
        """

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    [
                        "text": """
                        \(systemPrompt)
                        
                        CONTEXTO (única fuente autorizada):
                        \(context)
                        
                        PREGUNTA DEL USUARIO:
                        \(prompt)
                        
                        Responde basándote exclusivamente en el contexto anterior. No afirmes nada que no esté respaldado por esos pasajes.
                        """
                    ]
                ]
            ]],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 4096,
                "topP": 0.95,
                "topK": 40
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Agregar API key como parámetro query
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        urlRequest.url = components?.url

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiServiceError.requestFailed("Sin respuesta HTTP")
            }
            
            // Manejo de diferentes códigos de estado
            switch httpResponse.statusCode {
            case 200...299:
                break  // Éxito
            case 400:
                throw GeminiServiceError.requestFailed(Self.apiErrorMessage(from: data, fallback: "Solicitud inválida"))
            case 401, 403:
                throw GeminiServiceError.invalidAPIKey
            case 429:
                throw GeminiServiceError.requestFailed("Límite de solicitudes alcanzado. Intenta más tarde.")
            default:
                throw GeminiServiceError.requestFailed(Self.apiErrorMessage(from: data, fallback: "Servicio no disponible"))
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw GeminiServiceError.invalidResponse
            }

            let rawText = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let text = limpiarFormato(rawText)
            guard !text.isEmpty else {
                throw GeminiServiceError.decodingError("Respuesta vacía de Gemini")
            }

            // Extraer números de párrafos citados (ej: [Párrafo 15])
            let citasExtraidas = extraerCitas(from: text)
            let noEncontrado = text.lowercased().contains("no encontré")

            return GeminiResponse(
                respuesta: text,
                citas: citasExtraidas,
                noEncontrado: noEncontrado
            )
        } catch let error as GeminiServiceError {
            throw error
        } catch let error as URLError {
            throw GeminiServiceError.networkError(error)
        } catch {
            throw GeminiServiceError.networkError(error)
        }
    }

    private static func apiErrorMessage(from data: Data, fallback: String) -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.isEmpty
        else {
            return fallback
        }

        return message
    }

    private func limpiarFormato(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                    return String(trimmed.dropFirst(2))
                }
                return trimmed
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extrae números de párrafos del formato [Párrafo X]
    private func extraerCitas(from text: String) -> [CitaExtraida] {
        var citas: [CitaExtraida] = []
        
        // Buscar patrones como [Párrafo 15] o [paragraph 42]
        let patterns = [
            "\\[Párrafo\\s+(\\d+)\\]",
            "\\[paragraph\\s+(\\d+)\\]",
            "\\[parrafo\\s+(\\d+)\\]",
            "Párrafo\\s+(\\d+)",
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)
                
                for match in matches {
                    if let range = Range(match.range(at: 1), in: text),
                       let numero = Int(String(text[range])) {
                        citas.append(CitaExtraida(parrafo: numero, texto: ""))
                    }
                }
            }
        }
        
        return citas
    }
}
