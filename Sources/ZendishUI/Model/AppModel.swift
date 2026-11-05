import Foundation
import Observation
import ZendishCore

public enum SidebarItem: Hashable, Sendable {
    case all
    case toReview
}

/// Holds what the screens show and runs the import queue. One recipe is read at a time,
/// because the model uses most of the Mac's memory while it works.
@MainActor @Observable
public final class AppModel {
    public private(set) var recipes: [Recipe] = []
    public var selection: SidebarItem = .all
    public var openRecipeID: UUID?
    public var isChoosingFiles = false
    /// Several images waiting for the person to say how they're grouped.
    public var imagesToGroup: [URL] = []
    public var message: String?

    public let library: ImageLibrary
    private let store: RecipeStore
    private let maker: CardMaker
    private var isReading = false

    public init(store: RecipeStore, library: ImageLibrary, maker: CardMaker = CardMaker()) {
        self.store = store
        self.library = library
        self.maker = maker
        Task {
            await refresh()
            await readWaitingRecipes()
        }
    }

    /// The real app, keeping its data in Application Support. ZENDISH_DATA_DIR overrides the
    /// folder, so testing never touches a real cookbook.
    public static func live() -> AppModel {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let override = ProcessInfo.processInfo.environment["ZENDISH_DATA_DIR"]
        let folder = override.map { URL(fileURLWithPath: $0) } ?? support.appendingPathComponent("Zendish")
        do {
            return AppModel(
                store: try RecipeStore(url: folder.appendingPathComponent("zendish.sqlite")),
                library: try ImageLibrary(folder: folder.appendingPathComponent("Images"))
            )
        } catch {
            fatalError("Zendish couldn't open its data folder: \(error)")
        }
    }

    // MARK: Lists

    public var shownRecipes: [Recipe] {
        switch selection {
        case .all: recipes.filter { $0.status == .saved }
        case .toReview: reviewQueue
        }
    }

    public var reviewQueue: [Recipe] {
        recipes.filter { $0.status != .saved }
    }

    public func refresh() async {
        do {
            recipes = try await store.recipes()
        } catch {
            message = "Your cookbook couldn't be loaded. \(error)"
        }
    }

    // MARK: Adding images

    /// Takes dropped or chosen files. Several images could be one recipe, so that's asked first.
    public func receive(_ urls: [URL]) {
        let images = urls.filter(ImageLibrary.isSupported)
        if images.count < urls.count {
            message = "Only images can be added. Files of other kinds were left out."
        }
        if images.count > 1 {
            imagesToGroup = images
        } else if let image = images.first {
            addRecipes(from: [[image]])
        }
    }

    public func addImagesToGroup(asOneRecipe: Bool) {
        let images = imagesToGroup.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        imagesToGroup = []
        addRecipes(from: asOneRecipe ? [images] : images.map { [$0] })
    }

    private func addRecipes(from groups: [[URL]]) {
        Task {
            var problems: [String] = []
            for group in groups {
                do {
                    let names = try group.map(library.add)
                    try await store.save(Recipe(imageNames: names, status: .reading))
                } catch {
                    problems.append(String(describing: error))
                }
            }
            if !problems.isEmpty { message = problems.joined(separator: "\n") }
            selection = .toReview
            await refresh()
            await readWaitingRecipes()
        }
    }

    // MARK: Reading

    private func readWaitingRecipes() async {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }
        while let next = recipes.last(where: { $0.status == .reading }) {
            await read(next)
            await refresh()
        }
    }

    private func read(_ waiting: Recipe) async {
        var recipe = waiting
        do {
            let made = try await maker.makeCard(from: recipe.imageNames.map(library.url(for:)))
            let card = made.recipe
            recipe.title = card.title
            recipe.ingredients = card.ingredients
            recipe.steps = card.steps
            recipe.totalTime = card.totalTime
            recipe.prepTime = card.prepTime
            recipe.cookTime = card.cookTime
            recipe.servings = card.servings
            recipe.flags = card.flags
            recipe.sourceText = made.sourceText
            recipe.problem = nil
        } catch {
            recipe.problem = String(describing: error)
        }
        recipe.status = .needsReview
        recipe.updatedAt = Date()
        do {
            try await store.save(recipe)
        } catch {
            message = "The card couldn't be saved. \(error)"
        }
    }

    // MARK: Reviewing

    public func recipe(id: UUID?) -> Recipe? {
        recipes.first { $0.id == id }
    }

    /// Keeps edits to a card without moving it out of the review queue.
    public func update(_ recipe: Recipe) {
        var edited = recipe
        edited.updatedAt = Date()
        persist(edited)
    }

    /// Accepts a reviewed card into the cookbook.
    public func saveToCookbook(_ recipe: Recipe) {
        var reviewed = recipe
        reviewed.status = .saved
        reviewed.flags = []
        reviewed.problem = nil
        reviewed.updatedAt = Date()
        persist(reviewed)
        openRecipeID = nil
    }

    /// Permanently deletes a recipe and its stored images.
    public func delete(_ recipe: Recipe) {
        openRecipeID = nil
        Task {
            do {
                try await store.deleteRecipe(id: recipe.id)
                library.remove(recipe.imageNames + [recipe.coverName].compactMap { $0 })
            } catch {
                message = "The recipe couldn't be deleted. \(error)"
            }
            await refresh()
        }
    }

    private func persist(_ recipe: Recipe) {
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        }
        Task {
            do {
                try await store.save(recipe)
            } catch {
                message = "Your changes couldn't be saved. \(error)"
            }
            await refresh()
        }
    }

    /// Tries a failed card again.
    public func retry(_ recipe: Recipe) {
        var waiting = recipe
        waiting.status = .reading
        waiting.problem = nil
        Task {
            try? await store.save(waiting)
            await refresh()
            await readWaitingRecipes()
        }
    }
}
