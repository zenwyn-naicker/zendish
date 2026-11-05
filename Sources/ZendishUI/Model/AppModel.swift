import AppKit
import Foundation
import Observation
import ZendishCore

public enum SidebarItem: Hashable, Sendable {
    case all
    case toReview
    case collection(UUID)
}

public enum SetupState: Equatable, Sendable {
    case checking
    case needsOllama
    case needsModel
    case downloading(Double)
    case ready
}

/// Holds what the screens show and runs the import queue. One recipe is read at a time,
/// because the model uses most of the Mac's memory while it works.
@MainActor @Observable
public final class AppModel {
    public private(set) var recipes: [Recipe] = []
    public private(set) var collections: [RecipeCollection] = []
    public private(set) var members: [UUID: Set<UUID>] = [:]
    public var selection: SidebarItem = .all {
        didSet { openRecipeID = nil }
    }
    public var openRecipeID: UUID? {
        didSet { isEditing = false }
    }
    /// True while a saved recipe is open for changes.
    public var isEditing = false
    public var searchText = ""
    /// Matching recipes, or nil when nothing is being searched for.
    public private(set) var searchMatches: Set<UUID>?
    public private(set) var setup: SetupState = .checking
    public var isChoosingFiles = false
    /// Several images waiting for the person to say how they're grouped.
    public var imagesToGroup: [URL] = []
    public var message: String?

    public let library: ImageLibrary
    private let store: RecipeStore
    private let maker: CardMaker
    private let ollama: OllamaClient?
    private var isReading = false

    /// Without `ollama`, setup counts as finished, which is what tests want.
    public init(store: RecipeStore, library: ImageLibrary, maker: CardMaker = CardMaker(), ollama: OllamaClient? = nil) {
        self.store = store
        self.library = library
        self.maker = maker
        self.ollama = ollama
        Task {
            await refresh()
            await checkSetup()
            applyDebugLaunchOptions()
        }
        Task { await TextRecognizer().warmUp() }
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
                library: try ImageLibrary(folder: folder.appendingPathComponent("Images")),
                ollama: OllamaClient()
            )
        } catch {
            fatalError("Zendish couldn't open its data folder: \(error)")
        }
    }

    // MARK: Lists

    public var shownRecipes: [Recipe] {
        let list: [Recipe]
        switch selection {
        case .all: list = recipes.filter { $0.status == .saved }
        case .toReview: list = reviewQueue
        case .collection(let id):
            let inside = members[id] ?? []
            list = recipes.filter { inside.contains($0.id) }
        }
        guard let searchMatches else { return list }
        return list.filter { searchMatches.contains($0.id) }
    }

    public var reviewQueue: [Recipe] {
        recipes.filter { $0.status != .saved }
    }

    public var selectedCollection: RecipeCollection? {
        guard case .collection(let id) = selection else { return nil }
        return collections.first { $0.id == id }
    }

    public func refresh() async {
        do {
            recipes = try await store.recipes()
            collections = try await store.collections()
            members = try await store.collectionMembers()
            if case .collection = selection, selectedCollection == nil { selection = .all }
        } catch {
            message = "Your cookbook couldn't be loaded. \(error)"
        }
    }

    public func search() async {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            searchMatches = nil
            return
        }
        searchMatches = (try? await store.searchRecipeIDs(matching: text)) ?? []
    }

    // MARK: Collections

    public func addCollection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        run { try await self.store.save(RecipeCollection(name: trimmed)) }
    }

    public func rename(_ collection: RecipeCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var renamed = collection
        renamed.name = trimmed
        let saved = renamed
        run { try await self.store.save(saved) }
    }

    /// Deletes the collection. Its recipes stay in the cookbook.
    public func delete(_ collection: RecipeCollection) {
        run { try await self.store.deleteCollection(id: collection.id) }
    }

    public func isRecipe(_ id: UUID, in collection: RecipeCollection) -> Bool {
        members[collection.id]?.contains(id) == true
    }

    public func setRecipe(_ id: UUID, in collection: RecipeCollection, to isMember: Bool) {
        run {
            if isMember {
                try await self.store.add(recipeID: id, to: collection)
            } else {
                try await self.store.remove(recipeID: id, from: collection)
            }
        }
    }

    private func run(_ change: @escaping @Sendable () async throws -> Void) {
        Task {
            do {
                try await change()
            } catch {
                message = "That change couldn't be saved. \(error)"
            }
            await refresh()
        }
    }

    // MARK: Setup

    public func checkSetup() async {
        guard let ollama else {
            setup = .ready
            await readWaitingRecipes()
            return
        }
        if case .downloading = setup { return }
        switch await ollama.readiness() {
        case .notRunning: setup = .needsOllama
        case .modelMissing: setup = .needsModel
        case .ready:
            setup = .ready
            await readWaitingRecipes()
        }
    }

    public func openOllama() {
        let workspace = NSWorkspace.shared
        if let app = workspace.urlForApplication(withBundleIdentifier: "com.electron.ollama") {
            workspace.openApplication(at: app, configuration: .init()) { _, _ in }
        } else if let page = URL(string: "https://ollama.com/download") {
            workspace.open(page)
        }
    }

    /// Space the model needs, including room to unpack it.
    private static let spaceNeeded: Int64 = 9_000_000_000

    public func downloadModel() {
        guard let ollama else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let free = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        if let free, free < Self.spaceNeeded {
            message = "The model needs about 9 GB of free space. Free up some space, then try again."
            return
        }
        setup = .downloading(0)
        Task {
            do {
                try await ollama.downloadModel { value in
                    Task { @MainActor in self.setup = .downloading(value) }
                }
                setup = .checking
            } catch {
                setup = .needsModel
                message = String(describing: error)
            }
            await checkSetup()
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
        guard !isReading, setup == .ready else { return }
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
            // The person may have discarded it while it was being read.
            if try await store.recipe(id: recipe.id) != nil {
                try await store.save(recipe)
            }
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
        if recipe.status == .saved {
            isEditing = false
        } else {
            openRecipeID = nil
        }
    }

    public func chooseCover(for recipe: Recipe, from imageName: String, crop: CGRect) throws -> String {
        let cover = try library.cropCover(from: imageName, to: crop)
        if let old = recipe.coverName { library.remove([old]) }
        return cover
    }

    /// Asks where to save, then writes the recipes to a PDF.
    public func exportPDF(_ recipes: [Recipe], named name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(name).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try RecipePDF.write(recipes, to: url)
        } catch {
            message = String(describing: error)
        }
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

    // MARK: Inspection

    /// Debug builds can open a screen directly, so each one can be inspected automatically.
    private func applyDebugLaunchOptions() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        switch environment["ZENDISH_SHOW"] {
        case "review":
            selection = .toReview
            openRecipeID = reviewQueue.first { !$0.flags.isEmpty }?.id ?? reviewQueue.first?.id
        case "queue": selection = .toReview
        case "recipe": openRecipeID = recipes.first { $0.status == .saved && $0.coverName != nil }?.id
        case "collection": selection = collections.first.map { .collection($0.id) } ?? .all
        default: break
        }
        if let text = environment["ZENDISH_SEARCH"] {
            searchText = text
            Task { await search() }
        }
        #endif
    }
}
