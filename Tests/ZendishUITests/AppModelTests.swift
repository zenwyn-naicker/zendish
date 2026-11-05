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

/// Stands in for text recognition, which is very slow on virtual Macs without a GPU. Reading
/// real images has its own tests in `TextRecognizerTests`.
struct StubReader: TextReader {
    func text(from images: [URL]) async throws -> String {
        "Soup\n2 cups stock\n1 tsp salt\nSimmer."
    }
}

struct SlowWriter: CardWriter {
    func writeCard(from text: String) async throws -> CardDraft {
        try await Task.sleep(for: .seconds(1))
        return CardDraft(title: "Soup", ingredients: ["2 cups stock"], steps: ["Simmer."])
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
            maker: CardMaker(reader: StubReader(), writer: writer)
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
            maker: CardMaker(reader: StubReader(), writer: StubWriter())
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

    @Test func editsKeptOnLeavingStayInTheReviewQueue() async throws {
        let (model, recipe) = try await reviewedCard()
        var edited = recipe
        edited.title = "Half-finished edit"
        model.update(edited)

        try await waitUntil { model.reviewQueue.first?.title == "Half-finished edit" }
        #expect(model.reviewQueue.first?.status == .needsReview)
    }

    @Test func aCardInterruptedByQuittingIsReadOnNextLaunch() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try RecipeStore()
        let library = try ImageLibrary(folder: folder.appendingPathComponent("Images"))
        let image = folder.appendingPathComponent("soup.png")
        try writeRecipeImage(["Soup", "2 cups stock", "1 tsp salt", "Simmer."], to: image)
        try await store.save(Recipe(imageNames: [try library.add(image)], status: .reading))

        let model = AppModel(store: store, library: library, maker: CardMaker(reader: StubReader(), writer: StubWriter()))
        try await waitUntil { model.reviewQueue.first?.status == .needsReview }
        #expect(model.reviewQueue.first?.title == "Soup")
    }

    @Test func discardingWhileReadingDoesNotBringTheCardBack() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel(
            store: try RecipeStore(),
            library: try ImageLibrary(folder: folder.appendingPathComponent("Images")),
            maker: CardMaker(reader: StubReader(), writer: SlowWriter())
        )
        let image = folder.appendingPathComponent("soup.png")
        try writeRecipeImage(["Soup", "2 cups stock", "1 tsp salt", "Simmer."], to: image)
        model.receive([image])
        try await waitUntil { model.reviewQueue.first?.status == .reading }

        model.delete(try #require(model.reviewQueue.first))
        try await Task.sleep(for: .seconds(2))
        await model.refresh()
        #expect(model.recipes.isEmpty)
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
        let model = AppModel(store: store, library: try ImageLibrary(folder: folder), maker: CardMaker(reader: StubReader(), writer: StubWriter()))
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

@MainActor @Suite(.serialized) struct RecipePhotoTests {
    @Test func aChosenPhotoIsCopiedAndReplacesTheOldOne() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(
            store: try RecipeStore(),
            library: try ImageLibrary(folder: folder.appendingPathComponent("Images")),
            maker: CardMaker(reader: StubReader(), writer: StubWriter())
        )
        let first = folder.appendingPathComponent("first.png")
        let second = folder.appendingPathComponent("second.jpg")
        try writeRecipeImage(["Soup"], to: first)
        try writeRecipeImage(["Soup"], to: second)

        let firstName = try model.choosePhoto(from: first, replacing: nil)
        #expect(FileManager.default.fileExists(atPath: model.library.url(for: firstName).path))

        let secondName = try model.choosePhoto(from: second, replacing: firstName)
        #expect(FileManager.default.fileExists(atPath: model.library.url(for: secondName).path))
        #expect(!FileManager.default.fileExists(atPath: model.library.url(for: firstName).path))
    }

    @Test func aFileThatIsNotAPhotoIsRefused() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(
            store: try RecipeStore(),
            library: try ImageLibrary(folder: folder.appendingPathComponent("Images")),
            maker: CardMaker(reader: StubReader(), writer: StubWriter())
        )
        let notes = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notes)
        #expect(throws: ImageLibraryError.notAnImage("notes.txt")) {
            _ = try model.choosePhoto(from: notes, replacing: nil)
        }
    }
}
