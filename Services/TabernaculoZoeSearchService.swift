import Foundation

struct TabernaculoZoeSearchResult: Identifiable {
    let messageID: String
    let title: String
    let code: String
    let paragraphNumber: Int
    let text: String

    var id: String { "\(messageID)-\(paragraphNumber)" }
}

struct ZoeSermonSummary: Identifiable, Hashable {
    let messageID: String
    let title: String
    let code: String
    let location: String
    let origin: String
    let audioURL: String?

    var id: String { messageID }
}

struct ZoeSermonParagraph: Identifiable, Hashable {
    let number: Int
    let text: String

    var id: Int { number }
}

enum TabernaculoZoeSearchError: Error, LocalizedError {
    case invalidResponse
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "La fuente devolvió una respuesta que no se pudo leer."
        case .requestFailed: "No se pudo consultar Tabernáculo Zoe."
        }
    }
}

final class TabernaculoZoeSearchService {
    static let sourceURL = URL(string: "https://tabernaculozoe.org/dove/index_zoe")!
    static let officialCatalogURL = URL(string: "https://themessage.com/es/sermonsdownload")!
    private let catalogEndpoint = URL(string: "https://tabernaculozoe.org/dove/controller/list_by_date.php")!
    private let searchEndpoint = URL(string: "https://tabernaculozoe.org/dove/controller/search_message_1.php")!
    private let messageEndpoint = URL(string: "https://tabernaculozoe.org/dove/controller/show_message.php")!

    private static let stopWords: Set<String> = [
        "a", "al", "algo", "como", "con", "cual", "cuando", "cuanto", "de", "del", "desde",
        "donde", "el", "ella", "ellas", "ellos", "en", "es", "esa", "ese", "eso", "esta",
        "este", "la", "las", "lo", "los", "mas", "me", "mi", "mis", "para", "por", "que",
        "se", "sin", "sobre", "su", "sus", "un", "una", "uno", "y", "yo", "dijo", "dice",
        "decir", "habla", "hablar", "enseña", "enseñó", "enseñar", "explica", "explicó", "segun",
        "branham", "william", "sermon", "sermones", "mensaje", "mensajes", "pregunta", "preguntas",
        "podria", "podrias", "dime", "qué", "quién", "cuál", "cuáles", "does", "what", "about",
        "tell", "said", "says", "sermon", "message", "please", "the", "and", "for", "with"
    ]

    func loadCatalog() async throws -> [ZoeSermonSummary] {
        let data = try await post(to: catalogEndpoint, parameters: [:])
        return try Self.decodeCatalog(from: data)
    }

    func loadSermon(messageID: String) async throws -> [ZoeSermonParagraph] {
        let data = try await post(to: messageEndpoint, parameters: ["id": messageID])
        return try Self.decodeMessageParagraphs(from: data, messageID: messageID)
    }

    static func decodeCatalog(from data: Data) throws -> [ZoeSermonSummary] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = payload["state"] as? Int,
              state == 1,
              let records = payload["resultado"] as? [[String: Any]] else {
            throw TabernaculoZoeSearchError.invalidResponse
        }

