import Foundation

/// Persisted Ollama connection settings (local-first: defaults to a localhost daemon).
enum OllamaSettings {
    static let defaultBaseURL = "http://localhost:11434"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: "muninn.ollama.baseURL") ?? defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: "muninn.ollama.baseURL") }
    }
    static var defaultModel: String {
        get { UserDefaults.standard.string(forKey: "muninn.ollama.model") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "muninn.ollama.model") }
    }
    static var baseURLValue: URL? { URL(string: baseURL.trimmingCharacters(in: .whitespaces)) }
}

enum OllamaError: LocalizedError {
    case badURL, http(Int), unreachable(String)
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid Ollama URL."
        case .http(let code): return "Ollama returned HTTP \(code)."
        case .unreachable(let m): return m
        }
    }
}

/// A minimal native Ollama client (URLSession). Lists installed models and streams a
/// generation. Everything stays on the machine — the daemon is local by default.
struct OllamaClient {
    let baseURL: URL
    var session: URLSession = .shared

    /// Installed model names, via `GET /api/tags`.
    func listModels() async throws -> [String] {
        let (data, resp) = try await session.data(from: baseURL.appendingPathComponent("api/tags"))
        guard let http = resp as? HTTPURLResponse else { throw OllamaError.unreachable("No response.") }
        guard (200..<300).contains(http.statusCode) else { throw OllamaError.http(http.statusCode) }
        return Self.parseTags(data)
    }

    /// Stream a completion for `prompt` from `model`, via `POST /api/generate` (NDJSON).
    /// Yields each response chunk in order; finishes when the daemon reports `done`.
    func generateStream(model: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model, "prompt": prompt, "stream": true,
                    ])
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw OllamaError.unreachable("No response.") }
                    guard (200..<300).contains(http.statusCode) else { throw OllamaError.http(http.statusCode) }
                    for try await line in bytes.lines {
                        guard let chunk = Self.parseGenerateLine(line) else { continue }
                        if !chunk.text.isEmpty { continuation.yield(chunk.text) }
                        if chunk.done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Stream a multi-turn chat completion via `POST /api/chat` (NDJSON). `messages` are
    /// `["role": "user"/"assistant", "content": "…"]`. Yields each content chunk in order.
    func chatStream(model: String, messages: [[String: String]]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model, "messages": messages, "stream": true,
                    ])
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw OllamaError.unreachable("No response.") }
                    guard (200..<300).contains(http.statusCode) else { throw OllamaError.http(http.statusCode) }
                    for try await line in bytes.lines {
                        guard let chunk = Self.parseChatLine(line) else { continue }
                        if !chunk.text.isEmpty { continuation.yield(chunk.text) }
                        if chunk.done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: pure parsing (unit-tested)

    static func parseTags(_ data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// One NDJSON line from `/api/generate` → (partial text, done). Nil for blank/garbage lines.
    static func parseGenerateLine(_ line: String) -> (text: String, done: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["response"] as? String ?? "", obj["done"] as? Bool ?? false)
    }

    /// One NDJSON line from `/api/chat` → (partial content, done). Nil for blank/garbage lines.
    static func parseChatLine(_ line: String) -> (text: String, done: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let content = (obj["message"] as? [String: Any])?["content"] as? String ?? ""
        return (content, obj["done"] as? Bool ?? false)
    }
}
