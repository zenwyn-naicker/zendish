import SwiftUI
import ZendishCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var isAddingCollection = false
    @State private var renaming: RecipeCollection?
    @State private var name = ""

    var body: some View {
        List(selection: $model.selection) {
            SidebarLabel("All Recipes", symbol: "book")
                .tag(SidebarItem.all)
                .listRowBackground(rowBackground(.all))
            SidebarLabel("To Review", symbol: "checklist")
                .badge(model.reviewQueue.count)
                .tag(SidebarItem.toReview)
                .listRowBackground(rowBackground(.toReview))

            Section {
                ForEach(model.collections) { collection in
                    SidebarLabel(collection.name, symbol: "folder")
                        .badge(model.members[collection.id]?.count ?? 0)
                        .tag(SidebarItem.collection(collection.id))
                        .listRowBackground(rowBackground(.collection(collection.id)))
                        .contextMenu {
                            Button("Rename…") {
                                name = collection.name
                                renaming = collection
                            }
                            Button("Delete Collection", role: .destructive) { model.delete(collection) }
                        }
                        .dropDestination(for: String.self) { ids, _ in
                            for id in ids.compactMap(UUID.init(uuidString:)) {
                                model.setRecipe(id, in: collection, to: true)
                            }
                            return true
                        }
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Button("New Collection", systemImage: "plus") {
                        name = ""
                        isAddingCollection = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .alert("New Collection", isPresented: $isAddingCollection) {
            TextField("Weeknight dinners", text: $name)
            Button("Create") { model.addCollection(named: name) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") { if let renaming { model.rename(renaming, to: name) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct SidebarLabel: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(title).foregroundStyle(Theme.text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
        }
    }
}

extension SidebarView {
    fileprivate func rowBackground(_ item: SidebarItem) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(model.selection == item ? Theme.selection : .clear)
            .padding(.horizontal, 8)
    }
}

struct CookbookView: View {
    @Bindable var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 18, alignment: .top)]

    var body: some View {
        Group {
            if model.shownRecipes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(model.shownRecipes) { recipe in
                            RecipeTile(model: model, recipe: recipe)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let collection = model.selectedCollection, !model.shownRecipes.isEmpty {
                    Button("Export PDF", systemImage: "arrow.down.doc") {
                        model.exportPDF(model.shownRecipes, named: collection.name)
                    }
                    .help("Export this collection as a PDF")
                }
                Button("Add Recipe", systemImage: "plus") { model.isChoosingFiles = true }
                    .help("Add images of a recipe")
            }
        }
    }

    private var title: String {
        switch model.selection {
        case .all: "All Recipes"
        case .toReview: "To Review"
        case .collection: model.selectedCollection?.name ?? ""
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.searchMatches != nil {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            switch model.selection {
            case .all:
                ContentUnavailableView {
                    Label("Start your cookbook", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Drop recipe screenshots anywhere in this window, or choose them from your Mac.")
                } actions: {
                    Button("Choose Images") { model.isChoosingFiles = true }
                }
            case .toReview:
                ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle", description: Text("New recipes appear here so you can check them before saving."))
            case .collection:
                ContentUnavailableView("No recipes here yet", systemImage: "folder", description: Text("Drag a recipe onto this collection in the sidebar."))
            }
        }
    }
}

struct RecipeTile: View {
    let model: AppModel
    let recipe: Recipe

    var body: some View {
        Button {
            model.openRecipeID = recipe.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                cover
                    .aspectRatio(4 / 3, contentMode: .fit)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.status == .reading ? "Reading recipe…" : recipe.title ?? "Untitled recipe")
                        .font(.headline)
                        .foregroundStyle(recipe.title == nil ? Theme.muted : Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    caption
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            }
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 0.5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(recipe.status == .reading)
        .draggable(recipe.id.uuidString)
        .contextMenu {
            if !model.collections.isEmpty, recipe.status == .saved {
                CollectionsMenu(model: model, recipeID: recipe.id)
            }
            Button("Delete", role: .destructive) { model.delete(recipe) }
        }
    }

    @ViewBuilder private var cover: some View {
        Rectangle()
            .fill(Theme.tile)
            .overlay {
                if recipe.status == .reading {
                    ProgressView().controlSize(.small)
                } else if let name = recipe.coverName {
                    LibraryImage(library: model.library, name: name, maxPixels: 640, fill: true)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.title)
                        .foregroundStyle(Theme.accent.opacity(0.55))
                }
            }
            .clipped()
    }

    @ViewBuilder private var caption: some View {
        if recipe.problem != nil {
            Text("Couldn’t be read").font(.caption).foregroundStyle(Theme.flag)
        } else if recipe.status == .needsReview, !recipe.flags.isEmpty {
            let count = recipe.flags.count
            Text(count == 1 ? "1 thing to check" : "\(count) things to check").font(.caption).foregroundStyle(Theme.flag)
        } else if let line = summary {
            Text(line).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
        }
    }

    private var summary: String? {
        let parts = [recipe.totalTime, recipe.servingsText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct CollectionsMenu: View {
    let model: AppModel
    let recipeID: UUID

    var body: some View {
        Menu("Collections") {
            ForEach(model.collections) { collection in
                Toggle(collection.name, isOn: Binding(
                    get: { model.isRecipe(recipeID, in: collection) },
                    set: { model.setRecipe(recipeID, in: collection, to: $0) }
                ))
            }
        }
    }
}

/// A clean card for reading while cooking.
struct RecipeView: View {
    let model: AppModel
    let recipe: Recipe
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let cover = recipe.coverName {
                    LibraryImage(library: model.library, name: cover, maxPixels: 1600, fill: true)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 14))
                }
                header
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ingredients.frame(width: 340)
                        steps
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        ingredients
                        steps
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") { model.openRecipeID = nil }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if !model.collections.isEmpty {
                    CollectionsMenu(model: model, recipeID: recipe.id)
                }
                Button("Export PDF", systemImage: "arrow.down.doc") {
                    model.exportPDF([recipe], named: recipe.title ?? "Recipe")
                }
                .help("Export this recipe as a PDF")
                Button("Edit") { model.isEditing = true }
                Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    .help("Delete this recipe")
            }
        }
        .confirmationDialog("Delete this recipe?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { model.delete(recipe) }
        } message: {
            Text("The card and its images will be removed from Zendish. This can't be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.title ?? "Untitled recipe")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(recipe.title == nil ? Theme.muted : Theme.text)
                .textSelection(.enabled)
            if !details.isEmpty {
                HStack(spacing: 6) {
                    ForEach(details, id: \.self) { detail in
                        Text(detail)
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Theme.sidebar, in: .capsule)
                    }
                }
            }
        }
    }

    private var details: [String] {
        [
            recipe.totalTime.map { "Total \($0)" }, recipe.prepTime.map { "Prep \($0)" },
            recipe.cookTime.map { "Cook \($0)" }, recipe.servingsText,
        ].compactMap { $0 }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ingredients")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 8)
            ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                let parts = ingredient.parts
                if let section = ingredient.section, section != recipe.ingredients[safe: index - 1]?.section {
                    Text(section)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, index == 0 ? 2 : 14)
                        .padding(.bottom, 2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(parts.quantity ?? "")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 92, alignment: .leading)
                    Text(parts.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .textSelection(.enabled)
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) {
                    if index < recipe.ingredients.count - 1 {
                        Rectangle().fill(Theme.line).frame(height: 0.5)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    /// One card per step, which makes it easy to keep your place while cooking.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .monospacedDigit()
                        .frame(width: 28, height: 28)
                        .background(Theme.sidebar, in: .circle)
                    Text(step)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                        .frame(idealWidth: 320, maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(Theme.surface, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 0.5))
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Lets a person drag a box over the food photo in a screenshot.
struct CropSheet: View {
    let library: ImageLibrary
    let names: [String]
    let choose: (String, CGRect) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var crop: CGRect?

    var body: some View {
        VStack(spacing: 14) {
            Text("Drag across the photo you want on the card").font(.headline)
            if names.count > 1 {
                Picker("Image", selection: $index) {
                    ForEach(names.indices, id: \.self) { Text("Image \($0 + 1)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .onChange(of: index) { crop = nil }
            }
            LibraryImage(library: library, name: names[index], maxPixels: 1400)
                .overlay { CropOverlay(crop: $crop) }
                .frame(maxHeight: 520)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use Photo") {
                    if let crop { choose(names[index], crop) }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(crop == nil)
                .opacity(crop == nil ? 0.5 : 1)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

/// Turns a drag into a crop measured in 0-to-1 fractions, kept inside the image.
func cropBox(from start: CGPoint, to end: CGPoint, in size: CGSize) -> CGRect {
    let box = CGRect(
        x: min(start.x, end.x) / size.width,
        y: min(start.y, end.y) / size.height,
        width: abs(end.x - start.x) / size.width,
        height: abs(end.y - start.y) / size.height
    )
    return box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
}

private struct CropOverlay: View {
    @Binding var crop: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(.rect)
                if let crop {
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 2)
                        .background(Theme.accent.opacity(0.2))
                        .frame(width: crop.width * size.width, height: crop.height * size.height)
                        .offset(x: crop.minX * size.width, y: crop.minY * size.height)
                }
            }
            .gesture(DragGesture(minimumDistance: 4).onChanged { drag in
                crop = cropBox(from: drag.startLocation, to: drag.location, in: size)
            })
        }
    }
}

/// A slim bar that appears only when something is needed before recipes can be read.
struct SetupBar: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.setup {
            case .ready, .checking:
                EmptyView()
            case .needsOllama:
                bar("Zendish needs Ollama, the free app that runs the AI on your Mac.") {
                    Button("Open Ollama") { model.openOllama() }
                    Button("Check Again") { Task { await model.checkSetup() } }
                }
            case .needsModel:
                bar("Zendish needs its AI model, a one-time download of about 7.6 GB.") {
                    Button("Download") { model.downloadModel() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            case .downloading(let progress):
                bar("Downloading the AI model. You can keep using Zendish.") {
                    ProgressView(value: progress).frame(width: 160)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func bar<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 10) {
            Text(text)
            Spacer()
            actions()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }
}
