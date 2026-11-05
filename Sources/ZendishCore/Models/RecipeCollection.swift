import Foundation

/// A named group of recipes, such as "Weeknight dinners". A recipe can be in several.
public struct RecipeCollection: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
