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
