import SwiftUI
import ZendishCore

/// The card beside its original images. Flags appear only when something needs checking.
struct ReviewView: View {
    let model: AppModel
    @State private var draft: Recipe
    @State private var isConfirmingDiscard = false
    @State private var isChoosingPhoto = false

    init(model: AppModel, recipe: Recipe) {
        self.model = model
        _draft = State(initialValue: recipe)
    }

    var body: some View {
        HSplitView {
            OriginalImagesView(library: model.library, names: draft.imageNames)
                .frame(minWidth: 280, idealWidth: 400)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    banners
                    TextField("Title", text: text(\.title), prompt: Text("Recipe title"))
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                    details
                    photo
                    ingredients
                    steps
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(minWidth: 380, maxWidth: .infinity)
        }
        .navigationTitle(draft.status == .saved ? "Edit Recipe" : "Check This Recipe")
        .sheet(isPresented: $isChoosingPhoto) {
            CropSheet(library: model.library, names: draft.imageNames) { name, crop in
                do {
                    draft.coverName = try model.chooseCover(for: draft, from: name, crop: crop)
                } catch {
                    model.message = String(describing: error)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") { closeKeepingEdits() }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Discard", systemImage: "trash", role: .destructive) { isConfirmingDiscard = true }
                    .help("Delete this recipe and its images")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(draft.status == .saved ? "Save Changes" : "Save to Cookbook") { model.saveToCookbook(draft) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s")
            }
        }
        .confirmationDialog("Delete this recipe?", isPresented: $isConfirmingDiscard) {
            Button("Delete", role: .destructive) { model.delete(draft) }
        } message: {
            Text("The card and its images will be removed from Zendish. This can't be undone.")
        }
    }

    private func closeKeepingEdits() {
        model.update(draft)
        if draft.status == .saved {
            model.isEditing = false
        } else {
            model.openRecipeID = nil
        }
    }

    // MARK: Sections

    @ViewBuilder private var banners: some View {
        if let problem = draft.problem {
            Banner(systemImage: "exclamationmark.triangle", text: problem) {
                Button("Try Again") {
                    model.retry(draft)
                    model.openRecipeID = nil
                }
            }
        }
        if draft.flags.contains(.noRecipe) {
            Banner(systemImage: "questionmark.circle", text: "No recipe was found in these images. You can type it in, or discard it.") {
                EmptyView()
            }
        }
    }

    private var photo: some View {
        HStack(spacing: 12) {
            if let cover = draft.coverName {
                LibraryImage(library: model.library, name: cover, maxPixels: 200)
                    .frame(width: 64, height: 48)
                    .clipShape(.rect(cornerRadius: 6))
            }
            Button(draft.coverName == nil ? "Choose Card Photo…" : "Change Photo…") { isChoosingPhoto = true }
            if draft.coverName != nil {
                Button("Remove Photo") { draft.coverName = nil }
                    .buttonStyle(.link)
            }
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Label2("Total")
                Label2("Prep")
                Label2("Cook")
                Label2("Serves")
            }
            GridRow {
                detailField(\.totalTime)
                detailField(\.prepTime)
                detailField(\.cookTime)
                detailField(\.servings)
            }
        }
    }

