import AppKit
import Foundation
import Testing
import ZendishCore
@testable import ZendishUI

struct StubWriter: CardWriter {
    var draft = CardDraft(title: "Soup", ingredients: ["2 cups stock", "1 tsp salt"], steps: ["Simmer."])
    var error: OllamaError?

    func writeCard(from text: String) async throws -> CardDraft {
        if let error { throw error }
        return draft
    }
}

@MainActor
func waitUntil(_ condition: @escaping () -> Bool) async throws {
    for _ in 0..<600 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(100))
    }
    Issue.record("Timed out waiting")
}

/// Draws lines of text to a PNG, so the real text recognition has something to read.
func writeRecipeImage(_ lines: [String], to url: URL) throws {
    let height = 110 * lines.count + 60
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 1000, height: height).fill()
    for (index, line) in lines.enumerated() {
        (line as NSString).draw(
            at: NSPoint(x: 40, y: height - 110 * (index + 1)),
            withAttributes: [.font: NSFont.systemFont(ofSize: 54), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
}

@MainActor @Suite(.serialized) struct AppModelTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func makeModel(writer: StubWriter = StubWriter()) throws -> AppModel {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return AppModel(
            store: try RecipeStore(),
            library: try ImageLibrary(folder: folder.appendingPathComponent("Images")),
            maker: CardMaker(writer: writer)
        )
    }

    private func image(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try writeRecipeImage(["Soup", "2 cups stock", "1 tsp salt", "Simmer."], to: url)
        return url
    }

    @Test func oneImageBecomesACardToReview() async throws {
        let model = try makeModel()
        model.receive([try image("soup.png")])

        try await waitUntil { model.reviewQueue.first?.status == .needsReview }
        #expect(model.selection == .toReview)
        #expect(model.reviewQueue.first?.title == "Soup")
        #expect(model.reviewQueue.first?.ingredients.count == 2)
    }

    @Test func severalImagesAskHowToGroup() async throws {
        let model = try makeModel()
        model.receive([try image("page-2.png"), try image("page-10.png"), try image("page-1.png")])
        #expect(model.imagesToGroup.count == 3)

        model.addImagesToGroup(asOneRecipe: true)
        try await waitUntil { model.reviewQueue.first?.status == .needsReview }
        #expect(model.reviewQueue.count == 1)
        #expect(model.reviewQueue.first?.imageNames.count == 3)
    }

    @Test func separateRecipesMakeOneCardEach() async throws {
        let model = try makeModel()
        model.receive([try image("one.png"), try image("two.png")])
        model.addImagesToGroup(asOneRecipe: false)
        try await waitUntil { model.reviewQueue.count == 2 && model.reviewQueue.allSatisfy { $0.status == .needsReview } }
    }

    @Test func otherFileTypesAreLeftOutWithAMessage() async throws {
        let model = try makeModel()
        let notes = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notes)
        model.receive([notes])
        #expect(model.message != nil)
        #expect(model.imagesToGroup.isEmpty)
    }

    @Test func aFailedCardExplainsWhyAndCanBeRetried() async throws {
        let model = try makeModel(writer: StubWriter(error: .notRunning))
        model.receive([try image("soup.png")])

        try await waitUntil { model.reviewQueue.first?.problem != nil }
        #expect(model.reviewQueue.first?.status == .needsReview)
        #expect(model.reviewQueue.first?.problem?.contains("Ollama") == true)
    }
}

@MainActor @Suite(.serialized) struct ReviewFlowTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func reviewedCard() async throws -> (AppModel, Recipe) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel(
            store: try RecipeStore(),
            library: try ImageLibrary(folder: folder.appendingPathComponent("Images")),
            maker: CardMaker(writer: StubWriter())
        )
        let url = folder.appendingPathComponent("soup.png")
        try writeRecipeImage(["Soup", "2 cups stock", "1 tsp salt", "Simmer."], to: url)
        model.receive([url])
        try await waitUntil { model.reviewQueue.first?.status == .needsReview }
        return (model, try #require(model.reviewQueue.first))
    }

    @Test func savingMovesACardIntoTheCookbook() async throws {
        let (model, recipe) = try await reviewedCard()
        var edited = recipe
        edited.title = "Winter soup"
        model.saveToCookbook(edited)
        model.selection = .all

        try await waitUntil { model.shownRecipes.first?.title == "Winter soup" }
        #expect(model.reviewQueue.isEmpty)
    }

    @Test func discardingRemovesTheCardAndItsImages() async throws {
        let (model, recipe) = try await reviewedCard()
        let stored = model.library.url(for: try #require(recipe.imageNames.first))
        #expect(FileManager.default.fileExists(atPath: stored.path))

        model.delete(recipe)
        try await waitUntil { model.recipes.isEmpty }
        #expect(!FileManager.default.fileExists(atPath: stored.path))
    }
}

@MainActor @Suite(.serialized) struct LibraryTests {
    private func model(with titles: [String]) async throws -> AppModel {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try RecipeStore()
        for title in titles {
            try await store.save(Recipe(title: title, ingredients: [Ingredient(text: "1 cup \(title) stock")], status: .saved))
        }
        let model = AppModel(store: store, library: try ImageLibrary(folder: folder), maker: CardMaker(writer: StubWriter()))
        try await waitUntil { model.recipes.count == titles.count }
        return model
    }

    @Test func searchNarrowsTheListAndClearing_restoresIt() async throws {
        let model = try await model(with: ["Tomato", "Lentil"])
        model.searchText = "tom"
        await model.search()
        #expect(model.shownRecipes.map(\.title) == ["Tomato"])

        model.searchText = ""
        await model.search()
        #expect(model.shownRecipes.count == 2)
    }

    @Test func collectionsFilterAndCount() async throws {
        let model = try await model(with: ["Tomato", "Lentil"])
        model.addCollection(named: "  Soups ")
        try await waitUntil { model.collections.count == 1 }
        let soups = try #require(model.collections.first)
        #expect(soups.name == "Soups")

        let tomato = try #require(model.recipes.first { $0.title == "Tomato" })
        model.setRecipe(tomato.id, in: soups, to: true)
        try await waitUntil { model.members[soups.id]?.count == 1 }

        model.selection = .collection(soups.id)
        #expect(model.shownRecipes.map(\.title) == ["Tomato"])
        #expect(model.isRecipe(tomato.id, in: soups))
    }

    @Test func blankCollectionNamesAreIgnored() async throws {
        let model = try await model(with: [])
        model.addCollection(named: "   ")
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.collections.isEmpty)
    }

    @Test func deletingTheOpenCollectionReturnsToAllRecipes() async throws {
        let model = try await model(with: ["Tomato"])
        model.addCollection(named: "Soups")
        try await waitUntil { model.collections.count == 1 }
        let soups = try #require(model.collections.first)
        model.selection = .collection(soups.id)

        model.delete(soups)
        try await waitUntil { model.collections.isEmpty }
        try await waitUntil { model.selection == .all }
        #expect(model.shownRecipes.count == 1)
    }

    @Test func editingASavedRecipeKeepsItInTheCookbook() async throws {
        let model = try await model(with: ["Tomato"])
        var recipe = try #require(model.recipes.first)
        model.openRecipeID = recipe.id
        model.isEditing = true
        recipe.title = "Roast Tomato"
        model.saveToCookbook(recipe)

        #expect(!model.isEditing)
        #expect(model.openRecipeID == recipe.id)
        try await waitUntil { model.recipes.first?.title == "Roast Tomato" }
    }
}
