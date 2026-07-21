import Foundation

/// One visited page (most-recent-first, deduped by URL).
struct HistoryEntry: Codable { var url: String; var title: String }

/// Persists recent browsing history to a JSON file in Application Support, for the
/// command bar's suggestions. Capped and deduped by URL.
@MainActor
final class HistoryStore {
    private let fileURL: URL
    private let cap = 500
    private(set) var entries: [HistoryEntry] = []

    init() {
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Muninn", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = list
        }
    }

    func record(url: URL, title: String) {
        guard url.scheme?.hasPrefix("http") == true else { return }
        let s = url.absoluteString
        entries.removeAll { $0.url == s }
        entries.insert(HistoryEntry(url: s, title: title.isEmpty ? (url.host ?? s) : title), at: 0)
        if entries.count > cap { entries.removeLast(entries.count - cap) }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }
}