        return records.compactMap { record in
            guard let messageID = stringValue(record["MessageId"]),
                  let title = stringValue(record["Title"]),
                  let code = stringValue(record["Date"]) else { return nil }
            return ZoeSermonSummary(
                messageID: messageID,
                title: title,
                code: code,
                location: stringValue(record["Lugar"]) ?? "",
                origin: stringValue(record["Origen"]) ?? "",
                audioURL: stringValue(record["urlAudio"]).flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    static func decodeMessageParagraphs(from data: Data, messageID: String) throws -> [ZoeSermonParagraph] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = payload["state"] as? Int,
              state == 1,
              let records = payload["resultado"] as? [[String: Any]] else {
            throw TabernaculoZoeSearchError.invalidResponse
        }

        return records.compactMap { record in
            guard stringValue(record["MessageId"]) == messageID,
                  let numberValue = record["Number"],
                  let number = Int(String(describing: numberValue)),
                  let text = record["Content"] as? String,
                  !text.isEmpty else { return nil }
            return ZoeSermonParagraph(number: number, text: text)
        }
        .sorted { $0.number < $1.number }
    }

    func search(query: String, limit: Int = 5) async throws -> [TabernaculoZoeSearchResult] {
        guard limit > 0 else { return [] }
        let requiredTerms = Self.queryTerms(for: query)
        guard !requiredTerms.isEmpty else { return [] }
        var completeResults: [TabernaculoZoeSearchResult] = []
        var seenParagraphs = Set<String>()

        for variant in Self.queryVariants(for: query) {
            let data = try await post(to: searchEndpoint, parameters: ["text": variant])
            let matches = try Self.decodeResults(from: data, limit: 40)
            var processedMessages = Set<String>()

            for match in matches {
                guard processedMessages.insert(match.messageID).inserted else { continue }
                let fullMessage = try await post(
                    to: messageEndpoint,
                    parameters: ["id": match.messageID]
                )
                let paragraphs = try Self.decodeFullParagraphs(
                    from: fullMessage,
                    messageID: match.messageID,
                    titleFallback: match.title,
                    codeFallback: match.code,
                    containing: requiredTerms
                )
                for paragraph in paragraphs where seenParagraphs.insert(paragraph.id).inserted {
                    completeResults.append(paragraph)
                    if completeResults.count >= limit { return completeResults }
                }
                if processedMessages.count >= 5 { break }
            }
        }

        return completeResults
    }

    static func queryVariants(for query: String) -> [String] {
        let tokens = tokenize(query)
        let meaningfulTokens = queryTerms(for: query)
        let searchableTokens = meaningfulTokens.filter { $0.count > 2 }
        var variants: [String] = []
        if meaningfulTokens.count > 1 {
            variants.append(meaningfulTokens.prefix(5).joined(separator: " "))
        }
        variants.append(contentsOf: searchableTokens.sorted { $0.count > $1.count }.prefix(4))

        if tokens.contains("fe") {
            variants.append(contentsOf: ["creencia", "creer"])
        }

        var seen = Set<String>()
        return variants.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(6).map { $0 }
    }

    static func queryTerms(for query: String) -> [String] {
        let normalizedStopWords = Set(stopWords.map { tokenize($0).joined() })
        return tokenize(query).filter {
            !normalizedStopWords.contains($0) && ($0.count > 2 || $0 == "fe")
        }
    }

    static func matchesQueryTerms(_ query: String, in paragraph: String) -> Bool {
        let terms = queryTerms(for: query)
        guard !terms.isEmpty else { return false }
        let paragraphTerms = Set(tokenize(paragraph))
        return terms.allSatisfy { paragraphTerms.contains($0) }
    }

    private static func tokenize(_ value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func post(to endpoint: URL, parameters: [String: String]) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TabernaculoZoeSearchError.requestFailed
        }
        return data
    }

    static func decodeResults(from data: Data, limit: Int = 5) throws -> [TabernaculoZoeSearchResult] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = payload["state"] as? Int,
              state == 1,
              let records = payload["resultado"] as? [[String: Any]] else {
            throw TabernaculoZoeSearchError.invalidResponse
        }

        return records.compactMap { record in
            guard let messageID = record["MessageId"] as? String,
                  let title = record["Title"] as? String,
                  let code = record["Date"] as? String,
                  let number = record["Number"] as? String,
                  let paragraphNumber = Int(number),
                  let text = record["Content"] as? String,
                  !text.isEmpty else {
                return nil
            }

            return TabernaculoZoeSearchResult(
                messageID: messageID,
                title: title,
                code: code,
                paragraphNumber: paragraphNumber,
                text: text
            )
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    static func decodeFullParagraphs(
        from data: Data,
        messageID: String,
        titleFallback: String,
        codeFallback: String,
        containing requiredTerms: [String]
    ) throws -> [TabernaculoZoeSearchResult] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = payload["state"] as? Int,
              state == 1,
              let records = payload["resultado"] as? [[String: Any]] else {
            throw TabernaculoZoeSearchError.invalidResponse
        }

        return records.compactMap { record in
            guard let returnedMessageID = Self.stringValue(record["MessageId"]),
                  returnedMessageID == messageID,
                  let numberValue = record["Number"],
                  let number = Int(String(describing: numberValue)),
                  let text = record["Content"] as? String,
                  !text.isEmpty else { return nil }

            let paragraphTerms = Set(tokenize(text))
            guard requiredTerms.allSatisfy({ paragraphTerms.contains($0) }) else { return nil }
            return TabernaculoZoeSearchResult(
                messageID: returnedMessageID,
                title: Self.stringValue(record["Title"]) ?? titleFallback,
                code: Self.stringValue(record["Date"]) ?? codeFallback,
                paragraphNumber: number,
                text: text
            )
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}