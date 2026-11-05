import Foundation

/// Saves recipes and collections in a local SQLite file. Being an actor, it handles one
/// request at a time, which keeps database work off the main thread and safe to share.
public actor RecipeStore {
    private let database: Database

    /// Opens the database at `url`, creating it and any missing tables.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        database = try Database(path: url.path)
        try database.execute("PRAGMA journal_mode = WAL")
        try Self.migrate(database)
    }

    /// Opens a temporary database that disappears when closed.
    public init() throws {
        database = try Database(path: ":memory:")
        try Self.migrate(database)
    }

    // MARK: Recipes

    /// Adds the recipe, or replaces the saved one with the same ID.
    public func save(_ recipe: Recipe) throws {
        let id = recipe.id.uuidString
        let flagText = String(decoding: try JSONEncoder().encode(recipe.flags), as: UTF8.self)
        try database.transaction {
            try database.execute(
                """
                INSERT INTO recipes (
                    id, title, total_time, prep_time, cook_time, servings, status, created_at, updated_at,
                    cover_name, flags, source_text, problem
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (id) DO UPDATE SET
                    title = excluded.title, total_time = excluded.total_time,
                    prep_time = excluded.prep_time, cook_time = excluded.cook_time,
                    servings = excluded.servings, status = excluded.status,
                    updated_at = excluded.updated_at, cover_name = excluded.cover_name,
                    flags = excluded.flags, source_text = excluded.source_text, problem = excluded.problem
                """,
                [
                    .text(id), .text(recipe.title), .text(recipe.totalTime), .text(recipe.prepTime),
                    .text(recipe.cookTime), .text(recipe.servings), .text(recipe.status.rawValue),
                    .real(recipe.createdAt.timeIntervalSince1970), .real(recipe.updatedAt.timeIntervalSince1970),
                    .text(recipe.coverName), .text(flagText), .text(recipe.sourceText), .text(recipe.problem),
                ]
            )

            for table in ["ingredients", "steps", "images"] {
                try database.execute("DELETE FROM \(table) WHERE recipe_id = ?", [.text(id)])
            }
            for (position, ingredient) in recipe.ingredients.enumerated() {
                try database.execute(
                    "INSERT INTO ingredients (recipe_id, position, text, section) VALUES (?, ?, ?, ?)",
                    [.text(id), .integer(position), .text(ingredient.text), .text(ingredient.section)]
                )
            }
            for (position, step) in recipe.steps.enumerated() {
                try database.execute(
                    "INSERT INTO steps (recipe_id, position, text) VALUES (?, ?, ?)",
                    [.text(id), .integer(position), .text(step)]
                )
            }
            for (position, name) in recipe.imageNames.enumerated() {
                try database.execute(
                    "INSERT INTO images (recipe_id, position, file_name) VALUES (?, ?, ?)",
                    [.text(id), .integer(position), .text(name)]
                )
            }
            try database.execute("DELETE FROM recipe_search WHERE recipe_id = ?", [.text(id)])
            try database.execute(
                "INSERT INTO recipe_search (recipe_id, title, ingredients) VALUES (?, ?, ?)",
                [.text(id), .text(recipe.title ?? ""), .text(recipe.ingredients.map(\.text).joined(separator: " "))]
            )
        }
    }

    public func recipe(id: UUID) throws -> Recipe? {
        try loadRecipes(where: "id = ?", [.text(id.uuidString)]).first
    }

    /// All recipes, most recently changed first.
    public func recipes() throws -> [Recipe] {
        try loadRecipes()
    }

    public func recipes(status: Recipe.Status) throws -> [Recipe] {
        try loadRecipes(where: "status = ?", [.text(status.rawValue)])
    }

    public func recipes(in collection: RecipeCollection) throws -> [Recipe] {
        try loadRecipes(
            where: "id IN (SELECT recipe_id FROM collection_recipes WHERE collection_id = ?)",
            [.text(collection.id.uuidString)]
        )
    }

    public func deleteRecipe(id: UUID) throws {
        try database.transaction {
            try database.execute("DELETE FROM recipe_search WHERE recipe_id = ?", [.text(id.uuidString)])
            try database.execute("DELETE FROM recipes WHERE id = ?", [.text(id.uuidString)])
        }
    }

    /// Finds recipes by dish or ingredient. Each word must match, and "tom" finds "tomato".
    public func searchRecipeIDs(matching text: String) throws -> Set<UUID> {
        let words = text.split(whereSeparator: \.isWhitespace)
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
        guard !words.isEmpty else { return [] }
        let ids = try database.query(
            "SELECT recipe_id FROM recipe_search WHERE recipe_search MATCH ?",
            [.text(words.joined(separator: " "))]
        ) { $0.text(0) }
        return Set(ids.compactMap { $0.flatMap(UUID.init(uuidString:)) })
    }

    // MARK: Collections

    /// Adds the collection, or renames the saved one with the same ID.
    public func save(_ collection: RecipeCollection) throws {
        try database.execute(
            """
            INSERT INTO collections (id, name, created_at) VALUES (?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET name = excluded.name
            """,
            [.text(collection.id.uuidString), .text(collection.name), .real(collection.createdAt.timeIntervalSince1970)]
        )
    }

    /// All collections, in alphabetical order.
    public func collections() throws -> [RecipeCollection] {
        try database.query("SELECT id, name, created_at FROM collections ORDER BY name COLLATE NOCASE") { row in
            (row.text(0), row.text(1), row.real(2))
        }.compactMap { id, name, created in
            guard let id = id.flatMap(UUID.init(uuidString:)), let name else { return nil }
            return RecipeCollection(id: id, name: name, createdAt: Date(timeIntervalSince1970: created))
        }
    }

    /// Deletes the collection. Its recipes are kept.
    public func deleteCollection(id: UUID) throws {
        try database.execute("DELETE FROM collections WHERE id = ?", [.text(id.uuidString)])
    }

    /// Which recipes are in each collection, for showing counts and filtering.
    public func collectionMembers() throws -> [UUID: Set<UUID>] {
        let pairs = try database.query("SELECT collection_id, recipe_id FROM collection_recipes") { ($0.text(0), $0.text(1)) }
        var members: [UUID: Set<UUID>] = [:]
        for (collection, recipe) in pairs {
            guard let collection = collection.flatMap(UUID.init(uuidString:)),
                  let recipe = recipe.flatMap(UUID.init(uuidString:)) else { continue }
            members[collection, default: []].insert(recipe)
        }
        return members
    }

    public func add(recipeID: UUID, to collection: RecipeCollection) throws {
        try database.execute(
            "INSERT OR IGNORE INTO collection_recipes (collection_id, recipe_id) VALUES (?, ?)",
            [.text(collection.id.uuidString), .text(recipeID.uuidString)]
        )
    }

    public func remove(recipeID: UUID, from collection: RecipeCollection) throws {
        try database.execute(
            "DELETE FROM collection_recipes WHERE collection_id = ? AND recipe_id = ?",
            [.text(collection.id.uuidString), .text(recipeID.uuidString)]
        )
    }

    // MARK: Loading

    private func loadRecipes(where condition: String = "1", _ values: [SQLValue] = []) throws -> [Recipe] {
        let rows = try database.query(
            """
            SELECT id, title, total_time, prep_time, cook_time, servings, status, created_at, updated_at,
                cover_name, flags, source_text, problem
            FROM recipes WHERE \(condition) ORDER BY updated_at DESC
            """,
            values
        ) { row in
            (
                id: row.text(0), title: row.text(1), total: row.text(2), prep: row.text(3), cook: row.text(4),
                servings: row.text(5), status: row.text(6), created: row.real(7), updated: row.real(8),
                cover: row.text(9), flags: row.text(10), source: row.text(11), problem: row.text(12)
            )
        }

        return try rows.compactMap { row in
            guard let text = row.id, let id = UUID(uuidString: text) else { return nil }
            let key: [SQLValue] = [.text(text)]
            return Recipe(
                id: id,
                title: row.title,
                ingredients: try database.query(
                    "SELECT text, section FROM ingredients WHERE recipe_id = ? ORDER BY position", key
                ) { Ingredient(text: $0.text(0) ?? "", section: $0.text(1)) },
                steps: try database.query(
                    "SELECT text FROM steps WHERE recipe_id = ? ORDER BY position", key
                ) { $0.text(0) ?? "" },
                totalTime: row.total,
                prepTime: row.prep,
                cookTime: row.cook,
                servings: row.servings,
                imageNames: try database.query(
                    "SELECT file_name FROM images WHERE recipe_id = ? ORDER BY position", key
                ) { $0.text(0) ?? "" },
                coverName: row.cover,
                status: row.status.flatMap(Recipe.Status.init(rawValue:)) ?? .needsReview,
                flags: row.flags.flatMap { try? JSONDecoder().decode([CardFlag].self, from: Data($0.utf8)) } ?? [],
                sourceText: row.source,
                problem: row.problem,
                createdAt: Date(timeIntervalSince1970: row.created),
                updatedAt: Date(timeIntervalSince1970: row.updated)
            )
        }
    }

    // MARK: Schema

    private static let currentVersion = 3

    /// Each version's changes run once, in order, so existing cookbooks are upgraded in place.
    private static func migrate(_ database: Database) throws {
        let version = try database.query("PRAGMA user_version") { $0.integer(0) }.first ?? 0
        if version > currentVersion {
            throw DatabaseError(description: "This cookbook was saved by a newer version of Zendish.")
        }
        if version < 1 { try createTables(database) }
        if version < 2 {
            try database.transaction {
                for column in ["cover_name", "flags", "source_text", "problem"] {
                    try database.execute("ALTER TABLE recipes ADD COLUMN \(column) TEXT")
                }
                try database.execute("PRAGMA user_version = 2")
            }
        }
        if version < 3 {
            try database.transaction {
                try database.execute(
                    """
                    CREATE VIRTUAL TABLE recipe_search USING fts5(
                        recipe_id UNINDEXED, title, ingredients, tokenize = 'unicode61 remove_diacritics 2'
                    )
                    """
                )
                try database.execute(
                    """
                    INSERT INTO recipe_search (recipe_id, title, ingredients)
                    SELECT id, coalesce(title, ''),
                        coalesce((SELECT group_concat(text, ' ') FROM ingredients WHERE recipe_id = recipes.id), '')
                    FROM recipes
                    """
                )
                try database.execute("PRAGMA user_version = 3")
            }
        }
    }

    private static func createTables(_ database: Database) throws {
        try database.transaction {
            try database.execute(
                """
                CREATE TABLE recipes (
                    id TEXT PRIMARY KEY,
                    title TEXT,
                    total_time TEXT,
                    prep_time TEXT,
                    cook_time TEXT,
                    servings TEXT,
                    status TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                )
                """
            )
            try database.execute(
                """
                CREATE TABLE ingredients (
                    recipe_id TEXT NOT NULL REFERENCES recipes (id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    section TEXT,
                    PRIMARY KEY (recipe_id, position)
                )
                """
            )
            try database.execute(
                """
                CREATE TABLE steps (
                    recipe_id TEXT NOT NULL REFERENCES recipes (id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    PRIMARY KEY (recipe_id, position)
                )
                """
            )
            try database.execute(
                """
                CREATE TABLE images (
                    recipe_id TEXT NOT NULL REFERENCES recipes (id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    file_name TEXT NOT NULL,
                    PRIMARY KEY (recipe_id, position)
                )
                """
            )
            try database.execute(
                """
                CREATE TABLE collections (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at REAL NOT NULL
                )
                """
            )
            try database.execute(
                """
                CREATE TABLE collection_recipes (
                    collection_id TEXT NOT NULL REFERENCES collections (id) ON DELETE CASCADE,
                    recipe_id TEXT NOT NULL REFERENCES recipes (id) ON DELETE CASCADE,
                    PRIMARY KEY (collection_id, recipe_id)
                )
                """
            )
            try database.execute("CREATE INDEX recipes_by_status ON recipes (status)")
            try database.execute("CREATE INDEX collection_recipes_by_recipe ON collection_recipes (recipe_id)")
            try database.execute("PRAGMA user_version = 1")
        }
    }
}
