import Foundation
import Testing
@testable import ZendishCore

@Suite struct CardChecksTests {
    private let page = """
    Golden Soup
    Prep
    12 min
    Cook
    18 min
    Serves 2
    2,418 likes
    00:12 / 00:38
    Ingredients
    2 small leeks, sliced
    11/2 tbsp olive oil
    For the sauce
    3 tbsp walnut oil
    1 tsp honey
    Method
    1. Warm the oil in a pan.
    2. Bake for 40 minutes.
    You may also like
    2 cups lettuce
    """

    @Test func anyMisreadFractionGetsASuggestion() {
        let card = CardDraft(ingredients: ["11/2 tbsp olive oil"])
        let flags = CardChecks.check(card, against: page).flags
        #expect(flags.contains(.checkQuantity(line: "11/2 tbsp olive oil", suggestion: "1 1/2 tbsp olive oil")))
    }

    @Test func ordinaryQuantitiesAreNotFlagged() {
        let card = CardDraft(ingredients: ["1 1/2 cups milk", "1/2 tsp salt", "12 eggs", "2.5 l stock"])
        let flags = CardChecks.check(card, against: "").flags
        #expect(flags.isEmpty)
    }

    @Test func droppedSectionsAreFlaggedButRelatedRecipesAreNot() {
        let card = CardDraft(
            ingredients: ["2 small leeks, sliced", "11/2 tbsp olive oil"],
            steps: ["Warm the oil in a pan.", "Bake for 40 minutes."]
        )
        let flags = CardChecks.check(card, against: page).flags
        #expect(flags.contains(.missingLine("3 tbsp walnut oil")))
        #expect(flags.contains(.missingLine("1 tsp honey")))
        #expect(!flags.contains(.missingLine("2 cups lettuce")))
    }

    @Test func aLineSplitInTwoOnTheCardIsNotReportedMissing() {
        let text = "Ingredients\n250 g cake flour, plus extra for dusting\n2 large eggs\nMethod\nMix well."
        let card = CardDraft(ingredients: ["250 g cake flour", "extra for dusting", "2 large eggs"], steps: ["Mix well."])
        #expect(CardChecks.check(card, against: text).flags.isEmpty)
    }

    @Test func labelledDetailsAreKept() {
        let card = CardDraft(prepTime: "12 min", cookTime: "18 min", servings: "2")
        let checked = CardChecks.check(card, against: page)
        #expect(checked.draft.prepTime == "12 min")
        #expect(checked.draft.cookTime == "18 min")
        #expect(checked.draft.servings == "2")
        #expect(checked.cleared.isEmpty)
    }

    @Test func unlabelledDetailsAreCleared() {
        let card = CardDraft(totalTime: "00:12 / 00:38", cookTime: "40 minutes", servings: "2,418")
        let checked = CardChecks.check(card, against: page)
        #expect(checked.draft.totalTime == nil)
        #expect(checked.draft.cookTime == nil)
        #expect(checked.draft.servings == nil)
        #expect(checked.cleared.count == 3)
    }

    @Test func prepTimeCannotBecomeTotalTime() {
        let checked = CardChecks.check(CardDraft(totalTime: "12 min"), against: page)
        #expect(checked.draft.totalTime == nil)
    }

    @Test func placeholderAndInventedTitlesAreCleared() {
        #expect(CardChecks.check(CardDraft(title: "Recipe"), against: page).draft.title == nil)
        #expect(CardChecks.check(CardDraft(title: "Beef Curry"), against: page).draft.title == nil)
        #expect(CardChecks.check(CardDraft(title: "Golden Soup"), against: page).draft.title == "Golden Soup")
    }

    @Test func stepNumbersAndBulletsAreRemoved() {
        let card = CardDraft(ingredients: ["• 2 eggs"], steps: ["1. Beat the eggs.", "2) Fry."])
        let draft = CardChecks.check(card, against: page).draft
        #expect(draft.ingredients == ["2 eggs"])
        #expect(draft.steps == ["Beat the eggs.", "Fry."])
    }

    @Test func textWithoutARecipeIsRecognised() {
        #expect(CardChecks.hasRecipe(in: page))
        #expect(!CardChecks.hasRecipe(in: "Dinner was amazing! Recipe soon. 2,418 likes"))
    }
}

@Suite struct CardMakerTests {
    struct FixedWriter: CardWriter {
        let draft: CardDraft
        func writeCard(from text: String) async throws -> CardDraft { draft }
    }

    struct FailingWriter: CardWriter {
        func writeCard(from text: String) async throws -> CardDraft { throw OllamaError.notRunning }
    }

    @Test func imagesWithoutARecipeNeverReachTheModel() async throws {
        let maker = CardMaker(writer: FailingWriter())
        let card = try await maker.makeCard(fromText: "A lovely sunset", imageNames: ["a.png"])
        #expect(!card.hasRecipe)
        #expect(card.recipe.imageNames == ["a.png"])
    }

    @Test func aCheckedCardBecomesARecipeToReview() async throws {
        let text = "Soup\nServes 2\n11/2 cups stock\n2 tsp salt\nStir well."
        let draft = CardDraft(title: "Soup", ingredients: ["11/2 cups stock"], steps: ["Stir well."], totalTime: "1 hour", servings: "2")
        let card = try await CardMaker(writer: FixedWriter(draft: draft)).makeCard(fromText: text)

        #expect(card.recipe.status == .needsReview)
        #expect(card.recipe.title == "Soup")
        #expect(card.recipe.totalTime == nil)
        #expect(card.recipe.servings == "2")
        #expect(card.flags.contains(.checkQuantity(line: "11/2 cups stock", suggestion: "1 1/2 cups stock")))
        #expect(card.flags.contains(.missingLine("2 tsp salt")))
    }
}
