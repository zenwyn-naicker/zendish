import Foundation

/// A recipe card. Any detail missing from the source stays `nil` rather than being guessed,
/// and text is kept exactly as written, including quantities such as "1 ½ cups".
public struct Recipe: Identifiable, Equatable, Sendable {
    public enum Status: String, Sendable {
        /// Waiting for, or going through, text recognition and the model.
        case reading
        case needsReview
        case saved
    }

    public var id: UUID
    public var title: String?
    public var ingredients: [Ingredient]
    public var steps: [String]
    public var totalTime: String?
    public var prepTime: String?
    public var cookTime: String?
    public var servings: String?
    /// File names of the original images, in reading order.
    public var imageNames: [String]
    /// File name of the cropped photo shown on the card, if one was chosen.
    public var coverName: String?
    public var status: Status
    /// What the card checks want a person to look at.
    public var flags: [CardFlag]
    /// The text read from the images, kept so the card can be rebuilt or searched.
    public var sourceText: String?
    /// Why the card couldn't be made, in words a person can act on.
    public var problem: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        ingredients: [Ingredient] = [],
        steps: [String] = [],
        totalTime: String? = nil,
        prepTime: String? = nil,
        cookTime: String? = nil,
        servings: String? = nil,
        imageNames: [String] = [],
        coverName: String? = nil,
        status: Status = .needsReview,
        flags: [CardFlag] = [],
        sourceText: String? = nil,
        problem: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.totalTime = totalTime
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.servings = servings
        self.imageNames = imageNames
        self.coverName = coverName
        self.status = status
        self.flags = flags
        self.sourceText = sourceText
        self.problem = problem
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension Recipe {
    /// Servings ready to show. Cards may hold just a number, which means nothing on its own.
    var servingsText: String? {
        guard let servings else { return nil }
        return servings.contains(/^[\d\s\-–]+$/) ? "Serves \(servings)" : servings
    }
}

/// One ingredient line, with the sub-heading it sits under, such as "For the sauce".
public struct Ingredient: Equatable, Sendable {
    public var text: String
    public var section: String?

    /// The line split into its amount and the rest, so amounts can line up in a column. The
    /// text itself is never changed, and a line with no clear amount has a nil quantity.
    public var parts: (quantity: String?, name: String) {
        if let pinch = text.firstMatch(of: /(?i)^(a )?pinch of (.+)$/) {
            return ("Pinch", String(pinch.2))
        }
        let pattern = /(?i)^((?:\d[\d\s.,\/\-–]*|[¼½¾⅓⅔⅛]\s*)[¼½¾⅓⅔⅛]?\s*(?:(?:g|kg|ml|l|oz|lb|lbs|cups?|tbsp|tsp|t|tablespoons?|teaspoons?|cloves?|cans?|parts?|sheets?|pinch(?:es)?)\b)?(?:\s*\/\s*\d[\d.]*\s*(?:g|kg|ml|l|oz|lb)\b)?)\s*(.+)$/
        guard let match = text.firstMatch(of: pattern) else { return (nil, text) }
        let quantity = String(match.1).trimmingCharacters(in: .whitespaces)
        let name = String(match.2)
        guard !quantity.isEmpty, name.first?.isLetter == true || name.first == "(" else { return (nil, text) }
        return (quantity, name)
    }

    public init(text: String, section: String? = nil) {
        self.text = text
        self.section = section
    }
}
