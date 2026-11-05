import Foundation
import PDFKit
import Testing
@testable import ZendishCore

@Suite struct RecipePDFTests {
    private func write(_ recipes: [Recipe]) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try RecipePDF.write(recipes, to: url)
        return try #require(PDFDocument(url: url))
    }

    @Test func aRecipeBecomesAPageWithItsText() throws {
        let recipe = Recipe(
            title: "Velvet Tomato Poha",
            ingredients: [Ingredient(text: "1 ½ cups thick poha"), Ingredient(text: "2 cloves garlic", section: "For the sauce")],
            steps: ["Rinse the poha."],
            totalTime: "25 min",
            servings: "Serves 4"
        )
        let document = try write([recipe])
        let text = document.string ?? ""
        #expect(document.pageCount == 1)
        for expected in ["Velvet Tomato Poha", "1 ½ cups thick poha", "For the sauce", "Rinse the poha.", "Total 25 min", "Serves 4"] {
            #expect(text.contains(expected), "\(expected)")
        }
    }

    @Test func blankDetailsLeaveNoEmptyLabels() throws {
        let text = try write([Recipe(title: "Soup")]).string ?? ""
        #expect(!text.contains("Total"))
        #expect(!text.contains("Ingredients"))
        #expect(!text.contains("nil"))
    }

    @Test func aLongRecipeRunsOntoMorePages() throws {
        let steps = (1...90).map { "Step \($0): stir the pot gently and keep an eye on the heat until it looks right." }
        let document = try write([Recipe(title: "Long stew", steps: steps)])
        #expect(document.pageCount > 1)
        #expect((document.string ?? "").contains("Step 90"))
    }

    @Test func eachRecipeStartsOnANewPage() throws {
        let document = try write([Recipe(title: "First"), Recipe(title: "Second")])
        #expect(document.pageCount == 2)
        #expect(document.page(at: 1)?.string?.contains("Second") == true)
    }
}
