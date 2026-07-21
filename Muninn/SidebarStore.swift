import Foundation

/// Persists the sidebar's favourites + pinned tabs to a JSON file in Application Support,
/// so they survive relaunch. Regular tabs are session-only (for now).
@MainActor
final class SidebarStore {
    private let fileURL: URL

    init() {
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Muninn", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("sidebar.json")
    }

    func load() -> [SavedTab] {
        guard let data = try? Data(contentsOf: fileURL),
              let tabs = try? JSONDecoder().decode([SavedTab].self, from: data) else { return [] }
        return tabs
    }

    func save(_ tabs: [SavedTab]) {
        guard let data = try? JSONEncoder().encode(tabs) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
