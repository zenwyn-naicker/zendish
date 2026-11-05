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
        let card = CardDraft(title: "Stock", ingredients: ["1 1/2 cups milk", "1/2 tsp salt", "12 eggs", "2.5 l stock"])
        let flags = CardChecks.check(card, against: "Stock").flags
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
        let text = "Cake\nIngredients\n250 g cake flour, plus extra for dusting\n2 large eggs\nMethod\nMix well."
        let card = CardDraft(title: "Cake", ingredients: ["250 g cake flour", "extra for dusting", "2 large eggs"], steps: ["Mix well."])
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

    @Test func siteLogosAreNotUsedAsTitles() {
        let text = "goodfood\nRecipetineats\nChakalaka\n2 cups beans\n1 tsp salt"
        #expect(CardChecks.check(CardDraft(title: "goodfood", ingredients: ["2 cups beans"]), against: text).draft.title == nil)
        #expect(CardChecks.check(CardDraft(title: "Recipetineats"), against: text).draft.title == nil)
        #expect(CardChecks.check(CardDraft(title: "Chakalaka"), against: text).draft.title == "Chakalaka")
    }

    @Test func aMissingTitleAsksForOne() {
        let card = CardDraft(ingredients: ["2 cups stock"])
        #expect(CardChecks.check(card, against: page).flags.contains(.needsTitle))
        let named = CardDraft(title: "Golden Soup", ingredients: ["2 cups stock"])
        #expect(!CardChecks.check(named, against: page).flags.contains(.needsTitle))
    }

    @Test func splitNotesJoinTheIngredientAbove() {
        let card = CardDraft(ingredients: [
            "225g self-raising flour", "preferably organic", "50g slightly salted butter", "chilled, cut in small pieces",
            "a little extra flour", "for dusting", "strawberry jam and clotted cream, to serve",
        ])
        #expect(CardChecks.check(card, against: "").draft.ingredients == [
            "225g self-raising flour, preferably organic",
            "50g slightly salted butter, chilled, cut in small pieces",
            "a little extra flour, for dusting",
            "strawberry jam and clotted cream, to serve",
        ])
    }

    @Test func shoutedTitlesAreCalmedDown() {
        let draft = CardChecks.check(CardDraft(title: "MILK TART"), against: "MILK TART").draft
        #expect(draft.title == "Milk Tart")
    }

    @Test func subHeadingsBecomeSections() {
        let lines = ["SPICE PASTE", "2 tbsp oil", "Filling", "1 onion", "For the sauce", "1 tsp honey", "Salt, to taste"]
        #expect(CardChecks.ingredients(from: lines) == [
            Ingredient(text: "2 tbsp oil", section: "Spice Paste"),
            Ingredient(text: "1 onion", section: "Filling"),
            Ingredient(text: "1 tsp honey", section: "For the sauce"),
            Ingredient(text: "Salt, to taste", section: "For the sauce"),
        ])
    }

    @Test func ordinaryIngredientsAreNotMistakenForHeadings() {
        let lines = ["Cubed ice", "Crushed ice", "Dash of soda water", "fresh cilantro", "Salt"]
        #expect(CardChecks.ingredients(from: lines).map(\.text) == lines)
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

@Suite struct IngredientPartsTests {
    @Test(arguments: [
        ("225g self-raising flour", "225g", "self-raising flour"),
        ("1 ½ tbsp olive oil", "1 ½ tbsp", "olive oil"),
        ("¾ cup / 180 ml oat cream", "¾ cup / 180 ml", "oat cream"),
        ("2 small leeks, sliced", "2", "small leeks, sliced"),
        ("1/2 tsp salt", "1/2 tsp", "salt"),
        ("11/2 cups thick poha", "11/2 cups", "thick poha"),
        ("2-3 cloves garlic", "2-3 cloves", "garlic"),
        ("1 lemon", "1", "lemon"),
        ("3/4 cup (150g) packed brown sugar", "3/4 cup", "(150g) packed brown sugar"),
        ("pinch of salt", "Pinch", "salt"),
        ("A pinch of saffron", "Pinch", "saffron"),
    ])
    func amountsAreSeparated(line: String, quantity: String, name: String) {
        let parts = Ingredient(text: line).parts
        #expect(parts.quantity == quantity)
        #expect(parts.name == name)
    }

    @Test func linesWithoutAnAmountStayWhole() {
        #expect(Ingredient(text: "Salt, to taste").parts.quantity == nil)
        #expect(Ingredient(text: "Salt, to taste").parts.name == "Salt, to taste")
        #expect(Ingredient(text: "400").parts.quantity == nil)
    }
}

@Suite struct ServingsTextTests {
    @Test func bareNumbersGetALabelAndWordsStayAsWritten() {
        #expect(Recipe(servings: "3").servingsText == "Serves 3")
        #expect(Recipe(servings: "4-5").servingsText == "Serves 4-5")
        #expect(Recipe(servings: "Makes 8 dumplings").servingsText == "Makes 8 dumplings")
        #expect(Recipe().servingsText == nil)
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
