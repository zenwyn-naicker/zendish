import Foundation

/// Helpers for comparing recipe text, so that "1 ½ Cups" and "1 1/2 cups" count as the same.
enum RecipeText {
    private static let fractions: [(String, String)] = [
        ("½", "1/2"), ("¼", "1/4"), ("¾", "3/4"), ("⅓", "1/3"), ("⅔", "2/3"),
        ("⅛", "1/8"), ("⅜", "3/8"), ("⅝", "5/8"), ("⅞", "7/8"),
    ]
    private static let ignored: Set<String> = [
        "a", "an", "the", "of", "and", "or", "to", "in", "on", "with", "for", "into", "then", "until", "your", "it", "is", "at",
    ]

    static func normalized(_ text: String) -> String {
        var result = text
        for (glyph, plain) in fractions {
            result = result.replacingOccurrences(of: glyph, with: " \(plain)")
        }
        result = result.replacingOccurrences(of: "⁄", with: "/")
            .replacingOccurrences(of: "–", with: "-")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9/.\- ]+"#, with: " ", options: .regularExpression)
        return result.split(separator: " ").joined(separator: " ")
    }

    static func numbers(in text: String) -> [String] {
        let source = normalized(text)
        return source.matches(of: /\d+(?:[.\/]\d+)?/).map { String(source[$0.range]) }
    }

    /// Removes a leading bullet or step number.
    static func withoutMarker(_ line: String) -> String {
        line.replacing(/^\s*(?:[-*•◦▪]|\d+[.)])\s+/, with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func keyWords(_ text: String) -> Set<String> {
        var words = Set<String>()
        for raw in normalized(text).split(separator: " ") {
            let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            guard !word.isEmpty, !ignored.contains(word) else { continue }
            words.insert(word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word)
        }
        return words
    }

    /// The share of `needle`'s words found in `haystack`, from 0 to 1.
    static func overlap(of needle: String, in haystack: String) -> Double {
        let wanted = keyWords(needle)
        guard !wanted.isEmpty else { return 1 }
        return Double(wanted.intersection(keyWords(haystack)).count) / Double(wanted.count)
    }
}
