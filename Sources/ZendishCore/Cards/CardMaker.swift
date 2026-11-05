import Foundation

/// The outcome of reading one recipe's images.
public struct MadeCard: Equatable, Sendable {
    public var recipe: Recipe
    public var flags: [CardFlag]
    public var cleared: [String]
    public var sourceText: String
    /// False when the images don't seem to contain a recipe.
    public var hasRecipe: Bool
}

/// Takes images through text recognition, the model and the card checks.
public struct CardMaker: Sendable {
    private let recognizer: TextRecognizer
    private let writer: any CardWriter

    public init(recognizer: TextRecognizer = TextRecognizer(), writer: any CardWriter = OllamaClient()) {
        self.recognizer = recognizer
        self.writer = writer
    }

    public func makeCard(from images: [URL]) async throws -> MadeCard {
        let text = try await recognizer.text(from: images)
        return try await makeCard(fromText: text, imageNames: images.map(\.lastPathComponent))
    }

    public func makeCard(fromText text: String, imageNames: [String] = []) async throws -> MadeCard {
        guard CardChecks.hasRecipe(in: text) else {
            return MadeCard(recipe: Recipe(imageNames: imageNames), flags: [], cleared: [], sourceText: text, hasRecipe: false)
        }
        let draft = try await writer.writeCard(from: text)
        let checked = CardChecks.check(draft, against: text)
        let card = checked.draft
        let recipe = Recipe(
            title: card.title,
            ingredients: card.ingredients.map { Ingredient(text: $0) },
            steps: card.steps,
            totalTime: card.totalTime,
            prepTime: card.prepTime,
            cookTime: card.cookTime,
            servings: card.servings,
            imageNames: imageNames
        )
        return MadeCard(recipe: recipe, flags: checked.flags, cleared: checked.cleared, sourceText: text, hasRecipe: draft.isRecipe)
    }
}
