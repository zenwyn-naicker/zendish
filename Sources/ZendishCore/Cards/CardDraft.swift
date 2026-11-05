import Foundation

/// The card as the model wrote it, before any checks.
public struct CardDraft: Equatable, Sendable, Decodable {
    public var isRecipe: Bool
    public var title: String?
    public var ingredients: [String]
    public var steps: [String]
    public var totalTime: String?
    public var prepTime: String?
    public var cookTime: String?
    public var servings: String?

    public init(
        isRecipe: Bool = true, title: String? = nil, ingredients: [String] = [], steps: [String] = [],
        totalTime: String? = nil, prepTime: String? = nil, cookTime: String? = nil, servings: String? = nil
    ) {
        self.isRecipe = isRecipe
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.totalTime = totalTime
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.servings = servings
    }

    private enum CodingKeys: String, CodingKey {
        case isRecipe = "is_recipe"
        case title, ingredients, steps
        case totalTime = "total_time"
        case prepTime = "prep_time"
        case cookTime = "cook_time"
        case servings
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func detail(_ key: CodingKeys) throws -> String? {
            Self.cleaned(try values.decodeIfPresent(String.self, forKey: key))
        }
        isRecipe = try values.decodeIfPresent(Bool.self, forKey: .isRecipe) ?? true
        title = try detail(.title)
        ingredients = try values.decodeIfPresent([String].self, forKey: .ingredients) ?? []
        steps = try values.decodeIfPresent([String].self, forKey: .steps) ?? []
        totalTime = try detail(.totalTime)
        prepTime = try detail(.prepTime)
        cookTime = try detail(.cookTime)
        servings = try detail(.servings)
    }

    /// Small models sometimes write the word "null" instead of leaving a detail empty.
    private static func cleaned(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !["null", "none", "n/a"].contains(text.lowercased()) else { return nil }
        return text
    }
}

/// Anything that can turn recognised text into a card.
public protocol CardWriter: Sendable {
    func writeCard(from text: String) async throws -> CardDraft
}
