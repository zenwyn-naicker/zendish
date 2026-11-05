import SwiftUI
import UniformTypeIdentifiers
import ZendishCore

public struct RootView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            Group {
                if let recipe = model.recipe(id: model.openRecipeID) {
                    if recipe.status == .saved, !model.isEditing {
                        RecipeView(model: model, recipe: recipe)
                    } else {
                        ReviewView(model: model, recipe: recipe).id(recipe.id)
                    }
                } else {
                    CookbookView(model: model)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { SetupBar(model: model) }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Dish or ingredient")
        .task(id: model.searchText) { await model.search() }
        .onChange(of: model.searchText) { model.openRecipeID = nil }
        .task {
            // Notices when Ollama is opened or the model arrives, without needing a click.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if model.setup != .ready { await model.checkSetup() }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.receive(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .fileImporter(
            isPresented: $model.isChoosingFiles,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.receive(urls) }
        }
        .confirmationDialog(
            "Are these \(model.imagesToGroup.count) images one recipe?",
            isPresented: Binding(
                get: { !model.imagesToGroup.isEmpty },
                set: { if !$0 { model.imagesToGroup = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("One Recipe") { model.addImagesToGroup(asOneRecipe: true) }
            Button("Separate Recipes") { model.addImagesToGroup(asOneRecipe: false) }
            Button("Cancel", role: .cancel) { model.imagesToGroup = [] }
        } message: {
            Text("Images of one recipe are read together, in file name order.")
        }
        .alert(
            "Zendish",
            isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })
        ) {
            Button("OK") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

