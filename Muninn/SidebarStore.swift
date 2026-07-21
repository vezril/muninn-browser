import Foundation

/// A named, colourable, collapsible group for pinned tabs.
struct Folder: Codable, Identifiable {
    var id: UUID
    var name: String
    /// Index into `Folder.palette` (kept as an index so the swatch survives renames).
    var colorIndex: Int
    var collapsed: Bool

    init(id: UUID = UUID(), name: String, colorIndex: Int = 0, collapsed: Bool = false) {
        self.id = id; self.name = name; self.colorIndex = colorIndex; self.collapsed = collapsed
    }

    /// The folder swatch palette (name shown in the colour menu → RGB).
    static let palette: [(name: String, rgb: (CGFloat, CGFloat, CGFloat))] = [
        ("Gray",   (0.56, 0.56, 0.58)),
        ("Blue",   (0.20, 0.52, 0.96)),
        ("Green",  (0.20, 0.72, 0.40)),
        ("Yellow", (0.98, 0.76, 0.18)),
        ("Orange", (0.98, 0.55, 0.20)),
        ("Red",    (0.94, 0.32, 0.31)),
        ("Purple", (0.64, 0.36, 0.92)),
        ("Pink",   (0.96, 0.40, 0.62)),
    ]
}

/// What the sidebar persists: the saved tabs plus the folder definitions.
struct SidebarState: Codable {
    var tabs: [SavedTab] = []
    var folders: [Folder] = []
}

/// Persists the sidebar's favourites + pinned tabs (and their folders) to a JSON file in
/// Application Support, so they survive relaunch. Regular tabs are session-only (for now).
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

    func load() -> SidebarState {
        guard let data = try? Data(contentsOf: fileURL) else { return SidebarState() }
        // Current format: a SidebarState object.
        if let state = try? JSONDecoder().decode(SidebarState.self, from: data) { return state }
        // Legacy format: a bare [SavedTab] array (pre-folders).
        if let tabs = try? JSONDecoder().decode([SavedTab].self, from: data) {
            return SidebarState(tabs: tabs, folders: [])
        }
        return SidebarState()
    }

    func save(_ state: SidebarState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
