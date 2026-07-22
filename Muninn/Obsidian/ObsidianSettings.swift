import Foundation

/// Persisted Obsidian integration settings. An Obsidian vault is just a folder of Markdown
/// files, so "integration" = writing `.md` notes into a chosen folder.
enum ObsidianSettings {
    static var vaultPath: String {
        get { UserDefaults.standard.string(forKey: "muninn.obsidian.vault") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "muninn.obsidian.vault") }
    }
    /// Absolute folder new notes land in. Empty → the vault root.
    static var notesPath: String {
        get { UserDefaults.standard.string(forKey: "muninn.obsidian.notes") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "muninn.obsidian.notes") }
    }

    static var isConfigured: Bool {
        !vaultPath.isEmpty && FileManager.default.fileExists(atPath: vaultPath)
    }
    /// Where a new note should be written (falls back to the vault root).
    static var notesFolder: URL? {
        guard !vaultPath.isEmpty else { return nil }
        let base = notesPath.isEmpty ? vaultPath : notesPath
        return URL(fileURLWithPath: base)
    }
}

/// Creates Obsidian notes (Markdown files with YAML frontmatter).
enum ObsidianNote {
    /// Write a note for `title`/`url` (optionally with a summary body) into `folder`. Returns the
    /// created file URL. Filenames are sanitised and de-duplicated.
    @discardableResult
    static func create(title: String, url: String, summary: String?, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = sanitizedFilename(title)
        var dest = folder.appendingPathComponent(base + ".md")
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(base) \(n).md"); n += 1
        }
        var content = frontmatter(title: title, url: url) + "\n# \(title)\n\n"
        if let summary, !summary.isEmpty { content += summary.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" }
        content += "[\(url)](\(url))\n"
        try content.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    static func frontmatter(title: String, url: String) -> String {
        let created = Date().ISO8601Format()
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        ---
        title: "\(safeTitle)"
        url: \(url)
        created: \(created)
        source: Muninn
        tags: [web-clip]
        ---
        """
    }

    /// Strip characters illegal in filenames; collapse whitespace; fall back to "Untitled".
    static func sanitizedFilename(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var s = raw.components(separatedBy: illegal).joined(separator: " ")
        s = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        s = String(s.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return s.isEmpty ? "Untitled" : s
    }

    /// `obsidian://open?path=…` URL to open a created note in Obsidian.
    static func openURL(for file: URL) -> URL? {
        guard let enc = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "obsidian://open?path=\(enc)")
    }
}