    private func detailField(_ path: WritableKeyPath<Recipe, String?>) -> some View {
        TextField("", text: text(path), prompt: Text("Not given"))
            .textFieldStyle(.roundedBorder)
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Ingredients")
            ForEach(draft.ingredients.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 3) {
                    EditableRow(text: $draft.ingredients[index].text, placeholder: "Ingredient", isFlagged: suggestion(for: index) != nil) {
                        draft.ingredients.remove(at: index)
                    }
                    if let flag = suggestion(for: index) {
                        QuantityFlagView(suggestion: flag.suggestion) {
                            draft.ingredients[index].text = flag.suggestion
                            remove(.checkQuantity(line: flag.line, suggestion: flag.suggestion))
                        } keep: {
                            remove(.checkQuantity(line: flag.line, suggestion: flag.suggestion))
                        }
                    }
                }
            }
            ForEach(missingLines, id: \.self) { line in
                MissingLineView(line: line) {
                    draft.ingredients.append(Ingredient(text: line))
                    remove(.missingLine(line))
                } ignore: {
                    remove(.missingLine(line))
                }
            }
            Button("Add Ingredient", systemImage: "plus") { draft.ingredients.append(Ingredient(text: "")) }
                .buttonStyle(.borderless)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Steps")
            ForEach(draft.steps.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    EditableRow(text: $draft.steps[index], placeholder: "Step", isFlagged: false) {
                        draft.steps.remove(at: index)
                    }
                }
            }
            Button("Add Step", systemImage: "plus") { draft.steps.append("") }
                .buttonStyle(.borderless)
        }
    }

    // MARK: Flags

    private func suggestion(for index: Int) -> (line: String, suggestion: String)? {
        let text = draft.ingredients[index].text
        for flag in draft.flags {
            if case .checkQuantity(let line, let suggestion) = flag, line == text {
                return (line, suggestion)
            }
        }
        return nil
    }

    private var missingLines: [String] {
        draft.flags.compactMap { if case .missingLine(let line) = $0 { line } else { nil } }
    }

    private func remove(_ flag: CardFlag) {
        draft.flags.removeAll { $0 == flag }
    }

    private func text(_ path: WritableKeyPath<Recipe, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: path] ?? "" },
            set: { draft[keyPath: path] = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct Label2: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).font(.headline)
    }
}

private struct EditableRow: View {
    @Binding var text: String
    let placeholder: String
    let isFlagged: Bool
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("", text: $text, prompt: Text(placeholder), axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isFlagged ? AnyShapeStyle(Color.orange.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.22)), in: .rect(cornerRadius: 6))
            Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
    }
}

private struct QuantityFlagView: View {
    let suggestion: String
    let use: () -> Void
    let keep: () -> Void

    /// Only the quantity, since that's the part in question.
    private var shortSuggestion: String {
        suggestion.split(separator: " ").prefix(3).joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Should this be “\(shortSuggestion)”?")
                .foregroundStyle(.orange)
            Button("Use This", action: use)
            Button("Keep As Is", action: keep)
        }
        .font(.callout)
        .buttonStyle(.link)
        .padding(.leading, 8)
    }
}

private struct MissingLineView: View {
    let line: String
    let add: () -> Void
    let ignore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("In the image, not on the card: \(line)")
                .foregroundStyle(.orange)
            Button("Add", action: add)
            Button("Ignore", action: ignore)
        }
        .font(.callout)
        .buttonStyle(.link)
        .padding(.leading, 8)
    }
}

private struct Banner<Action: View>: View {
    let systemImage: String
    let text: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.orange)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            action()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 8))
    }
}

/// The original images, stacked so the whole recipe can be scrolled through.
struct OriginalImagesView: View {
    let library: ImageLibrary
    let names: [String]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(names, id: \.self) { name in
                    LibraryImage(library: library, name: name, maxPixels: 1600)
                        .clipShape(.rect(cornerRadius: 6))
                }
            }
            .padding(14)
        }
        .background(.quaternary.opacity(0.35))
    }
}

/// Keeps recently shown images in memory, so scrolling back through a grid is instant.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let storage = NSCache<NSString, CGImage>()

    private init() { storage.countLimit = 300 }

    func image(for key: String) -> CGImage? { storage.object(forKey: key as NSString) }
    func store(_ image: CGImage, for key: String) { storage.setObject(image, forKey: key as NSString) }
}

/// Loads a downscaled copy away from the main thread, so scrolling stays smooth.
struct LibraryImage: View {
    let library: ImageLibrary
    let name: String
    let maxPixels: Int
    var fill = false
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                if fill {
                    Color.clear.overlay {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    }
                    .clipped()
                } else {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                }
            } else {
                Color.secondary.opacity(0.1).frame(minHeight: 120)
            }
        }
        .task(id: name) {
            let key = "\(name)-\(maxPixels)"
            if let cached = ImageCache.shared.image(for: key) {
                image = cached
                return
            }
            let library = library, name = name, maxPixels = maxPixels
            let loaded = await Task.detached(priority: .userInitiated) {
                library.thumbnail(named: name, maxPixels: maxPixels)
            }.value
            if let loaded { ImageCache.shared.store(loaded, for: key) }
            image = loaded
        }
    }
}
