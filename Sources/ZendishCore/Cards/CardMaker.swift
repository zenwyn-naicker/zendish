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
    private let reader: any TextReader
    private let writer: any CardWriter

    public init(reader: any TextReader = TextRecognizer(), writer: any CardWriter = OllamaClient()) {
        self.reader = reader
        self.writer = writer
    }

    public func makeCard(from images: [URL]) async throws -> MadeCard {
        let text = try await reader.text(from: images)
        return try await makeCard(fromText: text, imageNames: images.map(\.lastPathComponent))
    }

    public func makeCard(fromText text: String, imageNames: [String] = []) async throws -> MadeCard {
        guard CardChecks.hasRecipe(in: text) else {
            let recipe = Recipe(imageNames: imageNames, flags: [.noRecipe], sourceText: text)
            return MadeCard(recipe: recipe, flags: [.noRecipe], cleared: [], sourceText: text, hasRecipe: false)
        }
        var draft = try await writer.writeCard(from: text)
        // The text has ingredient lines, so an empty card is a slip by the model. Small models
        // do this now and then on the same text, and a second try usually works.
        if draft.ingredients.isEmpty || draft.steps.isEmpty {
            let second = try await writer.writeCard(from: text)
            if second.ingredients.count + second.steps.count > draft.ingredients.count + draft.steps.count {
                draft = second
            }
        }
        let checked = CardChecks.check(draft, against: text)
        let card = checked.draft
        let recipe = Recipe(
            title: card.title,
            ingredients: CardChecks.ingredients(from: card.ingredients),
            steps: card.steps,
            totalTime: card.totalTime,
            prepTime: card.prepTime,
            cookTime: card.cookTime,
            servings: card.servings,
            imageNames: imageNames,
            flags: draft.isRecipe ? checked.flags : [.noRecipe],
            sourceText: text
        )
        return MadeCard(recipe: recipe, flags: recipe.flags, cleared: checked.cleared, sourceText: text, hasRecipe: draft.isRecipe)
    }
}
