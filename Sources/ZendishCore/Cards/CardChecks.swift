import Foundation

/// Something on a card that a person should look at. Flags never change the card by themselves.
public enum CardFlag: Equatable, Hashable, Sendable, Codable {
    /// A quantity looks misread, such as "11/2" for "1 1/2".
    case checkQuantity(line: String, suggestion: String)
    /// A line that looks like an ingredient is in the image but not on the card.
    case missingLine(String)
}

public struct CheckedCard: Equatable, Sendable {
    public var draft: CardDraft
    public var flags: [CardFlag]
    /// Details that were removed because the text doesn't support them.
    public var cleared: [String]
}

/// Plain-code checks that catch what a small model gets wrong. They use no AI, so they behave
/// the same way every time.
public enum CardChecks {
    /// True when the text has too few ingredient-like lines to be a recipe, so it isn't worth
    /// running the model at all.
    public static func hasRecipe(in text: String) -> Bool {
        ingredientLines(in: lines(of: text)).count >= 2
    }

    public static func check(_ card: CardDraft, against text: String) -> CheckedCard {
        let source = lines(of: text)
        var draft = card
        var flags: [CardFlag] = []
        var cleared: [String] = []

        draft.ingredients = card.ingredients.map(RecipeText.withoutMarker).filter { !$0.isEmpty }
        draft.steps = card.steps.map(RecipeText.withoutMarker).filter { !$0.isEmpty }

        func clear(_ value: inout String?, _ name: String) {
            if let text = value {
                cleared.append("\(name): \(text)")
                value = nil
            }
        }

        if let value = draft.totalTime, !isLabelled(value, by: Label.total, in: source) { clear(&draft.totalTime, "Total time") }
        if let value = draft.prepTime, !isLabelled(value, by: Label.prep, in: source) { clear(&draft.prepTime, "Prep time") }
        if let value = draft.cookTime, !isLabelled(value, by: Label.cook, in: source) { clear(&draft.cookTime, "Cook time") }
        if let value = draft.servings, !isLabelled(value, by: Label.servings, in: source) { clear(&draft.servings, "Servings") }

        if let title = draft.title {
            let isPlaceholder = ["recipe", "ingredients", "method", "directions", "instructions"].contains(RecipeText.normalized(title))
            if isPlaceholder || RecipeText.overlap(of: title, in: text) < 1 { clear(&draft.title, "Title") }
        }

        for line in draft.ingredients {
            if let suggestion = fractionSuggestion(for: line) {
                flags.append(.checkQuantity(line: line, suggestion: suggestion))
            }
        }
        flags += missingLines(from: source, card: draft).map(CardFlag.missingLine)
        return CheckedCard(draft: draft, flags: flags, cleared: cleared)
    }

    // MARK: Labels

    private enum Label {
        static var total: Regex<(Substring, Substring)> { /(?i)\b(total|ready in)\b/ }
        static var prep: Regex<(Substring, Substring)> { /(?i)\b(prep|preparation)\b/ }
        static var cook: Regex<(Substring, Substring)> { /(?i)\b(cook|cooking|bake|baking)\b/ }
        static var servings: Regex<(Substring, Substring)> { /(?i)\b(serves?|servings?|yields?|makes|portions?)\b/ }
    }

    /// A value counts only when it sits on, or just below, its own short label. This stops
    /// video timers, like counts and times from inside the method being used.
    private static func isLabelled(_ value: String, by label: some RegexComponent, in lines: [String]) -> Bool {
        let wanted = Set(RecipeText.numbers(in: value))
        guard !wanted.isEmpty else { return false }
        for (index, line) in lines.enumerated() where line.count <= 60 {
            if line.contains(/(?i)\b(likes?|views?|comments?|followers?|shares?|reviews?|ratings?|stars?)\b/) { continue }
            guard wanted.isSubset(of: Set(RecipeText.numbers(in: line))) else { continue }
            let nearby = lines[max(0, index - 3)..<index].filter { $0.count <= 30 }
            if isLabelLine(line, label) || nearby.contains(where: { isLabelLine($0, label) }) {
                return true
            }
        }
        return false
    }

    private static func isLabelLine(_ line: String, _ label: some RegexComponent) -> Bool {
        guard line.contains(label) else { return false }
        // Rules out method lines such as "Bake for 30 minutes".
        return line.count <= 30 && line.split(separator: " ").count <= 6 && !line.lowercased().contains(" for ")
    }

    // MARK: Ingredient lines

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { RecipeText.withoutCheckbox(RecipeText.withoutMarker(String($0))) }.filter { !$0.isEmpty }
    }

    private static func ingredientLines(in lines: [String]) -> [String] {
        lines.filter(isIngredientLike)
    }

    private static func isIngredientLike(_ line: String) -> Bool {
        guard line.count <= 75, line.filter(\.isLetter).count >= 3 else { return false }
        if line.contains(/(?i)\b(min|mins|minutes|hours?|reviews?|stars?|likes?|comments?|views?|calories|kcal|protein|fat|carbs?|sugars?\s+\d)\b/) { return false }
        let startsWithAmount = line.contains(/(?i)^(\d|[½¼¾⅓⅔⅛]|a pinch|pinch|a splash|a knob)/)
        let hasUnit = line.contains(/(?i)(?:\b|\d)(g|kg|ml|l|oz|lb|cups?|tbsp|tsp|t|tablespoons?|teaspoons?|cloves?|cans?|sheets?|pinch|bulb|sticks?|stalks?|leaves|slices?|limes?|lemons?|eggs?|onions?|carrots?)\b/)
        // "1 Put the wedges into a glass" is a method step, not an ingredient.
        let readsLikeStep = line.contains(/^\d+\s+(?-i:[A-Z])[a-z]+\s+(the|a|in|into|your)\b/)
        return startsWithAmount && hasUnit && !readsLikeStep
    }

    /// Looks only between the top of the ingredient list and the start of the method, which
    /// leaves out sidebars, ads and related recipes.
    private static func missingLines(from lines: [String], card: CardDraft) -> [String] {
        let onCard = card.ingredients
        guard let firstMatch = lines.firstIndex(where: { line in
            onCard.contains { RecipeText.overlap(of: line, in: $0) >= 0.7 }
        }) else { return [] }
        let heading = lines[..<firstMatch].lastIndex { ["ingredients", "ingredient"].contains(RecipeText.normalized($0)) }
        let start = heading ?? firstMatch
        var end = lines.count
        if let firstStep = card.steps.first,
           let found = lines[firstMatch...].firstIndex(where: { RecipeText.overlap(of: $0, in: firstStep) >= 0.8 && !isIngredientLike($0) }) {
            end = found
        }
        guard start < end else { return [] }
        return lines[start..<end].filter { line in
            isIngredientLike(line) && !onCard.contains { RecipeText.overlap(of: line, in: $0) >= 0.7 }
        }
    }

    private static func fractionSuggestion(for line: String) -> String? {
        guard let match = line.firstMatch(of: /(^|[\s(])([1-9])([1-9]\/[2-8])\b/) else { return nil }
        return line.replacingCharacters(in: match.range, with: "\(match.1)\(match.2) \(match.3)")
    }
}

extension RecipeText {
    /// Text recognition reads a ticked or empty checkbox as a leading "O" or "o".
    static func withoutCheckbox(_ line: String) -> String {
        line.replacing(/^[Oo0☐□]\s+(?=[\d½¼¾⅓⅔⅛])/, with: "")
    }
}

private extension String {
    func replacingCharacters(in range: Range<String.Index>, with replacement: String) -> String {
        var copy = self
        copy.replaceSubrange(range, with: replacement)
        return copy
    }
}
