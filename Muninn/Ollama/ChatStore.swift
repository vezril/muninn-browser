import Foundation

/// One message in a chat session.
struct ChatMessage: Codable {
    enum Role: String, Codable { case user, assistant }
    var role: Role
    var text: String
}

/// A persisted chat session (conversation) with the local model.
struct ChatSession: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String = "New Chat"
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()

    /// A short title derived from the first user message.
    mutating func retitle() {
        if let first = messages.first(where: { $0.role == .user })?.text, !first.isEmpty {
            title = String(first.prefix(40))
        }
    }
}

/// Persists chat sessions to `chat.json` in Application Support so the conversation survives
/// closing the window.
@MainActor
final class ChatStore {
    private let fileURL: URL

    init() {
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Muninn", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("chat.json")
    }

    func load() -> [ChatSession] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? JSONDecoder().decode([ChatSession].self, from: data) else { return [] }
        return sessions
    }

    func save(_ sessions: [ChatSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
