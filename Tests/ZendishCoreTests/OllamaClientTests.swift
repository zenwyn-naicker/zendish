import Foundation
import Testing
@testable import ZendishCore

/// Answers requests with a canned reply, so these tests never need Ollama.
final class FakeOllama: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var replies: [String: (status: Int, body: String)] = [:]
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        guard let host = request.url?.host, let reply = Self.replies[host], let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct OllamaClientTests {
    private func client(host: String, status: Int = 200, body: String) -> OllamaClient {
        FakeOllama.replies[host] = (status, body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeOllama.self]
        return OllamaClient(baseURL: URL(string: "http://\(host)")!, session: URLSession(configuration: configuration))
    }

    private func wrapped(_ card: String) -> String {
        let content = String(data: try! JSONEncoder().encode(card), encoding: .utf8)!
        return #"{"message":{"content":\#(content)}}"#
    }

    @Test func aReplyBecomesACard() async throws {
        let card = #"{"is_recipe":true,"title":"Soup","ingredients":["1 ½ cups stock"],"steps":["Simmer."],"total_time":null,"prep_time":"null","cook_time":"","servings":"Serves 2"}"#
        let draft = try await client(host: "good", body: wrapped(card)).writeCard(from: "text")

        #expect(draft == CardDraft(title: "Soup", ingredients: ["1 ½ cups stock"], steps: ["Simmer."], servings: "Serves 2"))
    }

    @Test func theRequestIsLimitedAndUsesTheRecipeText() async throws {
        let card = #"{"is_recipe":false,"title":null,"ingredients":[],"steps":[],"total_time":null,"prep_time":null,"cook_time":null,"servings":null}"#
        _ = try await client(host: "limits", body: wrapped(card)).writeCard(from: "Secret family stew")

        let sent = try JSONSerialization.jsonObject(with: try #require(FakeOllama.lastBody)) as? [String: Any]
        let options = try #require(sent?["options"] as? [String: Any])
        #expect(options["num_predict"] as? Int == 1500)
        #expect(options["temperature"] as? Int == 0)
        #expect(sent?["stream"] as? Bool == false)
        #expect(String(decoding: FakeOllama.lastBody ?? Data(), as: UTF8.self).contains("Secret family stew"))
    }

    @Test func aCutOffReplyIsReported() async {
        await #expect(throws: OllamaError.unusableReply) {
            _ = try await client(host: "cutoff", body: wrapped(#"{"is_recipe":false,"title":"Pet"#)).writeCard(from: "text")
        }
    }

    @Test func aMissingModelIsReported() async {
        await #expect(throws: OllamaError.modelMissing(OllamaClient.defaultModel)) {
            _ = try await client(host: "missing", status: 404, body: #"{"error":"model not found"}"#).writeCard(from: "text")
        }
    }

    @Test func ollamaNotRunningIsReported() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeOllama.self]
        let client = OllamaClient(baseURL: URL(string: "http://offline")!, session: URLSession(configuration: configuration))
        await #expect(throws: OllamaError.notRunning) {
            _ = try await client.writeCard(from: "text")
        }
    }
}
