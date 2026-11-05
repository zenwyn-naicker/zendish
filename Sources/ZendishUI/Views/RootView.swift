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
            if let recipe = model.recipe(id: model.openRecipeID) {
                ReviewView(model: model, recipe: recipe).id(recipe.id)
            } else {
                CookbookView(model: model)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Recipe", systemImage: "plus") { model.isChoosingFiles = true }
                    .help("Add images of a recipe")
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

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Label("All Recipes", systemImage: "book").tag(SidebarItem.all)
            Label("To Review", systemImage: "checklist")
                .badge(model.reviewQueue.count)
                .tag(SidebarItem.toReview)
        }
    }
}

struct CookbookView: View {
    @Bindable var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)]

    var body: some View {
        Group {
            if model.shownRecipes.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "photo.on.rectangle")
                } description: {
                    Text(emptyDetail)
                } actions: {
                    Button("Choose Images") { model.isChoosingFiles = true }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.shownRecipes) { recipe in
                            Button {
                                model.openRecipeID = recipe.id
                            } label: {
                                Text(recipe.status == .reading ? "Reading…" : recipe.title ?? "Untitled recipe")
                                    .frame(maxWidth: .infinity, minHeight: 80)
                                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(recipe.status == .reading)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(model.selection == .all ? "All Recipes" : "To Review")
    }

    private var emptyTitle: String {
        model.selection == .all ? "Start your cookbook" : "Nothing to review"
    }

    private var emptyDetail: String {
        model.selection == .all
            ? "Drop recipe screenshots anywhere in this window, or choose them from your Mac."
            : "New recipes appear here so you can check them before saving."
    }
}
