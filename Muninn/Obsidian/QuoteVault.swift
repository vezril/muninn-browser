import Foundation

/// A quote pulled from the vault: the note's title is the quote; `author` and `from` (the source the
/// quote is from) come from frontmatter.
struct VaultQuote: Equatable {
    let text: String        // the note title (= the quote)
    let author: String?
    let from: String?       // where the quote is from (book, work, speech, …)
}

/// Scans an Obsidian folder for notes tagged `source/quotes` and serves a random one for the New Tab
/// page. A quote note = the filename is the quote, the frontmatter `author` (with `[[…]]` stripped) is
/// the attribution; the note body is ignored. Results are cached (5-min TTL) so opening many tabs is
/// cheap. Frontmatter parsing is pure + unit-tested.
@MainActor
final class QuoteVault {
    static let shared = QuoteVault()

    private let quoteTag = "source/quotes"
    private var cache: [VaultQuote] = []
    private var cachedAt = Date.distantPast
    private var cachedFolder = ""

    func randomQuote() -> VaultQuote? {
        refreshIfNeeded()
        return cache.randomElement()
    }

    /// Force a rescan on next access (e.g. after the folder setting changes).
    func invalidate() { cachedAt = .distantPast; cachedFolder = "" }

    private func refreshIfNeeded() {
        guard let folder = ObsidianSettings.quotesFolder else { cache = []; return }
        if folder.path == cachedFolder, Date().timeIntervalSince(cachedAt) < 300 { return }
        cache = Self.scan(folder, tag: quoteTag)
        cachedAt = Date(); cachedFolder = folder.path
    }

    // MARK: scanning

    nonisolated static func scan(_ folder: URL, tag: String) -> [VaultQuote] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: folder, includingPropertiesForKeys: nil,
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [VaultQuote] = []
        for case let url as URL in en where url.pathExtension.lowercased() == "md" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            if let q = quote(filename: name, content: content, tag: tag) { out.append(q) }
        }
        return out
    }

    /// Build a `VaultQuote` from a note if it's tagged `tag`, else nil. Pure — the unit-test entry point.
    nonisolated static func quote(filename: String, content: String, tag: String) -> VaultQuote? {
        guard let block = frontmatterBlock(content) else { return nil }
        let fields = parseFrontmatter(block)
        guard (fields["tags"] ?? []).contains(tag) else { return nil }
        let author = fields["author"]?.first(where: { !$0.isEmpty })
        let from = fields["from"]?.first(where: { !$0.isEmpty })
        return VaultQuote(text: filename, author: author, from: from)
    }

    // MARK: frontmatter (pure)

    /// The text between the leading `---` fences, or nil if there's no frontmatter at the top.
    nonisolated static func frontmatterBlock(_ content: String) -> String? {
        let lines = content.components(separatedBy: "\n")
        guard let open = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }),
              lines[..<open].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        guard let closeRel = lines[(open + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        return lines[(open + 1)..<closeRel].joined(separator: "\n")
    }

    /// Minimal YAML: scalars (`key: value`), block lists (`key:` then `  - item`), and inline lists
    /// (`key: [a, b]`). Values are cleaned of quotes and `[[wikilinks]]`. Enough for note frontmatter.
    nonisolated static func parseFrontmatter(_ block: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var currentKey: String?
        for raw in block.components(separatedBy: "\n") {
            let stripped = raw.drop { $0 == " " || $0 == "\t" }
            let indented = stripped.count != raw.count
            if indented, stripped.hasPrefix("- ") {                 // block-list item
                if let key = currentKey { result[key, default: []].append(clean(String(stripped.dropFirst(2)))) }
                continue
            }
            guard !indented, let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
                currentKey = nil; continue
            }
            currentKey = key
            let val = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if val.isEmpty {
                if result[key] == nil { result[key] = [] }          // block list follows
            } else if val.hasPrefix("[") {                          // inline list [a, b]
                let inner = val.dropFirst().prefix { $0 != "]" }
                result[key] = inner.split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty }
            } else {
                result[key] = [clean(val)]
            }
        }
        return result
    }

    /// Trim quotes and `[[wikilink]]` wrapping; for `[[Name|Alias]]` keep the alias.
    nonisolated static func clean(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        if v.count >= 4, v.hasPrefix("[["), v.hasSuffix("]]") {
            v = String(v.dropFirst(2).dropLast(2))
        }
        if let bar = v.firstIndex(of: "|") { v = String(v[v.index(after: bar)...]) }  // display alias
        return v.trimmingCharacters(in: .whitespaces)
    }
}
