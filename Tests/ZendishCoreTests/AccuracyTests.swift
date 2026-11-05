import Foundation
import Testing
@testable import ZendishCore

/// Runs the card checks over 20 invented recipe pages, using text and cards saved from a real
/// run of qwen3.5:9b. It's a regression check on a small, synthetic set, not a benchmark, and
/// it needs neither Ollama nor the original images.
@Suite struct AccuracyTests {
    struct Truth: Decodable {
        struct Line: Decodable { let text: String }
        let kind: String
        let ingredients: [Line]
        let total_time: String?
        let prep_time: String?
        let cook_time: String?
        let servings: String?
    }

    struct Case: Decodable {
        let id: String
        let text: String
        let card: CardDraft
        let truth: Truth
    }

    private func cases() throws -> [Case] {
        let url = try #require(Bundle.module.url(forResource: "invented-cases", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    @Test func everyCaseIsSortedIntoRecipeOrNot() throws {
        for item in try cases() {
            #expect(CardChecks.hasRecipe(in: item.text) == (item.truth.kind == "recipe"), "\(item.id)")
        }
    }

    @Test func noFalseTimesOrServingsSurvive() throws {
        for item in try cases() where item.truth.kind == "recipe" {
            let card = CardChecks.check(item.card, against: item.text).draft
            if item.truth.total_time == nil { #expect(card.totalTime == nil, "\(item.id)") }
            if item.truth.prep_time == nil { #expect(card.prepTime == nil, "\(item.id)") }
            if item.truth.cook_time == nil { #expect(card.cookTime == nil, "\(item.id)") }
            if item.truth.servings == nil { #expect(card.servings == nil, "\(item.id)") }
        }
    }

    @Test func correctTimesAndServingsAreKept() throws {
        // In case-06, text recognition read TOTAL as OTAL, so its details go blank instead.
        // A blank is the safe way to fail, because the card never shows a wrong time.
        for item in try cases() where item.truth.kind == "recipe" && item.id != "case-06" {
            let card = CardChecks.check(item.card, against: item.text).draft
            if item.truth.total_time != nil, item.card.totalTime != nil { #expect(card.totalTime != nil, "\(item.id)") }
            if item.truth.prep_time != nil, item.card.prepTime != nil { #expect(card.prepTime != nil, "\(item.id)") }
            if item.truth.cook_time != nil, item.card.cookTime != nil { #expect(card.cookTime != nil, "\(item.id)") }
            if item.truth.servings != nil, item.card.servings != nil { #expect(card.servings != nil, "\(item.id)") }
        }
    }

    @Test func everyJoinedFractionIsFlagged() throws {
        for item in try cases() where item.truth.kind == "recipe" {
            let joined = item.card.ingredients.filter { $0.contains(/(^|\s)11\/2/) }
            let flags = CardChecks.check(item.card, against: item.text).flags
            for line in joined {
                #expect(flags.contains { if case .checkQuantity(line, _) = $0 { true } else { false } }, "\(item.id)")
            }
        }
    }

    @Test func goodCardsRaiseNoMissingLineFlags() throws {
        for item in try cases() where item.truth.kind == "recipe" {
            let flags = CardChecks.check(item.card, against: item.text).flags
            let missing = flags.filter { if case .missingLine = $0 { true } else { false } }
            #expect(missing.isEmpty, "\(item.id): \(missing)")
        }
    }

    @Test func aDroppedSectionIsCaught() throws {
        let item = try #require(try cases().first { $0.id == "case-02" })
        var card = item.card
        card.ingredients.removeLast(3)
        let flags = CardChecks.check(card, against: item.text).flags
        #expect(flags.contains { if case .missingLine = $0 { true } else { false } })
    }
}
