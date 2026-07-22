import Foundation

/// A completed download, recorded for the Library.
struct DownloadRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var filename: String
    var path: String          // absolute destination path
    var sourceURL: String?    // where it came from
    var date: Date
    var byteSize: Int64

    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    /// Media = images / video / audio, by extension (drives the Library "Media" grid).
    var isMedia: Bool { Self.mediaExtensions.contains(url.pathExtension.lowercased()) }
    var isImage: Bool { Self.imageExtensions.contains(url.pathExtension.lowercased()) }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "svg"]
    static let mediaExtensions: Set<String> = imageExtensions.union(
        ["mp4", "mov", "m4v", "webm", "mkv", "avi", "mp3", "m4a", "wav", "aac", "flac", "ogg"])
}

/// Persists the download history to `downloads.json` in Application Support.
@MainActor
final class DownloadStore {
    private let fileURL: URL
    private(set) var records: [DownloadRecord] = []

    init() {
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Muninn", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("downloads.json")
        records = load()
    }

    private func load() -> [DownloadRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let r = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return [] }
        return r
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Record a finished download (newest first).
    func add(path: URL, source: URL?) {
        let size = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int64) ?? nil
        records.insert(DownloadRecord(filename: path.lastPathComponent, path: path.path,
                                      sourceURL: source?.absoluteString, date: Date(),
                                      byteSize: size ?? 0), at: 0)
        save()
    }

    func remove(_ id: UUID) { records.removeAll { $0.id == id }; save() }
    func clear() { records.removeAll(); save() }
}
