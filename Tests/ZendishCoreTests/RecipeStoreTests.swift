import Foundation
import Testing
@testable import ZendishCore

@Suite struct RecipeStoreTests {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(title: String? = "Velvet Tomato Poha", updatedAt: Date? = nil) -> Recipe {
        Recipe(
            title: title,
            ingredients: [
                Ingredient(text: "1 ½ cups thick poha"),
                Ingredient(text: "2–3 cloves garlic", section: "For the sauce"),
            ],
            steps: ["Rinse the poha.", "Warm gently."],
            totalTime: "25 min",
            servings: "Serves 4",
            imageNames: ["page-1.png", "page-2.png"],
            createdAt: moment,
            updatedAt: updatedAt ?? moment
        )
    }

    @Test func savedRecipeComesBackUnchanged() async throws {
        let store = try RecipeStore()
        let recipe = sample()
        try await store.save(recipe)
        #expect(try await store.recipe(id: recipe.id) == recipe)
    }

    @Test func blankDetailsStayBlank() async throws {
        let store = try RecipeStore()
        let recipe = Recipe(createdAt: moment, updatedAt: moment)
        try await store.save(recipe)

        let loaded = try #require(try await store.recipe(id: recipe.id))
        #expect(loaded.title == nil)
        #expect(loaded.totalTime == nil)
        #expect(loaded.servings == nil)
        #expect(loaded.ingredients.isEmpty)
    }

    @Test func savingAgainReplacesTheRecipe() async throws {
        let store = try RecipeStore()
        var recipe = sample()
        try await store.save(recipe)

        recipe.title = "Tomato Poha"
        recipe.ingredients = [Ingredient(text: "2 tomatoes")]
        recipe.steps = []
        recipe.status = .saved
        try await store.save(recipe)

        #expect(try await store.recipe(id: recipe.id) == recipe)
        #expect(try await store.recipes().count == 1)
    }

    @Test func recipesListNewestFirstAndFilterByStatus() async throws {
        let store = try RecipeStore()
        let older = sample(title: "Older")
        var newer = sample(title: "Newer", updatedAt: moment.addingTimeInterval(60))
        newer.status = .saved
        try await store.save(older)
        try await store.save(newer)

        #expect(try await store.recipes().map(\.title) == ["Newer", "Older"])
        #expect(try await store.recipes(status: .needsReview).map(\.title) == ["Older"])
    }

    @Test func textIsNeverTreatedAsSQL() async throws {
        let store = try RecipeStore()
        let title = "Robert'); DROP TABLE recipes;--"
        let recipe = sample(title: title)
        try await store.save(recipe)
        #expect(try await store.recipe(id: recipe.id)?.title == title)
    }

    @Test func deletingARecipeRemovesItFromCollections() async throws {
        let store = try RecipeStore()
        let recipe = sample()
        let collection = RecipeCollection(name: "Weeknight dinners", createdAt: moment)
        try await store.save(recipe)
        try await store.save(collection)
        try await store.add(recipeID: recipe.id, to: collection)

        try await store.deleteRecipe(id: recipe.id)

        #expect(try await store.recipe(id: recipe.id) == nil)
        #expect(try await store.recipes(in: collection).isEmpty)
    }

    @Test func collectionsHoldRecipesAndKeepThemWhenDeleted() async throws {
        let store = try RecipeStore()
        let recipe = sample()
        let baking = RecipeCollection(name: "baking", createdAt: moment)
        let dinners = RecipeCollection(name: "Dinners", createdAt: moment)
        try await store.save(recipe)
        try await store.save(dinners)
        try await store.save(baking)
        try await store.add(recipeID: recipe.id, to: baking)
        try await store.add(recipeID: recipe.id, to: baking)

        #expect(try await store.collections().map(\.name) == ["baking", "Dinners"])
        #expect(try await store.recipes(in: baking).count == 1)

        try await store.remove(recipeID: recipe.id, from: baking)
        #expect(try await store.recipes(in: baking).isEmpty)

        try await store.add(recipeID: recipe.id, to: baking)
        try await store.deleteCollection(id: baking.id)
        #expect(try await store.collections() == [dinners])
        #expect(try await store.recipe(id: recipe.id) != nil)
    }

    @Test func dataSurvivesReopeningTheFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("nested/zendish.sqlite")
        let recipe = sample()

        do {
            let store = try RecipeStore(url: url)
            try await store.save(recipe)
        }

        let reopened = try RecipeStore(url: url)
        #expect(try await reopened.recipe(id: recipe.id) == recipe)
    }

    @Test func aFailedTransactionChangesNothing() throws {
        let database = try Database(path: ":memory:")
        try database.execute("CREATE TABLE items (name TEXT NOT NULL)")

        #expect(throws: DatabaseError.self) {
            try database.transaction {
                try database.execute("INSERT INTO items (name) VALUES (?)", [.text("kept?")])
                try database.execute("INSERT INTO items (name) VALUES (?)", [.text(nil)])
            }
        }

        #expect(try database.query("SELECT count(*) FROM items") { $0.integer(0) } == [0])
    }

    @Test func aNewerDatabaseIsRefused() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("zendish.sqlite")

        do {
            let database = try Database(path: url.path)
            try database.execute("PRAGMA user_version = 99")
        }

        #expect(throws: DatabaseError.self) {
            _ = try RecipeStore(url: url)
        }
    }
}

@Suite struct RecipeReviewStorageTests {
    @Test func flagsAndSourceTextAreKept() async throws {
        let store = try RecipeStore()
        let recipe = Recipe(
            coverName: "cover.jpg",
            status: .reading,
            flags: [.checkQuantity(line: "11/2 cups", suggestion: "1 1/2 cups"), .missingLine("1 tsp salt"), .noRecipe],
            sourceText: "Read from the image",
            problem: "Ollama isn't open."
        )
        try await store.save(recipe)

        let loaded = try #require(try await store.recipe(id: recipe.id))
        #expect(loaded.flags == recipe.flags)
        #expect(loaded.sourceText == "Read from the image")
        #expect(loaded.problem == "Ollama isn't open.")
        #expect(loaded.coverName == "cover.jpg")
        #expect(loaded.status == .reading)
    }

    @Test func aVersionOneDatabaseIsUpgradedInPlace() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("zendish.sqlite")
        let id = UUID()

        do {
            let old = try Database(path: url.path)
            try old.execute("CREATE TABLE recipes (id TEXT PRIMARY KEY, title TEXT, total_time TEXT, prep_time TEXT, cook_time TEXT, servings TEXT, status TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL)")
            try old.execute("CREATE TABLE ingredients (recipe_id TEXT, position INTEGER, text TEXT, section TEXT)")
            try old.execute("CREATE TABLE steps (recipe_id TEXT, position INTEGER, text TEXT)")
            try old.execute("CREATE TABLE images (recipe_id TEXT, position INTEGER, file_name TEXT)")
            try old.execute("INSERT INTO recipes VALUES (?, 'Old soup', NULL, NULL, NULL, NULL, 'saved', 1, 1)", [.text(id.uuidString)])
            try old.execute("PRAGMA user_version = 1")
        }

        let store = try RecipeStore(url: url)
        let loaded = try #require(try await store.recipe(id: id))
        #expect(loaded.title == "Old soup")
        #expect(loaded.flags.isEmpty)
    }
}
