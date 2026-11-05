import Foundation

public enum OllamaError: Error, Equatable, CustomStringConvertible {
    case notRunning
    case modelMissing(String)
    case unusableReply
    case failed(String)

    public var description: String {
        switch self {
        case .notRunning: "Zendish can't reach Ollama. Open Ollama, then try again."
        case .modelMissing(let model): "The \(model) model isn't installed yet."
        case .unusableReply: "The model didn't finish this card. Try again, or fill it in by hand."
        case .failed(let message): "Ollama reported a problem: \(message)"
        }
    }
}

/// Talks to Ollama on this Mac. Recipe text never leaves the computer.
public struct OllamaClient: CardWriter {
    public static let defaultModel = "qwen3.5:9b"

    let baseURL: URL
    let model: String
    let session: URLSession

    /// Stops a model that gets stuck repeating itself, which would otherwise never finish.
    static let outputLimit = 1500

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        model: String = OllamaClient.defaultModel,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    public func writeCard(from text: String) async throws -> CardDraft {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,
            "format": Self.cardFormat,
            "options": ["temperature": 0, "seed": 1, "num_ctx": 8192, "num_predict": Self.outputLimit],
            "messages": [["role": "user", "content": Self.prompt(for: text)]],
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw OllamaError.unusableReply }
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "status \(status)"
            throw message.contains("not found") ? OllamaError.modelMissing(model) : OllamaError.failed(message)
        }
        do {
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            return try JSONDecoder().decode(CardDraft.self, from: Data(reply.message.content.utf8))
        } catch {
            throw OllamaError.unusableReply
        }
    }

    /// What Ollama reports about this Mac's setup.
    public enum Readiness: Equatable, Sendable {
        case notRunning
        case modelMissing
        case ready
    }

    public func readiness() async -> Readiness {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return .notRunning }
        let installed = (try? JSONDecoder().decode(Installed.self, from: data))?.models.map(\.name) ?? []
        return installed.contains(model) ? .ready : .modelMissing
    }

    /// Downloads the model, reporting progress from 0 to 1. A model arrives in several pieces,
    /// so progress is added up across them and is never allowed to go backwards.
    public func downloadModel(progress: @Sendable @escaping (Double) -> Void) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])

        let (lines, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (lines, response) = try await session.bytes(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw OllamaError.notRunning
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OllamaError.failed("the download couldn't start") }

        var pieces: [String: (done: Int64, total: Int64)] = [:]
        var shown = 0.0
        for try await line in lines.lines {
            let update = try JSONDecoder().decode(PullUpdate.self, from: Data(line.utf8))
            if let error = update.error { throw OllamaError.failed(error) }
            guard let digest = update.digest, let total = update.total, total > 0 else { continue }
            pieces[digest] = (update.completed ?? 0, total)
            let overall = Double(pieces.values.map(\.done).reduce(0, +)) / Double(pieces.values.map(\.total).reduce(0, +))
            if overall > shown {
                shown = overall
                progress(shown)
            }
        }
    }

    private struct Installed: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    private struct PullUpdate: Decodable {
        let digest: String?
        let total: Int64?
        let completed: Int64?
        let error: String?
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw OllamaError.notRunning
        }
    }

    static func prompt(for text: String) -> String {
        """
        You turn text read from a recipe screenshot into a recipe card.

        Rules:
        - Use only words in the text. Never invent or guess anything.
        - Copy quantities exactly as written.
        - If a detail is not in the text, use null for it. Do not work out or estimate times or servings.
        - Ignore ads, cookie notices, ratings, navigation, reader comments and other recipes.
        - If the text has no recipe, set "is_recipe" to false and leave everything else empty.

        Text:
        ---
        \(text)
        ---
        """
    }

    private static var cardFormat: [String: Any] {
        let detail: [String: Any] = ["type": ["string", "null"]]
        let lines: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let properties: [String: Any] = [
            "is_recipe": ["type": "boolean"], "title": detail, "ingredients": lines, "steps": lines,
            "total_time": detail, "prep_time": detail, "cook_time": detail, "servings": detail,
        ]
        return ["type": "object", "properties": properties, "required": Array(properties.keys).sorted()]
    }

    private struct Reply: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    private struct Failure: Decodable { let error: String }
}
