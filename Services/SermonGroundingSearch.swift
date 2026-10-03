import Foundation

struct GroundedSermonPassage: Identifiable {
    let code: String
    let title: String
    let paragraphNumber: Int
    let text: String
    let score: Int

    var id: String { "\(code)-\(paragraphNumber)" }
}

enum SermonGroundingSearch {
    private static let stopWords: Set<String> = [
        "a", "al", "algo", "como", "con", "cual", "cuando", "de", "del", "donde",
        "el", "ella", "ellas", "ellos", "en", "es", "esa", "ese", "eso", "esta", "este",
        "la", "las", "lo", "los", "me", "mi", "mis", "para", "por", "que", "se", "sobre",
        "su", "sus", "un", "una", "uno", "y", "the", "a", "an", "and", "are", "as", "at",
        "be", "by", "for", "from", "how", "in", "is", "it", "of", "on", "or", "that", "this",
        "to", "was", "what", "when", "where", "which", "who", "with"
    ]

    static func hasVerifiedCitations(in response: String, passages: [GroundedSermonPassage]) -> Bool {
        let allowedReferences = Set(passages.map {
            "\($0.code.lowercased())|\($0.paragraphNumber)"
        })
        let pattern = #"\[([A-Za-z0-9-]+),\s*párrafo\s+(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }

        let range = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, range: range)
        guard !matches.isEmpty else { return false }

        return matches.allSatisfy { match in
            guard let codeRange = Range(match.range(at: 1), in: response),
                  let paragraphRange = Range(match.range(at: 2), in: response),
                  let paragraphNumber = Int(response[paragraphRange]) else {
                return false
            }
            return allowedReferences.contains("\(response[codeRange].lowercased())|\(paragraphNumber)")
        }
    }

    static func retrieve(
        query: String,
        sermons: [SermonRecord],
        limit: Int = 12,
        perSermonLimit: Int = 3
    ) -> [GroundedSermonPassage] {
        let queryTokens = tokens(in: query)
        let queryKey = alphanumericKey(query)
        guard !queryTokens.isEmpty || !queryKey.isEmpty else { return [] }

        let passages = sermons.flatMap { sermon -> [GroundedSermonPassage] in
            let titleTokens = tokens(in: sermon.title)
            let codeKey = alphanumericKey(sermon.code)
            let codeMatches = !codeKey.isEmpty && queryKey.contains(codeKey)

            return sermon.body
                .components(separatedBy: "\n\n")
                .enumerated()
                .compactMap { offset, rawText in
                    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }

                    let paragraphTokens = tokens(in: text)
                    let titleMatches = queryTokens.intersection(titleTokens).count
                    let textMatches = queryTokens.intersection(paragraphTokens).count
                    let score = titleMatches * 3 + textMatches + (codeMatches ? 12 : 0)
                    guard score > 0 else { return nil }

                    return GroundedSermonPassage(
                        code: sermon.code,
                        title: sermon.title,
                        paragraphNumber: offset + 1,
                        text: text,
                        score: score
                    )
                }
        }

        let sorted = passages.sorted { first, second in
            if first.score != second.score { return first.score > second.score }
            if first.code != second.code { return first.code < second.code }
            return first.paragraphNumber < second.paragraphNumber
        }

        var countBySermon: [String: Int] = [:]
        return sorted.filter { passage in
            let count = countBySermon[passage.code, default: 0]
            guard count < perSermonLimit else { return false }
            countBySermon[passage.code] = count + 1
            return true
        }.prefix(limit).map { $0 }
    }

    private static func tokens(in value: String) -> Set<String> {
        Set(value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) })
    }

    private static func alphanumericKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}