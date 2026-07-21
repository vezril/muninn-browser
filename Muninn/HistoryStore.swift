import Foundation

/// One visited page (most-recent-first, deduped by URL). `visits` counts revisits (frequency).
struct HistoryEntry: Codable { var url: String; var title: String; var visits: Int = 1 }

/// Persists recent browsing history to a JSON file in Application Support, for the command bar's
/// suggestions and the address-bar / new-tab autocomplete. Capped and deduped by URL; ranks by
/// visit frequency + recency.
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
        let name = title.isEmpty ? (url.host ?? s) : title
        if let idx = entries.firstIndex(where: { $0.url == s }) {
            var e = entries.remove(at: idx); e.visits += 1; e.title = name
            entries.insert(e, at: 0)
        } else {
            entries.insert(HistoryEntry(url: s, title: name, visits: 1), at: 0)
        }
        if entries.count > cap { entries.removeLast(entries.count - cap) }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Deduped bare hosts (www. stripped), ranked by total visits then recency.
    func rankedHosts() -> [String] {
        var score: [String: (visits: Int, recency: Int)] = [:]
        for (i, e) in entries.enumerated() {
            guard let h = URL(string: e.url)?.host else { continue }
            let bare = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
            var s = score[bare] ?? (visits: 0, recency: entries.count - i)
            s.visits += e.visits
            s.recency = max(s.recency, entries.count - i)
            score[bare] = s
        }
        return score.sorted {
            $0.value.visits != $1.value.visits ? $0.value.visits > $1.value.visits
                                               : $0.value.recency > $1.value.recency
        }.map { $0.key }
    }

    /// The best inline completion for `typed` (e.g. "you" → "youtube.com"), preserving the user's
    /// typed casing and any scheme/`www.` prefix. Host-level only. nil when nothing fits.
    func bestCompletion(for typed: String) -> String? {
        let lower = typed.lowercased()
        guard !lower.isEmpty, !lower.contains(" ") else { return nil }
        var q = lower
        for pre in ["https://", "http://"] where q.hasPrefix(pre) { q = String(q.dropFirst(pre.count)) }
        if q.hasPrefix("www.") { q = String(q.dropFirst(4)) }
        guard !q.isEmpty, !q.contains("/") else { return nil }
        for host in rankedHosts() where host.hasPrefix(q) && host != q {
            return typed + host.dropFirst(q.count) // preserve the user's typed prefix + host suffix
        }
        return nil
    }
}
