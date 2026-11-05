import Foundation
import Testing
@testable import ZendishCore

/// Runs the whole pipeline with real images and a running Ollama. It's skipped unless
/// ZENDISH_LIVE_IMAGES points at a folder holding one subfolder of images per recipe.
@Suite struct LiveCheck {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZENDISH_LIVE_IMAGES"] != nil))
    func makeCardsFromRealImages() async throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["ZENDISH_LIVE_IMAGES"]))
        let manager = FileManager.default
        let folders = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter(\.hasDirectoryPath)
            .sorted { $0.path < $1.path }

        for folder in folders {
            let images = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { ["png", "jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.path < $1.path }
            let started = Date()
            let card = try await CardMaker().makeCard(from: images)
            let seconds = Date().timeIntervalSince(started)
            let recipe = card.recipe
            print("LIVE \(folder.lastPathComponent) \(String(format: "%.1f", seconds))s recipe=\(card.hasRecipe) title=\(recipe.title ?? "-") ingredients=\(recipe.ingredients.count) steps=\(recipe.steps.count) total=\(recipe.totalTime ?? "-") prep=\(recipe.prepTime ?? "-") cook=\(recipe.cookTime ?? "-") serves=\(recipe.servings ?? "-")")
            for flag in card.flags { print("LIVE   flag \(flag)") }
            for item in card.cleared { print("LIVE   cleared \(item)") }
        }
    }

    /// Asks a real Ollama for a model that's already installed, which proves the download
    /// messages are read correctly without fetching anything large.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZENDISH_LIVE_OLLAMA"] != nil))
    func readRealDownloadMessages() async throws {
        let client = OllamaClient(model: "nomic-embed-text:latest")
        #expect(await client.readiness() == .ready)
        try await client.downloadModel { print("LIVE progress \($0)") }
        #expect(await OllamaClient(model: "not-a-real-model:1b").readiness() == .modelMissing)
    }
}
